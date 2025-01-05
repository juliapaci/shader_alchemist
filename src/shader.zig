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

    /// look for "// @special" in `specials`
    fn analyse(self: *@This(), source: std.fs.File) !void {
        self.state = .{};

        var buf_reader = std.io.bufferedReader(source.reader());
        var reader = buf_reader.reader();
        var buffer: [1024]u8 = undefined;

        var is_special: struct {kind: Specials, for_next: bool} = undefined;

        while(try reader.readUntilDelimiterOrEof(&buffer, '\n')) |original_line| {
            const line = std.mem.trimLeft(u8, original_line, " ");

            if(!is_special.for_next) {
                var found = false;
                var tokens = std.mem.splitScalar(u8, line, ' ');
                const first = tokens.next() orelse break;
                if(first.len < 2) continue;

                inline for(@typeInfo(Specials).Enum.fields) |special| {

                    if(std.mem.eql(u8, first[0..2], "//") and
                        std.mem.eql(u8, if(first.len == 2) tokens.rest() else first[2..], "@" ++ special.name)
                    ) {
                        found = true;
                        is_special.kind = @enumFromInt(special.value);
                        break;
                    }
                }

                if(found) {
                    switch(is_special.kind) {
                        .inspect => is_special.for_next = true,
                        .pause => self.state.paused = true
                    }
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
    }

    fn reload(self: *@This()) !void {
        self.watcher.mutex.lock();
        defer self.watcher.mutex.unlock();

        const defaults_file = try std.fs.cwd().openFile(FRAGMENT_DEFAULT_PATH, .{});
        defer defaults_file.close();
        const defaults_file_size = try defaults_file.getEndPos();

        const user_file = try std.fs.cwd().openFile(self.path, .{});
        defer user_file.close();
        const user_file_size = try user_file.getEndPos();

        const fragment_source = try allocator.alloc(u8, user_file_size + defaults_file_size + 1);
        defer allocator.free(fragment_source);

        _ = try defaults_file.readAll(fragment_source[0..defaults_file_size]);
        _ = try user_file.readAll(fragment_source[defaults_file_size..defaults_file_size + user_file_size]);
        fragment_source[defaults_file_size + user_file_size] = 0;

        const prev = self.program;
        self.program = shaderMake(VERTEX_PATH, @ptrCast(@alignCast(fragment_source))) catch |err| {
            std.log.err("shader compilation error {s}\n", .{@errorName(err)});
            return;
        };
        if(prev != 0) c.glDeleteProgram(prev);
        c.glUseProgram(self.program);

        std.log.info("\rreloaded shader \"{s}\":\n{s}", .{self.path, fragment_source});

        try user_file.seekTo(0);
        try self.analyse(user_file);
    }

    // needs to be called from the main thread
    pub fn reloadOnChange(self: *@This()) !void {
        if(!self.watcher.state.modified)
            return;

        self.watcher.state.modified = false;
        // clear screen and reset cursor escape codes
        _ = try std.io.getStdIn().writer().write("\x1b[2J\x1b[H");
        try self.reload();
        std.log.info("state: {any}", .{self.state});
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
