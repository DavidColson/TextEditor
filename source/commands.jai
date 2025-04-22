
// Movement commands
// ------------------------------------

move_one_char_left :: (using panel: *Panel, args: []string) {
	character := document_cursor_step_one_backward(*cursor.head, true);

	if character == #char "\t" {
		cursor.virtualColumn -= chars_to_tabstop(cursor.virtualColumn);
	}
	else if character == #char "\n" {
		// wrapping back to the previous line
		// means we must calculate the visual column length of the previous line
		line := document_cursor_get_line(*cursor.head);
		lineStart := document_get_line_start(cursor.head.doc, line);

		cursor.virtualColumn = 0;
		tempCursor : DocumentCursor;
		tempCursor.doc = panel.document;
		tempCursor.node = panel.document.pieceChainHead;
		document_cursor_jump_to_offset(*tempCursor, lineStart);
		for tempCursor {
			if it == #char "\n" then break;
			if it == #char "\t" {
				cursor.virtualColumn += chars_to_tabstop(cursor.virtualColumn);
			}
			else {
				cursor.virtualColumn += 1;
			}
		}
	}
	else {
		cursor.virtualColumn -= 1;
	}

	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

move_one_char_right :: (using panel: *Panel, args: []string) {
	character := document_cursor_step_one_forward(*cursor.head, true);

	if character == #char "\t" {
		cursor.virtualColumn += chars_to_tabstop(cursor.virtualColumn);
	}
	else if character == #char "\n" {
		cursor.virtualColumn = 0;
	}
	else {
		cursor.virtualColumn += 1;
	}

	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

chars_to_tabstop :: (column: s64) -> s64 {
	return tabSize - column % tabSize;
}

move_to_line_visual :: (using panel: *Panel, currentLine: s64, targetLine: s64) {
	// please note this function assumes that cursor.head is on currentLine already

	lineStartNewLine := document_get_line_start(document, targetLine);

	// the target column actually needs to be the target visual column
	// so we must find the start of the current line, and then count forward
	// so that we can account for tabstops
	targetVisualColumn := 0;
	targetActualColumn := 0;
	currentLineCursor := cursor.head;
	for < currentLineCursor {
		if it == #char "\n" || it == 0 then break;
		targetActualColumn += 1;
	}
	document_cursor_step_one_forward(*currentLineCursor);
	for currentLineCursor {
		if targetActualColumn == it_index then break;
		if it == #char "\t" {
			targetVisualColumn += chars_to_tabstop(targetVisualColumn);
		}
		else {
			targetVisualColumn += 1;
		}
	}

	newCursor := document_create_cursor(panel.document, lineStartNewLine);
	newColumn := 0;
	if cursor.virtualColumn > newColumn {
		for newCursor {
			// stop if we get to the end of the new line
			if it == #char "\n" {
				document_cursor_step_one_backward(*newCursor);
				break;
			}

			// count the visual columns
			if it == #char "\t" {
				newColumn += chars_to_tabstop(newColumn);
			}
			else {
				newColumn += 1;
			}
			
			// stop when we're matching the target visual column
			if newColumn == cursor.virtualColumn then break;
			if newColumn > cursor.virtualColumn {
				document_cursor_step_one_backward(*newCursor);
				break;
			}
		}
	}
	cursor.head = newCursor;
}

move_one_line_down :: (using panel: *Panel, args: []string) {
	currentLine := document_cursor_get_line(*cursor.head);
	numLines := document_get_num_lines(document);
	newLine := min(currentLine+1, numLines - 1);

	move_to_line_visual(panel, currentLine, newLine);

	if !extendSelections {
		cursor.anchor = cursor.head;
	}

	// scroll the window if the cursor will now become out of view
	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	if newLine >= endVisibleLine {
		panel_scroll_to_line(panel, startVisibleLine + 1);
	}
}

move_one_line_up :: (using panel: *Panel, args: []string) {
	currentLine := document_cursor_get_line(*cursor.head);
	newLine :=max(currentLine-1, 0);

	move_to_line_visual(panel, currentLine, newLine);

	if !extendSelections {
		cursor.anchor = cursor.head;
	}

	// scroll the window if the cursor will now become out of view
	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	if newLine < startVisibleLine {
		panel_scroll_to_line(panel, startVisibleLine - 1);
	}

}

goto_document_start :: (using panel: *Panel, args: []string) {
	document_cursor_jump_to_offset(*cursor.head, 0);

	if !extendSelections {
		cursor.anchor = cursor.head;
	}

	// scroll the window if the cursor will now become out of view
	panel_scroll_to_line(panel, 0);
}

goto_document_end :: (using panel: *Panel, args: []string) {
	document_cursor_jump_to_offset(*cursor.head, document.size);

	if !extendSelections {
		cursor.anchor = cursor.head;
	}

	// scroll the window if the cursor will now become out of view
	pageSize := panel_get_page_size(panel);
	cursorLine := document_cursor_get_line(*cursor.head);
	panel_scroll_to_line(panel, cursorLine - pageSize + 1);
}

goto_line_end :: (using panel: *Panel, args: []string) { 
	for :skip_returns cursor.head {
		if it == #char "\n" {
			document_cursor_step_one_backward(*cursor.head, true);
			break;
		}
	}

	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

goto_line_start :: (using panel: *Panel, args: []string) { 
	for < :skip_returns cursor.head {
		if it == #char "\n" {
			document_cursor_step_one_forward(*cursor.head, true);
			break;
		}
	}

	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

CharCategory :: enum {
	LINE_ENDING;
	WHITESPACE;
	WORD;
	PUNCTUATION;
	UNKNOWN;
}

categorize_char :: (ch: u8) -> CharCategory {
	// @todo note that there are more punctuation marks in full unicode
	// something to support later. Generally unicode may break the assumptions in here
	punctuation :: "\"!#$%&'()*+,-./:;<=>?@[\\]^_`{|}~";
	isPunctuation := false;
	for punctuation {
		if ch == it then isPunctuation = true;
	}

	if ch == #char "\n" {
		return .LINE_ENDING;
	}
	else if ch == #char " " || ch == #char "\t" || ch == #char "\r" {
		return .WHITESPACE;
	}
	else if is_alnum(ch) {
		return .WORD;
	}
	else if isPunctuation {
		return .PUNCTUATION;
	}
	else {
		return .UNKNOWN;
	}
}

is_lower :: inline (char: u8) -> bool {
    return char >= #char "a" && char <= #char "z";
}

is_upper :: inline (char: u8) -> bool {
    return char >= #char "A" && char <= #char "Z";
}

move_word_forward :: (using panel: *Panel, checkPosition: (u8, u8, CharCategory, CharCategory) -> bool) {
	if !extendSelections {
		cursor.anchor = cursor.head;
	}
	for cursor.head {
		next := document_cursor_get_char(*cursor.head);
		prevCharCategory := categorize_char(it);
		nextCharCategory := categorize_char(next);
		if checkPosition(it, next, prevCharCategory, nextCharCategory) {
			if it_index == 0 {
				if !extendSelections then cursor.anchor = cursor.head;
			}
			else {
				if nextCharCategory != .LINE_ENDING then document_cursor_step_one_backward(*cursor.head);
				if prevCharCategory == .LINE_ENDING then cursor.anchor = cursor.head;
				break;
			}
		}
	}
}

move_word_reverse :: (using panel: *Panel, checkPosition: (u8, u8, CharCategory, CharCategory) -> bool) {
	if !extendSelections {
		cursor.anchor = cursor.head;
	}
	prev := document_cursor_get_char(*cursor.head);
	for < :skip_returns cursor.head {
		nextCharCategory := categorize_char(it);
		prevCharCategory := categorize_char(prev);
		if checkPosition(prev, it, prevCharCategory, nextCharCategory) {
			if it_index == 0  && !extendSelections {
				if !extendSelections then cursor.anchor = cursor.head;
			}
			else {
				document_cursor_step_one_forward(*cursor.head, true);
				break;
			}
		}
		prev = it;
	}
}

move_word_start :: (using panel: *Panel, args: []string) { 
	move_word_forward(panel, (prev: u8, next: u8, prevCharCategory: CharCategory, nextCharCategory: CharCategory) -> bool {
		isWordBoundary := nextCharCategory != prevCharCategory;
		nextIsLineEnding := nextCharCategory == .LINE_ENDING;
		nextIsWhitespace := nextCharCategory == .WHITESPACE;
		return isWordBoundary && (nextIsLineEnding || !nextIsWhitespace);
	});
}

move_long_word_start :: (using panel: *Panel, args: []string) { 
	move_word_forward(panel, (prev: u8, next: u8, prevCharCategory: CharCategory, nextCharCategory: CharCategory) -> bool {
		isLongWordBoundary := prevCharCategory != nextCharCategory;
		if (nextCharCategory == .WORD && prevCharCategory == .PUNCTUATION) 
		|| (nextCharCategory == .PUNCTUATION && prevCharCategory == .WORD) {
			isLongWordBoundary = false;
		}

		nextIsLineEnding := nextCharCategory == .LINE_ENDING;
		nextIsWhitespace := nextCharCategory == .WHITESPACE;
		return isLongWordBoundary && (nextIsLineEnding || !nextIsWhitespace);
	});
}

move_sub_word_start :: (using panel: *Panel, args: []string) { 
	move_word_forward(panel, (prev: u8, next: u8, prevCharCategory: CharCategory, nextCharCategory: CharCategory) -> bool {
		isSubWordBoundary := prev != next;
		if nextCharCategory == .WORD && prevCharCategory == .WORD {
			if (prev == #char "_") != (next == #char "_") {
				isSubWordBoundary = true;
			}
			else {
				isSubWordBoundary = is_lower(prev) && is_upper(next);
			}
		}

		nextIsLineEnding := nextCharCategory == .LINE_ENDING;
		nextIsWhitespace := nextCharCategory == .WHITESPACE;
		return isSubWordBoundary && (nextIsLineEnding || !(nextIsWhitespace || next == #char "_"));
	});
}

move_prev_word_start :: (using panel: *Panel, args: []string) { 
	move_word_reverse(panel, (prev: u8, next: u8, prevCharCategory: CharCategory, nextCharCategory: CharCategory) -> bool {
		isWordBoundary := nextCharCategory != prevCharCategory;
		if nextCharCategory == .LINE_ENDING && prevCharCategory == .LINE_ENDING {
			isWordBoundary = true;
		}
		nextIsLineEnding := nextCharCategory == .LINE_ENDING;
		prevIsWhitespace := prevCharCategory == .WHITESPACE;
		return isWordBoundary && (!prevIsWhitespace || nextIsLineEnding);
	});
}

move_word_end :: (using panel: *Panel, args: []string) { 
	move_word_forward(panel, (prev: u8, next: u8, prevCharCategory: CharCategory, nextCharCategory: CharCategory) -> bool {
		isWordBoundary := nextCharCategory != prevCharCategory;
		nextIsLineEnding := nextCharCategory == .LINE_ENDING;
		prevIsWhitespace := prevCharCategory == .WHITESPACE;
		return isWordBoundary && (!prevIsWhitespace || nextIsLineEnding);
	});
}

move_long_word_end :: (using panel: *Panel, args: []string) { 
	move_word_forward(panel, (prev: u8, next: u8, prevCharCategory: CharCategory, nextCharCategory: CharCategory) -> bool {
		isLongWordBoundary := prevCharCategory != nextCharCategory;
		if (nextCharCategory == .WORD && prevCharCategory == .PUNCTUATION) 
		|| (nextCharCategory == .PUNCTUATION && prevCharCategory == .WORD) {
			isLongWordBoundary = false;
		}
		nextIsLineEnding := nextCharCategory == .LINE_ENDING;
		prevIsWhitespace := prevCharCategory == .WHITESPACE;
		return isLongWordBoundary && (!prevIsWhitespace || nextIsLineEnding);
	});
}

move_sub_word_end :: (using panel: *Panel, args: []string) { 
	move_word_forward(panel, (prev: u8, next: u8, prevCharCategory: CharCategory, nextCharCategory: CharCategory) -> bool {
		isSubWordBoundary := ifx prev != next then true else false;
		if nextCharCategory == .WORD && prevCharCategory == .WORD {
			if (prev == #char "_") != (next == #char "_") {
				isSubWordBoundary = true;
			}
			else {
				isSubWordBoundary = is_lower(prev) && is_upper(next);
			}
		}

		nextIsLineEnding := nextCharCategory == .LINE_ENDING;
		prevIsWhitespace := prevCharCategory == .WHITESPACE;
		return isSubWordBoundary && (!(prevIsWhitespace || prev == #char "_") || nextIsLineEnding);
	});
}

jump_to_char :: (using panel: *Panel, args: []string) { 
	for cursor.head {
		next := document_cursor_get_char(*cursor.head);
		// @todo: assumes the args are single char, this may not always be true
		if args[0][0] == next {
			break;
		}
	}
}

jump_to_last_char :: (using panel: *Panel, args: []string) { 
	for < cursor.head {
		// @todo: assumes the args are single char, this may not always be true
		if args[0][0] == it {
			break;
		}
	}
}

jump_to_before_char :: (using panel: *Panel, args: []string) { 
	for cursor.head {
		next := document_cursor_get_char(*cursor.head);
		// @todo: assumes the args are single char, this may not always be true
		if args[0][0] == next {
			document_cursor_step_one_backward(*cursor.head);
			break;
		}
	}
}

jump_to_before_last_char :: (using panel: *Panel, args: []string) { 
	for < cursor.head {
		// @todo: assumes the args are single char, this may not always be true
		if args[0][0] == it {
			document_cursor_step_one_forward(*cursor.head, true);
			break;
		}
	}
}


// Normal Mode Changes
// ------------------------------

enter_normal_mode :: (panel: *Panel, args: []string) {
	panel_reset_dialogs(panel);
	editorMode = .NORMAL;
	extendSelections = false;
}

enter_insert_mode_start :: (using panel: *Panel, args: []string) {
	if cursor.head.documentOffset > cursor.anchor.documentOffset {
		flip_cursors(*cursor.head, *cursor.anchor);
	}
	panel_reset_dialogs(panel);
	editorMode = .INSERT;
}

enter_insert_mode_end :: (using panel: *Panel, args: []string) {
	if cursor.head.documentOffset < cursor.anchor.documentOffset {
		flip_cursors(*cursor.head, *cursor.anchor);
	}
	document_cursor_step_one_forward(*focusedPanel.cursor.head, true);
	panel_reset_dialogs(panel);
	editorMode = .INSERT;
}

enter_insert_mode_line_start :: (using panel: *Panel, args: []string) {
	extendSelections = false;
	goto_line_start(panel, args);
	cursorChar := document_cursor_get_char(*cursor.head);
	if is_space(cursorChar) {
		for cursor.head {
			next := document_cursor_get_char(*cursor.head);
			if !is_space(next) break;
		}
	}
	cursor.anchor = cursor.head;

	panel_reset_dialogs(panel);
	editorMode = .INSERT;
}

enter_insert_mode_line_end :: (using panel: *Panel, args: []string) {
	extendSelections = false;
	goto_line_end(panel, args);

	panel_reset_dialogs(panel);
	editorMode = .INSERT;
}

toggle_extend_selections :: (using panel: *Panel, args: []string) { 
	extendSelections = !extendSelections;
}

select_register :: (using panel: *Panel, args: []string) { 
	registers.selectedRegister = args[0][0];
}

delete_selection :: (using panel: *Panel, args: []string) {
	if cursor.head.documentOffset < cursor.anchor.documentOffset {
		end := cursor.anchor;
		document_cursor_step_one_forward(*end, true);
		cursor.head = document_delete_text(document, cursor.head, end);
	}
	else {
		end := cursor.head;
		document_cursor_step_one_forward(*end, true);
		cursor.head = document_delete_text(document, cursor.anchor, end);
	}
	cursor.anchor = cursor.head;
}

change_selection :: (using panel: *Panel, args: []string) {
	delete_selection(panel, args);
	enter_insert_mode_start(panel, args);
}

yank_selection :: (using panel: *Panel, args: []string) {
	// read the selection from the document
	// @todo: it may be useful to pull out this snippet as a generic "read range from document"
	readCursor: DocumentCursor;
	stopCursor: DocumentCursor;
	if cursor.head.documentOffset < cursor.anchor.documentOffset {
		readCursor = cursor.head;
		stopCursor = cursor.anchor;
	}
	else {
		readCursor = cursor.anchor;
		stopCursor = cursor.head;
	}

	text: [..]u8;
	for readCursor {
		array_add(*text, it,,temp);
		if readCursor.documentOffset >= stopCursor.documentOffset+1 then break;
	}
	textStr := string.{text.count, text.data};
	push_notification(sprint("Yanked into register %", string.{1,*registers.selectedRegister}));

	write_register(registers.selectedRegister, textStr);
}

paste_after_selection :: (using panel: *Panel, args: []string) {
	// read from register (either default or selected)
	textToPaste := read_register(registers.selectedRegister);

	// insert into document
	at := cursor.head;
	document_cursor_step_one_forward(*at, true);
	cursor.anchor = document_insert_text(document, at, textToPaste);

	// move cursor head to the right side of the pasted region
	cursor.head = cursor.anchor;
	if textToPaste.count > 0 {
		for cursor.head {
			if it_index >= textToPaste.count-2 then break;
		}
	}
}

paste_before_selection :: (using panel: *Panel, args: []string) {
	// read from register (either default or selected)
	textToPaste := read_register(registers.selectedRegister);

	// insert into document
	cursor.anchor = document_insert_text(document, cursor.head, textToPaste);

	// move cursor head to the right side of the pasted region
	cursor.head = cursor.anchor;
	if textToPaste.count > 0 {
		for cursor.head {
			if it_index >= textToPaste.count-2 then break;
		}
	}
}

replace_selection :: (using panel: *Panel, args: []string) {
	rangeLength := abs(cursor.head.documentOffset - cursor.anchor.documentOffset);

	delete_selection(panel, args);

	builder : String_Builder;
	builder.allocator = temp;
	init_string_builder(*builder);

	for 0..rangeLength {
		append(*builder, args[0]);
	}

	focusedPanel.cursor.head = document_insert_text(focusedPanel.document, focusedPanel.cursor.head, builder_to_string(*builder,,temp));

	// update cursor positions
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	if rangeLength > 0 {
		for focusedPanel.cursor.head {
			if it_index >= rangeLength-1 then break;
		}
	}
}

new_line_below :: (using panel: *Panel, args: []string) {
	goto_line_end(panel, args);
	insert_mode_line_break(panel, args);
	enter_insert_mode_start(panel, args);
}

new_line_above :: (using panel: *Panel, args: []string) {
	for < cursor.head {
		if it == #char "\n" {
			break;
		}
	}
	cursor.anchor = cursor.head;
	insert_mode_line_break(panel, args);
	enter_insert_mode_start(panel, args);
}

undo :: (using panel: *Panel, args: []string) {
	cursor.head = document_undo(document, cursor.head);
	cursor.anchor = cursor.head;
}

redo :: (using panel: *Panel, args: []string) {
	cursor.head = document_redo(document, cursor.head);
	cursor.anchor = cursor.head;
}


// File Search Commands
// --------------------------------

start_document_search :: (using panel: *Panel, args: []string) {
	// show search bar
	editorMode = .DIALOG;
	panel.activeDialog = .SEARCH;
	panel.searchInput.onEditCallback = document_search_on_edit;
	panel.searchInput.userData = cast(*void) panel;
	panel.previousScrollState = scrollPos;
}

confirm_document_search :: (using panel: *Panel, args: []string) {
	// set real cursor to the match that was found, setup stepping
	if panel.hasMatches {
		panel.cursor.anchor = panel.results[0].start;
		panel.cursor.head = panel.results[0].end;
		document_cursor_step_one_backward(*panel.cursor.head);
	}
	editorMode = .NORMAL;

	input_field_reset_keeping_memory(*panel.searchInput);
	panel.searchInput.onEditCallback = null;
	panel.searchInput.userData = null;
	if panel.results.count {
		array_reset(*panel.results);
	}
	panel.activeDialog = .NONE;
}

end_document_search :: (using panel: *Panel) { 
	panel.scrollPos = panel.previousScrollState; 
	input_field_reset_keeping_memory(*panel.searchInput);
	panel.searchInput.onEditCallback = null;
	panel.searchInput.userData = null;
	if panel.results.count {
		array_reset(*panel.results);
	}
}

next_search_result :: (using panel: *Panel, args: []string) {
	// clear previous result
	if panel.results.count {
		array_reset(*panel.results);
	}

	startOffset := panel.cursor.head.documentOffset;
	if panel.cursor.anchor.documentOffset > startOffset {
		startOffset = panel.cursor.anchor.documentOffset; 
	}
	panel.hasMatches, panel.results = match(panel.document, startOffset, panel.document.size, panel.currentRegex);

	// wrap around to start of document if no matches
	if !panel.hasMatches {
		panel.hasMatches, panel.results = match(panel.document, 0, panel.document.size, panel.currentRegex);
	}

	panel.cursor.anchor = panel.results[0].start;
	panel.cursor.head = panel.results[0].end;
	document_cursor_step_one_backward(*panel.cursor.head);

	// is the result off the edge of the screen? if so scroll so it's centered
	matchLine := document_cursor_get_line(*panel.results[0].start);
	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	pageSize := endVisibleLine - startVisibleLine;
	if matchLine < startVisibleLine || matchLine >= (endVisibleLine-1) {
		panel_scroll_to_line(panel, matchLine - pageSize/2); 
	}
}

previous_search_result :: (using panel: *Panel, args: []string) {
	// you basically need to find all from document start to the cursor, 
	start := 0;
	end := panel.cursor.anchor.documentOffset;
	if panel.cursor.head.documentOffset < end {
		end = panel.cursor.head.documentOffset; 
	}
	needToWrap := true;
	while true {
		hasMatch, results := match(panel.document, start, end, panel.currentRegex);
		if hasMatch {
			if panel.results.count {
				array_reset(*panel.results);
			}

			panel.results = results;
			start = results[0].end.documentOffset;
			needToWrap = false; // we found something first time around, so don't wrap
		}
		else if needToWrap {
			start = end;
			end = panel.document.size;
			needToWrap = false; // we're starting the wrap, so don't do it again
		}
		else {
			break;
		}
	}
	panel.cursor.anchor = panel.results[0].start;
	panel.cursor.head = panel.results[0].end;
	document_cursor_step_one_backward(*panel.cursor.head);

	// is the result off the edge of the screen? if so scroll so it's centered
	matchLine := document_cursor_get_line(*panel.results[0].start);
	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	pageSize := endVisibleLine - startVisibleLine;
	if matchLine < startVisibleLine || matchLine >= (endVisibleLine-1) {
		panel_scroll_to_line(panel, matchLine - pageSize/2); 
	}
}

document_search_on_edit :: (userData: *void, input: string) {
	panel := cast(*Panel) userData;

	if panel.currentRegex.prog {
		uninit(*panel.currentRegex);
	}

	// search for capital letters, if they do not exist, do not do a case sensitive search
	doCaseSensitive := false;
	for input {
		if is_upper(it) then doCaseSensitive = true;
	}

	success: bool;
	flags := ParseFlags.LikePerl;
	if !doCaseSensitive {
		flags |= .FoldCase;
	}
	panel.currentRegex, success = compile(input, flags);
	if success {
		startOffset := panel.cursor.head.documentOffset;
		if panel.cursor.anchor.documentOffset > startOffset {
			startOffset = panel.cursor.anchor.documentOffset; 
		}
		panel.hasMatches, panel.results = match(panel.document, startOffset, panel.document.size, panel.currentRegex);

		// is the result off the edge of the screen? if so scroll so it's centered
		if panel.hasMatches {
			matchLine := document_cursor_get_line(*panel.results[0].start);
			startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
			pageSize := endVisibleLine - startVisibleLine;
			if matchLine < startVisibleLine || matchLine >= (endVisibleLine-1) {
				panel_scroll_to_line(panel, matchLine - pageSize/2); 
			}
		}

	}
}


// Insert Mode
// -----------------------------

insert_mode_insert_string :: (input: string) {
	// do the insert
	distanceToAnchor := focusedPanel.cursor.anchor.documentOffset - focusedPanel.cursor.head.documentOffset;
	focusedPanel.cursor.head = document_insert_text(focusedPanel.document, focusedPanel.cursor.head, input);

	// update the anchor
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	if distanceToAnchor > 0 {
		for focusedPanel.cursor.anchor {
			if it_index >= distanceToAnchor-1 then break;
		}
	}
	else if distanceToAnchor < 0 {
		for < focusedPanel.cursor.anchor {
			if it_index >= abs(distanceToAnchor)-1 then break;
		}
	}
	
	// move the cursors as appropriate,
	// head will move right, anchor will also move if it's ahead of the head
	extendSelections = true;
	if focusedPanel.cursor.head.documentOffset <= focusedPanel.cursor.anchor.documentOffset {
		document_cursor_step_one_forward(*focusedPanel.cursor.anchor, true);
	}
	move_one_char_right(*focusedPanel, string.[]);
	extendSelections = false;
}

insert_mode_handle_text_input :: (char: Utf8_Char) {
	textToInsert := to_string(*char);
	insert_mode_insert_string(textToInsert);
}

insert_mode_line_break :: (using panel: *Panel, args: []string) {
	textToInsert := "\r\n";
	if panel.document.lineEndings == .LF || panel.document.lineEndings == .MIXED_MAJORITY_LF {
		textToInsert = "\n";
	}
	insert_mode_insert_string(textToInsert);
}

insert_tab_character :: (using panel: *Panel, args: []string) {
	textToInsert := "\t";
	insert_mode_insert_string(textToInsert);
}

insert_mode_backward_delete_char :: (using panel: *Panel, args: []string) {
	distanceToAnchor := focusedPanel.cursor.anchor.documentOffset - focusedPanel.cursor.head.documentOffset;

	stepCursor := cursor.head;
	document_cursor_step_one_backward(*stepCursor, true);
	cursor.head = document_delete_text(document, stepCursor, cursor.head);

	// update the anchor
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	if distanceToAnchor > 0 {
		for focusedPanel.cursor.anchor {
			if it_index >= distanceToAnchor-1 then break;
		}
	}
	else if distanceToAnchor < 0 {
		for < focusedPanel.cursor.anchor {
			if it_index >= abs(distanceToAnchor)-1 then break;
		}
	}

	// move anchor as appropriate
	if focusedPanel.cursor.head.documentOffset > focusedPanel.cursor.anchor.documentOffset {
		document_cursor_step_one_forward(*focusedPanel.cursor.anchor, true);
	}
}

insert_mode_forward_delete_char :: (using panel: *Panel, args: []string) {
	distanceToAnchor := focusedPanel.cursor.anchor.documentOffset - focusedPanel.cursor.head.documentOffset;

	stepCursor := cursor.head;
	document_cursor_step_one_forward(*stepCursor, true);
	cursor.head = document_delete_text(document, cursor.head, stepCursor);

	// if the anchor is ahead of us, it should move back one
	if distanceToAnchor > 0 {
	 	document_cursor_step_one_backward(*focusedPanel.cursor.anchor, true);
	}
	else if distanceToAnchor == 0 {
		focusedPanel.cursor.anchor = focusedPanel.cursor.head;
	}
}


// View Commands
// ------------------------------

page_up :: (using panel: *Panel, args: []string) {
	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	pageSize := endVisibleLine - startVisibleLine;

	// move the cursor up half a page
	cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
	move_to_line_visual(*focusedPanel, cursorLine, max(cursorLine - pageSize, 0));
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;

	// scroll to keep the cursor in the same relative place on screen
	panel_scroll_to_line(panel, startVisibleLine - pageSize);
}

page_down :: (using panel: *Panel, args: []string) {
	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	pageSize := endVisibleLine - startVisibleLine;
	numLinesDocument := document_get_num_lines(panel.document);

	// move the cursor down half a page
	cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
	move_to_line_visual(*focusedPanel, cursorLine, min(cursorLine + pageSize, numLinesDocument));
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;

	// scroll to keep the cursor in the same relative place on screen
	panel_scroll_to_line(panel, startVisibleLine + pageSize);
}

half_page_up :: (using panel: *Panel, args: []string) {
	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	pageSize := endVisibleLine - startVisibleLine;

	// move the cursor up half a page
	cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
	move_to_line_visual(*focusedPanel, cursorLine, max(cursorLine - pageSize/2, 0));
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;

	// scroll to keep the cursor in the same relative place on screen
	panel_scroll_to_line(panel, startVisibleLine - pageSize/2);
}

half_page_down :: (using panel: *Panel, args: []string) {
	startVisibleLine, endVisibleLine := panel_calculate_visible_lines(panel);
	pageSize := endVisibleLine - startVisibleLine;
	numLinesDocument := document_get_num_lines(panel.document);

	// move the cursor down half a page
	cursorLine := document_cursor_get_line(*focusedPanel.cursor.head);
	move_to_line_visual(*focusedPanel, cursorLine, min(cursorLine + pageSize/2, numLinesDocument));
	focusedPanel.cursor.anchor = focusedPanel.cursor.head;

	// scroll to keep the cursor in the same relative place on screen
	panel_scroll_to_line(panel, startVisibleLine + pageSize/2);
}


// Dialog Commands
// -----------------------------

dialog_select_next :: (using panel: *Panel, args: []string) {
	if activeDialog == {
		case .NONE; return;
		case .COMMAND_PICKER;
			command_picker_select_next(panel, args);
		case .FILESYSTEM_NAVIGATOR;
			filesystem_nav_select_next(panel, args);
		case .FILE_FINDER;
			file_finder_select_next(panel);
		case .SEARCH; return;
	}
}

dialog_select_previous :: (using panel: *Panel, args: []string) {
	if activeDialog == {
		case .NONE; return;
		case .COMMAND_PICKER;
			command_picker_select_previous(panel, args);
		case .FILESYSTEM_NAVIGATOR;
			filesystem_nav_select_previous(panel, args);
		case .FILE_FINDER;
			file_finder_select_previous(panel);
		case .SEARCH; return;
	}
}

dialog_action_item :: (using panel: *Panel, args: []string) {
	if activeDialog == {
		case .NONE; return;
		case .COMMAND_PICKER;
			command_picker_execute_command(panel, args);
		case .FILESYSTEM_NAVIGATOR;
			filesystem_nav_action_item(panel, args);
		case .FILE_FINDER;
			file_finder_select_file(panel);
		case .SEARCH;
			confirm_document_search(panel, args);
	}
}


dialog_backward_delete :: (using panel: *Panel, args: []string) {
	inputField := *commandPicker.input;
	if activeDialog == {
		case .FILE_FINDER; inputField = *fileFinder.input;
		case .FILESYSTEM_NAVIGATOR; inputField = *filesystemNav.input;
		case .COMMAND_PICKER; inputField = *commandPicker.input;
		case .SEARCH; inputField = *searchInput;
	}

	if activeDialog == {
		case .FILESYSTEM_NAVIGATOR; 
			state := *filesystemNav;
			if state.currentPath.count > 0 && state.input.text.count == 0 {
				state.currentPath.count -= 1;
				filesystem_nav_refresh_directory_list(state);
				return;
			}
			#through;
		case .COMMAND_PICKER; #through;
		case .SEARCH; #through;
		case .FILE_FINDER;
			inputField.text.count -= 1;
			inputField.cursor -= 1;
			if inputField.text.count <= 0 {
				inputField.text.count = 0;
			}
			if inputField.onEditCallback {
				inputField.onEditCallback(inputField.userData, string.{inputField.text.count, inputField.text.data});
			}
		case .NONE; return;
	}
}

dialog_handle_text_input :: (using panel: *Panel, char: Utf8_Char) {
	inputField := *commandPicker.input;
	if activeDialog == {
		case .FILE_FINDER; inputField = *fileFinder.input;
		case .FILESYSTEM_NAVIGATOR; inputField = *filesystemNav.input;
		case .COMMAND_PICKER; inputField = *commandPicker.input;
		case .SEARCH; inputField = *searchInput;
	}

	for 0..char.count-1 {
		array_add(*inputField.text, char.bytes[it]);
		inputField.cursor += 1;
	}
	if inputField.onEditCallback {
		inputField.onEditCallback(inputField.userData, string.{inputField.text.count, inputField.text.data});
	}
}


// Misc Commands
// ------------------------------

quit :: (panel: *Panel, args: []string) {
	pendingQuit = true;
}

open_file :: (panel: *Panel, args: []string) {
	panel.activeDialog = .FILESYSTEM_NAVIGATOR;
	filesystem_nav_open(*panel.filesystemNav);
}

open_file_in_working_dir :: (panel: *Panel, args: []string) {
	panel.activeDialog = .FILESYSTEM_NAVIGATOR;
	filesystem_nav_open(*panel.filesystemNav, false, get_working_directory());
}

save_file :: (panel: *Panel, args: []string) {
	document_save(panel.document, panel.document.path);
}

save_file_as :: (panel: *Panel, args: []string) {
	panel.activeDialog = .FILESYSTEM_NAVIGATOR;
	filesystem_nav_open(*panel.filesystemNav, true);
}

print_piece_chain_debug :: (panel: *Panel, args: []string) {
	document_debug_print_piece_chain(panel.document);
	push_notification("Piecechain debug printed to stdout");
}

visualize_undos :: (using panel: *Panel, args: []string) {
	document_debug_print_undos(document);
}

toggle_render_line_endings :: (panel: *Panel, args: []string) {
	my_font.render_new_lines = !my_font.render_new_lines;
	Simp.force_regenerate_glyph_table(my_font);
}

normalize_line_endings_lf :: (panel: *Panel, args: []string) {
	document_normalize_line_endings(panel.document, .LF);
}

normalize_line_endings_crlf :: (panel: *Panel, args: []string) {
	document_normalize_line_endings(panel.document, .CRLF);
}
