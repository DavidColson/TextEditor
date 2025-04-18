FileFinder :: struct {
	FileEntry :: struct {
		doc: *Document;
		sortKey: s64;
	}
	fileList: [..]FileEntry;
	selectedEntry:s32;
	input: InputField;
}

file_finder_open :: (using panel: *Panel, args: []string) {
	panel.activeDialog = .FILE_FINDER;
	editorMode = .DIALOG;

	for * doc: open_documents {
		entry := array_add(*fileFinder.fileList);
		entry.doc = doc;
		entry.sortKey = 10;
	}

	fileFinder.input.onEditCallback = file_finder_input_field_on_edit;
	fileFinder.input.userData = *fileFinder;
}

file_finder_input_field_on_edit :: (userData: *void, input: string) {
	state: *FileFinder = cast(*FileFinder) userData;

	// :@todo: filter list
}

file_finder_reset :: (panel: *Panel) {
	finder := *panel.fileFinder;
	input_field_reset_keeping_memory(*finder.input);
	finder.selectedEntry = 0;
	array_reset(*finder.fileList);
	input_field_reset_keeping_memory(*finder.input);
	panel.activeDialog = .NONE;
}

file_finder_select_file :: (panel: *Panel) {
	finder := *panel.fileFinder;
	entry := finder.fileList[finder.selectedEntry].doc; 
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
