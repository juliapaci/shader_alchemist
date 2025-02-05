const std = @import("std");
const ren = @import("renderer.zig");
const c = @cImport({
    @cInclude("glad/glad.h");
    @cInclude("GLFW/glfw3.h");
});

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const window = ren.createWindow() catch |err| {
        std.log.err("window creation error: {s}", .{@errorName(err)});
        return;
    };
    defer c.glfwTerminate();

    var args = std.process.argsWithAllocator(allocator) catch {return;};
    if(!args.skip()) return;
    defer args.deinit();

    const shader = args.next();
    if(shader == null) {
        std.log.err("please supply a shader file to load", .{});
        return;
    }

    var renderer = ren.Renderer.init(shader.?, allocator) catch |err| {
        std.log.err("failed to initialise: {s}", .{@errorName(err)});
        return;
    };
    defer renderer.deinit();
    c.glfwSetWindowUserPointer(window, &renderer);

    while (c.glfwWindowShouldClose(window) == c.GLFW_FALSE) {
        ren.Renderer.draw();
        try renderer.shader.reloadOnChange();
        renderer.shader.update();

        if (c.glfwGetKey(window, c.GLFW_KEY_ESCAPE) == c.GLFW_PRESS)
            c.glfwSetWindowShouldClose(window, c.GLFW_TRUE);

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }
}
