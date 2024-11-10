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

command_picker_open :: () {
	editorMode = .COMMAND_PICKER;

    push_allocator(flat_pool_allocator_proc, *focusedPanel.commandPicker.memory);

	for command: commandList {
		entry := array_add(*focusedPanel.commandPicker.filteredCommandList);
		entry.command = *command;
		entry.sortKey = 10;
	}
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

command_picker_delete_char :: () {
	state := *focusedPanel.commandPicker;

	state.textInput.count -= 1;
	state.cursor -= 1;
	if state.textInput.count <= 0 {
		state.textInput.count = 0;
		command_picker_refresh_list(state);
		return;
	}
	command_picker_refresh_list(state);
}

command_picker_execute_command :: () {
	state := *focusedPanel.commandPicker;

	cmd := state.filteredCommandList[state.selectedCommand].command; 
	editorMode = .NORMAL;
	cmd.execute();
	command_picker_reset(state);
}

command_picker_select_next :: () {
	state := *focusedPanel.commandPicker;

	maxCommand := state.filteredCommandList.count - 1;
	state.selectedCommand = clamp(state.selectedCommand+1, 0, xx maxCommand);
}

command_picker_select_previous :: () {
	state := *focusedPanel.commandPicker;

	maxCommand := state.filteredCommandList.count - 1;
	state.selectedCommand = clamp(state.selectedCommand-1, 0, xx maxCommand);
}

command_picker_handle_text_input :: (state: *CommandPicker, char: Utf8_Char) {
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

