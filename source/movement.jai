
move_one_char_left :: (using panel: *Panel, args: []string) {
	document_cursor_step_one_backward(*cursor.head);
	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

move_one_char_right :: (using panel: *Panel, args: []string) {
	document_cursor_step_one_forward(*cursor.head);
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

	newCursor : DocumentCursor;
	newCursor.doc = panel.document;
	newCursor.node = panel.document.pieceChainHead;
	document_cursor_jump_to_offset(*newCursor, lineStartNewLine);
	newColumn := 0;
	if targetVisualColumn > newColumn {
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
			if newColumn == targetVisualColumn then break;
			if newColumn > targetVisualColumn {
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
}

move_one_line_up :: (using panel: *Panel, args: []string) {
	currentLine := document_cursor_get_line(*cursor.head);
	newLine :=max(currentLine-1, 0);

	move_to_line_visual(panel, currentLine, newLine);

	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

goto_document_start :: (using panel: *Panel, args: []string) {
	document_cursor_jump_to_offset(*cursor.head, 0);

	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

goto_document_end :: (using panel: *Panel, args: []string) {
	document_cursor_jump_to_offset(*cursor.head, document.size);

	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

goto_line_end :: (using panel: *Panel, args: []string) { 
	for cursor.head {
		if it == #char "\n" {
			document_cursor_step_one_backward(*cursor.head);
			break;
		}
	}

	if !extendSelections {
		cursor.anchor = cursor.head;
	}
}

goto_line_start :: (using panel: *Panel, args: []string) { 
	for < cursor.head {
		if it == #char "\n" {
			document_cursor_step_one_forward(*cursor.head);
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
	prev := document_cursor_get_char(*cursor.head);
	for < cursor.head {
		nextCharCategory := categorize_char(it);
		prevCharCategory := categorize_char(prev);
		if checkPosition(prev, it, prevCharCategory, nextCharCategory) {
			if it_index == 0  && !extendSelections {
				if !extendSelections {
					cursor.anchor = cursor.head;
					document_cursor_step_one_forward(*cursor.anchor);
				}
			}
			else {
				document_cursor_step_one_forward(*cursor.head);
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
			document_cursor_step_one_forward(*cursor.head);
			break;
		}
	}
}
