const std = @import("std");
const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
});
const shader = @import("shader.zig");

fn framebuffer_size_callback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    c.glViewport(0, 0, width, height);

    const renderer: ?*Renderer = @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)));

    // TODO: need better api for defaults updates
    renderer.?.shader.lock.lock();
    defer renderer.?.shader.lock.unlock();
    renderer.?.shader.defaults.viewport = .{
        .width = @floatFromInt(width),
        .height = @floatFromInt(height)
    };

    c.glUniform2f(
        c.glGetUniformLocation(renderer.?.shader.program, "u_viewport"),
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

    const window = c.glfwCreateWindow(800, 600, "shader alchemist", null, null);
    errdefer c.glfwTerminate();
    if (window == null)
        return error.glfwWindowCreation;
    c.glfwMakeContextCurrent(window);

    _ = c.glfwSetFramebufferSizeCallback(window, framebuffer_size_callback);

    if (c.gladLoadGLLoader(@ptrCast(&c.glfwGetProcAddress)) == c.GL_FALSE)
        return error.gladLoading;

    return @ptrCast(window);
}

pub const Renderer = struct {
    vao: c.GLuint,
    ibo: c.GLuint,
    vbo: c.GLuint,

    shader: *shader.Shader,

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

    pub fn init(shader_name: []const u8) !@This() {
        var self: @This() = undefined;
        try self.initBuffers();
        c.glEnable(c.GL_BLEND);
        c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
        self.shader = try shader.Shader.init(shader_name);

        return self;
    }

    pub fn free(self: *@This()) void {
        c.glDeleteVertexArrays(1, &self.vao);
        c.glDeleteBuffers(1, &self.vbo);
        c.glDeleteBuffers(1, &self.ibo);

        self.shader.free();
    }

    pub fn draw() void {
        c.glClearColor(0.1, 0.1, 0.1, 1);
        c.glClear(c.GL_COLOR_BUFFER_BIT);

        c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
    }
};
