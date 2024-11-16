
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

	textX := 0;
	textY := headerHeight;
	if lineNumbers {
		nDigits := tprint("%", mainDocument.lineStarts.count).count;
		textX = my_font.mono_x_advance * (nDigits + 2); // extra 2 for padding
	}

	startVisibleLines : s64;
	endVisibleLines : s64;
	visibleLines: [..]string;
	visibleLines.allocator = temp;

	startVisibleLines = clamp(-scrollPos / my_font.character_height, 0, mainDocument.lineStarts.count - 1);
	endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, mainDocument.lineStarts.count - 1);

	// Draw line numbers
	lineY := textY + my_font.character_height;
	for startVisibleLines..endVisibleLines {
		width := Simp.prepare_text(my_font, tprint("%", it+1));
		Simp.draw_prepared_text(my_font, (textX - width - my_font.mono_x_advance), lineY, Vector4.{0.5, 0.5, 0.5, 1.0});
		lineY += my_font.character_height;
	}

	// Draw the actual code glyphs, with custom rendering
	Simp.draw_code_prepare(my_font,xx textX,xx textY, xx my_font.character_height);
	lineY = textY + my_font.character_height;
	for startVisibleLines..endVisibleLines {
		line:= document_get_line_content(panel.document, xx it);
		Simp.draw_code_line(line);
	}
	Simp.draw_code_end();

	// Draw cursor
	if panel.cursorLine >= startVisibleLines && panel.cursorLine <= endVisibleLines {
		Simp.set_shader_for_color();


		cursorRect: Rect;
		cursorRect.x = cast(float)(textX + my_font.mono_x_advance * panel.cursorColumn);
		cursorRect.y = cast(float)(textY - my_font.typical_descender + my_font.character_height * (panel.cursorLine-startVisibleLines));
		cursorRect.w = cast(float)my_font.mono_x_advance;
		cursorRect.h = cast(float)my_font.character_height;

		draw_rect(cursorRect, Vector4.{0.9, 0.9, 0.9, 1.0});

		overlayChar := document_offset_from_coordinate(panel.document, panel.cursorLine, panel.cursorColumn);
		Simp.prepare_text(my_font, tprint("%", cast(string) u8.[panel.document.bytes[overlayChar]]));
		Simp.draw_prepared_text(my_font, xx cursorRect.x, xx cursorRect.y + my_font.typical_descender + my_font.character_height, Vector4.{0.1, 0.1, 0.1, 1.0});
	}

	// Draw panel header + scroll bar
	Simp.set_shader_for_color();
	Simp.immediate_quad(cast(float)panel.rect.x,
						cast(float)panel.rect.y,
						cast(float)panel.rect.w,
						cast(float)panel.rect.y + headerHeight,
						Vector4.{0.3, 0.3, 0.3, 1.0});

	width := Simp.prepare_text(my_font, tprint("NORM | % - %:% crlf", panel.document.path, 32, 16));
	Simp.draw_prepared_text(my_font, 2, my_font.character_height + 2, Vector4.{0.8, 0.8, 0.8, 1.0});

	// Draw command list
	if editorMode == .COMMAND_PICKER {
		draw_command_picker(panel.rect, *panel.commandPicker);
	}

	if editorMode == .FILESYSTEM_NAVIGATOR {
		draw_filesystem_navigator(panel.rect, *panel.filesystemNav);
	}
}
