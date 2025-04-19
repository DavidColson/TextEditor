
panel_set_active_document :: (panel: *Panel, doc: *Document) {
	panel.document = doc;
	panel.cursor = .{};
	panel.cursor.head = document_create_cursor(panel.document);
	panel.cursor.anchor = document_create_cursor(panel.document);
}

panel_reset_dialogs :: (panel: *Panel) {
	if panel.activeDialog == {
		case .FILE_FINDER; file_finder_reset(panel);
		case .FILESYSTEM_NAVIGATOR; filesystem_nav_reset(panel);
		case .COMMAND_PICKER; command_picker_reset(panel);
		case .SEARCH; end_document_search(panel);
	}
	panel.activeDialog = .NONE;
}

panel_scroll_with_mouse :: (panel: *Panel, mouseDelta: int) {
	// @todo: smooth lerp animations on this
	// have a rawscroll value, and then a lerped value that we lerp toward every frame
	panel.scrollPos += mouseDelta;
	numLines := document_get_num_lines(panel.document);
	panel.scrollPos = clamp(panel.scrollPos, -(my_font.character_height * numLines) + my_font.character_height * 5, 0);

	// keep the cursor on the screen when we scroll
	if abs(Input.mouse_delta_z) > 0 {
		startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
		cursorLine := document_cursor_get_line(*panel.cursor.head);
		if cursorLine < startVisibleLine {
			move_to_line_visual(panel, cursorLine, startVisibleLine);
			panel.cursor.anchor = panel.cursor.head;
		}
		else if cursorLine > endVisibleLine {
			move_to_line_visual(panel, cursorLine, endVisibleLine-1);
			panel.cursor.anchor = panel.cursor.head;
		}
	}
}

// targetLine will be the top edge of the panel, such that target line = 0 will leave you scrolled
// up as high as you can go. Will allow you to scroll off the end as far as a couple lines are still visible
panel_scroll_to_line :: (panel: *Panel, targetLine: s64) {
	startVisibleLine := -panel.scrollPos / my_font.character_height;
	numLinesDocument := document_get_num_lines(panel.document);

	// @todo: these need to be parameterized styling values for the UI
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;
	heightForCode := panel.rect.h - headerHeight;
	maxScroll := cast(s64) (numLinesDocument * my_font.character_height + heightForCode - 2); 

	delta := targetLine - startVisibleLine;
	panel.scrollPos -= my_font.character_height * delta;
	panel.scrollPos = clamp(panel.scrollPos, -maxScroll, 0);
}

panel_calculate_visible_lines :: (panel: *Panel, clamped := false) -> s64, s64 {
	numLines := document_get_num_lines(panel.document);
	// @todo: these need to be parameterized styling values for the UI
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;
	heightForCode := panel.rect.h - headerHeight;
	startVisibleLines := clamp(-panel.scrollPos / my_font.character_height, 0, numLines - 1);
	endVisibleLinesUnclamped := startVisibleLines + cast(s64)heightForCode / my_font.character_height;
	endVisibleLines := clamp(endVisibleLinesUnclamped, 0, numLines - 1);

	if clamped {
		return startVisibleLines, endVisibleLines;
	}
	else {
		return startVisibleLines, endVisibleLinesUnclamped;
	}
}

panel_get_page_size :: (panel: *Panel) -> s64 {
	// @todo: these need to be parameterized styling values for the UI
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;
	heightForCode := panel.rect.h - headerHeight;
	return cast(s64) (heightForCode / my_font.character_height);
}
