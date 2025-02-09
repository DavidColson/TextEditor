CommandPicker :: struct {
	// @todo: all this really has to manage is the command list
	// might not be worth using a pool here?
	memory : Flat_Pool;

	CommandEntry :: struct {
		command: *Command;
		// right now this is just the search score, but i'd like to add
		// the last use time of the command, or how often it's used
		sortKey: s64;
	}
	filteredCommandList: [..]CommandEntry;
	selectedCommand:s32;
	input: InputField;
}

command_picker_open :: (using panel: *Panel, args: []string) {
	editorMode = .COMMAND_PICKER;

    push_allocator(flat_pool_allocator_proc, *commandPicker.memory);

	for command: commandList {
		if !(command.flags & .HIDDEN) {
			entry := array_add(*commandPicker.filteredCommandList);
			entry.command = *command;
			entry.sortKey = 10;
		}
	}

	commandPicker.input.onEditCallback = command_picker_input_field_on_edit;
	commandPicker.input.userData = *commandPicker;
	focusedInputField = *commandPicker.input;
}

command_picker_input_field_on_edit :: (userData: *void, input: string) {
	state: *CommandPicker = cast(*CommandPicker) userData;

    push_allocator(flat_pool_allocator_proc, *state.memory);

	array_reset_keeping_memory(*state.filteredCommandList);

	for command: commandList {
		if !(command.flags & .HIDDEN) {
			score := fuzzy_search(command.name, input);
			entry := array_add(*state.filteredCommandList);
			entry.command = *command;
			entry.sortKey = score;
		}
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

command_picker_reset :: (state: *CommandPicker) {
	state.selectedCommand = 0;
	array_reset(*state.filteredCommandList);
	#if BUILD_TYPE == BuildType.DEBUG {
		reset(*state.memory, overwrite_memory=true);
	} else {
		reset(*state.memory, overwrite_memory=false);
	}
	// input field manages it's own memory
	input_field_reset_keeping_memory(*state.input);
	focusedInputField = null;
}

command_picker_execute_command :: (using panel: *Panel, args: []string) {
	state := *commandPicker;

	cmd := state.filteredCommandList[state.selectedCommand].command; 
	editorMode = .NORMAL;
	cmd.execute(panel, string.[]); // @todo: command picker can't give arguments yet? Needs this ability
	command_picker_reset(state);
}

command_picker_select_next :: (using panel: *Panel, args: []string) {
	state := *commandPicker;

	maxCommand := state.filteredCommandList.count - 1;
	state.selectedCommand = clamp(state.selectedCommand+1, 0, xx maxCommand);
}

command_picker_select_previous :: (using panel: *Panel, args: []string) {
	state := *commandPicker;

	maxCommand := state.filteredCommandList.count - 1;
	state.selectedCommand = clamp(state.selectedCommand-1, 0, xx maxCommand);
}

