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

    // TODO: maybe load defaults to string/file at runtime
    defaults: struct {
        viewport: struct {
            width: f32 = 0.0,
            height: f32 = 0.0
        } = .{}
    } = .{},

    user: struct {
        // name -> location
        uniforms: std.StringHashMap(c.GLuint) = std.StringHashMap(c.GLuint).init(allocator)
    } = .{},

    // compile time paths are relative to the source file
    // while runtime paths are relative to cwd of execution
    const VERTEX_PATH = "shader.vs";
    const FRAGMENT_DEFAULT_PATH = "src/shader_defaults.fs";

    pub fn init(shader_path: []const u8) !*@This() {
        const self: *@This() = try allocator.create(@This());

        self.* = .{
            .path = shader_path,
            .watcher = try std.Thread.spawn(.{}, watch, .{self})
        };
        self.watcher.detach();

        return self;
    }

    pub fn free(self: *@This()) void {
        c.glDeleteProgram(self.program);
        self.user.uniforms.deinit();

        allocator.destroy(self);
    }

    fn reload(self: *@This()) !void {
        self.lock.lock();
        defer self.lock.unlock();

        if(self.program != 0)
            c.glDeleteProgram(self.program);

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

        self.program = try shaderMake(VERTEX_PATH, @ptrCast(@alignCast(fragment_source)));
        c.glUseProgram(self.program);

        std.debug.print("reloaded shader \"{s}\":\n{s}\n", .{self.path, fragment_source});
    }

    // should run on different thread
    // sets state if file was changed
    fn watch(self: *@This()) !void {
        var last: i128 = 0;

        while(true) {
            const stat = try std.fs.cwd().statFile(self.path);
            if(stat.mtime != last) {
                last = stat.mtime;
                std.debug.print("shader changed at {d}\n", .{last});
                self.lock.lock();
                self.modified = true;
                self.lock.unlock();
            }

            std.time.sleep(std.time.ns_per_s);
        }
    }

    // needs to be called from the main thread
    pub fn reload_on_change(self: *@This()) !void {
        if(self.modified) {
            self.modified = false;
            try self.reload();
        }
    }
};
