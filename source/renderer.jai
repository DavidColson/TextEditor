
RendererState :: struct {
	window: Window_Type;

	instanceVbo: GLuint;
	vao: GLuint;
	vertexShader: GLuint;
	fragmentShader: GLuint;
	program: GLuint;
	resolutionUniformLocation: GLint;
	whiteDefaultTex: GLuint;

    MAX_INSTANCES :: 2400;
    instances: [MAX_INSTANCES] Instance;
	numInstances: s32;

	MAX_GROUPS :: 256;
	instanceGroups: [MAX_GROUPS]InstanceGroup;
	numGroups: s32;

	testBitmap: Bitmap;
}
renderState: RendererState;

InstanceGroup :: struct {
	instanceStart: s32;
	instanceEnd: s32;
	texture: *Bitmap;
}

Instance :: struct {
	dstRect: Rect;
	srcRect: Rect;
	color: Vector4;
	cornerRadii: Vector4;
	edgeSoftness: float; // negative will result in inverse rounded corners
	borderThickness: float;
}

Bitmap :: struct {
	width: s32;
	height: s32;

	data: []u8;
	texHandle: GLuint;
	format: BitmapFormat;
}

BitmapFormat :: enum {
	RGBA8;
	R8;
}

init_renderer :: (_window: Window_Type) {
	using renderState;
	window = _window;

	// all initialization
	gl_create_context(window, 4, 2);

	gl_load(*gl);
	gl_enable_debug_output(break_on_error = true);

	glViewport(0, 0, xx windowWidth, xx windowHeight);

	numInstances = 0;
	numGroups = 0;

	// make vertex shader
	{
		shaderSource := VERTEX_SHADER.data;
		vertexShader = glCreateShader(GL_VERTEX_SHADER);
		glShaderSource(vertexShader, 1, *shaderSource, null);
		glCompileShader(vertexShader);
		report_shader_errors(vertexShader, "Vertex");

        DumpGLErrors("vertex shader");
	}
	// make fragment shader
	{
		shaderSource := FRAGMENT_SHADER.data;
		fragmentShader = glCreateShader(GL_FRAGMENT_SHADER);
		glShaderSource(fragmentShader, 1,  *shaderSource, null);
		glCompileShader(fragmentShader);
		report_shader_errors(fragmentShader, "Fragment");

        DumpGLErrors("fragment shader");
	}
	// make program
	{
		program = glCreateProgram();
		glAttachShader(program, vertexShader);
		glAttachShader(program, fragmentShader);
		glLinkProgram(program);

		resolutionUniformLocation = glGetUniformLocation(program, "resolution");

        DumpGLErrors("program");
	}
	// setup the VAO
	{
		glGenVertexArrays(1, *vao);
		glGenBuffers(1, *instanceVbo);

		glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, instanceVbo);

		T :: Instance;
		stride : u32 = size_of(T);
		offset: *T: null;

		// dstRect
		glEnableVertexAttribArray(0);
		glVertexAttribPointer(0, 4, GL_FLOAT, xx false, stride, xx *offset.dstRect);
		glVertexAttribDivisor(0, 1); // update the attribute once per instance

		// srcRect
		glEnableVertexAttribArray(1);
		glVertexAttribPointer(1, 4, GL_FLOAT, xx false, stride, xx *offset.srcRect);
		glVertexAttribDivisor(1, 1);

		// color
		glEnableVertexAttribArray(2);
		glVertexAttribPointer(2, 4, GL_FLOAT, xx false, stride, xx *offset.color);
		glVertexAttribDivisor(2, 1);

		// cornerRadii
		glEnableVertexAttribArray(3);
		glVertexAttribPointer(3, 4, GL_FLOAT, xx false, stride, xx *offset.cornerRadii);
		glVertexAttribDivisor(3, 1);

		// edgeSoftness
		glEnableVertexAttribArray(4);
		glVertexAttribPointer(4, 1, GL_FLOAT, xx false, stride, xx *offset.edgeSoftness);
		glVertexAttribDivisor(4, 1);

		// borderThickness
		glEnableVertexAttribArray(5);
		glVertexAttribPointer(5, 1, GL_FLOAT, xx false, stride, xx *offset.borderThickness);
		glVertexAttribDivisor(5, 1);

		DumpGLErrors("vao");
	}

	// test texture loading
	{
		testBitmap = make_bitmap_from_file(tprint("%../../fonts/house-solid.png", path_strip_filename(get_path_of_running_executable())));
		load_bitmap_to_gpu(*testBitmap);
	}

	// create default white texture
	{
		glGenTextures(1, *whiteDefaultTex);
		glBindTexture(GL_TEXTURE_2D, whiteDefaultTex);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_REPEAT);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_REPEAT);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		whiteData: []u8 = .[0xFF, 0xFF, 0xFF, 0xFF];
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, whiteData.data);
		glGenerateMipmap(GL_TEXTURE_2D);
		glBindTexture(GL_TEXTURE_2D, 0);
	}

	// blending setup
	{
		glEnable(GL_BLEND);
		glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);  
	}
}

render_frame :: () {
	using renderState;

	c := hex_to_color_vec4("282c34");
    glClearColor(c.x, c.y, c.z, 0.0);
	glClear(GL_COLOR_BUFFER_BIT);

	glBindVertexArray(vao);
	glBindBuffer(GL_ARRAY_BUFFER, instanceVbo);
	glBufferData(GL_ARRAY_BUFFER, size_of(Instance) * numInstances, instances.data, GL_STREAM_DRAW);

	glUseProgram(program);
	resolutionUniformLocation = glGetUniformLocation(program, "resolution");
	glUniform2f(resolutionUniformLocation, xx windowWidth, xx windowHeight);

	for 0..numGroups-1 {
		instance := *instanceGroups[it];
		if instance.texture == null {
			glBindTexture(GL_TEXTURE_2D, whiteDefaultTex);
		}
		else {
			glBindTexture(GL_TEXTURE_2D, instance.texture.texHandle);
		}

		count := instance.instanceEnd - instance.instanceStart;
		glDrawArraysInstancedBaseInstance(GL_TRIANGLES, 0, 6, xx count, xx instance.instanceStart);
	}

	platform_swap_buffers(window);

	numInstances = 0;
	numGroups = 0;
}

// @todo: could groups be automatic?
// you just submit your instance with it's texture data
// if the texture is different (or any other parameter) to the one used
// in the current instance, then you split off into a new group
start_instance_group :: (tex: *Bitmap = null) {
	using renderState;
	instanceGroups[numGroups] = .{numInstances, 0, tex};
	numGroups += 1;
}

submit_instance :: (instance: Instance) {
	using renderState;
	instances[numInstances] = instance;
	numInstances += 1;
}

end_instance_group :: () {
	using renderState;
	instanceGroups[numGroups-1].instanceEnd = numInstances;
}

resize_backbuffer :: () {
	glViewport(0, 0, xx windowWidth, xx windowHeight);
}

make_bitmap_from_file :: (path: string) -> Bitmap {
	bitmap: Bitmap;
	w, h, channels: s32;
	stbi_set_flip_vertically_on_load(1);
	bitmap.data.data = stbi_load(temp_c_string(path), *w, *h, *channels, 0); 
	bitmap.data.count = channels * w * h; 
	bitmap.width = w;
	bitmap.height = h;
	bitmap.format = .RGBA8;

	return bitmap;
}

alloc_bitmap :: (bitmap: *Bitmap, w: s32, h: s32, format: BitmapFormat) {
	bytesPerPixel := 1;
	if format == .RGBA8 {
		bytesPerPixel = 4;
	}
	
	size := bytesPerPixel * w * h;
	bitmap.data = NewArray(size, u8);
	bitmap.format = format;
	bitmap.width = w;
	bitmap.height = h;
}

load_bitmap_to_gpu :: (bitmap: *Bitmap) {
	glGenTextures(1, *bitmap.texHandle);
	glBindTexture(GL_TEXTURE_2D, bitmap.texHandle);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S,     GL_CLAMP_TO_BORDER);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T,     GL_CLAMP_TO_BORDER);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);

	glformat := GL_RGBA;
	if bitmap.format == .R8 {
		glformat = GL_RED;
	}
	glTexImage2D(GL_TEXTURE_2D, 0, xx glformat, xx bitmap.width, xx bitmap.height, 0, xx glformat, GL_UNSIGNED_BYTE, bitmap.data.data);

	glGenerateMipmap(GL_TEXTURE_2D);
	glBindTexture(GL_TEXTURE_2D, 0);
}

#import "GL"(DUMP_GL_ERRORS=true);
#import "stb_image";

#scope_file

report_shader_errors :: (shader: GLuint, shaderName: string) {
	success : GLint;
	glGetShaderiv(shader, GL_COMPILE_STATUS, *success);

	if !success then {
		log_data: [512] u8;
		glGetShaderInfoLog(shader, log_data.count, null, log_data.data);
		log("%:\n%", shaderName, to_string(log_data.data), flags=.ERROR);
	}
}


VERTEX_SHADER :: #string END
#version 330 core
layout (location = 0) in vec4 dstRect;
layout (location = 1) in vec4 srcRect;
layout (location = 2) in vec4 inColor;
layout (location = 3) in vec4 inCornerRadii;
layout (location = 4) in float inEdgeSoftness;
layout (location = 5) in float inBorderThickness;

uniform vec2 resolution;
uniform sampler2D bitmap;

out vec2 dstSize;
out vec2 uv;
out vec4 color;
out vec4 cornerRadii;
out float edgeSoftness;
out float borderThickness;

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

	vec2 screenPos = dstRect.xy + (quadVerts[gl_VertexID]) * dstRect.zw;

	vec2 pos;
	pos.x = (screenPos.x / resolution.x) * 2.0 - 1.0;
	pos.y = 1.0 - (screenPos.y / resolution.y) * 2.0;

    gl_Position = vec4(pos, 0.0, 1.0);

	vec2 texSize = textureSize(bitmap, 0);
	uv = srcRect.xy + quadVerts[gl_VertexID] * srcRect.zw;
	uv.x = uv.x / texSize.x;
	uv.y = 1.0 - uv.y / texSize.y;

	color = inColor; 
	cornerRadii = inCornerRadii;
	edgeSoftness = inEdgeSoftness;
	borderThickness = inBorderThickness;
	dstSize = dstRect.zw;
}
END

FRAGMENT_SHADER :: #string END
#version 330 core
out vec4 FragColor;

uniform sampler2D bitmap;

in vec2 dstSize;
in vec2 uv;
in vec4 color;
in vec4 cornerRadii;
in float edgeSoftness;
in float borderThickness;

float sdfRoundedBox(vec2 pt, vec2 halfDimensions, vec4 radii)
{
    radii.xy = (pt.x > 0.0) ? radii.zw : radii.yx;
    radii.x = (pt.y > 0.0) ? radii.x : radii.y;
    vec2 q = abs(pt) - halfDimensions + radii.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radii.x;
}

void main()
{
    FragColor = color * texture(bitmap, uv);

	vec2 softnessPadding = vec2(max(0, edgeSoftness-1), max(0, edgeSoftness-1));
	vec2 pt = (uv - vec2(0.5, 0.5)) * dstSize; 
	vec2 halfSize = (dstSize/2) - softnessPadding;

	float borderFactor = 1.0;
	if (borderThickness != 0.0) {

		vec2 interiorHalfSize = (dstSize/2) - softnessPadding - borderThickness;
		float interiorRadiusReduce = min(interiorHalfSize.x/halfSize.x, interiorHalfSize.y/halfSize.y);
		vec4 interiorRadii = cornerRadii * (interiorRadiusReduce*interiorRadiusReduce);
		float dist = sdfRoundedBox(pt, interiorHalfSize, interiorRadii);
		borderFactor = smoothstep(-edgeSoftness, 0, dist);
	}

	float dist = sdfRoundedBox(pt, halfSize, cornerRadii);
	float mainSDFfactor = 1 - smoothstep(-edgeSoftness, 0, dist);

	FragColor.a *= mainSDFfactor * borderFactor;
} 
END
