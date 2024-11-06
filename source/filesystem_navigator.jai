
FileSystemNavigator :: struct {
	// @todo: arena for currentPathStrings, itemList, and text input.
	// reset the arena and memset this struct when finished with the tool
	// probably make a reset tool function which zeroes what it needs to
	textInput: [..]u8;
	cursor: s32;

	pendingAction: bool;
	// @todo: we're not using this properly, just use an array of strings instead
	currentPath: Path;
	itemList: [..]Item;
	selectedItem:s64;
	numToDisplay:s64; // number of items with positive sortkeys

	Item :: struct {
		name: string;
		sortKey: s64;
	}
}

filesystem_nav_input_handler :: (event: Input.Event) {
	if event.type == .KEYBOARD {
		// @todo refactor these into commands, bound in the appropriate mode
		// though these are conceptually similar, for now just have a different command for
		// command mode delete vs insert mode delete

		if fileSystemNav.pendingAction {

			if event.key_pressed && event.key_code == .ENTER {
				open_document(path_to_string(fileSystemNav.currentPath,,temp));
				fileSystemNav.pendingAction = false;
				editorMode = .NORMAL;
				// @todo might want to just memset filesystemnav?
				fileSystemNav.textInput.count = 0;
				fileSystemNav.itemList.count = 0;
				fileSystemNav.currentPath.words.count = 0;
			}

			if event.key_pressed && event.key_code == #char "D" {
			}

			if event.key_pressed && event.key_code == #char "R" {
			}
		}
		else {
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

				array_add(*fileSystemNav.currentPath.words, item.name);

				if platform_is_path_directory(fileSystemNav.currentPath) {
					filesystem_nav_refresh_directory_list();
					fileSystemNav.textInput.count = 0;
				}
				else {
					fileSystemNav.pendingAction = true;
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
			item.name = copy_string(it); // @todo make an arena for the itemlist itself, reset when we refresh
			item.sortKey = 1;
			fileSystemNav.numToDisplay += 1;
		}
	} else {
		visitor :: (info: *File_Visit_Info, items: *[..]FileSystemNavigator.Item) {
			new_item: FileSystemNavigator.Item;
			new_item.name = copy_string(info.short_name); // @todo put in arena for itemlist 
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
