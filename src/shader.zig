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

    lock: std.Thread.Mutex = .{},
    watcher: std.Thread,
    modified: bool = false,

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

    pub fn init(shader_path: []const u8) !*@This() {
        var self: *@This() = try allocator.create(@This());

        self.* = .{
            .path = shader_path,
            .watcher = try std.Thread.spawn(.{}, watch, .{self})
        };
        self.watcher.detach();

        try self.defaults.uniforms.put("u_time", 0);

        return self;
    }

    pub fn free(self: *@This()) void {
        c.glDeleteProgram(self.program);

        self.defaults.uniforms.deinit();
        self.user.uniforms.deinit();

        allocator.destroy(self);
    }

    fn update_uniforms(self: *@This()) void {
        if(!self.state.paused)
            c.glUniform1f(self.defaults.uniforms.get("u_time").?, @floatCast(self.defaults.time));
    }

    pub fn update(self: *@This()) void {
        self.defaults.time = c.glfwGetTime();

        self.update_uniforms();
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
        self.lock.lock();
        defer self.lock.unlock();

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

    // should run on different thread
    // sets state if file was changed
    // TODO: inotify?
    fn watch(self: *@This()) !void {
        var last: i128 = 0;

        while(true) {
            const stat = try std.fs.cwd().statFile(self.path);
            if(stat.mtime != last) {
                last = stat.mtime;
                std.log.info("shader changed at {d}", .{last});
                self.lock.lock();
                self.modified = true;
                self.lock.unlock();
            }

            std.time.sleep(std.time.ns_per_s);
        }
    }

    // needs to be called from the main thread
    pub fn reload_on_change(self: *@This()) !void {
        if(!self.modified)
            return;

        self.modified = false;
        // clear screen and reset cursor escape codes
        _ = try std.io.getStdIn().writer().write("\x1b[2J\x1b[H");
        try self.reload();
    }
};
