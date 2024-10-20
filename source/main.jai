window: Window_Type;
windowWidth  : s32 = 1920;
windowHeight : s32 = 1080;

image_test: Simp.Texture;

screenshot_index := 0;

BuildType :: enum u8
{
	DEBUG;
	OPTIMIZED;
	RELEASE;
}

Document :: struct {
	// @todo use arena to yeet entire buffer memory at once
	path: string;
    bytes: []u8;
    lines: [..]string;
}

Rect :: struct {
	x: s32;
	y: s32;
	w: s32;
	h: s32;
}

Panel :: struct {
	// @todo use arena to yeet entire panel memory at once
	document: *Document;

	WrappedLine :: struct {
		line: string;
		lineNum: s32;
	}
	wrappedLines: [..]WrappedLine;

	rect: Rect;
	commandMessage: string;
}

// globals
editorMode := EditorMode.NORMAL;
mainPanel : Panel;
mainDocument : Document;
commandLine: CommandLine;
scrollPos := 0;

EditorMode :: enum_flags u8 {
	NORMAL;
	COMMAND;
	INSERT;
}

Command :: struct {
	name: string;
	execute: ()->string;
	mode: EditorMode;
	mapping: string;
}
// command map
// @Todo for fast access to the command when actually doing commands
// we should store a hash table that maps the mapping to the command
// Can probably generate it at startup
commandList :: Command.[
	.{ "command_mode", command_mode, .NORMAL, ":"},
	.{ "open_file", open_file, .COMMAND, ":o"},
	.{ "save_file", save_file, .COMMAND, ":w"},
];

CommandLine :: struct {
	// @todo several arrays in here using memory, should group it all into an arena
	text: [..]u8;
	// @todo, undos, cursor movement etc

	CommandEntry :: struct {
		command: *Command;
		// right now this is just the search score, but i'd like to add
		// the last use time of the command, or how often it's used
		sortKey: s64;
	}
	filteredCommandList: [..]CommandEntry;
}

// options
lineWrap := true;
textSize := 14;
tabSize := 4;
lineNumbers := true;

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    WANTED_MSAA :: 8;
    // On Linux, we need to pass the MSAA value to create_window
    window = create_window(windowWidth, windowHeight, "TextEditor", wanted_msaa = WANTED_MSAA);

    // On other operating systems, the MSAA value needs to be passed to *_create_context, so we
    // need to have an extra step here if you want MSAA.
    msaa := Simp.prepare_window(window, wanted_msaa = WANTED_MSAA);
    log("Wanted MSAA: %\nChosen MSAA: %", WANTED_MSAA, msaa);

    // Actual render size in pixels can be different from the window dimensions we specified above (for example on high-resolution displays on macOS/iOS).
    windowWidth, windowHeight = Simp.get_render_dimensions(window);

    Simp.set_render_target(window, .LEFT_HANDED);

    my_init_fonts();

	// load our example file
    example_file := read_entire_file("build.jai");

	mainDocument.path = "test/build.jai";
	mainDocument.bytes.data = example_file.data;
	mainDocument.bytes.count = example_file.count;

	mainPanel.document = *mainDocument;
	mainPanel.rect.x = 0;
	mainPanel.rect.y = 0;
	mainPanel.rect.w = windowWidth;
	mainPanel.rect.h = windowHeight;

	// for loop through the file, searching for new lines
	// should only happen on load adjust when editing
	lastNewLine := 0;
	for byte, i: mainDocument.bytes {
		if byte == #char "\n" { // line feed character
			line: string;
			line.data = mainDocument.bytes.data + lastNewLine;
			// TODO: +1 here for carraige return, if using \n line endings, don't need the +1
			line.count = i+1 - lastNewLine;
			lastNewLine = i+1;
			array_add(*mainDocument.lines, line);
		}
	}
	lastLine : string;
	lastLine.data = mainDocument.bytes.data + lastNewLine;
	lastLine.count = mainDocument.bytes.count - lastNewLine;
	array_add(*mainDocument.lines, lastLine);

    quit := false;
    want_screenshot := false;
    while !quit {
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);  // Simp will do nothing if it doesn't care about this window.

            if it.window == window {
                should_reinit := (it.width != windowWidth) || (it.height != windowHeight);

                windowWidth  = it.width;
                windowHeight = it.height;

				mainPanel.rect.x = 0;
				mainPanel.rect.y = 0;
				mainPanel.rect.w = windowWidth;
				mainPanel.rect.h = windowHeight;
				rescan_wrapped_lines(mainPanel);

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

            if it.type == {
              case .KEYBOARD;
                if it.key_pressed && it.key_code == .ESCAPE {
                    quit = true;
                }
            }
			if it.type == .TEXT_INPUT {
				char: Utf8_Char = convert_utf32_to_utf8(it.utf32);
				if editorMode & .COMMAND {
					// process the actual text input on the command line
					for 0..char.count-1 {
						array_add(*commandLine.text, char.bytes[it]);
					}

					// update the filtered command list
					search_query:= string.{commandLine.text.count, commandLine.text.data};
					array_reset_keeping_memory(*commandLine.filteredCommandList);
					for command: commandList {
						score := fuzzy_search(command.name, search_query);
						entry := array_add(*commandLine.filteredCommandList);
						entry.command = *command;
						entry.sortKey = score;
					}

					compare_entries :: (e1: CommandLine.CommandEntry, e2: CommandLine.CommandEntry) -> s64 {
						diff := e2.sortKey - e1.sortKey;
						if diff != 0 return diff;
						return memcmp(e1.command.name.data, e2.command.name.data, min(e1.command.name.count, e2.command.name.count));
					}
					quick_sort(commandLine.filteredCommandList, compare_entries);
				}
				else if editorMode & .NORMAL {
					for command: commandList {
						// is this command relevant for the current mode?
						if command.mode & editorMode {
							char: Utf8_Char = convert_utf32_to_utf8(it.utf32);
							input:= to_string(*char);
							if input == command.mapping {
								// found the desired command
								mainPanel.commandMessage = command.execute();
							}
						}
					}
				}
			}
		}

		draw_one_frame(example_file);

		// todo: smooth lerp animations on this
		// have a rawscroll value, and then a lerped value that we lerp toward every frame
		scrollPos += Input.mouse_delta_z;
		if !lineWrap {
			scrollPos = clamp(scrollPos, -(my_font.character_height * mainDocument.lines.count) + my_font.character_height * 5, 0);
		}
		else {
			scrollPos = clamp(scrollPos, -(my_font.character_height * mainPanel.wrappedLines.count) + my_font.character_height * 5, 0);
		}

        sleep_milliseconds(16);
        reset_temporary_storage();
    }
}

draw_one_frame :: (fileContents: string) {
	c,_ := hex_to_color_vec4("282c34");
    Simp.clear_render_target(c.x, c.y, c.z, 0.0);

    Simp.set_shader_for_color();

    time := seconds_since_init();

	draw_panel(mainPanel);
    
    Simp.swap_buffers(window);
}

draw_command_lister :: (panel: Panel) {
	commandLinePadding := 6;
	commandLineHeight := my_font.character_height + commandLinePadding;

	x: float = cast(float) panel.rect.x;
	y: float = cast(float) panel.rect.y + panel.rect.h/2;
	w: float = cast(float) panel.rect.w;
	h: float = cast(float) panel.rect.y + (panel.rect.h - commandLineHeight);
	Simp.set_shader_for_color();
	Simp.immediate_quad(x, y, w, h, Vector4.{0.4, 0.4, 0.4, 1.0});

	commandHeight := my_font.character_height + 4;
	textY := cast(int) h - 5;
	for commandEntry: commandLine.filteredCommandList  {
		if commandEntry.sortKey == 0 continue;
		command := commandEntry.command;
		width := Simp.prepare_text(my_font, command.name);
		Simp.draw_prepared_text(my_font, 2, textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		textY -= commandHeight;
	}
}

draw_panel :: (panel: Panel) {

	headerPadding := 6;
	headerHeight := my_font.character_height + headerPadding;

	commandLinePadding := 6;
	commandLineHeight := my_font.character_height + commandLinePadding;
    
	// Draw actual code + line numbers
	heightForCode := panel.rect.h - headerHeight - commandLineHeight;

	color: Vector4;
	color.x = 1;
	color.y = 1;
	color.z = 1;
	color.w = 1;

	textX := 0;
	textY := headerHeight;
	if lineNumbers {
		nDigits := tprint("%", mainDocument.lines.count).count;
		textX = my_font.mono_x_advance * (nDigits + 2); // extra 2 for padding
	}

	startVisibleLines : s64;
	endVisibleLines : s64;
	visibleLines: []string;
	if !lineWrap {
		startVisibleLines = clamp(-scrollPos / my_font.character_height, 0, mainDocument.lines.count - 1);
		endVisibleLines = clamp(startVisibleLines + heightForCode / my_font.character_height, 0, mainDocument.lines.count - 1);
		visibleLines.data = mainDocument.lines.data + startVisibleLines;
		visibleLines.count = endVisibleLines - startVisibleLines;

		// line numbers
		lineY := textY + my_font.character_height;
		for startVisibleLines..endVisibleLines {
			width := Simp.prepare_text(my_font, tprint("%", it+1));
			Simp.draw_prepared_text(my_font, (textX - width - my_font.mono_x_advance), lineY, Vector4.{0.5, 0.5, 0.5, 1.0});
			lineY += my_font.character_height;
		}
	}
	else {
		startVisibleLines = clamp(-scrollPos / my_font.character_height, 0, mainPanel.wrappedLines.count - 1);
		endVisibleLines = clamp(startVisibleLines + heightForCode / my_font.character_height, 0, mainPanel.wrappedLines.count - 1);
		visibleLinesTemp: [..]string;
		visibleLinesTemp.allocator = temp;
		array_reserve(*visibleLinesTemp, endVisibleLines - startVisibleLines);

		// line numbers
		lineY := textY + my_font.character_height;
		lastLineNum := -1;
		for startVisibleLines..endVisibleLines {
			wrappedLine := mainPanel.wrappedLines[it];
			array_add(*visibleLinesTemp, wrappedLine.line);

			if lastLineNum != wrappedLine.lineNum {
				width := Simp.prepare_text(my_font, tprint("%", wrappedLine.lineNum));
				Simp.draw_prepared_text(my_font, (textX - width - my_font.mono_x_advance), lineY, Vector4.{0.5, 0.5, 0.5, 1.0});
				lastLineNum = wrappedLine.lineNum;
			}
			lineY += my_font.character_height;
		}
		visibleLines = visibleLinesTemp;
	}

	Simp.draw_code(my_font, textX, textY, xx my_font.character_height, visibleLines);

	// Draw panel header + scroll bar
	Simp.set_shader_for_color();
	Simp.immediate_quad(cast(float)panel.rect.x,
						cast(float)panel.rect.y,
						cast(float)panel.rect.w,
						cast(float)panel.rect.y + headerHeight,
						Vector4.{0.3, 0.3, 0.3, 1.0});

	width := Simp.prepare_text(my_font, tprint("NORM | % - %:% crlf", panel.document.path, 32, 16));
	Simp.draw_prepared_text(my_font, 2, my_font.character_height + 2, Vector4.{0.8, 0.8, 0.8, 1.0});


	// Draw command line
	commandLineTopEdge := (panel.rect.y + panel.rect.h) - commandLineHeight;
	Simp.set_shader_for_color();
	Simp.immediate_quad(cast(float)panel.rect.x,
						cast(float)commandLineTopEdge,
						cast(float)panel.rect.w,
						cast(float)panel.rect.y + panel.rect.h,
						Vector4.{0.3, 0.3, 0.3, 1.0});
	
	width = Simp.prepare_text(my_font, tprint(":%", string.{commandLine.text.count, commandLine.text.data}, 32, 16));
	Simp.draw_prepared_text(my_font, 2, commandLineTopEdge + my_font.character_height, Vector4.{0.8, 0.8, 0.8, 1.0});

	if editorMode == .COMMAND {
		draw_command_lister(panel);
	}
}

my_init_fonts :: () {
    my_font = Simp.get_font_at_size("fonts", "FiraMonoNerdFontMono-Medium.ttf", textSize);
    assert(my_font != null);
}

rescan_wrapped_lines :: (panel: Panel) {
	// todo non monospace fonts
	assert(my_font.is_monospace);

	maxLineWidth :int = panel.rect.w - my_font.mono_x_advance;
	if lineNumbers {
		nDigits := tprint("%", panel.document.lines.count).count;
		maxLineWidth -= my_font.mono_x_advance * (nDigits + 2); // extra 2 for padding
	}

	array_reset_keeping_memory(*panel.wrappedLines);
    currentLineWidth := 0;
	currentActualLine :s32 = 1;
	lastLineBreak := 0;
	for byte, i: mainDocument.bytes {

		if byte == #char "\t" {
			currentLineWidth += (tabSize - currentLineWidth % tabSize) * my_font.mono_x_advance;
		} 
		else if byte != #char "\n" && byte != #char "\r" { // don't count line endings for wrapping
			currentLineWidth += my_font.mono_x_advance;
		}

		if currentLineWidth > maxLineWidth {
			wrappedLine: Panel.WrappedLine;
			wrappedLine.lineNum = currentActualLine;
			wrappedLine.line.data = panel.document.bytes.data + lastLineBreak;
			wrappedLine.line.count = i - lastLineBreak;
			lastLineBreak = i;
			array_add(*panel.wrappedLines, wrappedLine);
			currentLineWidth = 0;
		}

		if byte == #char "\n" {
			wrappedLine: Panel.WrappedLine;
			wrappedLine.lineNum = currentActualLine;
			wrappedLine.line.data = panel.document.bytes.data + lastLineBreak;
			// TODO: +1 here for carraige return, if using \n line endings, don't need the +1
			wrappedLine.line.count = i+1 - lastLineBreak;
			lastLineBreak = i+1;
			array_add(*panel.wrappedLines, wrappedLine);
			currentLineWidth = 0;
			currentActualLine += 1;
		}
	}
	// last line
	lastLine : Panel.WrappedLine;
	lastLine.line.data = panel.document.bytes.data + lastLineBreak;
	lastLine.line.count = panel.document.bytes.count - lastLineBreak;
	lastLine.lineNum = currentActualLine;
	array_add(*panel.wrappedLines, lastLine);
}

// color stuff
hex_to_color_vec4 :: (src_hex: string) -> Vector4, success: bool {
    hex := src_hex;
    if hex.count == 6 then hex = tprint("%FF", hex);
    if hex.count != 8 return Vector4.{}, false;

    r := slice(hex, 0, 2);
    g := slice(hex, 2, 2);
    b := slice(hex, 4, 2);
    a := slice(hex, 6, 2);

    to_float :: (byte_str: string) -> float {
        hex_digit_to_int :: (char: u8) -> int {
            char = to_upper(char);
            if #char "0" <= char && char <= #char "9" return char - #char "0";
            if #char "A" <= char && char <= #char "F" return 10 + char - #char "A";
            return -1;
        }

        d1, d0 := cast(float)hex_digit_to_int(byte_str[0]), cast(float) hex_digit_to_int(byte_str[1]);
        if d1 < 0 || d0 < 0 return -1;

        return (16 * d1 + d0) / 255;
    }

    c := Vector4.{ to_float(r), to_float(g), to_float(b), to_float(a) };

    return c, c.x >= 0 && c.y >= 0 && c.z >= 0 && c.w >= 0;
}


// commands
open_file :: () -> string {
	return "open file";
}
save_file :: () -> string {
	return "save file";
}
command_mode :: () -> string {
	editorMode = .COMMAND;

	array_reset_keeping_memory(*commandLine.filteredCommandList);

	for command: commandList {
		entry := array_add(*commandLine.filteredCommandList);
		entry.command = *command;
		entry.sortKey = 10;
	}
	
	// @todo recommend sorting on last used command here on initial show of the command list

	return "hello world";
}


// fuzzy searching
fuzzy_search :: (stringToSearch: string, filter: string) -> s32 {
	// @todo case insensitive
	i := find_index_from_left(stringToSearch, filter);

	MAX_CHARS :: 200;
	if i < 0 {
		return 0; // no match means you get no score
	}
	// If it matched, we'll give it more if the filter was bigger
	// and we'll give it more if the match was closer to the start of the search
	score := (100 + cast(s32) filter.count) * (MAX_CHARS - i);
	return xx score;
}


// unicode stuff
convert_utf32_to_utf8 :: (ch: u32) -> Utf8_Char {
    UNI_MAX_LEGAL_UTF32 :: 0x0010FFFF;
    UNI_REPLACEMENT_CHAR :: 0x0000FFFD;

    count := 0;
    if ch < 0x80                        count = 1;
    else if ch < 0x800                  count = 2;
    else if ch < 0x10000                count = 3;
    else if ch <= UNI_MAX_LEGAL_UTF32   count = 4;
    else {
        count = 3;
        ch = UNI_REPLACEMENT_CHAR;
    }

    byteMask :: 0xBF;
    byteMark :: 0x80;

    bytes: [4] u8 = ---;

    if count == {
        case 4; bytes[3] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 3; bytes[2] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 2; bytes[1] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 1; bytes[0] = xx (ch | firstByteMark[count]);
    }

    result: Utf8_Char = ---;
    result.bytes = bytes;
    result.count = xx count;
    return result;
}

to_string :: (utf8_char: *Utf8_Char) -> string {
    str: string = ---;
    str.data  = *utf8_char.bytes[0];
    str.count = utf8_char.count;
    return str;
}

Utf8_Char :: struct {
    bytes: [4] u8;
    count: s32;
}



my_font: *Simp.Dynamic_Font;

Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.
#import "File";
#import "Unicode";
#import "Sort";

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console();
    }
}
