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

	searchActive := false;
	commandPicker: CommandPicker;
	filesystemNav: FilesystemNavigator;
}

EditorMode :: enum u8 {
	NORMAL;
	INSERT;
	COMMAND_PICKER;
	FILESYSTEM_NAVIGATOR;
}

Notification :: struct {
	content: string;
	timer: float64;
}

EDITOR_MODE_NUM :: #run enum_highest_value(EditorMode) + 1;

// globals
// @todo: should put this in a global editor state struct
editorMode := EditorMode.NORMAL;
extendSelections := false;
focusedPanel : Panel;
mainDocument : Document;
scrollPos := 0;
window: Window_Type;
windowWidth  : s32 = 1920;
windowHeight : s32 = 1080;
pendingQuit := false;
backupSaveTimer:float64 = 300;

notifications : [10]Notification;
numActiveNotifications := 0;
notificationTime: float64 = 10;

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

	focusedPanel.rect.x = 0;
	focusedPanel.rect.y = 0;
	focusedPanel.rect.w = xx windowWidth;
	focusedPanel.rect.h = xx windowHeight;
	focusedPanel.document = *mainDocument;

	document_open("C:/Dev/TextEditor/source/main.jai");

	lastTime := seconds_since_init();
    want_screenshot := false;
    while !pendingQuit {
		now := seconds_since_init();
		delta : float64 = now - lastTime;
		lastTime = now;

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

		// @todo: don't re-render if nothing's changed
		draw_one_frame();

		// @todo: smooth lerp animations on this
		// have a rawscroll value, and then a lerped value that we lerp toward every frame
		scrollPos += Input.mouse_delta_z;

		numLines := document_get_num_lines(*mainDocument);
		scrollPos = clamp(scrollPos, -(my_font.character_height * numLines) + my_font.character_height * 5, 0);

		// keep the cursor on the screen when we scroll
		startVisibleLine, endVisibleLine := panel_calculate_visible_lines(*focusedPanel);
		cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
		if cursorLine < startVisibleLine {
			move_to_line_visual(*focusedPanel, cursorLine, startVisibleLine);
			focusedPanel.cursor.anchor = focusedPanel.cursor.head;
		}
		else if cursorLine > endVisibleLine {
			move_to_line_visual(*focusedPanel, cursorLine, endVisibleLine-1);
			focusedPanel.cursor.anchor = focusedPanel.cursor.head;
		}

		// update notifications
		nNotificationsToRemove := 0;
		it := 0;
		while it < numActiveNotifications {
			notif := *notifications[it];
			notif.timer -= delta;
			if notif.timer < 0 {
				nNotificationsToRemove += 1;
			}
			it += 1;
		}

		if nNotificationsToRemove > 0 {
			memcpy(notifications.data, notifications.data+nNotificationsToRemove, nNotificationsToRemove*size_of(Notification));
			numActiveNotifications -= nNotificationsToRemove;
		}

		// update backups timer
		backupSaveTimer -= delta;
		if backupSaveTimer <= 0 {
			if mainDocument.unsaved {
				builder : String_Builder;
				builder.allocator = temp;
				init_string_builder(*builder);

				append(*builder, get_working_directory());
				append(*builder, "\\backups\\");
				append(*builder, path_filename(mainDocument.path));

				document_save(*mainDocument, builder_to_string(*builder,,temp), true);
			}
		}

        sleep_milliseconds(cast(s32) (16 - delta/1000));
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
quit :: (panel: *Panel, args: []string) {
	pendingQuit = true;
}

open_file :: (panel: *Panel, args: []string) {
	editorMode = .FILESYSTEM_NAVIGATOR;
	filesystem_nav_refresh_directory_list(*panel.filesystemNav);
}

save_file :: (panel: *Panel, args: []string) {
	document_save(panel.document, panel.document.path);
}

save_file_as :: (panel: *Panel, args: []string) {
	// open filesystem navigator
	editorMode = .FILESYSTEM_NAVIGATOR;
	panel.filesystemNav.saveMode = true;
	filesystem_nav_refresh_directory_list(*panel.filesystemNav);
}

print_piece_chain_debug :: (panel: *Panel, args: []string) {
	document_debug_print_piece_chain(panel.document);
	push_notification("Piecechain debug printed to stdout");
}

toggle_render_line_endings :: (panel: *Panel, args: []string) {
	my_font.render_new_lines = !my_font.render_new_lines;
	Simp.force_regenerate_glyph_table(my_font);
}

normalize_line_endings_lf :: (panel: *Panel, args: []string) {
	document_normalize_line_endings(panel.document, .LF);
}

normalize_line_endings_crlf :: (panel: *Panel, args: []string) {
	document_normalize_line_endings(panel.document, .CRLF);
}

enter_normal_mode :: (panel: *Panel, args: []string) {
	if editorMode == .FILESYSTEM_NAVIGATOR {
		filesystem_nav_reset(*panel.filesystemNav);
	}
	else if editorMode == .COMMAND_PICKER {
		command_picker_reset(*panel.commandPicker);
	}
	editorMode = .NORMAL;
	extendSelections = false;
	panel.searchActive = false;
}

enter_insert_mode_start :: (using panel: *Panel, args: []string) {
	if cursor.head.documentOffset > cursor.anchor.documentOffset {
		flip_cursors(*cursor.head, *cursor.anchor);
	}
	if editorMode == .FILESYSTEM_NAVIGATOR {
		filesystem_nav_reset(*panel.filesystemNav);
	}
	else if editorMode == .COMMAND_PICKER {
		command_picker_reset(*panel.commandPicker);
	}
	editorMode = .INSERT;
}

enter_insert_mode_end :: (using panel: *Panel, args: []string) {
	if cursor.head.documentOffset < cursor.anchor.documentOffset {
		flip_cursors(*cursor.head, *cursor.anchor);
	}
	document_cursor_step_one_forward(*focusedPanel.cursor.head);
	if editorMode == .FILESYSTEM_NAVIGATOR {
		filesystem_nav_reset(*panel.filesystemNav);
	}
	else if editorMode == .COMMAND_PICKER {
		command_picker_reset(*panel.commandPicker);
	}
	editorMode = .INSERT;
}

enter_insert_mode_line_start :: (using panel: *Panel, args: []string) {
	extendSelections = false;
	goto_line_start(panel, args);
	cursorChar := document_cursor_get_char(*cursor.head);
	if is_space(cursorChar) {
		for cursor.head {
			next := document_cursor_get_char(*cursor.head);
			if !is_space(next) break;
		}
	}
	cursor.anchor = cursor.head;

	if editorMode == .FILESYSTEM_NAVIGATOR {
		filesystem_nav_reset(*panel.filesystemNav);
	}
	else if editorMode == .COMMAND_PICKER {
		command_picker_reset(*panel.commandPicker);
	}
	editorMode = .INSERT;
}

enter_insert_mode_line_end :: (using panel: *Panel, args: []string) {
	extendSelections = false;
	goto_line_end(panel, args);

	if editorMode == .FILESYSTEM_NAVIGATOR {
		filesystem_nav_reset(*panel.filesystemNav);
	}
	else if editorMode == .COMMAND_PICKER {
		command_picker_reset(*panel.commandPicker);
	}
	editorMode = .INSERT;
}

toggle_extend_selections :: (using panel: *Panel, args: []string) { 
	extendSelections = !extendSelections;
}

delete_selection :: (using panel: *Panel, args: []string) {
	if cursor.head.documentOffset < cursor.anchor.documentOffset {
		end := cursor.anchor;
		document_cursor_step_one_forward(*end);
		cursor.head = document_delete_text(document, cursor.head, end);
	}
	else {
		end := cursor.head;
		document_cursor_step_one_forward(*end);
		cursor.head = document_delete_text(document, cursor.anchor, end);
	}
	cursor.anchor = cursor.head;
}

change_selection :: (using panel: *Panel, args: []string) {
	delete_selection(panel, args);
	enter_insert_mode_start(panel, args);
}

replace_selection :: (using panel: *Panel, args: []string) {
	rangeLength := abs(cursor.head.documentOffset - cursor.anchor.documentOffset);

	delete_selection(panel, args);

	builder : String_Builder;
	builder.allocator = temp;
	init_string_builder(*builder);

	for 0..rangeLength {
		append(*builder, args[0]);
	}

	focusedPanel.cursor.head = document_insert_text(focusedPanel.document, focusedPanel.cursor.head, builder_to_string(*builder,,temp));

	// update cursor positions
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	if rangeLength > 0 {
		for focusedPanel.cursor.head {
			if it_index >= rangeLength-1 then break;
		}
	}
}

new_line_below :: (using panel: *Panel, args: []string) {
	goto_line_end(panel, args);
	insert_mode_line_break(panel, args);
	enter_insert_mode_start(panel, args);
}

new_line_above :: (using panel: *Panel, args: []string) {
	for < cursor.head {
		if it == #char "\n" {
			break;
		}
	}
	cursor.anchor = cursor.head;
	insert_mode_line_break(panel, args);
	enter_insert_mode_start(panel, args);
}

// search

search_document :: (using panel: *Panel, args: []string) {
	// show search bar
	panel.searchActive = true;
}

// insert mode stuff

insert_mode_insert_string :: (input: string) {
	// do the insert
	distanceToAnchor := focusedPanel.cursor.anchor.documentOffset - focusedPanel.cursor.head.documentOffset;
	focusedPanel.cursor.head = document_insert_text(focusedPanel.document, focusedPanel.cursor.head, input);

	// update the anchor
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	if distanceToAnchor > 0 {
		for focusedPanel.cursor.anchor {
			if it_index >= distanceToAnchor-1 then break;
		}
	}
	else if distanceToAnchor < 0 {
		for < focusedPanel.cursor.anchor {
			if it_index >= abs(distanceToAnchor)-1 then break;
		}
	}
	
	// move the cursors as appropriate,
	// head will move right, anchor will also move if it's ahead of the head
	extendSelections = true;
	if focusedPanel.cursor.head.documentOffset <= focusedPanel.cursor.anchor.documentOffset {
		document_cursor_step_one_forward(*focusedPanel.cursor.anchor);
	}
	move_one_char_right(*focusedPanel, string.[]);
	extendSelections = false;
}

insert_mode_handle_text_input :: (char: Utf8_Char) {
	textToInsert := to_string(*char);
	insert_mode_insert_string(textToInsert);
}

insert_mode_line_break :: (using panel: *Panel, args: []string) {
	textToInsert := "\r\n";
	if panel.document.lineEndings == .LF || panel.document.lineEndings == .MIXED_MAJORITY_LF {
		textToInsert = "\n";
	}
	insert_mode_insert_string(textToInsert);
}

insert_tab_character :: (using panel: *Panel, args: []string) {
	textToInsert := "\t";
	insert_mode_insert_string(textToInsert);
}

insert_mode_delete_left_char :: (using panel: *Panel, args: []string) {
	distanceToAnchor := focusedPanel.cursor.anchor.documentOffset - focusedPanel.cursor.head.documentOffset;

	stepCursor := cursor.head;
	document_cursor_step_one_backward(*stepCursor);
	cursor.head = document_delete_text(document, stepCursor, cursor.head);

	// update the anchor
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	if distanceToAnchor > 0 {
		for focusedPanel.cursor.anchor {
			if it_index >= distanceToAnchor-1 then break;
		}
	}
	else if distanceToAnchor < 0 {
		for < focusedPanel.cursor.anchor {
			if it_index >= abs(distanceToAnchor)-1 then break;
		}
	}

	// move anchor as appropriate
	if focusedPanel.cursor.head.documentOffset > focusedPanel.cursor.anchor.documentOffset {
		document_cursor_step_one_forward(*focusedPanel.cursor.anchor);
	}
}

// view commands
page_up :: (using panel: *Panel, args: []string) {
	numLines := document_get_num_lines(*mainDocument);

	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	numVisibleLines := endVisibleLine - startVisibleLine;

	scrollPosOld := scrollPos;
	scrollPos += my_font.character_height * numVisibleLines;
	scrollPos = clamp(scrollPos, -(my_font.character_height * numLines) + my_font.character_height * 5, 0);

	if scrollPos != scrollPosOld {
		cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
		lineRelativeToPanel := cursorLine - startVisibleLine;
		newLine := (startVisibleLine - numVisibleLines) + lineRelativeToPanel;
		move_to_line_visual(*focusedPanel, cursorLine, newLine);
		focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	}
}

page_down :: (using panel: *Panel, args: []string) {
	numLines := document_get_num_lines(*mainDocument);

	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	numVisibleLines := endVisibleLine - startVisibleLine;

	scrollPosOld := scrollPos;
	scrollPos -= my_font.character_height * numVisibleLines;
	scrollPos = clamp(scrollPos, -(my_font.character_height * numLines) + my_font.character_height * 5, 0);

	if scrollPos != scrollPosOld {
		cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
		lineRelativeToPanel := cursorLine - startVisibleLine;
		newLine := endVisibleLine + lineRelativeToPanel;
		move_to_line_visual(*focusedPanel, cursorLine, newLine);
		focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	}
}

half_page_up :: (using panel: *Panel, args: []string) {
	numLines := document_get_num_lines(*mainDocument);

	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	linesToScroll := (endVisibleLine - startVisibleLine) / 2;

	scrollPosOld := scrollPos;
	scrollPos += my_font.character_height * linesToScroll;
	scrollPos = clamp(scrollPos, -(my_font.character_height * numLines) + my_font.character_height * 5, 0);

	if scrollPos != scrollPosOld {
		cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
		lineRelativeToPanel := cursorLine - startVisibleLine;
		newLine := (startVisibleLine - linesToScroll) + lineRelativeToPanel;
		move_to_line_visual(*focusedPanel, cursorLine, newLine);
		focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	}
}

half_page_down :: (using panel: *Panel, args: []string) {
	numLines := document_get_num_lines(*mainDocument);

	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	linesToScroll := (endVisibleLine - startVisibleLine) / 2;

	scrollPosOld := scrollPos;
	scrollPos -= my_font.character_height * linesToScroll;
	scrollPos = clamp(scrollPos, -(my_font.character_height * numLines) + my_font.character_height * 5, 0);

	if scrollPos != scrollPosOld {
		cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
		lineRelativeToPanel := cursorLine - startVisibleLine;
		newLine := startVisibleLine + linesToScroll + lineRelativeToPanel;
		move_to_line_visual(*focusedPanel, cursorLine, newLine);
		focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	}
}

// panel functions @todo, move to it's own file
panel_calculate_visible_lines :: (panel: *Panel, clamped := false) -> s64, s64 {
	numLines := document_get_num_lines(panel.document);
	// @todo: these need to be parameterized styling values for the UI
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;
	heightForCode := panel.rect.h - headerHeight;
	startVisibleLines := clamp(-scrollPos / my_font.character_height, 0, numLines - 1);
	endVisibleLinesUnclamped := startVisibleLines + cast(s64)heightForCode / my_font.character_height;
	endVisibleLines := clamp(endVisibleLinesUnclamped, 0, numLines - 1);

	if clamped {
		return startVisibleLines, endVisibleLines;
	}
	else {
		return startVisibleLines, endVisibleLinesUnclamped;
	}
}

// utilities 
convert_cursor_to_coordinate_range :: (cursor: Cursor, includeCursor: bool = true) -> start: Coordinate, end: Coordinate {
	rangeStart: Coordinate;
	rangeEnd: Coordinate;
	cursorBonus := ifx includeCursor then 1 else 0;

	cursorHead := document_cursor_get_coordinate(*cursor.head);
	cursorAnchor := document_cursor_get_coordinate(*cursor.anchor);

	if cursorHead.line < cursorAnchor.line {
		// cursor is clearly earlier than the anchor
		rangeStart.line = cursorHead.line;
		rangeStart.col = cursorHead.col;
		rangeEnd.line = cursorAnchor.line;
		rangeEnd.col = cursorAnchor.col+cursorBonus;
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
			rangeEnd.col = cursorAnchor.col+cursorBonus;
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

// notifications

// this function will not copy the string
push_notification :: (message: string) {
	if numActiveNotifications < 10 {
		notifications[numActiveNotifications] = Notification.{message, notificationTime}; 
		numActiveNotifications += 1;
	}
	else {
		// we'll delete the oldest element to make space for this one, so no notifications get missed
		memcpy(notifications.data, notifications.data+1, size_of(Notification));
		notifications[9] = Notification.{message, 20}; 
	}
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
#load "movement.jai";

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        // WR.disable_runtime_console();
    }
}
