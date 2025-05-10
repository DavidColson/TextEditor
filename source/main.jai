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
	document: *Document;
	rect: Rect;
	scrollPos := 0;

	// cursors
	cursor: Cursor;

	// Dialogs
	activeDialog: DialogType;
	commandPicker: CommandPicker;
	filesystemNav: FilesystemNavigator;
	fileFinder: FileFinder;

	// search state (this is too a dialog, may want to group it up)
	searchInput: InputField;
	currentRegex: Regexp;
	hasMatches := false;
	previousScrollState := 0;
	results: []DocumentRange;
}

DialogType :: enum u8 {
	NONE;
	COMMAND_PICKER;
	FILESYSTEM_NAVIGATOR;
	FILE_FINDER;
	SEARCH;
}

EditorMode :: enum u8 {
	NORMAL;
	INSERT;
	DIALOG;
}

Notification :: struct {
	content: string;
	timer: float64;
}

style: struct {
	// colors
	backgroundDark := Vector4.{0.10980, 0.12157, 0.14510, 1.0}; // #1C1F25
	backgroundMid := Vector4.{0.15686, 0.17255, 0.20392, 1.0};  // #282C34
	backgroundLight := Vector4.{0.23137, 0.25490, 0.29804, 1.0}; // #3B414C

	textPrimary := Vector4.{0.76471, 0.78039, 0.81569, 1.0}; // #C3C7D0
	textSecondary := Vector4.{0.36078, 0.38824, 0.43922, 1.0}; // #5C6370

	// fonts
	fontSize := 15;
	codeFont := string.["FiraMonoNerdFontMono-Regular.ttf", "consola.ttf"];
	uiFont := string.["segoeui.ttf"];
};

EDITOR_MODE_NUM :: #run enum_highest_value(EditorMode) + 1;

// globals
editorMode := EditorMode.NORMAL;
extendSelections := false;
focusedPanel : Panel;
watcher: File_Watcher(void);
watchedFiles: [..]string;
window: Window_Type;
windowWidth  : s32 = 1920;
windowHeight : s32 = 1080;
dpiScale := 1.0;
pendingQuit := false;
backupSaveTimer:float64 = 300;
requestRedraw := true;

notifications : [10]Notification;
numActiveNotifications := 0;
notificationTime: float64 = 10;

// registers
DEFAULT_REGISTER :: #char "+";
Registers :: struct {
	registerPool: Flat_Pool;
	registerAllocator: Allocator;
	table: Table(u8, [..]u8);
	selectedRegister:u8 = DEFAULT_REGISTER;
}
registers: Registers;

// fonts
fontUI: *Font;
fontCode: *Font;
fontIcons: *Font;

// options
textSize :: 15;
tabSize :: 4;
lineNumbers :: true;

Arguments :: struct {
}

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

	success, args, isSet, filesToOpen := parse_arguments(Arguments);
	if !success {
		return;
	}

	// create window
    window = create_window(windowWidth, windowHeight, "TextEditor");
	init_renderer(window);
	my_init_fonts();
	init_font_cache();
	load_fonts();
	init_ui();
	rebuild_key_map();

	registers.registerAllocator = Allocator.{ proc = flat_pool_allocator_proc, data = *registers.registerPool };

	if !init(*watcher, file_change_callback, watch_recursively = false) {
        push_notification("Could not initialize the file watcher. Files won't be reloaded. This is likely a bug.");
    }

	focusedPanel.rect.x = 0;
	focusedPanel.rect.y = 0;
	focusedPanel.rect.w = xx windowWidth;
	focusedPanel.rect.h = xx windowHeight;
	focusedPanel.activeDialog = .NONE;

	if filesToOpen.count > 0 {
		panel_set_active_document(*focusedPanel, document_open(filesToOpen[0]));
	}

	platform_set_backup_timer(window, do_backup_callback);

	lastTime := seconds_since_init();
    want_screenshot := false;
    while !pendingQuit {
		if !requestRedraw platform_wait_message();
		requestRedraw = false;

		now := seconds_since_init();
		delta : float64 = min(now - lastTime, 0.016);
		lastTime = now;

        Input.update_window_events();

        for Input.get_window_resizes() {
            if it.window == window {
                should_reinit := (it.width != windowWidth) || (it.height != windowHeight);

                windowWidth  = it.width;
                windowHeight = it.height;

				resize_backbuffer();

				focusedPanel.rect.x = 0;
				focusedPanel.rect.y = 0;
				focusedPanel.rect.w = xx windowWidth;
				focusedPanel.rect.h = xx windowHeight;

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for Input.events_this_frame {
            if it.type == .QUIT then pendingQuit = true;

			array_add(*uiState.events, it);
			// @todo: you will want to refactor this to send input events to the specific UI elements
			// that are active
			input_handler(it);
		}

		process_changes(*watcher);

		newDpiScale := platform_get_dpi_scale(window);
		if newDpiScale != dpiScale && newDpiScale != 0.0 {
			dpiScale = newDpiScale;
			my_init_fonts();
		}

		build_ui();

		panel_scroll_with_mouse(*focusedPanel, Input.mouse_delta_z);

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
		if numActiveNotifications > 0 {
			requestRedraw = true;
		}

		// @todo: may want to support 120hz or higher? 
        sleep_milliseconds(cast(s32) (16 - delta/1000));
        reset_temporary_storage();
    }
}

build_ui :: () {
	begin_ui();

	panel := *focusedPanel;
	panelRect := panel.rect;

	// global styles
	push_font_size(xx style.fontSize);
	push_palette(.{text = style.textPrimary, background=style.backgroundMid});
	push_text_padding(top_font_size() * 0.2);

	set_next_width(parent_pct(1.0, 1.0));
	set_next_height(parent_pct(1.0, 1.0));
	set_next_child_layout_axis(.Y);
	panelBox := box(.DRAW_BACKGROUND);
	{
		scope_parent(panelBox);

		// header
		palette := top_palette();
		palette.background = style.backgroundLight;
		set_next_palette(palette);
		set_next_width(parent_pct(1.0, 1.0));
		set_next_height(child_sum(1.0));
		set_next_child_layout_axis(.Y);
		header := box(.DRAW_BACKGROUND); 
		{
			padding := 0.3;
			scope_parent(header);
			scope_padding(em(padding, 1.0));
			{
				set_next_width(child_sum(1.0));
				set_next_height(child_sum(1.0));
				scope_parent(box(0));

				scope_padding(em(padding, 1.0));
				scope_width(text_dim(0.0, 1.0));
				scope_height(text_dim(0.0, 1.0));

				// mode
				palette.background = style.backgroundDark;
				set_next_palette(palette);
				modeText := "NORMAL";
				if extendSelections && editorMode == .NORMAL {
					modeText = "SELECT";
				}
				else if editorMode == .INSERT {
					modeText = "INSERT";
				}
				// set_next_text_padding(3);
				box(.DRAW_BACKGROUND | .DRAW_TEXT, modeText);

				// filename
				box(.DRAW_TEXT, path_filename(panel.document.path));

				// icon for file save status

				// lock icon

				// fill space
				set_next_width(parent_pct(1.0, 0.0));
				box(0);

				// pending keys
				pendingKeys := string.{keyMap.pendingKeyString.count, keyMap.pendingKeyString.data};
				box(.DRAW_TEXT, pendingKeys);

				// location
				cursorCoordinate := document_cursor_get_coordinate(*panel.cursor.head);
				locationText := tprint("Ln: % Col: % Byte: %", cursorCoordinate.line+1, cursorCoordinate.col, panel.cursor.head.documentOffset);
				box(.DRAW_TEXT, locationText);

				// line endings
				lineEndingText := "[Mixed]";
				if panel.document.lineEndings == .LF {
					lineEndingText = "LF";
				}
				else if panel.document.lineEndings == .CRLF {
					lineEndingText = "CRLF";
				}
				else if panel.document.lineEndings == .MIXED_MAJORITY_LF {
					lineEndingText = "[Mixed]";
				}
				box(.DRAW_TEXT, lineEndingText);

				// file type
				box(.DRAW_TEXT, "Jai");

				// panel options button
				palette.background = style.backgroundMid;
				set_next_palette(palette);
				box(.DRAW_BACKGROUND | .DRAW_TEXT, "Options");
			}
		}


		// code
		set_next_font(fontCode);
		set_next_width(parent_pct(1.0, 0.0));
		set_next_height(parent_pct(1.0, 0.0));
		codeBox := box(0, "code"); 
		codeBox.customDrawFunction = custom_draw_code;
		codeBox.customDrawUdata = cast(*void) panel;

		// search
		// set_next_palette(palette);
		// set_next_width(parent_pct(1.0, 1.0));
		// set_next_height(em(2.0, 1.0));
		// box(.DRAW_BACKGROUND); 
	}

	// Following this you can introduce scrolling as a feature for boxes for the code window

	// after this we will explore the picker/finder widgets

	// maybe this should be "ui_end_frame"
	end_ui();

	render_frame();
}

// @todo: probably want to move this somewhere else?
custom_draw_code :: (box: *UIBox, udata: *void) {
	panel:*Panel = cast(*Panel)udata;

	if panel.document {
		metrics := get_font_metrics(box.font, xx box.fontSize);
		documentLines := document_get_num_lines(panel.document);

		startVisibleLines : s64;
		endVisibleLines : s64;
		visibleLines: [..]string;
		visibleLines.allocator = temp;

		startVisibleLines = clamp(-panel.scrollPos / metrics.characterHeight, 0, documentLines - 1);
		endVisibleLines = clamp(startVisibleLines + cast(s64)box.rect.h / metrics.characterHeight, 0, documentLines - 1);

		// Draw line numbers
		gutterWidth := 0;
		if lineNumbers {
			y := box.rect.y + metrics.lineSpacing;
			maxLinesRun := generate_text_run(tprint(" % ", documentLines), xx box.fontSize, box.font,,temp);
			gutterWidth = xx maxLinesRun.width;

			for startVisibleLines..endVisibleLines {
				lineNoRun := generate_text_run(tprint("% ", it+1), xx box.fontSize, box.font,,temp);
				draw_text_run(lineNoRun, box.rect.x + (gutterWidth - lineNoRun.width), y, style.textSecondary);
				y += metrics.lineSpacing;
			}
		}

		// @todo: refactor to use document cursors to walk through text rather than get_line_content for every line
		linesOnScreen: [..]string;
		linesOnScreen.allocator = temp;
		for startVisibleLines..endVisibleLines {
			array_add(*linesOnScreen, document_get_line_content(panel.document, xx it));
		}

		// now actually draw the text
		x := box.rect.x + gutterWidth;
		y := box.rect.y + metrics.lineSpacing;
		for line: linesOnScreen {
			run := generate_text_run(line, xx box.fontSize, box.font,,temp);
			draw_text_run(run, x, y, style.textPrimary);
			y += metrics.lineSpacing;
		}
	}
}

do_backup_callback :: () {
	for * open_documents {
		if it.unsaved {
			builder : String_Builder;
			builder.allocator = temp;
			init_string_builder(*builder);

			append(*builder, path_strip_filename(get_path_of_running_executable()));
			append(*builder, "\\backups\\");
			append(*builder, path_filename(it.path));

			document_save(it, builder_to_string(*builder,,temp), true);
		}
	}
}

file_change_callback :: (watcher: *File_Watcher(void), change: *File_Change, userdata: *void) {
	found := array_find(watchedFiles, change.full_path);
	if found {
		success, doc := document_get_by_path(change.full_path);
		if change.events & .MODIFIED {
			// reload file
			if doc.unsaved == false {
				document_load_from_disk(doc);
			}
			else {
				// @todo: when we have nicer UI this should give a popup or something more explicit
				doc.unsaved = true;
				push_notification("File on disk changed, but you have unsaved edits");
			}
		}
		if change.events & .REMOVED {
			doc.unsaved = true;
		}
	}
}

write_register :: (name: u8, value: string) {
	if name == DEFAULT_REGISTER {
		os_clipboard_set_text(value);
	}

	// we write to the default yank
	registerData := find_or_add(*registers.table, name,,registers.registerAllocator); 
	array_reset_keeping_memory(registerData);

	array_reserve(registerData, value.count,,registers.registerAllocator);
	memcpy(registerData.data, value.data, value.count * size_of(u8));
	registerData.count = value.count;
}

read_register :: (name: u8) -> string {
	if name == DEFAULT_REGISTER {
		return os_clipboard_get_text();
	}
	else {
		registerData := table_find_pointer(*registers.table, name); 
		if registerData {
			return string.{registerData.count, registerData.data};
		}
	}
	return string.{};
}

load_fonts :: () {
	fontUI,_ = load_font("segoeui.ttf");

	// attempt to load my personal font, then fallback to consolas
	// @todo: ideally my font would be in a config file somewhere not in here
	success: bool;
	fontCode,success = load_font("FiraMonoNerdFontMono-Regular.ttf");
	if !success { 
		fontCode,_ = load_font("consola.ttf");
	}

	fontIcons = load_font_from_memory(#run read_entire_file("fonts/Font Awesome 6 Free-Regular-400.otf"));
}

// @todo: remove
my_init_fonts :: () {
	// @todo: embed the default font into the exe with #run
	my_font = New(Dynamic_Font);
	my_font.character_height = 10;
	my_font.mono_x_advance = 10;
}

// color stuff
hex_to_color_vec4 :: (src_hex: string) -> Vector4 {
    hex := src_hex;
    if hex.count == 6 then hex = tprint("%FF", hex);
    if hex.count != 8 return Vector4.{};

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

    return c;
}

// utilities 
convert_cursors_to_coordinate_range :: (cursor1: DocumentCursor, cursor2: DocumentCursor, includeCursor: bool = true) -> start: Coordinate, end: Coordinate {
	rangeStart: Coordinate;
	rangeEnd: Coordinate;
	cursorBonus := ifx includeCursor then 1 else 0;

	coordinate1 := document_cursor_get_coordinate(*cursor1);
	coordinate2 := document_cursor_get_coordinate(*cursor2);

	if coordinate1.line < coordinate2.line {
		// coordinate1 is clearly earlier than coordinate2
		rangeStart.line = coordinate1.line;
		rangeStart.col = coordinate1.col;
		rangeEnd.line = coordinate2.line;
		rangeEnd.col = coordinate2.col+cursorBonus;
	}
	else if coordinate1.line > coordinate2.line { 
		// coordinate2 is clearly earlier than the coordinate1
		rangeStart.line = coordinate2.line;
		rangeStart.col = coordinate2.col;
		rangeEnd.line = coordinate1.line;
		rangeEnd.col = coordinate1.col+cursorBonus; // cursor itself is considered part of the selection
	}
	else {
		// they are on the same line, pick based on column
		if coordinate1.col <= coordinate2.col {
			rangeStart.line = coordinate1.line;
			rangeStart.col = coordinate1.col;
			rangeEnd.line = coordinate2.line;
			rangeEnd.col = coordinate2.col+cursorBonus;
		}
		else {
			rangeStart.line = coordinate2.line;
			rangeStart.col = coordinate2.col;
			rangeEnd.line = coordinate1.line;
			rangeEnd.col = coordinate1.col+cursorBonus;
		}
	}
	return rangeStart, rangeEnd;
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
	requestRedraw = true;
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

// simple input field

InputField :: struct {
	text: [..]u8;
	cursor: s32;
	onEditCallback: (*void, string);
	userData: *void;
}

input_field_reset :: (inputField: *InputField) {
	array_reset(*inputField.text);
	inputField.cursor = 0;
}

input_field_reset_keeping_memory :: (inputField: *InputField) {
	inputField.text.count = 0;
	inputField.cursor = 0;
}

input_field_get_text :: (inputField: *InputField) -> string {
	return string.{inputField.text.count, inputField.text.data};
}

Utf8_Char :: struct {
    bytes: [4] u8;
    count: s32;
}

// @todo: temporary stub until we replace it with our custom renderer 
Dynamic_Font :: struct {
    character_height:       int = 10;
	mono_x_advance:			int = 10;
	render_new_lines: bool = false;
	render_tabs: bool = false;
}
my_font: *Dynamic_Font;

Input :: #import "Input";
#import "Window_Creation";
#import "Basic";
#import "Math";
#import "System";
#import "String";
#import "File";
#import "Hash";
#import "File_Utilities";
#import "Unicode";
#import "Sort";
#import "Flat_Pool";
#import "Hash_Table";
#import "Clipboard";
#import "Command_Line";
#import "File_Watcher";
#import "Bucket_Array";

#load "rect.jai";
#load "command_picker.jai";
#load "filesystem_navigator.jai";
#load "file_finder.jai";
#load "keymap.jai";
#load "document.jai";
#load "commands.jai";
#load "panel.jai";
#load "ui.jai";
#load "renderer.jai";
#load "font.jai";
#load "uniform/module.jai";

#if OS == .WINDOWS {
	#load "platform_windows.jai";
}


