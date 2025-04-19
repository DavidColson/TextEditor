
RendererState :: struct {
	window: Window_Type;
}
renderState: RendererState;

init_renderer :: (window: Window_Type) {
	renderState.window = window;

	// all initialization
	gl_create_context(window, 3, 3);

	// shaders, programs etc
}

render_frame :: () {
	c,_ := hex_to_color_vec4("282c34");
    glClearColor(c.x, c.y, c.z, 0.0);

	glClear(GL_COLOR_BUFFER_BIT);

	platform_swap_buffers(renderState.window);
}

#import "GL";
