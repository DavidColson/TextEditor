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
commandPicker: CommandPicker;
fileSystemNav: FileSystemNavigator;
scrollPos := 0;

EditorMode :: enum_flags u8 {
	NORMAL;
	INSERT;
	COMMAND_PICKER;
	FILESYSTEM_NAVIGATOR;
}

Command :: struct {
	name: string;
	execute: ()->string;
	// really the mapping and the mode should be tied together as one
	// you want to be able to access any command in any mode, given an appropriate mapping
	mode: EditorMode;
	mapping: string;
}
// command map
// @Todo for fast access to the command when actually doing commands
// we should store a hash table that maps the mapping to the command
// Can probably generate it at startup
commandList :: Command.[
	.{ "Open Command List", open_command_picker, .NORMAL, ":"},
	.{ "Open File", open_file, .COMMAND_PICKER, ":o"},
	.{ "Save File As", save_file, .COMMAND_PICKER, ":w"},
];

CommandPicker :: struct {
	// @todo several arrays in here using memory, should group it all into an arena
	textInput: [..]u8;
	cursor: s32;

	// @todo, undos, cursor movement etc

	CommandEntry :: struct {
		command: *Command;
		// right now this is just the search score, but i'd like to add
		// the last use time of the command, or how often it's used
		sortKey: s64;
	}
	filteredCommandList: [..]CommandEntry;
	selectedCommand:s32;
}

FileSystemNavigator :: struct {
	textInput: [..]u8;
	cursor: s32;

	currentPath: Path;
	itemList: [..]Item;
	selectedItem:s64;
	numToDisplay:s64; // number of items with positive sortkeys

	Item :: struct {
		name: string;
		sortKey: s64;
	}
}

// options
lineWrap := true;
textSize := 15;
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
	mainPanel.rect.w = xx windowWidth;
	mainPanel.rect.h = xx windowHeight;

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
				mainPanel.rect.w = xx windowWidth;
				mainPanel.rect.h = xx windowHeight;
				rescan_wrapped_lines(mainPanel);

                if should_reinit my_init_fonts();  // Resize the font for the new window size.
            }
        }

        for Input.events_this_frame {
            if it.type == .QUIT then quit = true;

			if editorMode & .NORMAL {
				normal_mode_input_handler(it);
			}
			else if editorMode & .COMMAND_PICKER {
				command_picker_input_handler(it);
			}
			else if editorMode & .FILESYSTEM_NAVIGATOR {
				filesystem_nav_input_handler(it);
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

draw_rect :: (rect: Rect, color: Vector4) {
	Simp.immediate_quad(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, color);
}

draw_filesystem_navigator :: (panel: Panel) {
	// @todo pull out to general style settings
	entryPadding := 5;
	entryHeight := my_font.character_height + entryPadding * 2;

	// @todo, this is duplicating below, pull it out
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;

	navigatorRect:Rect;
	navigatorRect.w = panel.rect.w / 2;
	navigatorRect.h = cast(float) entryHeight * (fileSystemNav.numToDisplay + 1);
	navigatorRect.x = panel.rect.x + (panel.rect.w - navigatorRect.w) / 2;
	navigatorRect.y = panel.rect.y + headerHeight;

	Simp.set_shader_for_color();
	draw_rect(navigatorRect, Vector4.{0.4, 0.4, 0.4, 1.0});

	inputRect: Rect;
	inputRect, navigatorRect = cut_bottom(navigatorRect, xx entryHeight);
	inputRect = shrink(inputRect, 3);
	draw_rect(inputRect, Vector4.{0.5, 0.5, 0.5, 1.0});

	// draw current path as blocks
	curPathRect: Rect;
	curPathRect = shrink(inputRect, 2);
	textY := inputRect.y + entryHeight - 10;
	textX := curPathRect.x + 2;
	for fileSystemNav.currentPath.words {
		width := Simp.prepare_text(my_font, it);
		blockRect: Rect;
		blockRect, curPathRect = cut_left(curPathRect, xx width, 2);
		Simp.set_shader_for_color();
		draw_rect(blockRect, Vector4.{0.4, 0.4, 0.4, 1.0});

		Simp.draw_prepared_text(my_font, xx blockRect.x, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		textX = blockRect.x + blockRect.w + 2;
	}

	// draw input filter text
	Simp.prepare_text(my_font, string.{fileSystemNav.textInput.count, fileSystemNav.textInput.data});
	Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});

	entryRect := cut_bottom(navigatorRect, xx entryHeight);
	for * item, i: fileSystemNav.itemList  {
		if item.sortKey == 0 continue;

		if i == fileSystemNav.selectedItem {
			cmdID := fileSystemNav.selectedItem+1;
			Simp.set_shader_for_color();
			draw_rect(entryRect, Vector4.{0.5, 0.5, 0.5, 1.0});
		}

		width := Simp.prepare_text(my_font, item.name);

		textX = entryRect.x + entryPadding;
		textY = entryRect.y + entryHeight - 8;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		entryRect.y += entryHeight;
	}
}

draw_command_picker :: (panel: Panel) {
	// @todo pull out to general style settings
	commandEntryPadding := 5;
	commandEntryHeight := my_font.character_height + commandEntryPadding * 2;

	// @todo, this is duplicating below, pull it out
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;

	commandsRect:Rect;
	commandsRect.w = panel.rect.w / 2;
	commandsRect.h = cast(float) commandEntryHeight * (commandPicker.filteredCommandList.count + 1);
	commandsRect.x = panel.rect.x + (panel.rect.w - commandsRect.w) / 2;
	commandsRect.y = panel.rect.y + headerHeight;

	Simp.set_shader_for_color();
	draw_rect(commandsRect, Vector4.{0.4, 0.4, 0.4, 1.0});

	inputRect: Rect;
	inputRect, commandsRect = cut_bottom(commandsRect, xx commandEntryHeight);
	inputRect = shrink(inputRect, 3);
	draw_rect(inputRect, Vector4.{0.5, 0.5, 0.5, 1.0});

	Simp.prepare_text(my_font, string.{commandPicker.textInput.count, commandPicker.textInput.data});
	textX := inputRect.x + commandEntryPadding;
	textY := inputRect.y + commandEntryHeight - 10;
	Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});

	entryRect := cut_bottom(commandsRect, xx commandEntryHeight);
	for commandEntry, i: commandPicker.filteredCommandList  {
		if commandEntry.sortKey == 0 continue;

		if i == commandPicker.selectedCommand {
			cmdID := commandPicker.selectedCommand+1;
			Simp.set_shader_for_color();
			draw_rect(entryRect, Vector4.{0.5, 0.5, 0.5, 1.0});
		}

		command := commandEntry.command;
		width := Simp.prepare_text(my_font, command.name);

		textX = entryRect.x + commandEntryPadding;
		textY = entryRect.y + commandEntryHeight - 8;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		entryRect.y += commandEntryHeight;
	}
}

draw_panel :: (panel: Panel) {

	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;

	// Draw actual code + line numbers
	heightForCode := panel.rect.h - headerHeight;

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
		endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, mainDocument.lines.count - 1);
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
		endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, mainPanel.wrappedLines.count - 1);
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

	// Draw command list
	if editorMode == .COMMAND_PICKER {
		draw_command_picker(panel);
	}

	if editorMode == .FILESYSTEM_NAVIGATOR {
		draw_filesystem_navigator(panel);
	}
}

my_init_fonts :: () {
    my_font = Simp.get_font_at_size("fonts", "FiraMonoNerdFontMono-Medium.ttf", textSize);
    assert(my_font != null);
}

rescan_wrapped_lines :: (panel: Panel) {
	// todo non monospace fonts
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
open_file :: () -> string {
	editorMode = .FILESYSTEM_NAVIGATOR;

	filesystem_nav_refresh_directory_list();
	return "open file";
}

save_file :: () -> string {
	return "save file";
}

open_command_picker :: () -> string {
	editorMode = .COMMAND_PICKER;

	commandPicker.cursor = 0;
	commandPicker.selectedCommand = 0;
	array_reset_keeping_memory(*commandPicker.filteredCommandList);

	for command: commandList {
		entry := array_add(*commandPicker.filteredCommandList);
		entry.command = *command;
		entry.sortKey = 10;
	}
	
	// @todo recommend sorting on last used command here on initial show of the command list

	return "hello world";
}

// code for specific modes
command_picker_input_handler :: (event: Input.Event) {
	if event.type == .KEYBOARD {
		// @todo refactor these into commands, bound in the appropriate mode
		// though these are conceptually similar, for now just have a different command for
		// command mode delete vs insert mode delete
		if event.key_pressed && event.key_code == .BACKSPACE {
			commandPicker.textInput.count -= 1;
			commandPicker.cursor -= 1;
			if commandPicker.textInput.count <= 0 {
				commandPicker.textInput.count = 0;
				command_picker_refresh_list();
				return;
			}
			command_picker_refresh_list();
		}

		if event.key_pressed && event.key_code == .ESCAPE {
			editorMode = .NORMAL;
			commandPicker.textInput.count = 0;
		}

		if event.key_pressed && event.key_code == .ENTER {
			cmd := commandPicker.filteredCommandList[commandPicker.selectedCommand].command; 
			cmd.execute();
		}
		
		if event.key_pressed && event.key_code == .ARROW_UP {
			maxCommand := commandPicker.filteredCommandList.count - 1;
			commandPicker.selectedCommand = clamp(commandPicker.selectedCommand-1, 0, xx maxCommand);
		}
		if event.key_pressed && event.key_code == .ARROW_DOWN {
			maxCommand := commandPicker.filteredCommandList.count - 1;
			commandPicker.selectedCommand = clamp(commandPicker.selectedCommand+1, 0, xx maxCommand);
		}
	}
	else if event.type == .TEXT_INPUT {
		char: Utf8_Char = convert_utf32_to_utf8(event.utf32);

		// process the actual text input on the command line
		for 0..char.count-1 {
			array_add(*commandPicker.textInput, char.bytes[it]);
			commandPicker.cursor += 1;
		}

		// update the filtered command list
		command_picker_refresh_list();
	}
}

filesystem_nav_input_handler :: (event: Input.Event) {
	if event.type == .KEYBOARD {
		// @todo refactor these into commands, bound in the appropriate mode
		// though these are conceptually similar, for now just have a different command for
		// command mode delete vs insert mode delete
		if event.key_pressed && event.key_code == .BACKSPACE {
			if fileSystemNav.currentPath.words.count > 0 && fileSystemNav.textInput.count == 0 {
				fileSystemNav.currentPath.words.count -= 1;
				filesystem_nav_refresh_directory_list();
				return;
			}

			fileSystemNav.textInput.count -= 1;
			fileSystemNav.cursor -= 1;
			if fileSystemNav.textInput.count <= 0 {
				fileSystemNav.textInput.count = 0;
				filesystem_nav_filter_directory_list();

				return;
			}
			filesystem_nav_filter_directory_list();
		}

		if event.key_pressed && event.key_code == .ESCAPE {
			editorMode = .NORMAL;
			fileSystemNav.textInput.count = 0;
		}

		if event.key_pressed && event.key_code == .ENTER {
			item := fileSystemNav.itemList[fileSystemNav.selectedItem];

			// only if item is a directory
			if platform_is_path_directory(fileSystemNav.currentPath) {
				// need to append item to the current path
				array_add(*fileSystemNav.currentPath.words, item.name);
				// then refresh the itemlist with new entries in the new path
				filesystem_nav_refresh_directory_list();

				// then clear the filter input text
				fileSystemNav.textInput.count = 0;
			}
		}

		if event.key_pressed && event.key_code == .ARROW_UP {
			maxItems := fileSystemNav.itemList.count - 1;
			fileSystemNav.selectedItem = clamp(fileSystemNav.selectedItem-1, 0, xx maxItems);
		}
		if event.key_pressed && event.key_code == .ARROW_DOWN {
			maxItems := fileSystemNav.itemList.count - 1;
			fileSystemNav.selectedItem = clamp(fileSystemNav.selectedItem+1, 0, xx maxItems);
		}
	}
	else if event.type == .TEXT_INPUT {
		char: Utf8_Char = convert_utf32_to_utf8(event.utf32);

		// process the actual text input on the command line
		for 0..char.count-1 {
			array_add(*fileSystemNav.textInput, char.bytes[it]);
			fileSystemNav.cursor += 1;
		}
		filesystem_nav_filter_directory_list();
	}
}

filesystem_nav_refresh_directory_list :: () {
	fileSystemNav.numToDisplay = 0;
	array_reset_keeping_memory(*fileSystemNav.itemList);
	// start with drives
	if fileSystemNav.currentPath.words.count == 0 {
		// @todo, at some point it should use the project directory maybe, or the current file
		for platform_enumerate_logical_drives() {
			item := array_add(*fileSystemNav.itemList);
			item.name = copy_string(it);
			item.sortKey = 1;
			fileSystemNav.numToDisplay += 1;
		}
	} else {
		visitor :: (info: *File_Visit_Info, items: *[..]FileSystemNavigator.Item) {
			new_item: FileSystemNavigator.Item;
			new_item.name = copy_string(info.short_name); // put in arena for fsn
			new_item.sortKey = 1;
			array_add(items, new_item);
			fileSystemNav.numToDisplay += 1;
		}
		visit_files(path_to_string(fileSystemNav.currentPath,,temp), false, *fileSystemNav.itemList, visitor, visit_directories=true);
	}
}

filesystem_nav_filter_directory_list :: () {
	fileSystemNav.numToDisplay = 0;
	search_query:= string.{fileSystemNav.textInput.count, fileSystemNav.textInput.data};
	for * item: fileSystemNav.itemList {
		score := fuzzy_search(item.name, search_query);
		item.sortKey = score;
		if score > 0 {
			fileSystemNav.numToDisplay += 1;
		}
	}

	compare_entries :: (e1: FileSystemNavigator.Item, e2: FileSystemNavigator.Item) -> s64 {
		diff := e2.sortKey - e1.sortKey;
		if diff != 0 return diff;
		// todo: should also sort on other things like folder or file etc
		return memcmp(e1.name.data, e2.name.data, min(e1.name.count, e2.name.count));
	}
	quick_sort(fileSystemNav.itemList, compare_entries);

	maxItem := fileSystemNav.itemList.count - 1;
	fileSystemNav.selectedItem = clamp(fileSystemNav.selectedItem-1, 0, xx maxItem);
}

command_picker_refresh_list :: () {
	search_query:= string.{commandPicker.textInput.count, commandPicker.textInput.data};
	array_reset_keeping_memory(*commandPicker.filteredCommandList);
	for command: commandList {
		score := fuzzy_search(command.name, search_query);
		entry := array_add(*commandPicker.filteredCommandList);
		entry.command = *command;
		entry.sortKey = score;
	}

	compare_entries :: (e1: CommandPicker.CommandEntry, e2: CommandPicker.CommandEntry) -> s64 {
		diff := e2.sortKey - e1.sortKey;
		if diff != 0 return diff;
		return memcmp(e1.command.name.data, e2.command.name.data, min(e1.command.name.count, e2.command.name.count));
	}
	quick_sort(commandPicker.filteredCommandList, compare_entries);

	maxCommand := commandPicker.filteredCommandList.count - 1;
	commandPicker.selectedCommand = clamp(commandPicker.selectedCommand-1, 0, xx maxCommand);
}

normal_mode_input_handler :: (event: Input.Event) {
	if event.type == .TEXT_INPUT {
		for command: commandList {
			// is this command relevant for the current mode?
			if command.mode & editorMode {
				char: Utf8_Char = convert_utf32_to_utf8(event.utf32);
				input:= to_string(*char);

				// @todo there will be mappings that are multi character, so you 
				// will want to match against the first character only at first
				// if there is a match, then cool, 
				// if there are _multiple_ matches, then you need to save the input
				// and wait for another, continuing to check for a match
				// or similarly, command such as match mode, may have "args", which we'll have to communicate
				// in the mapping, and then wait for the required number of chars for the arg before continuing


				// one implementation could be a hash tree, where each entry could be a leaf (a command) or another hash table
				if input == command.mapping {
					// found the desired command
					mainPanel.commandMessage = command.execute();
				}
			}
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

platform_is_path_directory :: (path: Path) -> bool {
    push_allocator(temp);
	path_str := path_to_string(path);
	attrib := GetFileAttributesW(utf8_to_wide_new(path_str));
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
#import "System";  // For get_path_of_running_executable. @Cleanup.
#import "String";  // For path_strip_filename. @Cleanup.
#import "File";
#import "File_Utilities";
#import "Unicode";
#import "Sort";

kernel32 :: #system_library "kernel32";
#import "Windows";
#import "Windows_Utf8";
GetLogicalDriveStringsW :: (nBufferLength: DWORD, lpBuffer: *u16) -> DWORD #foreign kernel32;

#load "rect.jai";

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        WR.disable_runtime_console();
    }
}
