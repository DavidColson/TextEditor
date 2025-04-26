
// fonts?

// how should this work?

// consider how the renderer will work
// when you draw text, we will want to produce however many instance groups are required to render said text
// drawing code (with colors n shit) is ultimately not that different really, 
// presumably draw text will allow ranges with colors and boldness etc, other highlights


// this is presumably what we'll store in the atlas information

Font :: struct {
	fileData: []u8;

	face: FT_Face;

	atlasList: [..]Atlas;

	pool: Flat_Pool;
	allocator: Allocator;

	// some kind of lookup
	// codepoint to atlas id and glyph id
}

Glyph :: struct {
	uv: Rect;
	// drawing metrics go here
}

Atlas :: struct {
	// texture: Texture;
	glyphs: [..]Glyph;

	nodes: [..]AtlasNode;
	width: s32;
	height: s32;
}

AtlasNode :: struct {
	x: s32;
	y: s32;
	width: s32;
}

TextRun :: struct {
	// list of glyphs ready to render
	// bounds/dimensions
}

init_font_cache :: () {
	// initialize freetype
	error := FT_Init_FreeType(*freetype);
	assert(!error);

	// load default fonts
	// @todo: shouldn't really be in this file, cleanup at some point
	path := tprint("%../../fonts/FiraMonoNerdFontMono-Medium.ttf", path_strip_filename(get_path_of_running_executable()));
	defaultFont = load_font(path, textSize);
}

load_font :: (path: string, sizePixels: int) -> *Font {
	font := New(Font);
	font.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *font.pool };
	font.atlasList.allocator = font.allocator;

	// load the file
	file, success := read_entire_file(path,,font.allocator);
	assert(success);
	font.fileData.data = file.data;
	font.fileData.count = file.count;

	error := FT_New_Memory_Face(freetype, file.data, xx file.count, 0, *font.face);
	assert(!error);

	FT_Set_Pixel_Sizes(font.face, 0, xx sizePixels);

	// setup our first atlas
	atlas := array_add(*font.atlasList);
	atlas.nodes.allocator = font.allocator;
	atlas.width = 1024;
	atlas.height = 1024;

	initialNode := array_add(*atlas.nodes);
	initialNode.x = 0;
	initialNode.y = 0;
	initialNode.width = atlas.width;

	// generate an ascii atlas first
	for 0..127 {

	}

	return font;
}

draw_text :: (text: string) {
	// generate line of text, produce render instances from it
}

#scope_file

freetype : FT_Library;
// @todo: move outside
defaultFont : *Font;

#import "freetype-2.12.1";
