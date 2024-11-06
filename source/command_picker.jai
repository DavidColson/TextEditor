CommandPicker :: struct {
	// @todo several arrays in here using memory, should group it all into an arena
	// reset the arena and memset this struct when finished with the tool
	// probably make a reset tool function which zeroes what it needs to
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
			commandPicker.textInput.count = 0;
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

