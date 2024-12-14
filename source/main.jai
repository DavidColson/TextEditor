BuildType :: enum u8
{
	DEBUG;
	OPTIMIZED;
	RELEASE;
}

Cursor :: struct {
	head: DocumentCursor;
	anchor: DocumentCursor;

	// when users move up and down lines, this stores the 
	// column that we should try stick to as we move up and down
	// gets reset when the user actually moves left or right
	virtualColumn: s64; 
}

Panel :: struct {
	// @todo make a free panel function which yeets the wrapped lines
	document: *Document;

	cursor: Cursor;
	rect: Rect;
	commandMessage: string;

	commandPicker: CommandPicker;
	filesystemNav: FilesystemNavigator;
}

EditorMode :: enum u8 {
	NORMAL;
	INSERT;
	COMMAND_PICKER;
	FILESYSTEM_NAVIGATOR;
}

EDITOR_MODE_NUM :: #run enum_highest_value(EditorMode) + 1;

// globals
editorMode := EditorMode.NORMAL;
focusedPanel : Panel;
mainDocument : Document;
scrollPos := 0;
window: Window_Type;
windowWidth  : s32 = 1920;
windowHeight : s32 = 1080;
pendingQuit := false;

// options
textSize :: 15;
tabSize :: 4;
lineNumbers :: true;

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

	rebuild_key_map();

	document_open("C:/Dev/TextEditor/build.jai");

	focusedPanel.rect.x = 0;
	focusedPanel.rect.y = 0;
	focusedPanel.rect.w = xx windowWidth;
	focusedPanel.rect.h = xx windowHeight;
	focusedPanel.document = *mainDocument;
	focusedPanel.cursor.head.doc = focusedPanel.document;
	focusedPanel.cursor.head.node = mainDocument.pieceChainHead;
	focusedPanel.cursor.anchor.doc = focusedPanel.document;
	focusedPanel.cursor.anchor.node = mainDocument.pieceChainHead;

    want_screenshot := false;
    while !pendingQuit {
        Input.update_window_events();

        for Input.get_window_resizes() {
            Simp.update_window(it.window);  // Simp will do nothing if it doesn't care about this window.

            if it.window == window {
                should_reinit := (it.width != windowWidth) || (it.height != windowHeight);

                windowWidth  = it.width;
                windowHeight = it.height;

				focusedPanel.rect.x = 0;
				focusedPanel.rect.y = 0;
				focusedPanel.rect.w = xx windowWidth;
				focusedPanel.rect.h = xx windowHeight;

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for Input.events_this_frame {
            if it.type == .QUIT then pendingQuit = true;
			input_handler(it);
		}

		draw_one_frame();

		// todo: smooth lerp animations on this
		// have a rawscroll value, and then a lerped value that we lerp toward every frame
		numLines := document_get_num_lines(*mainDocument);
		scrollPos += Input.mouse_delta_z;
		scrollPos = clamp(scrollPos, -(my_font.character_height * numLines) + my_font.character_height * 5, 0);

        sleep_milliseconds(16);
        reset_temporary_storage();
    }
}

my_init_fonts :: () {
    my_font = Simp.get_font_at_size("fonts", "FiraMonoNerdFontMono-Medium.ttf", textSize);
	my_font.render_tabs = false;
	my_font.render_new_lines = false;
    assert(my_font != null);
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

// basic commands
// @todo move these into files
// for example file for "motions", file for "changes"
quit :: (panel: *Panel, extend: bool) {
	pendingQuit = true;
}

open_file :: (panel: *Panel, extend: bool) {
	editorMode = .FILESYSTEM_NAVIGATOR;
	filesystem_nav_refresh_directory_list(*panel.filesystemNav);
}

print_piece_chain_debug :: (panel: *Panel, extend: bool) {
	document_debug_print_piece_chain(panel.document);
}

toggle_render_line_endings :: (panel: *Panel, extend: bool) {
	my_font.render_new_lines = !my_font.render_new_lines;
	Simp.force_regenerate_glyph_table(my_font);
}

enter_normal_mode :: (panel: *Panel, extend: bool) {
	if editorMode == .FILESYSTEM_NAVIGATOR {
		filesystem_nav_reset(*panel.filesystemNav);
	}
	else if editorMode == .COMMAND_PICKER {
		command_picker_reset(*panel.commandPicker);
	}
	editorMode = .NORMAL;
}

enter_insert_mode :: (panel: *Panel, extend: bool) {
	if editorMode == .FILESYSTEM_NAVIGATOR {
		filesystem_nav_reset(*panel.filesystemNav);
	}
	else if editorMode == .COMMAND_PICKER {
		command_picker_reset(*panel.commandPicker);
	}
	editorMode = .INSERT;
}

move_one_char_left :: (using panel: *Panel, extend: bool) {
	document_cursor_step_one_backward(*cursor.head);
	if !extend {
		cursor.anchor = cursor.head;
	}
}

move_one_char_right :: (using panel: *Panel, extend: bool) {
	document_cursor_step_one_forward(*cursor.head);
	if !extend {
		cursor.anchor = cursor.head;
	}
}

move_one_line_down :: (using panel: *Panel, extend: bool) {
	numLines := document_get_num_lines(document);
	newLine := min(cursor.head.documentPos.line+1, numLines - 1);
	document_cursor_jump_to_position(*cursor.head, .{newLine, cursor.head.documentPos.col});

	if !extend {
		cursor.anchor = cursor.head;
	}
}

move_one_line_up :: (using panel: *Panel, extend: bool) {
	document_cursor_jump_to_position(*cursor.head, .{max(cursor.head.documentPos.line - 1, 0), cursor.head.documentPos.col});
	if !extend {
		cursor.anchor = cursor.head;
	}
}

delete_selection :: (using panel: *Panel, extend: bool) {
	rangeStart, rangeEnd := convert_cursor_to_range(panel.cursor);

	// @todo don't end the deletion in the middle of a crlf
	// is this needed now with the nodetrim functions handling this?
	// cursorChar := document_get_char_at_location(document, rangeEnd.line, rangeEnd.col);
	// if cursorChar == #char "\n" then rangeEnd.col += 1;

	document_delete_text(document, cursor.head, cursor.anchor);

	// @todo the cursors should be regenerated here from scratch because the node pointers are likely to have
	// become outdated

	// cursor.line = rangeStart.line;
	// cursor.column = rangeStart.col;
	// cursor.anchorLine = rangeStart.line;
	// cursor.anchorColumn = rangeStart.col;
}

// insert mode text handler
insert_mode_handle_text_input :: (char: Utf8_Char) {
	textToInsert := to_string(*char);
	focusedPanel.cursor.head = document_insert_text(focusedPanel.document, focusedPanel.cursor.head, textToInsert);
	move_one_char_right(*focusedPanel, false);

	// @todo the cursors should be regenerated here from scratch because the node pointers are likely to have
	// become outdated, something you could do on a background thread though
}

insert_mode_delete_left_char :: (using panel: *Panel, extend: bool) {
	if cursor.head.documentPos.line == 0 && cursor.head.documentPos.col == 0 {
		return;
	}

	// @todo the cursors should be regenerated here from scratch because the node pointers are likely to have
	// become outdated

	// @todo: refactor with document cursor, essentially just copy the cursor
	// step back one and then delete that, then save the new version
	// This should do everything, it'll even wrap back a line for you (theoretically)

	// // @todo What happens if you delete and cursor.column is 0?
	// deletePos := Coordinate.{cursor.line, cursor.column-1};
	// if cursor.column == 0 {
	// 	deletePos.line -= 1;
	// 	// get back to the end of the previous line (before line endings)
	// 	deletePos.col = document_get_line_length(document, deletePos.line, true);
	//
	// 	// @todo deleting two chars because of crlf line endings, change when doing another line ending type
	// 	document_delete_text(document, deletePos, 2);
	//
	// 	// move the cursor back up to the deletion point
	// 	cursor.line = deletePos.line;
	// 	cursor.column = deletePos.col;
	// 	cursor.anchorLine = cursor.line;
	// 	cursor.anchorColumn = cursor.column;
	// }
	// else {
	// 	document_delete_text(document, deletePos, 1);
	// 	move_one_char_left(panel, false);
	// }
}

insert_mode_line_break :: (using panel: *Panel, extend: bool) {
	textToInsert := "\r\n"; // @todo this should be changed depenending on document type
	document_insert_text(document, cursor.head, textToInsert);

	// @todo the cursors should be regenerated here from scratch because the node pointers are likely to have
	// become outdated

	move_one_line_down(panel, false);
	// cursor.column = 0;
	// cursor.virtualColumn = cursor.column;
	// cursor.anchorLine = cursor.line;
	// cursor.anchorColumn = cursor.column;
}

// utilities 
convert_cursor_to_range :: (cursor: Cursor, includeCursor: bool = true) -> start: Coordinate, end: Coordinate {
	rangeStart: Coordinate;
	rangeEnd: Coordinate;
	cursorBonus := ifx includeCursor then 1 else 0;

	cursorHead := cursor.head.documentPos;
	cursorAnchor := cursor.anchor.documentPos;

	if cursorHead.line < cursorAnchor.line {
		// cursor is clearly earlier than the anchor
		rangeStart.line = cursorHead.line;
		rangeStart.col = cursorHead.col;
		rangeEnd.line = cursorAnchor.line;
		rangeEnd.col = cursorAnchor.col;
	}
	else if cursorHead.line > cursorAnchor.line { 
		// anchor is clearly earlier than the cursor
		rangeStart.line = cursorAnchor.line;
		rangeStart.col = cursorAnchor.col;
		rangeEnd.line = cursorHead.line;
		rangeEnd.col = cursorHead.col+cursorBonus; // cursor itself is considered part of the selection
	}
	else {
		// they are on the same line, pick based on column
		if cursorHead.col <= cursorAnchor.col {
			rangeStart.line = cursorHead.line;
			rangeStart.col = cursorHead.col;
			rangeEnd.line = cursorAnchor.line;
			rangeEnd.col = cursorAnchor.col;
		}
		else {
			rangeStart.line = cursorAnchor.line;
			rangeStart.col = cursorAnchor.col;
			rangeEnd.line = cursorHead.line;
			rangeEnd.col = cursorHead.col+cursorBonus;
		}
	}
	return rangeStart, rangeEnd;
}


// @todo: this is windows only, move to windows file
platform_enumerate_logical_drives :: () -> [] string {
    drives: [..] string;

    drives_buf: [500] u16;
    GetLogicalDriveStringsW(500, drives_buf.data);

    drive_wstr := drives_buf.data;
    for drives_buf {
        if it == 0 { // split on null terminator
            drive, success := wide_to_utf8_new(drive_wstr,, allocator = temp);
            if !drive || !success break;
            drive.count -= 1;  // cut off separator
            array_add(*drives, drive);
            drive_wstr = *drives_buf[it_index + 1];
        }
    }

    return drives;
}

platform_is_path_directory :: (path: string) -> bool {
    push_allocator(temp);
	attrib := GetFileAttributesW(utf8_to_wide_new(path));
	if attrib & FILE_ATTRIBUTE_DIRECTORY {
		return true;
	}
	return false;
}

// fuzzy searching
fuzzy_search :: (stringToSearch: string, filter: string) -> s32 {
	if filter.count == 0 return 1;
	// @todo case insensitive
	i := find_index_from_left_nocase(stringToSearch, filter);

	MAX_CHARS :: 200;
	if i < 0 {
		return 0; // no match means you get no score
	}
	// If it matched, we'll give it more if the filter was bigger
	// and we'll give it more if the match was closer to the start of the search
	score := (100 + cast(s32) filter.count) * (MAX_CHARS - i);
	return xx score;
}

find_index_from_left_nocase :: (s: string, substring: string, start_index := 0) -> s64 {
    if !substring return -1;

    for i: start_index..s.count-substring.count {
        t := slice(s, i, substring.count);
        if equal_nocase(t, substring) return i;
    }

    return -1;
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
#import "System";
#import "String";
#import "File";
#import "File_Utilities";
#import "Unicode";
#import "Sort";
#import "Flat_Pool";
#import "Hash_Table";

// @todo: this should be moved to a relevant "platform file"
kernel32 :: #system_library "kernel32";
#import "Windows";
#import "Windows_Utf8";
GetLogicalDriveStringsW :: (nBufferLength: DWORD, lpBuffer: *u16) -> DWORD #foreign kernel32;

#load "rect.jai";
#load "command_picker.jai";
#load "filesystem_navigator.jai";
#load "draw.jai";
#load "keymap.jai";
#load "document.jai";

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        // WR.disable_runtime_console();
    }
}
