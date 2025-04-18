
draw_one_frame :: () {
	c,_ := hex_to_color_vec4("282c34");
    Simp.clear_render_target(c.x, c.y, c.z, 0.0);

    Simp.set_shader_for_color();

    time := seconds_since_init();

	draw_panel(*focusedPanel);


	// draw notifications
	// @todo: styling variable here
	notificationY := my_font.character_height + 20 * dpiScale;
	it := numActiveNotifications;
	while it > 0 {
		notif := notifications[it-1];
		
		width := Simp.prepare_text(my_font, notif.content);

		Simp.set_shader_for_color();
		notifRect:Rect;
		// @todo: styling variable
		// @todo: make the notifications bigger and in bold
		textPadding := 5 * dpiScale;
		notifRect.w = cast(float) width + textPadding * 2;
		notifRect.h = cast(float) my_font.character_height + 4 * dpiScale;
		notifRect.x = cast(float) windowWidth - (width + textPadding + 20 * dpiScale);
		notifRect.y = cast(float) notificationY + (numActiveNotifications-it) * notifRect.h;

		fadeOutTime := cast(float) notificationTime*0.3;
		timeFactor := cast(float) clamp(notif.timer, 0.0, fadeOutTime) / fadeOutTime;
		alpha := lerp(0.0, 1.0, timeFactor);
		draw_rect(notifRect, Vector4.{c.x, c.y, c.z, alpha});

		textX := notifRect.x + textPadding;
		textY := notifRect.y + notifRect.h - textPadding;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, alpha});
		it -= 1;
	}

    Simp.swap_buffers(window);
}

draw_rect :: (rect: Rect, color: Vector4) {
	Simp.immediate_quad(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, color);
}

draw_filesystem_navigator :: (panelRect: Rect, navigator: *FilesystemNavigator) {
	// @todo pull out to general style settings
	entryPadding := 5 * dpiScale;
	entryHeight := my_font.character_height + entryPadding * 2;

	// @todo, this is duplicating below, pull it out
	headerPadding := 8 * dpiScale;
	headerHeight := my_font.character_height + headerPadding;

	navigatorRect:Rect;
	navigatorRect.w = panelRect.w / 2;
	navigatorRect.h = cast(float) entryHeight * (navigator.numToDisplay + 1) + 4 * dpiScale;
	navigatorRect.x = panelRect.x + (panelRect.w - navigatorRect.w) / 2;
	navigatorRect.y = panelRect.y + headerHeight;

	Simp.set_shader_for_color();
	draw_rect(navigatorRect, Vector4.{0.4, 0.4, 0.4, 1.0});

	inputRect: Rect;
	inputRect, navigatorRect = cut_bottom(navigatorRect, xx entryHeight + 4 * dpiScale);
	inputRect = shrink(inputRect, 4 * dpiScale);
	draw_rect(inputRect, Vector4.{0.5, 0.5, 0.5, 1.0});

	curPathRect: Rect;
	curPathRect = shrink(inputRect, 2 * dpiScale);
	textY := inputRect.y + entryHeight - 10 * dpiScale;
	textX := curPathRect.x + 2 * dpiScale;

	if navigator.pendingAction {
		if navigator.saveMode {
			Simp.prepare_text(my_font, "Overwite file? Enter: Confirm - Esc: Cancel");
		}
		else {
			Simp.prepare_text(my_font, "Enter: open file - D: Delete File - R: Rename/Move");
		}
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.7, 0.7, 0.7, 1.0});
	}
	else {
		// draw current path as blocks
		for navigator.currentPath {
			width := Simp.prepare_text(my_font, it) + 4 * dpiScale;
			blockRect: Rect;
			blockRect, curPathRect = cut_left(curPathRect, xx width, 2);
			Simp.set_shader_for_color();
			draw_rect(blockRect, Vector4.{0.4, 0.4, 0.4, 1.0});

			Simp.draw_prepared_text(my_font, xx (blockRect.x + 2 * dpiScale), xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
			textX = blockRect.x + blockRect.w + cast(int) (4 * dpiScale);
		}

		// draw input filter text
		Simp.prepare_text(my_font, input_field_get_text(*navigator.input));
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
	}

	// draw list of options
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
		textY = entryRect.y + entryHeight - 8 * dpiScale;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		entryRect.y += entryHeight;
	}
	
	// special case, draw the save as item
	if navigator.saveMode && navigator.currentPath.count > 0 && navigator.input.text.count > 0 {
		entryRect.y -= entryHeight;
		builder: String_Builder;
		builder.allocator = temp;
		init_string_builder(*builder);

		append(*builder, "Save As - ");
		for navigator.currentPath {
			append(*builder, it);
			if (it_index != navigator.currentPath.count-1)  append(*builder, "/");
		}
		append(*builder, "/");
		append(*builder, input_field_get_text(*navigator.input));
    
		Simp.prepare_text(my_font, builder_to_string(*builder,,temp));
		textX = entryRect.x + entryPadding;
		textY = entryRect.y + entryHeight - 8;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		entryRect.y += entryHeight;
	}
}

draw_command_picker :: (panelRect: Rect, picker: *CommandPicker) {
	// @todo pull out to general style settings
	commandEntryPadding := 5 * dpiScale;
	commandEntryHeight := my_font.character_height + commandEntryPadding * 2;

	// @todo, this is duplicating below, pull it out
	headerPadding := 8 * dpiScale;
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
	inputRect = shrink(inputRect, 3 * dpiScale);
	draw_rect(inputRect, Vector4.{0.5, 0.5, 0.5, 1.0});

	Simp.prepare_text(my_font, input_field_get_text(*picker.input));
	textX := inputRect.x + commandEntryPadding;
	textY := inputRect.y + commandEntryHeight - 10 * dpiScale;
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
		textY = entryRect.y + commandEntryHeight - 8 * dpiScale;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
		entryRect.y += commandEntryHeight;
	}
}

draw_cursor_range :: (textAreaX: s64, textAreaY: s64, cursor1: DocumentCursor, cursor2: DocumentCursor, linesOnScreen: []string, startVisibleLine: s64, includeCursor := false) {
    Simp.set_shader_for_color();
	rangeStart, rangeEnd := convert_cursors_to_coordinate_range(cursor1, cursor2, includeCursor);
	lineWidths: [..] s32;
	lineWidths.allocator = temp;
	endVisibleLine := startVisibleLine + linesOnScreen.count;
	if rangeStart.line < startVisibleLine || rangeEnd.line > endVisibleLine {
		return;
	}
	for rangeStart.line..rangeEnd.line {
		line := linesOnScreen[it - startVisibleLine];
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
		selection.x = cast(float)(textAreaX + selectionX);
		selection.y = cast(float)(textAreaY - my_font.typical_descender + my_font.character_height * (it-startVisibleLine));
		selection.w = cast(float)selectionW;
		selection.h = cast(float)my_font.character_height;

		draw_rect(selection, .{0.4, 0.4, 0.4, 1.0});
	}

}

draw_panel :: (panel: *Panel) {
	// @todo: global styling here
	headerPadding := cast(int) (8 * dpiScale);
	headerHeight := my_font.character_height + headerPadding;

	// Draw actual code + line numbers
	heightForCode := panel.rect.h - headerHeight;

	color: Vector4;
	color.x = 1;
	color.y = 1;
	color.z = 1;
	color.w = 1;

	if panel.document {
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

		startVisibleLines = clamp(-panel.scrollPos / my_font.character_height, 0, documentLines - 1);
		endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, documentLines - 1);

		cursorLine := document_cursor_get_line(*panel.cursor.head);

		// Draw line numbers
		lineY := textRegionY + my_font.character_height;
		for startVisibleLines..endVisibleLines {
			width := Simp.prepare_text(my_font, tprint("%", it+1));
			// @monospace doesn't work for non-monospace numbers
			Simp.draw_prepared_text(my_font, (textRegionX - width - my_font.mono_x_advance), lineY, Vector4.{0.5, 0.5, 0.5, 1.0});
			lineY += my_font.character_height;
		}

		// collect together the actual lines of text we need to render
		// @todo: refactor to use document cursors to walk through text rather than get_line_content for every line
		linesOnScreen: [..]string;
		linesOnScreen.allocator = temp;
		for startVisibleLines..endVisibleLines {
			array_add(*linesOnScreen, document_get_line_content(panel.document, xx it));
		}

		// draw the cursor selection
		if panel.activeDialog != .SEARCH && cursorLine >= startVisibleLines && cursorLine <= endVisibleLines {
			Simp.set_shader_for_color();
			if panel.cursor.head.documentOffset != panel.cursor.anchor.documentOffset {
				draw_cursor_range(textRegionX, textRegionY, panel.cursor.head, panel.cursor.anchor, linesOnScreen, startVisibleLines, true);
			}
		}

		// draw search results
		if panel.activeDialog == .SEARCH {
			for panel.results {
				draw_cursor_range(textRegionX, textRegionY, it.start, it.end, linesOnScreen, startVisibleLines);
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
		if panel.activeDialog != .SEARCH && cursorLine >= startVisibleLines && cursorLine <= endVisibleLines {
			Simp.set_shader_for_color();
			cursorChar := document_cursor_get_char(*panel.cursor.head);
			cursorCharWidth := calculate_string_length_pixels(my_font, cast(string) u8.[cursorChar]);

			cursorColumn := panel.cursor.head.documentOffset - document_get_line_start(panel.document, cursorLine);
			line := linesOnScreen[cursorLine - startVisibleLines];
			line.count = cursorColumn;
			cursorX := calculate_string_length_pixels(my_font, line);

			cursorRect: Rect;
			cursorRect.x = cast(float)(textRegionX + cursorX);
			cursorRect.y = cast(float)(textRegionY - my_font.typical_descender + my_font.character_height * (cursorLine-startVisibleLines));
			cursorRect.w = cast(float)cursorCharWidth;
			cursorRect.h = cast(float)my_font.character_height;

			color: Vector4 = .{0.8, 0.8, 0.8, 1.0};
			if editorMode == .INSERT {
				color = .{1.0, 1.0, 1.0, 1.0};
			}
			draw_rect(cursorRect, color);

			if cursorChar != 0 {
				Simp.prepare_text(my_font, tprint("%", cast(string) u8.[cursorChar]));
				Simp.draw_prepared_text(my_font, xx cursorRect.x, xx cursorRect.y + my_font.typical_descender + my_font.character_height, Vector4.{0.1, 0.1, 0.1, 1.0});
			}
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
	else if editorMode == .INSERT {
		modeText = "INS";
	}

	if panel.document {
		lineEndingText := "[Mixed line endings, will be normalized to CRLF on save]";
		if panel.document.lineEndings == .LF {
			lineEndingText = "LF";
		}
		else if panel.document.lineEndings == .CRLF {
			lineEndingText = "CRLF";
		}
		else if panel.document.lineEndings == .MIXED_MAJORITY_LF {
			lineEndingText = "[Mixed line endings, will be normalized to LF on save]";
		}

		cursorCoordinate := document_cursor_get_coordinate(*panel.cursor.head);
		width := Simp.prepare_text(my_font, tprint("% | %0% - %:%(%) %", 
									modeText,
									panel.document.path,
									ifx panel.document.unsaved then "[UNSAVED]" else "",
									cursorCoordinate.line+1,
									cursorCoordinate.col,
									panel.cursor.head.documentOffset,
									lineEndingText));
		Simp.draw_prepared_text(my_font, cast(int) (2 * dpiScale), my_font.character_height + cast(int) (2 * dpiScale), Vector4.{0.8, 0.8, 0.8, 1.0});
	}
	else {
		width := Simp.prepare_text(my_font, tprint("% | NO DOCUMENT LOADED", modeText));
		Simp.draw_prepared_text(my_font, cast(int) (2 * dpiScale), my_font.character_height + cast(int) (2 * dpiScale), Vector4.{0.8, 0.8, 0.8, 1.0});
	}

	registerText := "";
	if registers.selectedRegister != DEFAULT_REGISTER {
		registerText = tprint("reg=%", string.{1,*registers.selectedRegister});
	}

	pendingKeys := string.{keyMap.pendingKeyString.count, keyMap.pendingKeyString.data};
	width := Simp.prepare_text(my_font, tprint("% %", registerText, pendingKeys));
	Simp.draw_prepared_text(my_font, cast(s64) (panel.rect.w - width - my_font.mono_x_advance), my_font.character_height + cast(int) (2 * dpiScale), Vector4.{0.8, 0.8, 0.8, 1.0});

	// Draw command list
	if panel.activeDialog == .COMMAND_PICKER {
		draw_command_picker(panel.rect, *panel.commandPicker);
	}

	if panel.activeDialog == .FILESYSTEM_NAVIGATOR {
		draw_filesystem_navigator(panel.rect, *panel.filesystemNav);
	}

	// Draw search bar
	if panel.activeDialog == .SEARCH {
		Simp.set_shader_for_color();

		// search bar itself
		// @todo: styling params
		searchBarTextPadding := 3 * dpiScale;
		searchBarInputBoxPadding := 4 * dpiScale;

		searchBarRect: Rect;
		searchBarRect.w = cast(float) panel.rect.w;
		searchBarRect.h = cast(float) my_font.character_height + searchBarInputBoxPadding*2 + searchBarTextPadding*2;
		searchBarRect.x = cast(float) panel.rect.x;
		searchBarRect.y = cast(float) panel.rect.h - searchBarRect.h;

		draw_rect(searchBarRect, .{0.4, 0.4, 0.4, 1.0});

		width = Simp.prepare_text(my_font, "Search: ");

		inputBoxRect := shrink(searchBarRect, xx searchBarInputBoxPadding);
		inputBoxRect.x += width + searchBarTextPadding;
		inputBoxRect.w -= width + searchBarTextPadding;

		Simp.draw_prepared_text(my_font, cast(s64) (inputBoxRect.x - width), cast(s64) (inputBoxRect.y + my_font.character_height), Vector4.{0.8, 0.8, 0.8, 1.0});

		Simp.set_shader_for_color();
		draw_rect(inputBoxRect, .{0.5, 0.5, 0.5, 1.0});

		Simp.prepare_text(my_font, input_field_get_text(*panel.searchInput));
		textX := inputBoxRect.x + searchBarTextPadding;
		textY := inputBoxRect.y + my_font.character_height;
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});

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
