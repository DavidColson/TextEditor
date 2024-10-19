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
    bytes: []u8;
    lines: [..]string;
}

Panel :: struct {
	document: Document;

	WrappedLine :: struct {
		line: string;
		lineNum: s32;
	}
	wrappedLines: [..]WrappedLine;

	width : s32;
	height : s32;
}

mainPanel : Panel;
mainDocument : Document;
scrollPos := 0;

// options
lineWrap := true;
textSize := 14;
tabSize := 4;


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

	mainDocument.bytes.data = example_file.data;
	mainDocument.bytes.count = example_file.count;

	mainPanel.document = mainDocument;
	mainPanel.width = windowWidth;
	mainPanel.height = windowHeight;

	// for loop through the file, searching for new lines
	// should only happen on load adjust when editing
	for byte, i: mainDocument.bytes {
		if byte == 0x0A { // line feed character
			line: string;
			line.data = mainDocument.bytes.data + i+1;
			array_add(*mainDocument.lines, line);

			if mainDocument.lines.count > 1 {
				previousLine := *mainDocument.lines[mainDocument.lines.count - 2];
				previousLine.count = line.data - previousLine.data; 
			}
		}
	}
	// last line
	lastLine := *mainDocument.lines[mainDocument.lines.count - 1];
	lastLine.count = (mainDocument.bytes.data + mainDocument.bytes.count) - lastLine.data;

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

				mainPanel.width = windowWidth;
				mainPanel.height = windowHeight;
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

                if it.key_pressed && it.key_code == #char " " {  // Press spacebar to take a screenshot.
                    want_screenshot = true;
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

    // Draw some text.
    {
        color: Vector4;
        color.x = 1;
        color.y = 1;
        color.z = 1;
        color.w = 1;

		textX := 0;
		textY := 0;

		if !lineWrap {
			startVisibleLines := clamp(-scrollPos / my_font.character_height, 0, mainDocument.lines.count - 1);
			endVisibleLines := clamp(startVisibleLines + windowHeight / my_font.character_height, 0, mainDocument.lines.count - 1);
			visibleLines: []string;
			visibleLines.data = mainDocument.lines.data + startVisibleLines;
			visibleLines.count = endVisibleLines - startVisibleLines;
			Simp.draw_code(my_font, textX, textY, xx my_font.character_height, visibleLines);
		}
		else {
			startVisibleLines := clamp(-scrollPos / my_font.character_height, 0, mainPanel.wrappedLines.count - 1);
			endVisibleLines := clamp(startVisibleLines + windowHeight / my_font.character_height, 0, mainPanel.wrappedLines.count - 1);
			visibleLines: [..]string;
			visibleLines.allocator = temp;
			array_reserve(*visibleLines, endVisibleLines - startVisibleLines);
			for startVisibleLines..endVisibleLines {
				wrappedLine := mainPanel.wrappedLines[it];
				array_add(*visibleLines, wrappedLine.line);
			}
			Simp.draw_code(my_font, textX, textY, xx my_font.character_height, visibleLines);
		}
    }

    Simp.swap_buffers(window);
}

my_init_fonts :: () {
    my_font = Simp.get_font_at_size("fonts", "FiraMonoNerdFontMono-Medium.ttf", textSize);
    assert(my_font != null);
}

rescan_wrapped_lines :: (panel: Panel) {
	// todo non monospace fonts
	assert(my_font.is_monospace);

	array_reset_keeping_memory(*panel.wrappedLines);
    currentLineWidth := 0;
	currentActualLine :s32 = 1;
	for byte, i: mainDocument.bytes {

		if byte == #char "\n" {
			currentActualLine += 1;
		}

		if byte == #char "\t" {
			currentLineWidth += (tabSize - currentLineWidth % tabSize) * my_font.mono_x_advance;
		} 
		else {
			currentLineWidth += my_font.mono_x_advance;
		}

		if currentLineWidth > (panel.width-my_font.mono_x_advance) || byte == #char "\n" {
			wrappedLine: Panel.WrappedLine;
			wrappedLine.lineNum = currentActualLine;
			wrappedLine.line.data = mainDocument.bytes.data + i + 1;
			array_add(*panel.wrappedLines, wrappedLine);

			currentLineWidth = 0;
			if panel.wrappedLines.count > 1 {
				previousLine := *panel.wrappedLines[panel.wrappedLines.count - 2];
				previousLine.line.count = wrappedLine.line.data - previousLine.line.data; 
			}
		}
	}
	// last line
	lastLine := *panel.wrappedLines[panel.wrappedLines.count - 1];
	lastLine.line.count = (mainDocument.bytes.data + mainDocument.bytes.count) - lastLine.line.data;
}

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

my_font: *Simp.Dynamic_Font;

Simp  :: #import "Simp";
Input :: #import "Input";

#import "Window_Creation";

#import "Basic";
#import "Math";
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.
#import "File";

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console();
    }
}
