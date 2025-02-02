
draw_one_frame :: () {
	c,_ := hex_to_color_vec4("282c34");
    Simp.clear_render_target(c.x, c.y, c.z, 0.0);

    Simp.set_shader_for_color();

    time := seconds_since_init();

	draw_panel(*focusedPanel);
    
    Simp.swap_buffers(window);
}

draw_rect :: (rect: Rect, color: Vector4) {
	Simp.immediate_quad(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, color);
}

draw_filesystem_navigator :: (panelRect: Rect, navigator: *FilesystemNavigator) {
	// @todo pull out to general style settings
	entryPadding := 5;
	entryHeight := my_font.character_height + entryPadding * 2;

	// @todo, this is duplicating below, pull it out
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;

	navigatorRect:Rect;
	navigatorRect.w = panelRect.w / 2;
	navigatorRect.h = cast(float) entryHeight * (navigator.numToDisplay + 1);
	navigatorRect.x = panelRect.x + (panelRect.w - navigatorRect.w) / 2;
	navigatorRect.y = panelRect.y + headerHeight;

	Simp.set_shader_for_color();
	draw_rect(navigatorRect, Vector4.{0.4, 0.4, 0.4, 1.0});

	inputRect: Rect;
	inputRect, navigatorRect = cut_bottom(navigatorRect, xx entryHeight);
	inputRect = shrink(inputRect, 3);
	draw_rect(inputRect, Vector4.{0.5, 0.5, 0.5, 1.0});

	curPathRect: Rect;
	curPathRect = shrink(inputRect, 2);
	textY := inputRect.y + entryHeight - 10;
	textX := curPathRect.x + 2;

	if navigator.pendingAction {
		Simp.prepare_text(my_font, "Enter: open file - D: Delete File - R: Rename/Move");
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.7, 0.7, 0.7, 1.0});
	}
	else {
		// draw current path as blocks
		for navigator.currentPath {
			width := Simp.prepare_text(my_font, it);
			blockRect: Rect;
			blockRect, curPathRect = cut_left(curPathRect, xx width, 2);
			Simp.set_shader_for_color();
			draw_rect(blockRect, Vector4.{0.4, 0.4, 0.4, 1.0});

			Simp.draw_prepared_text(my_font, xx blockRect.x, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
			textX = blockRect.x + blockRect.w + 2;
		}

		// draw input filter text
		Simp.prepare_text(my_font, string.{navigator.textInput.count, navigator.textInput.data});
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
	}

	entryRect := cut_bottom(navigatorRect, xx entryHeight);
	for * item, i: navigator.itemList  {
		if item.sortKey == 0 continue;

		if i == navigator.selectedItem {
			cmdID := navigator.selectedItem+1;
			Simp.set_shader_for_color();
			draw_rect(entryRect, Vector4.{0.5, 0.5, 0.5, 1.0});
		}

		width := Simp.prepare_text(my_font, item.name);

		textX = entryRect.x + entryPadding;
		textY = entryRect.y + entryHeight - 8;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		entryRect.y += entryHeight;
	}
}

draw_command_picker :: (panelRect: Rect, picker: *CommandPicker) {
	// @todo pull out to general style settings
	commandEntryPadding := 5;
	commandEntryHeight := my_font.character_height + commandEntryPadding * 2;

	// @todo, this is duplicating below, pull it out
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;

	commandsRect:Rect;
	commandsRect.w = panelRect.w / 2;
	commandsRect.h = cast(float) commandEntryHeight * (picker.filteredCommandList.count + 1);
	commandsRect.x = panelRect.x + (panelRect.w - commandsRect.w) / 2;
	commandsRect.y = panelRect.y + headerHeight;

	Simp.set_shader_for_color();
	draw_rect(commandsRect, Vector4.{0.4, 0.4, 0.4, 1.0});

	inputRect: Rect;
	inputRect, commandsRect = cut_bottom(commandsRect, xx commandEntryHeight);
	inputRect = shrink(inputRect, 3);
	draw_rect(inputRect, Vector4.{0.5, 0.5, 0.5, 1.0});

	Simp.prepare_text(my_font, string.{picker.textInput.count, picker.textInput.data});
	textX := inputRect.x + commandEntryPadding;
	textY := inputRect.y + commandEntryHeight - 10;
	Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});

	entryRect := cut_bottom(commandsRect, xx commandEntryHeight);
	for commandEntry, i: picker.filteredCommandList  {
		if commandEntry.sortKey == 0 continue;

		if i == picker.selectedCommand {
			cmdID := picker.selectedCommand+1;
			Simp.set_shader_for_color();
			draw_rect(entryRect, Vector4.{0.5, 0.5, 0.5, 1.0});
		}

		command := commandEntry.command;
		width := Simp.prepare_text(my_font, command.name);

		textX = entryRect.x + commandEntryPadding;
		textY = entryRect.y + commandEntryHeight - 8;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		entryRect.y += commandEntryHeight;
	}
}

draw_panel :: (panel: *Panel) {

	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;

	// Draw actual code + line numbers
	heightForCode := panel.rect.h - headerHeight;

	color: Vector4;
	color.x = 1;
	color.y = 1;
	color.z = 1;
	color.w = 1;

	documentLines := document_get_num_lines(panel.document);
	textRegionX := 0;
	textRegionY := headerHeight;
	if lineNumbers {
		nDigits := tprint("%", documentLines).count;
		// @monospace
		textRegionX = my_font.mono_x_advance * (nDigits + 2); // extra 2 for padding
	}

	startVisibleLines : s64;
	endVisibleLines : s64;
	visibleLines: [..]string;
	visibleLines.allocator = temp;

	startVisibleLines = clamp(-scrollPos / my_font.character_height, 0, documentLines - 1);
	endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, documentLines - 1);

	// scroll the panel to keep the primary cursor on screen
	cursorLine := document_cursor_get_line(*panel.cursor.head);
	if cursorLine < startVisibleLines {
		difference := cursorLine - startVisibleLines;
		scrollPos -= my_font.character_height * difference;
		startVisibleLines = clamp(-scrollPos / my_font.character_height, 0, documentLines - 1);
		endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, documentLines - 1);
	}

	// Since we may scroll off the end of the document, this is how many lines _could_ be shown if they existed
	endVisibleLinesUnclamped := startVisibleLines + cast(s64)heightForCode / my_font.character_height;
	if cursorLine > (endVisibleLinesUnclamped-1) {
		difference := (endVisibleLinesUnclamped-1) - cursorLine;
		scrollPos += my_font.character_height * difference;
		startVisibleLines = clamp(-scrollPos / my_font.character_height, 0, documentLines - 1);
		endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, documentLines - 1);
	}

	// Draw line numbers
	lineY := textRegionY + my_font.character_height;
	for startVisibleLines..endVisibleLines {
		width := Simp.prepare_text(my_font, tprint("%", it+1));
		// @monospace doesn't work for non-monospace numbers
		Simp.draw_prepared_text(my_font, (textRegionX - width - my_font.mono_x_advance), lineY, Vector4.{0.5, 0.5, 0.5, 1.0});
		lineY += my_font.character_height;
	}

	// collect together the actual lines of text we need to render
	linesOnScreen: [..]string;
	linesOnScreen.allocator = temp;
	for startVisibleLines..endVisibleLines {
		array_add(*linesOnScreen, document_get_line_content(panel.document, xx it));
	}

	// draw the cursor selection
	anchorLine := document_cursor_get_line(*panel.cursor.anchor);
	if cursorLine >= startVisibleLines && cursorLine <= endVisibleLines {
		Simp.set_shader_for_color();
		if panel.cursor.head.documentOffset != panel.cursor.anchor.documentOffset {
			rangeStart, rangeEnd := convert_cursor_to_coordinate_range(panel.cursor, true);
			lineWidths: [..] s32;
			lineWidths.allocator = temp;
			for rangeStart.line..rangeEnd.line {
				line := linesOnScreen[it - startVisibleLines];
				lineWidth := calculate_string_length_pixels(my_font, line);

				isFirstLine:= it == rangeStart.line;
				isLastLine:= it == rangeEnd.line;

				selectionX := 0;
				selectionW := lineWidth;
				if isFirstLine {
					selectionX = calculate_string_length_pixels(my_font, string.{rangeStart.col,line.data});
					selectionW = lineWidth - selectionX;
				}
				if isLastLine {
					selectionW = calculate_string_length_pixels(my_font, string.{rangeEnd.col,line.data}) - selectionX;
				}
				

				selection: Rect;
				selection.x = cast(float)(textRegionX + selectionX);
				selection.y = cast(float)(textRegionY - my_font.typical_descender + my_font.character_height * (it-startVisibleLines));
				selection.w = cast(float)selectionW;
				selection.h = cast(float)my_font.character_height;

				draw_rect(selection, .{0.4, 0.4, 0.4, 1.0});
			}
		}
	}

	// Draw the actual code glyphs, with custom rendering
	Simp.draw_code_prepare(my_font,xx textRegionX,xx textRegionY, xx my_font.character_height);
	lineY = textRegionY + my_font.character_height;
	for line: linesOnScreen {
		Simp.draw_code_line(line);
	}
	Simp.draw_code_end();

	// Draw cursor
	if cursorLine >= startVisibleLines && cursorLine <= endVisibleLines {
		Simp.set_shader_for_color();

		cursorColumn := panel.cursor.head.documentOffset - document_get_line_start(panel.document, cursorLine);
		line := linesOnScreen[cursorLine - startVisibleLines];
		line.count = cursorColumn;
		cursorX := calculate_string_length_pixels(my_font, line);

		// @monospace need actual letter width here 
		cursorRect: Rect;
		cursorRect.x = cast(float)(textRegionX + cursorX);
		cursorRect.y = cast(float)(textRegionY - my_font.typical_descender + my_font.character_height * (cursorLine-startVisibleLines));
		cursorRect.w = cast(float)my_font.mono_x_advance;
		cursorRect.h = cast(float)my_font.character_height;

		color: Vector4 = .{0.8, 0.8, 0.8, 1.0};
		if editorMode == .INSERT {
			color = .{1.0, 1.0, 1.0, 1.0};
		}
		draw_rect(cursorRect, color);

		overlayChar := document_cursor_get_char(*panel.cursor.head);
		if overlayChar != 0 {
			Simp.prepare_text(my_font, tprint("%", cast(string) u8.[overlayChar]));
			Simp.draw_prepared_text(my_font, xx cursorRect.x, xx cursorRect.y + my_font.typical_descender + my_font.character_height, Vector4.{0.1, 0.1, 0.1, 1.0});
		}
	}

	// Draw panel header + scroll bar
	Simp.set_shader_for_color();
	Simp.immediate_quad(cast(float)panel.rect.x,
						cast(float)panel.rect.y,
						cast(float)panel.rect.w,
						cast(float)panel.rect.y + headerHeight,
						Vector4.{0.3, 0.3, 0.3, 1.0});

	modeText := "NOR";
	if extendSelections && editorMode == .NORMAL {
		modeText = "SEL";
	}
	if editorMode == .INSERT {
		modeText = "INS";
	}

	cursorCoordinate := document_cursor_get_coordinate(*panel.cursor.head);
	width := Simp.prepare_text(my_font, tprint("% | % - %:% crlf", modeText, panel.document.path, cursorCoordinate.line+1, cursorCoordinate.col));
	Simp.draw_prepared_text(my_font, 2, my_font.character_height + 2, Vector4.{0.8, 0.8, 0.8, 1.0});

	pendingKeys := string.{keyMap.pendingKeyString.count, keyMap.pendingKeyString.data};
	width = Simp.prepare_text(my_font, tprint("%", pendingKeys));
	Simp.draw_prepared_text(my_font, cast(s64) (panel.rect.w - width - my_font.mono_x_advance), my_font.character_height + 2, Vector4.{0.8, 0.8, 0.8, 1.0});

	// Draw command list
	if editorMode == .COMMAND_PICKER {
		draw_command_picker(panel.rect, *panel.commandPicker);
	}

	if editorMode == .FILESYSTEM_NAVIGATOR {
		draw_filesystem_navigator(panel.rect, *panel.filesystemNav);
	}
}

#scope_file
calculate_string_length_pixels :: (font: *Simp.Dynamic_Font, s: string) -> s64 {
	len := 0;
	for s {
		if it == #char "\t" {
			chars_to_tabstop := tabSize - len % tabSize;
			len = len + my_font.mono_x_advance * chars_to_tabstop;
		}
		else {
			len = len + my_font.mono_x_advance;
		}
	}
	return len;
}
