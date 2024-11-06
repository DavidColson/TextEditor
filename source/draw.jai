
draw_one_frame :: () {
	c,_ := hex_to_color_vec4("282c34");
    Simp.clear_render_target(c.x, c.y, c.z, 0.0);

    Simp.set_shader_for_color();

    time := seconds_since_init();

	draw_panel(mainPanel);
    
    Simp.swap_buffers(window);
}

draw_rect :: (rect: Rect, color: Vector4) {
	Simp.immediate_quad(rect.x, rect.y, rect.x + rect.w, rect.y + rect.h, color);
}

draw_filesystem_navigator :: (panel: Panel) {
	// @todo pull out to general style settings
	entryPadding := 5;
	entryHeight := my_font.character_height + entryPadding * 2;

	// @todo, this is duplicating below, pull it out
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;

	navigatorRect:Rect;
	navigatorRect.w = panel.rect.w / 2;
	navigatorRect.h = cast(float) entryHeight * (fileSystemNav.numToDisplay + 1);
	navigatorRect.x = panel.rect.x + (panel.rect.w - navigatorRect.w) / 2;
	navigatorRect.y = panel.rect.y + headerHeight;

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

	if fileSystemNav.pendingAction {
		Simp.prepare_text(my_font, "Enter: open file - D: Delete File - R: Rename/Move");
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.7, 0.7, 0.7, 1.0});
	}
	else {
		// draw current path as blocks
		for fileSystemNav.currentPath.words {
			width := Simp.prepare_text(my_font, it);
			blockRect: Rect;
			blockRect, curPathRect = cut_left(curPathRect, xx width, 2);
			Simp.set_shader_for_color();
			draw_rect(blockRect, Vector4.{0.4, 0.4, 0.4, 1.0});

			Simp.draw_prepared_text(my_font, xx blockRect.x, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
			textX = blockRect.x + blockRect.w + 2;
		}

		// draw input filter text
		Simp.prepare_text(my_font, string.{fileSystemNav.textInput.count, fileSystemNav.textInput.data});
		Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});
	}

	entryRect := cut_bottom(navigatorRect, xx entryHeight);
	for * item, i: fileSystemNav.itemList  {
		if item.sortKey == 0 continue;

		if i == fileSystemNav.selectedItem {
			cmdID := fileSystemNav.selectedItem+1;
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

draw_command_picker :: (panel: Panel) {
	// @todo pull out to general style settings
	commandEntryPadding := 5;
	commandEntryHeight := my_font.character_height + commandEntryPadding * 2;

	// @todo, this is duplicating below, pull it out
	headerPadding := 8;
	headerHeight := my_font.character_height + headerPadding;

	commandsRect:Rect;
	commandsRect.w = panel.rect.w / 2;
	commandsRect.h = cast(float) commandEntryHeight * (commandPicker.filteredCommandList.count + 1);
	commandsRect.x = panel.rect.x + (panel.rect.w - commandsRect.w) / 2;
	commandsRect.y = panel.rect.y + headerHeight;

	Simp.set_shader_for_color();
	draw_rect(commandsRect, Vector4.{0.4, 0.4, 0.4, 1.0});

	inputRect: Rect;
	inputRect, commandsRect = cut_bottom(commandsRect, xx commandEntryHeight);
	inputRect = shrink(inputRect, 3);
	draw_rect(inputRect, Vector4.{0.5, 0.5, 0.5, 1.0});

	Simp.prepare_text(my_font, string.{commandPicker.textInput.count, commandPicker.textInput.data});
	textX := inputRect.x + commandEntryPadding;
	textY := inputRect.y + commandEntryHeight - 10;
	Simp.draw_prepared_text(my_font, xx textX, xx textY, Vector4.{0.8, 0.8, 0.8, 1.0});

	entryRect := cut_bottom(commandsRect, xx commandEntryHeight);
	for commandEntry, i: commandPicker.filteredCommandList  {
		if commandEntry.sortKey == 0 continue;

		if i == commandPicker.selectedCommand {
			cmdID := commandPicker.selectedCommand+1;
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

draw_panel :: (panel: Panel) {

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
		nDigits := tprint("%", mainDocument.lines.count).count;
		textX = my_font.mono_x_advance * (nDigits + 2); // extra 2 for padding
	}

	startVisibleLines : s64;
	endVisibleLines : s64;
	visibleLines: []string;
	if !lineWrap {
		startVisibleLines = clamp(-scrollPos / my_font.character_height, 0, mainDocument.lines.count - 1);
		endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, mainDocument.lines.count - 1);
		visibleLines.data = mainDocument.lines.data + startVisibleLines;
		visibleLines.count = endVisibleLines - startVisibleLines;

		// line numbers
		lineY := textY + my_font.character_height;
		for startVisibleLines..endVisibleLines {
			width := Simp.prepare_text(my_font, tprint("%", it+1));
			Simp.draw_prepared_text(my_font, (textX - width - my_font.mono_x_advance), lineY, Vector4.{0.5, 0.5, 0.5, 1.0});
			lineY += my_font.character_height;
		}
	}
	else {
		startVisibleLines = clamp(-scrollPos / my_font.character_height, 0, mainPanel.wrappedLines.count - 1);
		endVisibleLines = clamp(startVisibleLines + cast(s64)heightForCode / my_font.character_height, 0, mainPanel.wrappedLines.count - 1);
		visibleLinesTemp: [..]string;
		visibleLinesTemp.allocator = temp;
		array_reserve(*visibleLinesTemp, endVisibleLines - startVisibleLines);

		// line numbers
		lineY := textY + my_font.character_height;
		lastLineNum := -1;
		for startVisibleLines..endVisibleLines {
			wrappedLine := mainPanel.wrappedLines[it];
			array_add(*visibleLinesTemp, wrappedLine.line);

			if lastLineNum != wrappedLine.lineNum {
				width := Simp.prepare_text(my_font, tprint("%", wrappedLine.lineNum));
				Simp.draw_prepared_text(my_font, (textX - width - my_font.mono_x_advance), lineY, Vector4.{0.5, 0.5, 0.5, 1.0});
				lastLineNum = wrappedLine.lineNum;
			}
			lineY += my_font.character_height;
		}
		visibleLines = visibleLinesTemp;
	}

	Simp.draw_code(my_font, textX, textY, xx my_font.character_height, visibleLines);

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
		draw_command_picker(panel);
	}

	if editorMode == .FILESYSTEM_NAVIGATOR {
		draw_filesystem_navigator(panel);
	}
}
