BuildType :: enum u8
{
	DEBUG;
	OPTIMIZED;
	RELEASE;
}

Document :: struct {
	// @todo arena for the buffer so we can have lots of spare memory addresses for expansion
	// normal memory for lines and path, make a free document function
	path: string;
    bytes: []u8;
    lines: [..]string;
}

Panel :: struct {
	// @todo make a free panel function which yeets the wrapped lines
	document: *Document;

	WrappedLine :: struct {
		line: string;
		lineNum: s32;
	}
	wrappedLines: [..]WrappedLine;

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
lineWrap :: true;
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

	rebuild_command_mapping();

	focusedPanel.rect.x = 0;
	focusedPanel.rect.y = 0;
	focusedPanel.rect.w = xx windowWidth;
	focusedPanel.rect.h = xx windowHeight;
	focusedPanel.document = *mainDocument;

	open_document("C:/Dev/TextEditor/build.jai");

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
				rescan_wrapped_lines(focusedPanel);

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
		scrollPos += Input.mouse_delta_z;
		if !lineWrap {
			scrollPos = clamp(scrollPos, -(my_font.character_height * mainDocument.lines.count) + my_font.character_height * 5, 0);
		}
		else {
			scrollPos = clamp(scrollPos, -(my_font.character_height * focusedPanel.wrappedLines.count) + my_font.character_height * 5, 0);
		}

        sleep_milliseconds(16);
        reset_temporary_storage();
    }
}

open_document :: (path: string) {
    file := read_entire_file(path);

	mainDocument.path = copy_string(path); // @todo put in arena for this specific document (i.e. reset when document is released)
	mainDocument.bytes.data = file.data;
	mainDocument.bytes.count = file.count;

	array_reset_keeping_memory(*mainDocument.lines);

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

	rescan_wrapped_lines(focusedPanel);
}

my_init_fonts :: () {
    my_font = Simp.get_font_at_size("fonts", "FiraMonoNerdFontMono-Medium.ttf", textSize);
    assert(my_font != null);
}

// Panel specific code
rescan_wrapped_lines :: (panel: Panel) {
	assert(my_font.is_monospace);

	maxLineWidth : = (cast(s64)panel.rect.w - 1) / xx my_font.mono_x_advance;
	if lineNumbers {
		nDigits:= tprint("%", panel.document.lines.count).count;
		maxLineWidth -= my_font.mono_x_advance * (nDigits + 2); // extra 2 for padding
	}

	array_reset_keeping_memory(*panel.wrappedLines);
    currentLineWidth:= 0;
	currentActualLine:= 1;
	lastLineBreak := 0;
	for byte, i: mainDocument.bytes {

		if byte == #char "\t" {
			currentLineWidth += (tabSize - currentLineWidth % tabSize);
		} 
		else if byte != #char "\n" && byte != #char "\r" { // don't count line endings for wrapping
			currentLineWidth += 1;
		}

		if currentLineWidth > maxLineWidth {
			wrappedLine: Panel.WrappedLine;
			wrappedLine.lineNum = cast(s32)currentActualLine;
			wrappedLine.line.data = panel.document.bytes.data + lastLineBreak;
			wrappedLine.line.count = i - lastLineBreak;
			lastLineBreak = i;
			array_add(*panel.wrappedLines, wrappedLine);
			currentLineWidth = 0;
		}

		if byte == #char "\n" {
			wrappedLine: Panel.WrappedLine;
			wrappedLine.lineNum = cast(s32)currentActualLine;
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
	lastLine.lineNum = cast(s32)currentActualLine;
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
KeyMappingDesc :: struct {
	mode: EditorMode = .NORMAL;
	keys: string = "";
}

Command :: struct {
	name: string;
	execute: ();
	mappings: []KeyMappingDesc;
}

KeyMap :: struct {
	memory : Flat_Pool;
	allocator: Allocator;
	root: [EDITOR_MODE_NUM]KeyMapNode;
}
keyMap: KeyMap;

KeyMapNode :: struct {
	children: *Table(string, *KeyMapNode); // null if leaf node
	cmd: *Command;
}

commandList :: Command.[
	.{ "Open Command List", open_command_picker, .[.{ mode=.NORMAL, keys=":"}] },
	.{ "Open File", open_file, .[.{ mode=.NORMAL, keys="ctrl+s"}]},
	.{ "Save File As", save_file, .[.{}]},
	.{ "Quit", quit, .[.{mode=.NORMAL, keys="Q"}]},

	// filesystem navigator
	.{ "FSN Path Delete", filesystem_nav_delete_path, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="<backspace>"}] },
	.{ "FSN Select Next", filesystem_nav_select_next, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="<down>"}] },
	.{ "FSN Select Previous", filesystem_nav_select_previous, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="<up>"}] },
	.{ "FSN Action Item", filesystem_nav_action_item, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="<enter>"}] },
	.{ "FSN Delete Item", filesystem_nav_delete_item, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="d"}] },
	.{ "FSN Rename/Move Item", filesystem_nav_rename_move_item, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="r"}] },

	// Command Picker
	.{ "CP Delete Previous Char", command_picker_delete_char, .[.{ mode=.COMMAND_PICKER, keys="<backspace>"}] },
	.{ "CP Execute Command", command_picker_execute_command, .[.{ mode=.COMMAND_PICKER, keys="<enter>"}] },
	.{ "CP Select Next", command_picker_select_next, .[.{ mode=.COMMAND_PICKER, keys="<down>"}] },
	.{ "CP Select Previous", command_picker_select_previous, .[.{ mode=.COMMAND_PICKER, keys="<up>"}] },

	// special keys will be <backspace>, <esc> etc
	// modifiers will be ctrl+b, W, alt+g, ctrl+<tab>
	// note, we dont store shift as a modifier, we store the capital letter or symbol directly
	// Modifiers plus letters would be ctrl+wl
	.{ "Enter Normal Mode", enter_normal_mode, .[
		.{ mode=.INSERT, keys="<escape>"},
		.{ mode=.COMMAND_PICKER, keys="<escape>"},
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="<escape>"},
	]},
];

rebuild_command_mapping :: ()  {
	keyMap.allocator = Allocator.{proc = flat_pool_allocator_proc, data = *keyMap.memory};

	for mode: 0..EDITOR_MODE_NUM-1 {
		keyMap.root[mode].children = New(Table(string, *KeyMapNode),,keyMap.allocator);
	}

	// for loop through the command list
	for * cmd : commandList {
		for mapping : cmd.mappings {
			// Grab the mapping for each command
			// for each key in the mapping (single char, or modified key, or special key)
			keys := mapping.keys;
			curNode := *keyMap.root[mapping.mode]; 
			while keys.count > 0 {
				hashKey:= keys;
				if begins_with(keys, "ctrl+") {
					advance(*keys, 5); 
				}

				if begins_with(keys, "shift+") {
					assert(false, "You can't bind shift like this, use the capital letter/symbol directly");
				}

				if begins_with(keys, "alt+") {
					advance(*keys, 4); 
				}

				if begins_with(keys, "<backspace>") {
					advance(*keys, 11); 
				}
				else if begins_with(keys, "<enter>") {
					advance(*keys, 7); 
				}
				else if begins_with(keys, "<escape>") {
					advance(*keys, 8); 
				}
				else if begins_with(keys, "<left>") {
					advance(*keys, 6); 
				}
				else if begins_with(keys, "<right>") {
					advance(*keys, 7); 
				}
				else if begins_with(keys, "<up>") {
					advance(*keys, 4); 
				}
				else if begins_with(keys, "<down>") {
					advance(*keys, 6); 
				}
				else {
					advance(*keys, 1); // take just the one letter key
				}

				// hashkey should be just what we grabbed from this loop iteration
				hashKey.count = hashKey.count - keys.count;

				// a few possibilities
				// if keys.count == 0, this is a leaf
				// If there's already an entry in the current table, assert
				// No existing entry, add the entry now
				// if keys.count > 0 this is not a leaf
				// If there's no entry, add a new non-leaf entry set this as current table
				// if there's already a non-leaf entry, set as current and loop
				// if there's already a leaf entry, assert

				if keys.count == 0 {
					assert(!table_contains(curNode.children, hashKey), "Mapping already exists");
					newNode := New(KeyMapNode,,keyMap.allocator);
					newNode.cmd = cmd;
					table_add(curNode.children, hashKey, newNode);
				}
				else if keys.count > 0 {
					entry, exists := table_find(curNode.children, hashKey);
					if !exists { 
						newNode := New(KeyMapNode,,keyMap.allocator);
						newNode.children = New(Table(string, *KeyMapNode),,keyMap.allocator);
						curNode = <<table_add(curNode.children, hashKey, newNode); 
					}
					else {
						assert(entry.cmd == null, "Start of this key sequence already exists as a direct mapping");
						curNode = entry;
					}
				}
			}
		}
	}
	pendingKeySequence = *keyMap.root[editorMode];
}

quit :: () {
	pendingQuit = true;
}

open_file :: () {
	editorMode = .FILESYSTEM_NAVIGATOR;
	filesystem_nav_refresh_directory_list(*focusedPanel.filesystemNav);
}

save_file :: () {
}

enter_normal_mode :: () {
	if editorMode == .FILESYSTEM_NAVIGATOR {
		filesystem_nav_reset(*focusedPanel.filesystemNav);
	}
	else if editorMode == .COMMAND_PICKER {
		command_picker_reset(*focusedPanel.commandPicker);
	}
	editorMode = .NORMAL;
}

open_command_picker :: () {
	editorMode = .COMMAND_PICKER;

    push_allocator(flat_pool_allocator_proc, *focusedPanel.commandPicker.memory);

	for command: commandList {
		entry := array_add(*focusedPanel.commandPicker.filteredCommandList);
		entry.command = *command;
		entry.sortKey = 10;
	}
}

// @todo: move
pendingKeySequence: *KeyMapNode;
ctrlHeld:= false;
altHeld:= false;
shiftHeld:= false;
input_handler :: (event: Input.Event) {
	keyString: string;

	if event.type == .TEXT_INPUT {
		char: Utf8_Char = convert_utf32_to_utf8(event.utf32);

		// if there are no pending key sequences allow the current mode to take the text input
		if pendingKeySequence == *keyMap.root[editorMode] {
			if editorMode == .COMMAND_PICKER {
				command_picker_handle_text_input(*focusedPanel.commandPicker, char);
				return;
			}
			else if editorMode == .FILESYSTEM_NAVIGATOR {
				filesystem_nav_handle_text_input(*focusedPanel.filesystemNav, char);
				return;
			}
		}
		builder : String_Builder;
		builder.allocator = temp;
		init_string_builder(*builder);

		if ctrlHeld {
			append(*builder, "ctrl+");
		}
		if altHeld {
			append(*builder, "alt+");
		}
		append(*builder, to_string(*char));

		keyString= builder_to_string(*builder,,temp);
	}
	else if event.type == .KEYBOARD {
		builder : String_Builder;
		builder.allocator = temp;
		init_string_builder(*builder);

		if event.key_pressed && event.key_code == .CTRL {
			ctrlHeld = true;
		}
		else if !event.key_pressed && event.key_code == .CTRL {
			ctrlHeld = false;
		}
		if event.key_pressed && event.key_code == .ALT {
			altHeld = true;
		}
		else if !event.key_pressed && event.key_code == .ALT {
			altHeld = false;
		}
		if event.key_pressed && event.key_code == .SHIFT {
			shiftHeld = true;
		}
		else if !event.key_pressed && event.key_code == .SHIFT {
			shiftHeld = false;
		}

		// modifiers first
		if ctrlHeld {
			append(*builder, "ctrl+");
		}
		if shiftHeld {
			append(*builder, "shift+");
		}
		if altHeld {
			append(*builder, "alt+");
		}

		gotInput := true;
		if event.key_pressed && event.key_code == .BACKSPACE {
			append(*builder, "<backspace>");
		}
		else if event.key_pressed && event.key_code == .ESCAPE {
			append(*builder, "<escape>");
		}
		else if event.key_pressed && event.key_code == .ARROW_UP {
			append(*builder, "<up>");
		}
		else if event.key_pressed && event.key_code == .ARROW_DOWN {
			append(*builder, "<down>");
		}
		else if event.key_pressed && event.key_code == .ENTER {
			append(*builder, "<enter>");
		}
		else {
			gotInput = false;
		}

		if gotInput keyString = builder_to_string(*builder,,temp);
	}

	if keyString.count == 0 return;

	nodePtr := table_find_pointer(pendingKeySequence.children, keyString);
	if nodePtr {
		node := <<nodePtr;
		if node.cmd {
			node.cmd.execute();
			pendingKeySequence = *keyMap.root[editorMode];
		}
		else {
			pendingKeySequence = node;
		}
	}
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

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console();
    }
}
