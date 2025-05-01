
// fonts?

// how should this work?

// consider how the renderer will work
// when you draw text, we will want to produce however many instance groups are required to render said text
// drawing code (with colors n shit) is ultimately not that different really, 
// presumably draw text will allow ranges with colors and boldness etc, other highlights


// this is presumably what we'll store in the atlas information

FontCache :: struct {
	freetype : FT_Library;
	atlasList: [..]Atlas;
	pool: Flat_Pool;
	allocator: Allocator;
}

Font :: struct {
	fileData: []u8;
	face: FT_Face;

	// keyed by size currently
	styleTable: Table(int, FontStyle);
}

FontStyle :: struct {
	// keyed by glyphIndex in the font face
	glyphTable: Table(u32, GlyphData);

	// metrics
	characterHeight: int;
	typicalAscender: int;
	typicalDescender: int;
}

GlyphData :: struct {
	atlas: s32;
	subRect: Rect;
	offsetX: s32;
	offsetY: s32;
	advance: s32;
}

TextRun :: struct {
	glyphs: []GlyphData;
	// in pixels
	height: s32;
	width: s32; 
}

init_font_cache :: () {
	// initialize freetype
	error := FT_Init_FreeType(*fontCache.freetype);
	assert(!error);

	fontCache.allocator = Allocator.{ proc = flat_pool_allocator_proc, data = *fontCache.pool };
	fontCache.atlasList.allocator = fontCache.allocator;

	// setup our first atlas
	atlas := array_add(*fontCache.atlasList);
	atlas.nodes.allocator = fontCache.allocator;
	alloc_bitmap(*atlas.texture, 1024, 1024, .R8,,fontCache.allocator);

	initialNode := array_add(*atlas.nodes);
	initialNode.x = 0;
	initialNode.y = 0;
	initialNode.width = atlas.texture.width;

	// load default fonts
	// @todo: shouldn't really be in this file, cleanup at some point
	path := tprint("%../../fonts/FiraMonoNerdFontMono-Medium.ttf", path_strip_filename(get_path_of_running_executable()));
	defaultFont = load_font(path);
}

load_font :: (path: string) -> *Font {
	font := New(Font);

	// load the file
	file, success := read_entire_file(path,,fontCache.allocator);
	assert(success);
	font.fileData.data = file.data;
	font.fileData.count = file.count;

	error := FT_New_Memory_Face(fontCache.freetype, file.data, xx file.count, 0, *font.face);
	assert(!error);
	font.styleTable.allocator = fontCache.allocator;

	return font;
}

// @todo should really take a font, or some kind of handle to a font
// maybe you can specify a default font in the cache?
generate_text_run :: (text: string, size: int) -> TextRun {
	textCopy := text;
	nCodepoints := 0;
	while textCopy.count > 0 {
		nBytes := 1 + trailingBytesForUTF8[textCopy[0]];
		textCopy.data += nBytes; 
		textCopy.count -= nBytes; 
		nCodepoints += 1;
	}
	
	result: TextRun;
	result.width = 0;
	result.height = 0;
	result.glyphs = NewArray(nCodepoints,GlyphData);

	textCopy = text;
	i := 0;
	while textCopy.count > 0 {
		utf32,success := utf8_next_character(*textCopy);
		if success == .CONVERSION_OK {
			glyphIndex := FT_Get_Char_Index(defaultFont.face, utf32);

			glyphData := find_or_make_glyph(defaultFont, size, glyphIndex);
			result.glyphs[i] = glyphData;
			result.width += glyphData.advance;
			result.height = max(cast(s32)glyphData.subRect.h, result.height);
		}
		i += 1;
	}
	return result;
}

draw_text :: (text: string, size: int, x: float, y: float) {
	run := generate_text_run(text, size,,temp);

	// render the text run at the desired position
	for run.glyphs {
		submit_instance(.{
			dstRect = .{x + it.offsetX, y - it.offsetY, it.subRect.w, it.subRect.h},
			srcRect = it.subRect,
			color = .{1.0, 1.0, 1.0, 1.0},
			cornerRadii = .{0.0, 0.0, 0.0, 0.0},
			edgeSoftness = 0.0,
			borderThickness = 0.0,
			texture = *fontCache.atlasList[it.atlas].texture,
			shader = .TEXT
		});
		x += it.advance;
	}
}



#scope_file

Atlas :: struct {
	texture: Bitmap;
	nodes: [..]AtlasNode;
}

AtlasNode :: struct {
	x: s32;
	y: s32;
	width: s32;
}

find_or_make_glyph :: (font: *Font, size: int, glyphIndex: u32) -> GlyphData {
	fontStyle,newStyle := find_or_add(*font.styleTable, size);

	// cache miss on the font style
	if newStyle {
		fontStyle.glyphTable.allocator = fontCache.allocator;
		FT_Set_Pixel_Sizes(font.face, 0, xx size);

		// calculate basic metrics
		fontStyle.characterHeight = size;
		glyphIndexTemp := FT_Get_Char_Index(font.face, #char "T");
		if glyphIndexTemp {
			FT_Load_Glyph(font.face, glyphIndexTemp, FT_LOAD_DEFAULT);
			fontStyle.typicalAscender = FT_ROUND(font.face.glyph.metrics.horiBearingY - font.face.glyph.metrics.height);
		}

		glyphIndexTemp = FT_Get_Char_Index(font.face, #char "g");
		if glyphIndexTemp {
			FT_Load_Glyph(font.face, glyphIndexTemp, FT_LOAD_DEFAULT);
			fontStyle.typicalDescender = FT_ROUND(font.face.glyph.metrics.horiBearingY - font.face.glyph.metrics.height);
		}
	}

	glyphData,newGlyph := find_or_add(*fontStyle.glyphTable, glyphIndex);
	
	// cache miss on the glyph
	if newGlyph {
		FT_Set_Pixel_Sizes(font.face, 0, xx size);

		// Try LOAD_NO_HINTING if you want to allow no hinting
		error := FT_Load_Glyph(font.face, glyphIndex, FT_LOAD_DEFAULT);
		assert(!error);

		// @todo: here is where you'd specify LCD subpixel rendering
		FT_Render_Glyph(font.face.glyph, .FT_RENDER_MODE_NORMAL);

		glyphData.offsetX = font.face.glyph.bitmap_left;
		glyphData.offsetY = font.face.glyph.bitmap_top;
		glyphData.advance = (font.face.glyph.advance.x >> 6);

		if !try_add_glyph_to_atlas(*fontCache.atlasList[fontCache.atlasList.count-1], font.face, glyphData) {
			// @todo: failed to find space in atlas, make a new one
			assert(false);
		}
	}
	return <<glyphData;
}

can_rect_fit_in_atlas :: (atlas: *Atlas, atNode: s32, w: s32, h: s32) -> s32 {
	x := atlas.nodes[atNode].x;
	y := atlas.nodes[atNode].y;

	// check we're not going off the edge of the bitmap
	if x + w > atlas.texture.width {
		return -1;
	}

	// We're going to loop over all the nodes from atNode to however many this new rect "covers"
    // We want to find the highest rect underneath this rect to place it at.
	remainingSpace := w;
	index := atNode;
	while remainingSpace > 0 {
		if index == atlas.nodes.count {
			return -1;
		}

		node := *atlas.nodes[index];

		if node.y > y
			y = node.y;

		if y + h > atlas.texture.height
			return -1; // off the edge of the bitmap

		remainingSpace -= node.width;
		index += 1;
	}

	return y;
}

try_add_glyph_to_atlas :: (atlas: *Atlas, face: FT_Face, glyphData: *GlyphData) -> bool {
	bestHeight: s32 = atlas.texture.height;
	bestWidth: s32 = atlas.texture.width;
	bestNode: s32 = -1;
	bestX, bestY: s32;

	glyphWidth:s32 = xx face.glyph.bitmap.width;
	glyphHeight:s32 = xx face.glyph.bitmap.rows;

	// find the best location for the glyph
	for * atlas.nodes {
		highestY := can_rect_fit_in_atlas(atlas, xx it_index, glyphWidth, glyphHeight); 

		if highestY != -1 {
			// Settling a tie here on best height by checking lowest width we can use up
			if highestY + glyphHeight < bestHeight || (highestY + glyphHeight == bestHeight && it.width < bestWidth) {
				bestNode = xx it_index;
				bestWidth = it.width;
				bestHeight = highestY + glyphHeight;
				bestX = it.x;
				bestY = highestY;
			}
		}
	}

	if bestNode == -1
		return false; // glyph cannot fit in this atlas

	newNode: AtlasNode;
	newNode.width = glyphWidth;
	newNode.x = bestX;
	newNode.y = bestY + glyphHeight;
	array_insert_at(*atlas.nodes, newNode, bestNode);

	// now find all the nodes underneath this one and remove them
	i := bestNode+1;
	while i < atlas.nodes.count {
		node := *atlas.nodes[i];
		prevNode := *atlas.nodes[i-1];
		// check to see if the current node is underneath the previous node
		// remember that "it" starts as the first node after we inserted, so the previous node is the one we inserted
		if node.x < prevNode.x + prevNode.width {
			amountToShrink := (prevNode.x + prevNode.width) - node.x;
			node.x += amountToShrink;
			node.width -= amountToShrink;

			if node.width <= 0 {
				// we've reduced this node so much it can be removed
				array_ordered_remove_by_index(*atlas.nodes, i);
				i -= 1; // move back since we've removed a node
			}
			else {
				break; // if we don't need to remove this node, we've reached the extents of our new covering node
			}
		}
		else {
			break; // nothing being covered
		}
		i += 1;
	}

	// Find any skyline nodes that are the same height and merge them
	i = 0;
	while i < atlas.nodes.count-1 {
		if atlas.nodes[i].y == atlas.nodes[i+1].y {
			atlas.nodes[i].width += atlas.nodes[i+1].width;
			array_ordered_remove_by_index(*atlas.nodes, i+1);
			i -= 1;
		}
		i += 1;
	}

	// actually copy the bitmap data into the atlas
	rows  := cast(s32) face.glyph.bitmap.rows;
	width := cast(s32) face.glyph.bitmap.width;
	pitch := cast(s32) face.glyph.bitmap.pitch;
	for j : 0..rows-1 {
		for i : 0..width-1 {
            dst_pixel := atlas.texture.data.data + ((bestY + j) * atlas.texture.width + (bestX + i));
            <<dst_pixel = face.glyph.bitmap.buffer[(rows - 1 - j) * pitch + i];
		}
	}
	atlas.texture.dirty = true;

	// set the uv rect for rendering
	glyphData.subRect.x = cast(float)  bestX;
	glyphData.subRect.y = cast(float) (atlas.texture.height - bestY - rows);
	glyphData.subRect.w = cast(float)  width;
	glyphData.subRect.h = cast(float)  rows;

	return true;
}

defaultFont : *Font;

fontCache: FontCache;

FT_ROUND :: inline (x: int) -> int {
    if x >= 0 return (x + 0x1f) >> 6;
    return -(((-x) + 0x1f) >> 6);
}

// @todo: move outside

#import "freetype-2.12.1";
