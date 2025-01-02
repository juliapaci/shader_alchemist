const std = @import("std");
const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
});

fn framebuffer_size_callback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    c.glViewport(0, 0, width, height);

    const renderer: ?*Renderer = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));
    renderer.?.viewport.width = width;
    renderer.?.viewport.height = height;

    c.glUniform2f(
        c.glGetUniformLocation(renderer.?.shader, "u_viewport"),
        @floatFromInt(width),
        @floatFromInt(height)
    );
}

const WindowCreationError = error{
    glfwInit,
    glfwWindowCreation,
    gladLoading
};

pub fn createWindow() !*c.GLFWwindow {
    if (c.glfwInit() == 0)
        return error.glfwInit;
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
    c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 3);
    c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);

    const window = c.glfwCreateWindow(800, 600, "dreamscape", null, null);
    errdefer c.glfwTerminate();
    if (window == null)
        return error.glfwWindowCreation;
    c.glfwMakeContextCurrent(window);

    _ = c.glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);

    if (c.gladLoadGLLoader(@ptrCast(&c.glfwGetProcAddress)) == c.GL_FALSE)
        return error.gladLoading;

    // remove optional pointer since we wouldve propagated the error already
    return @ptrCast(window);
}

pub const Renderer = struct {
    vao: c.GLuint,
    ibo: c.GLuint,
    vbo: c.GLuint,

    shader_name: []const u8,
    shader: c.GLuint,

    viewport: struct {
        width: c_int,
        height: c_int
    },

    fn initBuffers(self: *@This()) !void {
        c.glGenVertexArrays(1, &self.vao);
        c.glBindVertexArray(self.vao);

        const indices = [6]c.GLuint{ 0, 1, 2, 0, 3, 2 };
        c.glGenBuffers(1, &self.ibo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, self.ibo);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, c.GL_STATIC_DRAW);

        const vertices = [_]c.GLfloat{0} ** 4;
        c.glGenBuffers(1, &self.vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, self.vbo);
        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, c.GL_STATIC_DRAW);

        c.glVertexAttribPointer(0, 1, c.GL_FLOAT, c.GL_FALSE, @sizeOf(c.GLfloat), null);
        c.glEnableVertexAttribArray(0);
    }

    fn shaderErrorCheck(shader: c.GLuint, pname: c.GLenum) !void {
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

    fn reload(self: *@This()) !void {
        if(self.shader != 0)
            c.glDeleteProgram(self.shader);

        const defaults_file = try std.fs.cwd().openFile("src/shader_defaults.fs", .{});
        defer defaults_file.close();
        const defaults_file_size = try defaults_file.getEndPos();

        const user_file = try std.fs.cwd().openFile(self.shader_name, .{});
        defer user_file.close();
        const user_file_size = try user_file.getEndPos();

        const fragment_source = try std.heap.page_allocator.alloc(u8, user_file_size + defaults_file_size + 1);
        defer std.heap.page_allocator.free(fragment_source);

        _ = try defaults_file.readAll(fragment_source[0..defaults_file_size]);
        _ = try user_file.readAll(fragment_source[defaults_file_size..defaults_file_size + user_file_size]);
        fragment_source[defaults_file_size + user_file_size] = 0;
        std.debug.print("shader source:\n{s}\n", .{fragment_source});

        self.shader = try shaderMake("shader.vs", @ptrCast(@alignCast(fragment_source)));

        c.glUseProgram(self.shader);
    }

    pub fn init(shader_name: []const u8) !@This() {
        var self: @This() = undefined;
        try self.initBuffers();

        self.shader_name = shader_name;
        try self.reload();

        return self;
    }

    pub fn free(self: *@This()) void {
        c.glDeleteVertexArrays(1, &self.vao);
        c.glDeleteBuffers(1, &self.vbo);
        c.glDeleteBuffers(1, &self.ibo);

        c.glDeleteProgram(self.shader);
    }

    pub fn draw() void {
        c.glClearColor(0.1, 0.1, 0.1, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
    }
};
