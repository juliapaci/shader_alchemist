const std = @import("std");
const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
});

fn shaderErrorCheck(shader: c.GLuint, comptime pname: c.GLenum) !void {
    var success: c.GLint = undefined;

    if(pname == c.GL_COMPILE_STATUS) {
        c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &success);
    } else if(pname == c.GL_LINK_STATUS) {
        c.glGetProgramiv(shader, c.GL_LINK_STATUS, &success);
    }

    if(success == 0) {
        var info_log: [512]c.GLchar = undefined;
        @memset(&info_log, 0);
        c.glGetShaderInfoLog(shader, 512, null, &info_log);
        std.log.err("shader fail log: {s}", .{info_log});
        return error.ShaderCompilationFailed;
    }
}

fn shaderMake(comptime vertex_path: []const u8, fragment_source: *[*:0]const u8) !c.GLuint {
    const vertex_source = @embedFile(vertex_path);

    const vertex = c.glCreateShader(c.GL_VERTEX_SHADER);
    const fragment = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    defer c.glDeleteShader(vertex);
    defer c.glDeleteShader(fragment);
    c.glShaderSource(vertex, 1, @ptrCast(&vertex_source), null);
    c.glShaderSource(fragment, 1, @ptrCast(&fragment_source), null);
    c.glCompileShader(vertex);
    c.glCompileShader(fragment);
    try shaderErrorCheck(vertex, c.GL_COMPILE_STATUS);
    try shaderErrorCheck(fragment, c.GL_COMPILE_STATUS);

    const shader = c.glCreateProgram();
    c.glAttachShader(shader, vertex);
    c.glAttachShader(shader, fragment);
    defer c.glDetachShader(shader, vertex);
    defer c.glDetachShader(shader, fragment);
    c.glLinkProgram(shader);
    try shaderErrorCheck(shader, c.GL_LINK_STATUS);

    return shader;
}

// will be stored on the heap because it must be shared between threads
pub const Shader = struct {
    const allocator = std.heap.page_allocator;

    watcher: *Watcher,

    path: []const u8,
    program: c.GLuint = 0,

    state: struct { paused: bool = false } = .{},

    // TODO: maybe load defaults to shader string/file at runtime
    defaults: struct {
        // name -> location
        uniforms: std.StringHashMap(c.GLint) = std.StringHashMap(c.GLint).init(allocator),

        viewport: struct {
            width: f32 = 0.0,
            height: f32 = 0.0
        } = .{},

        time: f64 = 0
    } = .{},

    user: struct {
        // name -> location
        uniforms: std.StringHashMap(c.GLint) = std.StringHashMap(c.GLint).init(allocator)
    } = .{},

    // compile time paths are relative to the source file
    // while runtime paths are relative to cwd of execution
    const VERTEX_PATH = "shader.vs";
    const FRAGMENT_DEFAULT_PATH = "src/shader_defaults.fs";

    pub fn addDefaultUniformLocation(self: *@This(), uniform: []const u8) !void {
        try self.defaults.uniforms.put(uniform, c.glGetUniformLocation(self.program, try allocator.dupeZ(u8, uniform)));
    }

    pub fn init(self: *@This(), shader_path: []const u8) !void {
        self.* = .{
            .path = shader_path,
            .watcher = try Watcher.init(shader_path)
        };

        try self.reload();
        try self.addDefaultUniformLocation("u_time");
        try self.addDefaultUniformLocation("u_viewport");
    }

    pub fn deinit(self: *@This()) void {
        c.glDeleteProgram(self.program);

        self.watcher.deinit();

        self.defaults.uniforms.deinit();
        self.user.uniforms.deinit();
    }

    fn updateUniforms(self: *@This()) void {
        if(!self.state.paused)
            c.glUniform1f(self.defaults.uniforms.get("u_time").?, @floatCast(self.defaults.time));
    }

    pub fn update(self: *@This()) void {
        self.defaults.time = c.glfwGetTime();

        self.updateUniforms();
    }

    /// called by users using "// @special"
    const Specials = enum {inspect, pause};

    /// look for @special" in `specials` and modifiers the source bufer to remove them for compilation
    /// returns new size of file
    fn analyse(self: *@This(), source: std.fs.File, buffer: []u8) !u64 {
        self.state = .{};

        var buf_reader = std.io.bufferedReader(source.reader());
        var reader = buf_reader.reader();
        var line_buffer: [1024]u8 = undefined;

        var is_special: struct {kind: Specials, for_next: bool} = undefined;

        var index: usize = 0;
        while(try reader.readUntilDelimiterOrEof(&line_buffer, '\n')) |original_line| {
            @memcpy(buffer[index..index + original_line.len], original_line);
            index += original_line.len;
            buffer[index] = '\n';
            index += 1;

            const line = std.mem.trimLeft(u8, original_line, " ");

            if(!is_special.for_next) {
                var tokens = std.mem.splitScalar(u8, line, ' ');
                const special = tokens.next() orelse break;
                if(special.len < 2 or special[0] != '@') continue;

                const variant = std.meta.stringToEnum(Specials, special[1..]) orelse continue;

                // if we found a special then let the next line overwrite the prev buffer line so that the shader compiles
                index -= original_line.len + 1;

                switch(variant) {
                    .inspect => is_special.for_next = true,
                    .pause => self.state.paused = true
                }

                continue;
            }

            is_special.for_next = false;

            // next line after @inspect should be an expression
            const types = enum {uniform, int, vec, float};
            _ = types;
            var tokens = std.mem.tokenizeAny(u8, line, " (),+-/*=;");
            while(tokens.next()) |token| {
                std.log.debug("{s}", .{token});
                // switch(std.meta.stringToEnum(types, token) orelse continue) {
                    // .uniform =>
                // }
            }
        }

        return index;
    }

    fn reload(self: *@This()) !void {
        self.watcher.mutex.lock();
        defer self.watcher.mutex.unlock();

        const defaults_file = try std.fs.cwd().openFile(FRAGMENT_DEFAULT_PATH, .{});
        defer defaults_file.close();
        const defaults_fs = try defaults_file.getEndPos();

        const user_file = try std.fs.cwd().openFile(self.path, .{});
        defer user_file.close();
        const user_fs = try user_file.getEndPos();

        const fragment_source = try allocator.alloc(u8, user_fs + defaults_fs + 1);
        defer allocator.free(fragment_source);

        _ = try defaults_file.readAll(fragment_source[0..defaults_fs]);
        const size = try self.analyse(user_file, fragment_source[defaults_fs..]);
        fragment_source[defaults_fs + size] = 0;

        const prev = self.program;
        self.program = shaderMake(VERTEX_PATH, @ptrCast(@alignCast(fragment_source))) catch return;
        if(prev != 0) c.glDeleteProgram(prev);
        c.glUseProgram(self.program);

        std.log.info("\rreloaded shader \"{s}\":\n{s}", .{self.path, fragment_source[0..defaults_fs+size]});
    }

    // needs to be called from the main thread
    pub fn reloadOnChange(self: *@This()) !void {
        if(!self.watcher.state.modified)
            return;

        self.watcher.state.modified = false;
        // clear screen and reset cursor escape codes
        _ = try std.io.getStdIn().writer().write("\x1b[2J\x1b[H");
        try self.reload();
        std.log.info("state:", .{});
        inline for(@typeInfo(@TypeOf(self.state)).Struct.fields) |field| {
            std.log.info("\t{s}: {any}", .{field.name, @field(self.state, field.name)});
        }
    }
};

const Watcher = struct {
    const allocator = std.heap.page_allocator;

    inotify_fd: i32,
    mutex: std.Thread.Mutex = .{},
    thread: std.Thread,

    path: []const u8,
    state: struct {playing: bool = true, modified: bool = false} = .{},

    fn inotify_add(self: *@This()) !void {
        _ = try std.posix.inotify_add_watch(self.inotify_fd, self.path, std.os.linux.IN.MODIFY);
    }

    fn init(path: []const u8) !*@This() {
        const self: *@This() = try allocator.create(@This());
        self.* = .{
            .inotify_fd = try std.posix.inotify_init1(std.os.linux.IN.NONBLOCK),
            .thread = try std.Thread.spawn(.{}, watch, .{self}),
            .path = path
        };

        try self.inotify_add();
        return self;
    }

    fn deinit(self: *@This()) void {
        self.state.playing = false;
        self.thread.join();
        std.posix.close(self.inotify_fd);
        allocator.destroy(self);
    }

    // should run on different thread
    // sets state if file was changed
    fn watch(self: *@This()) !void {
        var buffer: [4096]std.os.linux.inotify_event = undefined;

        while(self.state.playing) {
            const length = std.posix.read(self.inotify_fd, std.mem.sliceAsBytes(&buffer)) catch |err| switch(err) {
                error.WouldBlock => {
                    std.time.sleep(std.time.ns_per_s);
                    continue;
                },
                else => return err
            };

            var i: u32 = 0;
            while(i < length) : (i += buffer[i].len + 1) {
                if (buffer[i].mask & std.os.linux.IN.IGNORED != 0) {
                    // re ad file from temporary buffer
                    // if (buffer[i].wd != 1) return error.InvalidWatchDescriptor;
                    try self.inotify_add();
                } else if(buffer[i].mask & std.os.linux.IN.MODIFY == 0)
                    continue;

                self.mutex.lock();
                self.state.modified = true;
                self.mutex.unlock();
            }
        }
    }
};
