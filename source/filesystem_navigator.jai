
FilesystemNavigator :: struct {
	memory : Flat_Pool;

	textInput: [..]u8;
	cursor: s32;

	pendingAction: bool;
	currentPath: [..]string;
	itemList: [..]Item;
	selectedItem:s64;
	numToDisplay:s64; // number of items with positive sortkeys

	Item :: struct {
		name: string;
		sortKey: s64;
	}
}

filesystem_nav_reset :: (state: *FilesystemNavigator) {
	#if BUILD_TYPE == BuildType.DEBUG {
		reset(*state.memory, overwrite_memory=true);
	} else {
		reset(*state.memory, overwrite_memory=false);
	}
	state.cursor = 0;
	state.numToDisplay = 0;
	state.pendingAction = false;
	array_reset(*state.currentPath);
}

filesystem_nav_delete_path :: () {
	state := *focusedPanel.filesystemNav;

	if state.currentPath.count > 0 && state.textInput.count == 0 {
		state.currentPath.count -= 1;
		filesystem_nav_refresh_directory_list(state);
		return;
	}

	state.textInput.count -= 1;
	state.cursor -= 1;
	if state.textInput.count <= 0 {
		state.textInput.count = 0;
		filesystem_nav_filter_directory_list(state);

		return;
	}
	filesystem_nav_filter_directory_list(state);
}

filesystem_nav_select_next :: () {
	state := *focusedPanel.filesystemNav;
	maxItems := state.itemList.count - 1;
	state.selectedItem = clamp(state.selectedItem+1, 0, xx maxItems);
}

filesystem_nav_select_previous :: () {
	state := *focusedPanel.filesystemNav;
	maxItems := state.itemList.count - 1;
	state.selectedItem = clamp(state.selectedItem-1, 0, xx maxItems);
}

filesystem_nav_action_item :: () {
	state := *focusedPanel.filesystemNav;

	if state.pendingAction {
		open_document(make_path_from_strings(state.currentPath,,temp));
		editorMode = .NORMAL;
		filesystem_nav_reset(state);
	} else {
		item := state.itemList[state.selectedItem];

		array_add(*state.currentPath, item.name,, get_allocator(state));

		if platform_is_path_directory(make_path_from_strings(state.currentPath,,temp)) {
			filesystem_nav_refresh_directory_list(state);
			state.textInput.count = 0;
		}
		else {
			state.pendingAction = true;
		}
	}
}

filesystem_nav_delete_item :: () {
	state := *focusedPanel.filesystemNav;
	print("Not implemented, delete item");
}

filesystem_nav_rename_move_item :: () {
	state := *focusedPanel.filesystemNav;
	print("Not implemented, rename/move item");
}

filesystem_nav_handle_text_input :: (state: *FilesystemNavigator, char: Utf8_Char) {
	for 0..char.count-1 {
		array_add(*state.textInput, char.bytes[it],,get_allocator(state));
		state.cursor += 1;
	}
	filesystem_nav_filter_directory_list(state);
}

filesystem_nav_refresh_directory_list :: (state: *FilesystemNavigator) {
	state.numToDisplay = 0;
	array_reset_keeping_memory(*state.itemList);
	// start with drives
	if state.currentPath.count == 0 {
		// @todo, at some point it should use the project directory maybe, or the current file
		for platform_enumerate_logical_drives() {
			item := array_add(*state.itemList,,get_allocator(state));
			item.name = copy_string(it,,get_allocator(state));
			item.sortKey = 1;
			state.numToDisplay += 1;
		}
	} else {
		visitor :: (info: *File_Visit_Info, state: *FilesystemNavigator) {
			new_item: FilesystemNavigator.Item;
			new_item.name = copy_string(info.short_name,,get_allocator(state));
			new_item.sortKey = 1;
			array_add(*state.itemList, new_item,,get_allocator(state));
		}
		visit_files(make_path_from_strings(state.currentPath,,temp), false, state, visitor, visit_directories=true);
		state.numToDisplay = state.itemList.count;
	}
}

filesystem_nav_filter_directory_list :: (state: *FilesystemNavigator) {
	state.numToDisplay = 0;
	search_query:= string.{state.textInput.count, state.textInput.data};
	for * item: state.itemList {
		score := fuzzy_search(item.name, search_query);
		item.sortKey = score;
		if score > 0 {
			state.numToDisplay += 1;
		}
	}

	compare_entries :: (e1: FilesystemNavigator.Item, e2: FilesystemNavigator.Item) -> s64 {
		diff := e2.sortKey - e1.sortKey;
		if diff != 0 return diff;
		// todo: should also sort on other things like folder or file etc
		return memcmp(e1.name.data, e2.name.data, min(e1.name.count, e2.name.count));
	}
	quick_sort(state.itemList, compare_entries);

	maxItem := state.itemList.count - 1;
	state.selectedItem = clamp(state.selectedItem-1, 0, xx maxItem);
}

#scope_file

get_allocator :: (state: *FilesystemNavigator) -> Allocator {
	return Allocator.{ proc = flat_pool_allocator_proc, data = *state.memory };
}

make_path_from_strings :: (strings: []string) -> string {
    builder: String_Builder;
    init_string_builder(*builder);

    for strings {
        append(*builder, it);
		if (it_index != strings.count-1)  append(*builder, "/");
    }
    
    return builder_to_string(*builder);
}

