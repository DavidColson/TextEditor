CommandPicker :: struct {
	memory : Flat_Pool;

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

command_picker_reset :: (state: *CommandPicker) {
	state.cursor = 0;
	state.selectedCommand = 0;
	array_reset(*state.filteredCommandList);
	state.textInput.count = 0;
	#if BUILD_TYPE == BuildType.DEBUG {
		reset(*state.memory, overwrite_memory=true);
	} else {
		reset(*state.memory, overwrite_memory=false);
	}
}

command_picker_input_handler :: (state: *CommandPicker, event: Input.Event) {
	if event.type == .KEYBOARD {
		// @todo refactor these into commands, bound in the appropriate mode
		// though these are conceptually similar, for now just have a different command for
		// command mode delete vs insert mode delete
		if event.key_pressed && event.key_code == .BACKSPACE {
			state.textInput.count -= 1;
			state.cursor -= 1;
			if state.textInput.count <= 0 {
				state.textInput.count = 0;
				command_picker_refresh_list(state);
				return;
			}
			command_picker_refresh_list(state);
		}

		if event.key_pressed && event.key_code == .ESCAPE {
			editorMode = .NORMAL;
			command_picker_reset(state);
		}

		if event.key_pressed && event.key_code == .ENTER {
			cmd := state.filteredCommandList[state.selectedCommand].command; 
			editorMode = .NORMAL;
			cmd.execute();
			command_picker_reset(state);
		}
		
		if event.key_pressed && event.key_code == .ARROW_UP {
			maxCommand := state.filteredCommandList.count - 1;
			state.selectedCommand = clamp(state.selectedCommand-1, 0, xx maxCommand);
		}
		if event.key_pressed && event.key_code == .ARROW_DOWN {
			maxCommand := state.filteredCommandList.count - 1;
			state.selectedCommand = clamp(state.selectedCommand+1, 0, xx maxCommand);
		}
	}
	else if event.type == .TEXT_INPUT {
		char: Utf8_Char = convert_utf32_to_utf8(event.utf32);

		// process the actual text input on the command line
		{
			push_allocator(flat_pool_allocator_proc, *state.memory);
			for 0..char.count-1 {
				array_add(*state.textInput, char.bytes[it]);
				state.cursor += 1;
			}
		}

		// update the filtered command list
		command_picker_refresh_list(state);
	}
}

command_picker_refresh_list :: (state: *CommandPicker) {
    push_allocator(flat_pool_allocator_proc, *state.memory);

	search_query:= string.{state.textInput.count, state.textInput.data};
	array_reset_keeping_memory(*state.filteredCommandList);

	for command: commandList {
		score := fuzzy_search(command.name, search_query);
		entry := array_add(*state.filteredCommandList);
		entry.command = *command;
		entry.sortKey = score;
	}

	compare_entries :: (e1: CommandPicker.CommandEntry, e2: CommandPicker.CommandEntry) -> s64 {
		diff := e2.sortKey - e1.sortKey;
		if diff != 0 return diff;
		return memcmp(e1.command.name.data, e2.command.name.data, min(e1.command.name.count, e2.command.name.count));
	}
	quick_sort(state.filteredCommandList, compare_entries);

	maxCommand := state.filteredCommandList.count - 1;
	state.selectedCommand = clamp(state.selectedCommand-1, 0, xx maxCommand);
}

