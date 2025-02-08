
FilesystemNavigator :: struct {
	memory : Flat_Pool;

	textInput: [..]u8;
	cursor: s32;

	saveMode: bool;
	pendingAction: bool;
	currentPath: [..]string;
	itemList: [..]Item;
	selectedItem:s64;
	numToDisplay:s64; // number of items with positive sortkeys

	Item :: struct {
		name: string;
		sortKey: s64;
		saveItem: bool;
	}
}

filesystem_nav_reset :: (state: *FilesystemNavigator) {
	state.cursor = 0;
	state.saveMode = false;
	state.numToDisplay = 0;
	state.pendingAction = false;
	array_reset(*state.currentPath);
	array_reset(*state.itemList);
	array_reset(*state.textInput);
	#if BUILD_TYPE == BuildType.DEBUG {
		reset(*state.memory, overwrite_memory=true);
	} else {
		reset(*state.memory, overwrite_memory=false);
	}
}

filesystem_nav_delete_path :: (using panel: *Panel, args: []string) {
	state := *filesystemNav;

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

filesystem_nav_select_next :: (using panel: *Panel, args: []string) {
	state := *filesystemNav;
	maxItems := state.numToDisplay - 1;
	state.selectedItem = clamp(state.selectedItem+1, 0, xx maxItems);
}

filesystem_nav_select_previous :: (using panel: *Panel, args: []string) {
	state := *filesystemNav;
	maxItems := state.numToDisplay - 1;
	state.selectedItem = clamp(state.selectedItem-1, 0, xx maxItems);
}

filesystem_nav_action_item :: (using panel: *Panel, args: []string) {
	state := *filesystemNav;

	if state.pendingAction {
		if state.saveMode {
			document_save(panel.document, make_path_from_strings(state.currentPath,,temp));
			editorMode = .NORMAL;
			filesystem_nav_reset(state);
		}
		else {
			// @todo: the action may be more than just open, could be delete or rename
			document_open(make_path_from_strings(state.currentPath,,temp));
			editorMode = .NORMAL;
			filesystem_nav_reset(state);
		}
	}
	else {
		item := state.itemList[state.selectedItem];
		if item.saveItem {
			// save item, we need to save this file
			fileName := copy_string(string.{state.textInput.count, state.textInput.data},,get_allocator(state));
			array_add(*state.currentPath, fileName,, get_allocator(state));
			document_save(panel.document, make_path_from_strings(state.currentPath,,temp));
			editorMode = .NORMAL;
			filesystem_nav_reset(state);
		}
		else {
			// normal case, add path element to list and refresh
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
}

filesystem_nav_delete_item :: (using panel: *Panel, args: []string) {
	state := *filesystemNav;
	// This actually won't work because a letter is consumed by the text input for this widget
	// unless you made a submode, something to think about when we get here
	print("Not implemented, delete item");
}

filesystem_nav_rename_move_item :: (using panel: *Panel, args: []string) {
	state := *filesystemNav;
	print("Not implemented, rename/move item");
}

filesystem_nav_handle_text_input :: (state: *FilesystemNavigator, char: Utf8_Char) {
	for 0..char.count-1 {
		// When you're in save mode we let you create new path sections by using path dividers
		if state.saveMode && (char.bytes[it] == #char "/" || char.bytes[it] == #char "\\") {
			dirName := copy_string(string.{state.textInput.count, state.textInput.data},,get_allocator(state));
			array_add(*state.currentPath, dirName,, get_allocator(state));
			filesystem_nav_refresh_directory_list(state);
			state.textInput.count = 0;
		}
		else {
			array_add(*state.textInput, char.bytes[it],,get_allocator(state));
			state.cursor += 1;
		}
	}
	filesystem_nav_filter_directory_list(state);
}

filesystem_nav_refresh_directory_list :: (state: *FilesystemNavigator) {
	state.numToDisplay = 0;
	array_reset_keeping_memory(*state.itemList);
	path := make_path_from_strings(state.currentPath,,temp);

	// start with drives
	if state.currentPath.count == 0 {
		// @todo, at some point it should use the project directory maybe, or the current file
		for platform_enumerate_logical_drives() {
			item := array_add(*state.itemList,,get_allocator(state));
			item.name = copy_string(it,,get_allocator(state));
			item.sortKey = 1;
			state.numToDisplay += 1;
		}
	} else if file_exists(path) {
		visitor :: (info: *File_Visit_Info, state: *FilesystemNavigator) {
			new_item: FilesystemNavigator.Item;
			new_item.name = copy_string(info.short_name,,get_allocator(state));
			new_item.sortKey = 1;
			array_add(*state.itemList, new_item,,get_allocator(state));
		}
		visit_files(path, false, state, visitor, visit_directories=true);
		state.numToDisplay = state.itemList.count;
	}

	if state.saveMode {
		item := array_add(*state.itemList,,get_allocator(state));
		item.sortKey = 1;
		item.saveItem = true;
	}

	maxItems := state.itemList.count - 1;
	state.selectedItem = clamp(state.selectedItem, 0, xx maxItems);
}

filesystem_nav_filter_directory_list :: (state: *FilesystemNavigator) {
	state.numToDisplay = 0;
	search_query:= string.{state.textInput.count, state.textInput.data};
	for * item: state.itemList {
		if !item.saveItem {
			item.sortKey = fuzzy_search(item.name, search_query);
		}
		else {
			// save item special case
			if state.currentPath.count > 0 && state.textInput.count > 0 {
				item.sortKey = 1;
			}
			else {
				item.sortKey = 0;
			}
		}

		if item.sortKey > 0 {
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

