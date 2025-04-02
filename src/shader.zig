const std = @import("std");
const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
});

// TODO: shadertoy importing
// TODO: export to video with ffmpeg
// TODO: texture loading
// TODO: graphing capabilities
// TODO: procedural synth sound from graphs

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

fn shaderMake(comptime vertex_path: []const u8, fragment_source_array: *std.ArrayList(u8)) !c.GLuint {
    const vertex_source = @embedFile(vertex_path);
    var fragment_source: [*c]const u8 = @ptrCast(@alignCast(&fragment_source_array.items));

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

fn printStruct(structure: anytype) void {
    std.log.info("{s}", .{@typeName(@TypeOf(structure))});
    inline for(@typeInfo(@TypeOf(structure)).Struct.fields) |field| {
        std.log.info("\t{s}: {any}", .{field.name, @field(structure, field.name)});
    }
}

// will be stored on the heap because it must be shared between threads
pub const Shader = struct {
    const SHARED_MEM = 10;
    const SHARED_TEX = 0;

    allocator: std.mem.Allocator,

    watcher: *Watcher,

    path: []const u8,
    program: c.GLuint = 0,

    // we use a texture to get values to/from cpu/gpu when we need to
    // used for override and inspect specials
    shared: struct {
        // if we are on the shared pass yet
        pass: bool = false,
        texture: c.GLuint = undefined,
        interested: std.ArrayList([]const u8)
    },

    state: struct { paused: bool = false} = .{},

    // TODO: maybe load defaults to shader string/file at runtime
    defaults: struct {
        // name -> location
        uniforms: std.StringHashMap(c.GLint),

        viewport: struct {
            width: f32 = 0.0,
            height: f32 = 0.0
        } = .{},

        time: f64 = 0.0
    },

    user: struct {
        // name -> location
        uniforms: std.StringHashMap(c.GLint),
    },

    // compile time paths are relative to the source file
    // while runtime paths are relative to cwd of execution
    const VERTEX_PATH = "shader.vs";
    const FRAGMENT_DEFAULT_PATH = "src/shader_defaults.fs";

    pub fn addDefaultUniformLocation(self: *@This(), uniform: []const u8) !void {
        try self.defaults.uniforms.put(uniform, c.glGetUniformLocation(self.program, try self.allocator.dupeZ(u8, uniform)));
    }

    pub fn init(self: *@This(), shader_path: []const u8, alloc: std.mem.Allocator) !void {
        self.* = .{
            .allocator = alloc,
            .path = shader_path,
            .watcher = try Watcher.init(shader_path, alloc),

            .shared = .{
                .interested = std.ArrayList([]const u8).init(alloc)
            },

            .defaults = .{
                .uniforms = @TypeOf(self.defaults.uniforms).init(alloc)
            },
            .user = .{
                .uniforms = @TypeOf(self.user.uniforms).init(alloc)
            }
        };

        c.glGenTextures(1, &self.shared.texture);
        c.glBindTexture(c.GL_TEXTURE_2D, self.shared.texture);
        c.glTexImage2D(
            c.GL_TEXTURE_2D,
            0,
            c.GL_RED,
            1, SHARED_MEM,
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_BYTE,
            null
        );
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

        try self.reload();
    }

    pub fn deinit(self: *@This()) void {
        c.glDeleteProgram(self.program);
        c.glDeleteTextures(1, &self.shared.texture);
        self.shared.interested.deinit();

        self.watcher.deinit();

        self.defaults.uniforms.deinit();
        self.user.uniforms.deinit();
    }

    fn updateUniforms(self: *@This()) void {
        c.glUniform1f(self.defaults.uniforms.get("u_time").?, @floatCast(self.defaults.time));
        c.glUniform1i(self.defaults.uniforms.get("u_private_shared").?, SHARED_TEX);
        // viewport is changed on change somewhere else
    }

    fn updateUniformLocations(self: *@This()) !void {
        try self.addDefaultUniformLocation("u_time");
        try self.addDefaultUniformLocation("u_viewport");
        try self.addDefaultUniformLocation("u_private_shared");
        // TODO: user ones
    }

    pub fn update(self: *@This()) void {
        if(self.state.paused) {
            c.glfwSetTime(self.defaults.time);
        } else {
            self.defaults.time = c.glfwGetTime();
        }

        self.updateUniforms();

        // printStruct(self.defaults);
    }

    pub fn updateViewportUniform(self: *@This()) void {
        c.glUniform2f(
            self.defaults.uniforms.get("u_viewport").?,
            self.defaults.viewport.width,
            self.defaults.viewport.height,
        );
    }

    /// called by users using "// @special"
    const Specials = enum {pause, reset, tick, inspect, override};

    /// look for @special" in `specials` and modifiers the source bufer to remove them for compilation
    /// returns new size of file
    fn analyse(self: *@This(), source: std.fs.File, buffer: *std.ArrayList(u8)) !void {
        self.state = .{};

        var buf_reader = std.io.bufferedReader(source.reader());
        var reader = buf_reader.reader();
        var line_buffer: [1024]u8 = undefined;

        // stack of specials that effect the next line of source code
        var special_stack = std.ArrayList(struct {kind: Specials}).init(self.allocator);
        defer special_stack.deinit();

        while(try reader.readUntilDelimiterOrEof(&line_buffer, '\n')) |original_line| {
            try buffer.appendSlice(original_line);
            try buffer.append('\n');

            const line = std.mem.trimLeft(u8, original_line, " ");
            var special_toks = std.mem.splitScalar(u8, line, ' ');
            var special_ident = special_toks.next() orelse break;
            if(special_ident.len == 0) continue;

            if(special_ident[0] == '@') {
                const variant = std.meta.stringToEnum(Specials, special_ident[1..]) orelse return error.invalidSpecial;

                // if we found a special then let the next line overwrite the prev buffer line so that the shader compiles
                buffer.items.len -= original_line.len + "\n".len;

                switch(variant) {
                    .pause  => self.state.paused = true,
                    .reset  => c.glfwSetTime(0.0),
                    .tick   => self.defaults.time += @as(f64, @floatFromInt(try std.fmt.parseInt(i16, special_toks.next() orelse "1", 10))) * 0.016, // very hacky fix
                    else    => try special_stack.append(.{.kind = variant}),
                }

                continue;
            }

            const special = special_stack.popOrNull() orelse continue;
            // TODO: actual parser after the special but for now we can just assume its a valid variable
            switch(special.kind) {
                .inspect => {
                    std.log.debug("s: {s}", .{special_ident});
                },
                .override => continue,
                else => unreachable
            }
        }
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

        var fragment_source = try std.ArrayList(u8).initCapacity(self.allocator, user_fs + defaults_fs + 1);
        defer fragment_source.deinit();

        fragment_source.appendSliceAssumeCapacity(try defaults_file.readToEndAlloc(self.allocator, user_fs));
        try self.analyse(user_file, &fragment_source);
        try fragment_source.append(0);

        self.program = shaderMake(VERTEX_PATH, &fragment_source) catch {
            var lines = std.mem.splitScalar(u8, @embedFile("shader_defaults.fs"), '\n');
            var line_amount: u64 = 0;
            while(lines.next() != null) : (line_amount += 1) {}
            line_amount -= 1;
            std.log.info("line offset from defaults: {d}", .{line_amount});
            return error.failedToMakeShader;
        };
        if(self.program != 0) c.glDeleteProgram(self.program);
        c.glUseProgram(self.program);

        try self.updateUniformLocations();
        self.updateUniforms();
        self.updateViewportUniform();

        // std.log.info("\rreloaded shader \"{s}\":\n{s}", .{self.path, fragment_source[0..defaults_fs+size]});
    }

    // needs to be called from the main thread
    pub fn reloadOnChange(self: *@This()) !void {
        if(!self.watcher.state.modified)
            return;

        self.watcher.state.modified = false;
        // clear screen and reset cursor escape codes
        // TODO: better way
        _ = try std.io.getStdIn().writer().write("\x1b[2J\x1b[H");
        try self.reload();
        // printStruct(self.state);
    }
};

const Watcher = struct {
    allocator: std.mem.Allocator,

    inotify_fd: i32,
    mutex: std.Thread.Mutex = .{},
    thread: std.Thread,

    path: []const u8,
    state: struct {playing: bool = true, modified: bool = false} = .{},

    fn inotify_add(self: *@This()) !void {
        _ = try std.posix.inotify_add_watch(self.inotify_fd, self.path, std.os.linux.IN.MODIFY);
    }

    fn init(path: []const u8, alloc: std.mem.Allocator) !*@This() {
        const self: *@This() = try alloc.create(@This());
        self.* = .{
            .allocator = alloc,
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
        self.allocator.destroy(self);
    }

    // should run on different thread
    // sets state if file was changed
    fn watch(self: *@This()) !void {
        var buffer: [4096]std.os.linux.inotify_event = undefined;

        while(self.state.playing) {
            const length = std.posix.read(self.inotify_fd, std.mem.sliceAsBytes(&buffer))
                catch |err| switch(err) {
                    error.WouldBlock => {
                        std.time.sleep(100 * std.time.ns_per_ms);
                        continue;
                    },
                    else => return err
                };

            var i: u32 = 0;
            while(i < length) : (i += buffer[i].len + @sizeOf(std.os.linux.inotify_event)) {
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
