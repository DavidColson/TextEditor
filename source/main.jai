my_window: Window_Type;
window_width  : s32 = 1920;
window_height : s32 = 1080;

image_test: Simp.Texture;

screenshot_index := 0;

BuildType :: enum u8
{
	DEBUG;
	OPTIMIZED;
	RELEASE;
}

Buffer :: struct {
    bytes: []u8;
    line_starts: [..]s32;
}

main_buffer : Buffer;

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        Windows.SetProcessDPIAware();

        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

    WANTED_MSAA :: 8;
    // On Linux, we need to pass the MSAA value to create_window
    my_window = create_window(window_width, window_height, "TextEditor", wanted_msaa = WANTED_MSAA);

    // On other operating systems, the MSAA value needs to be passed to *_create_context, so we
    // need to have an extra step here if you want MSAA.
    msaa := Simp.prepare_window(my_window, wanted_msaa = WANTED_MSAA);
    log("Wanted MSAA: %\nChosen MSAA: %", WANTED_MSAA, msaa);

    // Actual render size in pixels can be different from the window dimensions we specified above (for example on high-resolution displays on macOS/iOS).
    window_width, window_height = Simp.get_render_dimensions(my_window);

    Simp.set_render_target(my_window, .LEFT_HANDED);

    my_init_fonts();

	// load our example file
    example_file := read_entire_file("build.jai");

	main_buffer.bytes.data = example_file.data;
	main_buffer.bytes.count = example_file.count;

	// for loop through the file, searching for new lines
	for byte, i: main_buffer.bytes {
		if byte == 0x0A { // line feed character
			array_add(*main_buffer.line_starts, cast(s32)i);
		}
	}

    quit := false;
    want_screenshot := false;
    while !quit {
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);  // Simp will do nothing if it doesn't care about this window.

            if it.window == my_window {
                should_reinit := (it.width != window_width) || (it.height != window_height);

                window_width  = it.width;
                window_height = it.height;

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

        sleep_milliseconds(16);
        reset_temporary_storage();
    }
}

draw_one_frame :: (file_contents: string) {
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

		// Parse file looking for line endings
		// Mark the start and end of each line
		// Store the line starts in an array in a buffer structure
		// Loop through the line starts, making a string view and giving it to simp to draw
		text_x := 0;
		text_y := 0;

		for line_start, i: main_buffer.line_starts {
			line : string;
			line.data = main_buffer.bytes.data + line_start;
			line_end : *u8;
			if i == main_buffer.line_starts.count-1 {
				line_end = main_buffer.bytes.data + main_buffer.bytes.count;
			}
			else {
				line_end = main_buffer.bytes.data + main_buffer.line_starts[i+1];
			}
			line.count = line_end - line.data;

			text_width := Simp.prepare_text(my_font, line);

			text_y += my_font.character_height;

			Simp.draw_prepared_text(my_font, text_x, text_y, color);
		}

    }

    Simp.swap_buffers(my_window);
}

my_init_fonts :: () {
	pixel_height := 16;

    my_font = Simp.get_font_at_size("fonts", "FiraMonoNerdFontMono-Medium.ttf", pixel_height);
    assert(my_font != null);
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
