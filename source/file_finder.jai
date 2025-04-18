FileFinder :: struct {
	FileEntry :: struct {
		doc: *Document;
		sortKey: s64;
	}
	fileList: [..]FileEntry;
	selectedEntry:s32;
	numToDisplay:s32;
	input: InputField;
}

file_finder_open :: (using panel: *Panel, args: []string) {
	panel.activeDialog = .FILE_FINDER;
	editorMode = .DIALOG;

	for * doc: open_documents {
		entry := array_add(*fileFinder.fileList);
		entry.doc = doc;
		entry.sortKey = 10;
		fileFinder.numToDisplay += 1;
	}

	fileFinder.input.onEditCallback = file_finder_input_field_on_edit;
	fileFinder.input.userData = *fileFinder;
}

file_finder_input_field_on_edit :: (userData: *void, input: string) {
	finder: *FileFinder = cast(*FileFinder) userData;
	finder.numToDisplay = 0;
	array_reset_keeping_memory(*finder.fileList);

	for * doc: open_documents {
		// @todo: at some point you probably want to search the whole path for matches
		// need better UI to show the filepath
		filePath := doc.path;
		score := fuzzy_search(path_filename(filePath), input);
		entry := array_add(*finder.fileList);
		entry.doc = doc;
		entry.sortKey = score;
		if entry.sortKey > 0 {
			finder.numToDisplay += 1;
		}
	}

	compare_entries :: (e1: FileFinder.FileEntry, e2: FileFinder.FileEntry) -> s64 {
		diff := e2.sortKey - e1.sortKey;
		if diff != 0 return diff;
		return memcmp(e1.doc.path.data, e2.doc.path.data, min(e1.doc.path.count, e2.doc.path.count));
	}
	quick_sort(finder.fileList, compare_entries);

	maxItems := finder.fileList.count - 1;
	finder.selectedEntry = clamp(finder.selectedEntry-1, 0, xx maxItems);
}

file_finder_reset :: (panel: *Panel) {
	finder := *panel.fileFinder;
	finder.selectedEntry = 0;
	finder.numToDisplay = 0;
	array_reset(*finder.fileList);
	input_field_reset_keeping_memory(*finder.input);
	panel.activeDialog = .NONE;
}

file_finder_select_file :: (panel: *Panel) {
	finder := *panel.fileFinder;
	entry := finder.fileList[finder.selectedEntry].doc; 
	panel_set_active_document(panel, entry);
	file_finder_reset(panel);
	editorMode = .NORMAL;
}

file_finder_select_next :: (using panel: *Panel) {
	finder := *panel.fileFinder;

	maxEntry := finder.fileList.count - 1;
	finder.selectedEntry = clamp(finder.selectedEntry+1, 0, xx maxEntry);
}

file_finder_select_previous :: (using panel: *Panel) {
	finder := *panel.fileFinder;

	maxEntry := finder.fileList.count - 1;
	finder.selectedEntry = clamp(finder.selectedEntry-1, 0, xx maxEntry);
}
