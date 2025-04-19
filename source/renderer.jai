
RendererState :: struct {
	window: Window_Type;

	instanceVbo: GLuint;
	vao: GLuint;
	vertexShader: GLuint;
	fragmentShader: GLuint;
	program: GLuint;
	resolutionUniformLocation: GLint;

    MAX_INSTANCES :: 2400;
    instances: [MAX_INSTANCES] Instance;
	numInstances: s32;
}
renderState: RendererState;

Instance :: struct {
	rect: Rect;
}

init_renderer :: (_window: Window_Type) {
	using renderState;
	window = _window;

	// all initialization
	gl_create_context(window, 3, 3);

	gl_load(*gl);
	gl_enable_debug_output(break_on_error = true);

	glViewport(0, 0, xx windowWidth, xx windowHeight);

	numInstances = 0;
	instances[numInstances] = .{Rect.{ 5.0, 5.0, 100.0, 100.0}}; numInstances += 1;
	instances[numInstances] = .{Rect.{ 100.0, 100.0, 200.0, 100.0}}; numInstances += 1;
	instances[numInstances] = .{Rect.{ 10.0,  400.0, 50.0, 50.0}}; numInstances += 1;

	// make vertex shader
	{
		shaderSource := VERTEX_SHADER.data;
		vertexShader = glCreateShader(GL_VERTEX_SHADER);
		glShaderSource(vertexShader, 1, *shaderSource, null);
		glCompileShader(vertexShader);
		report_shader_errors(vertexShader);
	}
	// make fragment shader
	{
		shaderSource := FRAGMENT_SHADER.data;
		fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
		glShaderSource(fragmentShader, 1,  *shaderSource, null);
		glCompileShader(fragmentShader);
		report_shader_errors(vertexShader);
	}
	// make program
	{
		program = glCreateProgram();
		glAttachShader(program, vertexShader);
		glAttachShader(program, fragmentShader);
		glLinkProgram(program);

		resolutionUniformLocation = glGetUniformLocation(program, "resolution");
	}
	// setup the VAO
	{
		glGenVertexArrays(1, *vao);
		glGenBuffers(1, *instanceVbo);
		glBindVertexArray(vao);

		glBindBuffer(GL_ARRAY_BUFFER, instanceVbo);
		glBufferData(GL_ARRAY_BUFFER, size_of(Instance) * numInstances, instances.data, GL_STATIC_DRAW);

		glEnableVertexAttribArray(0);
		glVertexAttribPointer(0, 4, GL_FLOAT, xx false, 4 * size_of(float), xx 0);
		glVertexAttribDivisor(0, 1); // update the attribute once per instance
	}

}

render_frame :: () {
	using renderState;

	c,_ := hex_to_color_vec4("282c34");
    glClearColor(c.x, c.y, c.z, 0.0);

	glClear(GL_COLOR_BUFFER_BIT);

	glUseProgram(program);

	resolutionUniformLocation = glGetUniformLocation(program, "resolution");
	glUniform2f(resolutionUniformLocation, xx windowWidth, xx windowHeight);
	glBindVertexArray(vao);
	glDrawArraysInstanced(GL_TRIANGLES, 0, 6, 3);

	platform_swap_buffers(window);
}

renderer_resize_backbuffer :: () {
	glViewport(0, 0, xx windowWidth, xx windowHeight);
}

#import "GL";

#scope_file

report_shader_errors :: (shader: GLuint) {
	success : GLint;
	glGetShaderiv(shader, GL_COMPILE_STATUS, *success);

	if !success then {
		log_data: [512] u8;
		glGetShaderInfoLog(shader, log_data.count, null, log_data.data);
		log("%", to_string(log_data.data), flags=.ERROR);
	}
}

VERTEX_SHADER :: #string END
#version 330 core
layout (location = 0) in vec4 rect;

uniform vec2 resolution;

void main()
{
	vec2 quadVerts[6] = vec2[](
        vec2( 0.0,  0.0),
        vec2( 1.0,  0.0),
        vec2( 1.0,  1.0),
        vec2( 0.0,  0.0),
        vec2( 1.0,  1.0),
        vec2( 0.0,  1.0)
    );

	vec2 screenPos = rect.xy + (quadVerts[gl_VertexID]) * rect.zw;

	vec2 pos;
	pos.x = (screenPos.x / resolution.x) * 2.0 - 1.0;
	pos.y = 1.0 - (screenPos.y / resolution.y) * 2.0;

    gl_Position = vec4(pos, 0.0, 1.0);
}
END

FRAGMENT_SHADER :: #string END
#version 330 core
out vec4 FragColor;

void main()
{
    FragColor = vec4(1.0f, 0.5f, 0.2f, 1.0f);
} 
END
