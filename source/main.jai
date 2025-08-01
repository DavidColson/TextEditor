BuildType :: enum u8
{
	DEBUG;
	OPTIMIZED;
	RELEASE;
}

DialogType :: enum u8 {
	NONE;
	COMMAND_PICKER;
	FILESYSTEM_NAVIGATOR;
	FILE_FINDER;
	SEARCH;
}

EditorMode :: enum u8 {
	NORMAL;
	INSERT;
	DIALOG;
}

Notification :: struct {
	content: string;
	timer: float64;
}

style : struct {
	// colors
	backgroundDark := #run hex_to_color_vec4("1C1F25");
	backgroundMid := #run hex_to_color_vec4("282C34");
	backgroundLight := #run hex_to_color_vec4("3B414C");
	backgroundLighter := #run hex_to_color_vec4("4e5665");

	hotHighlight := #run hex_to_color_vec4("636f85");
	activeHighlight := #run hex_to_color_vec4("7e90bd");

	textPrimary := #run hex_to_color_vec4("C3C7D0");
	textSecondary := #run hex_to_color_vec4("5C6370");
	textHighlight := #run hex_to_color_vec4("7e90bd");
	textSelection := #run hex_to_color_vec4("434d60");

	borders := #run hex_to_color_vec4("5C6476");

	// fonts
	fontSize := 15;
	codeFont := string.["FiraMonoNerdFontMono-Regular.ttf", "consola.ttf"];
	uiFont := string.["segoeui.ttf"];

	// Icons
	iconVerticalEllipsis :: #run to_string(*convert_utf32_to_utf8(0xf142));
	iconCircle :: #run to_string(*convert_utf32_to_utf8(0xf111));
	iconLock :: #run to_string(*convert_utf32_to_utf8(0xf023));
	iconNumList :: #run to_string(*convert_utf32_to_utf8(0xf0cb));
	iconAlignLeft :: #run to_string(*convert_utf32_to_utf8(0xf036));
	iconFolder :: #run to_string(*convert_utf32_to_utf8(0xf07c));
	iconFile :: #run to_string(*convert_utf32_to_utf8(0xf15b));

	// animations
	scrollAnimRate := 14;
};

EDITOR_MODE_NUM :: #run enum_highest_value(EditorMode) + 1;

// globals
editorMode := EditorMode.NORMAL;
extendSelections := false;
focusedPanel : Panel;
watcher: File_Watcher(void);
watchedFiles: [..]string;
window: Window_Type;
windowWidth  : s32 = 1920;
windowHeight : s32 = 1080;
dpiScale := 1.0;
pendingQuit := false;
backupSaveTimer:float64 = 300;
requestRedraw := true;
deltaTime:float64 = 0.016;
lastTime:float64 = 0.0;

notifications : [10]Notification;
numActiveNotifications := 0;
notificationTime: float64 = 10;

// registers
DEFAULT_REGISTER :: #char "+";
Registers :: struct {
	registerPool: Flat_Pool;
	registerAllocator: Allocator;
	table: Table(u8, [..]u8);
	selectedRegister:u8 = DEFAULT_REGISTER;
}
registers: Registers;

// fonts
fontUI: *Font;
fontCode: *Font;
fontIcons: *Font;

// options
textSize :: 15;
tabSize :: 4;
lineNumbers := true;

Arguments :: struct {
	fetch_grammars: bool;
	build_grammars: bool;
}

// you really want a dynamic load here no?
// jai :: #library "../grammars/jai";
// tree_sitter_jai :: () -> *TSLanguage #foreign jai;

main :: () {
    #if OS == .WINDOWS {
        Windows :: #import "Windows";
        // Windows is very bad at thread-switching by default unless you do this. Sad.
        Windows.timeBeginPeriod(1);
    }

	success, args, isSet, filesToOpen := parse_arguments(Arguments);
	if !success {
		return;
	}

	if isSet.fetch_grammars then fetch_grammars();
	if isSet.build_grammars then build_grammars();
	if isSet.fetch_grammars || isSet.build_grammars then return;
	
	// create window
    window = create_window(windowWidth, windowHeight, "TextEditor");
	Input.window_move_callback = update;
	platform_set_border_color();
	init_renderer(window);
	init_font_cache();
	load_fonts();
	init_ui();
	rebuild_key_map();

	// treesitter test
	parser := ts_parser_new();

	// @todo: this syntax breaks the treesitter parser
	{
		language := get_grammar("jai")();
		log("name %", to_string(ts_language_name(language)));
		log("abi %", ts_language_abi_version(language));

		result := ts_parser_set_language(parser, language);
		log("setLangResult %", result);
	}
	
	treesitter_logger :: (payload: *void, log_type: TSLogType, buffer: *u8) #c_call {
	    push_context {
	        log("%", to_string(buffer));
	    }
	}
	
	ts_parser_set_logger(parser, .{null, treesitter_logger});

	exampleCpp := "myVariable := 5;";
	tree := ts_parser_parse_string(parser, null, exampleCpp.data, xx exampleCpp.count);

	if tree {
		rootNode := ts_tree_root_node(tree);
		debug := to_string(ts_node_string(rootNode));
		log("%", debug);
	}


	registers.registerAllocator = Allocator.{ proc = flat_pool_allocator_proc, data = *registers.registerPool };

	if !init(*watcher, file_change_callback, watch_recursively = false) {
        push_notification("Could not initialize the file watcher. Files won't be reloaded. This is likely a bug.");
    }

	focusedPanel.layoutRect.x = 0;
	focusedPanel.layoutRect.y = 0;
	focusedPanel.layoutRect.w = xx windowWidth;
	focusedPanel.layoutRect.h = xx windowHeight;
	focusedPanel.activeDialog = .NONE;

	if filesToOpen.count > 0 {
		doc := document_open(filesToOpen[0]);
		if doc {
			panel_set_active_document(*focusedPanel, doc);
		}
	}

	platform_set_backup_timer(window, do_backup_callback);

	lastTime = seconds_since_init();
    want_screenshot := false;
    while !pendingQuit {
		update();
	}
}

update :: () {
	if !requestRedraw platform_wait_message();
	requestRedraw = false;

	now := seconds_since_init();
	deltaTime = min(now - lastTime, 0.016);
	lastTime = now;

    Input.update_window_events();

    for Input.get_window_resizes() {
        if it.window == window {
            should_reinit := (it.width != windowWidth) || (it.height != windowHeight);

            windowWidth  = it.width;
            windowHeight = it.height;

			resize_backbuffer();

			focusedPanel.layoutRect.x = 0;
			focusedPanel.layoutRect.y = 0;
			focusedPanel.layoutRect.w = xx windowWidth;
			focusedPanel.layoutRect.h = xx windowHeight;
        }
    }

    for Input.events_this_frame {
        if it.type == .QUIT then pendingQuit = true;
		array_add(*uiState.events, it);
	}

	process_changes(*watcher);

	newDpiScale := platform_get_dpi_scale(window);
	if newDpiScale != dpiScale && newDpiScale != 0.0 {
		dpiScale = newDpiScale;
	}

	build_ui();

	// after ui has taken any inputs it wants, we'll give the rest to the default input handler
	for uiState.events {
		input_handler(it);
	}
	array_reset_keeping_memory(*uiState.events);

	// update notifications
	nNotificationsToRemove := 0;
	it := 0;
	while it < numActiveNotifications {
		notif := *notifications[it];
		notif.timer -= deltaTime;
		if notif.timer < 0 {
			nNotificationsToRemove += 1;
		}
		it += 1;
	}

	if nNotificationsToRemove > 0 {
		memcpy(notifications.data, notifications.data + nNotificationsToRemove, (numActiveNotifications - nNotificationsToRemove)*size_of(Notification));
		numActiveNotifications -= nNotificationsToRemove;
	}
	if numActiveNotifications > 0 {
		requestRedraw = true;
	}

	// @todo: may want to support 120hz or higher? 
    sleep_milliseconds(cast(s32) (16 - deltaTime/1000));
    reset_temporary_storage();
}

build_ui :: () {
	begin_ui();

	uiState.defaultPalette = .{
		text = style.textPrimary,
		textHighlight = style.textHighlight,
		background=style.backgroundMid,
		hot=style.hotHighlight,
		active=style.activeHighlight,
		border=style.borders
	};
	uiState.defaultFont = fontUI;
	uiState.defaultFontSize = style.fontSize * dpiScale;
	uiState.defaultTextPadding = em(0.2);

	// Draw notifications
	
	fontMetrics := get_font_metrics(uiState.defaultFont, xx uiState.defaultFontSize);

	maxWidth := 0.0;
	for * notifications {
		textRun := generate_text_run(it.content, xx uiState.defaultFontSize, uiState.defaultFont,,temp);
		maxWidth = max(maxWidth, textRun.width);
	}

	it := numActiveNotifications;
	notificationBox := box(ui_key("notifBox"), .{
		flags=0,
		layout=.{
			childLayoutAxis = .Y,
			width=fit(),
			height=fit(),
			childAlignment=.RIGHT,
			childGap=em(0.5)
		},
		fixedX= windowWidth - maxWidth - em(2.5),
		fixedY= em(3.0),
	});
	{
		push_parent(notificationBox); defer pop_parent();
		while it > 0 {
			notif := notifications[it-1];
			fadeOutTime := cast(float) notificationTime*0.3;
			timeFactor := cast(float) clamp(notif.timer, 0.0, fadeOutTime) / fadeOutTime;
			alpha := lerp(0.0, 1.0, timeFactor);

			backgroundCol := style.activeHighlight;
			backgroundCol.w = alpha;
			textCol := style.backgroundMid;
			textCol.w = alpha;
			box(ui_key("%##%", notif.content, it), .{
				flags=.DRAW_TEXT | .DRAW_BACKGROUND,
				layout=.{ width=text_content(), height=text_content() },
				palette=.{background=backgroundCol, text=textCol},
				textPadding=em(0.4),
				cornerRadius=corner_rad_all(em(0.3))
			});
			it -= 1;
		}
	}
	
	// Draw the panel
	if focusedPanel.document {
		build_ui_panel(*focusedPanel);
	}
	else {
		build_ui_empty_panel(*focusedPanel);
	}

	end_ui();

	render_frame();
}

build_ui_empty_panel :: (panel: *Panel) {
	panelBox := box(ui_key("panel1"), .{
		flags=.DRAW_BACKGROUND,
		layout=.{
			childLayoutAxis = .Y,
			width=fixed(panel.layoutRect.w),
			height=fixed(panel.layoutRect.h),
			childAlignment=.CENTER
		},
	});
	push_parent(panelBox); defer pop_parent();

	header := box(ui_key_nil, .{
		flags=.DRAW_BACKGROUND | .DRAW_SIDE_BOTTOM,
		layout=.{ 
			childLayoutAxis = .X,
			width=grow(),
			height=fit(),
			padding= padding_all(em(0.3))
		},
		palette=.{ background=style.backgroundLight },
		borderThickness=1.0
	});
	{
		push_parent(header); defer pop_parent();
		box(ui_key("DUMMY"), .{
			flags=0,
			layout=.{ width=text_content(), height=text_content() },
		});
	}
	

	build_ui_panel_dialogs(panel);

	spacer(.Y, fixed(em(5.0)));

	box(ui_key("No Document Loaded"), .{
		flags=.DRAW_TEXT,
		layout=.{ width=text_content(), height=text_content() },
	});

	spacer(.Y, fixed(em(3.0)));

	box(ui_key("Open file with '<space>O'"), .{
		flags=.DRAW_TEXT,
		layout=.{ width=text_content(), height=text_content() },
	});
	box(ui_key("Open command palette with ':'"), .{
		flags=.DRAW_TEXT,
		layout=.{ width=text_content(), height=text_content() },
	});
}

build_ui_panel :: (panel: *Panel) {
	panelBox := box(ui_key("panel1"), .{
		flags=.DRAW_BACKGROUND,
		layout=.{childLayoutAxis = .Y, width=fixed(panel.layoutRect.w), height=fixed(panel.layoutRect.h)},
	});
	push_parent(panelBox); defer pop_parent();

	header := box(ui_key_nil, .{
		flags=.DRAW_BACKGROUND | .DRAW_SIDE_BOTTOM,
		layout=.{ 
			childLayoutAxis = .X,
			width=grow(),
			height=fit(),
			padding= padding_all(em(0.3)),
			childAlignment=.CENTER
		},
		palette=.{ background=style.backgroundLight },
		borderThickness=1.0
	});
	{
		push_parent(header); defer pop_parent();

		// mode
		modeText := "NORMAL";
		if extendSelections && editorMode == .NORMAL {
			modeText = "SELECT";
		}
		else if editorMode == .INSERT {
			modeText = "INSERT";
		}
		box(ui_key(modeText), .{
			flags=.DRAW_BACKGROUND | .DRAW_TEXT,
			layout=.{ width=text_content(), height=text_content() },
			palette=.{ background=style.backgroundDark },
		});

		spacer(.X, fixed(em(0.5)));

		// filename
		fileLabel := box(ui_key(path_filename(panel.document.path)), .{
			flags=.DRAW_TEXT,
			layout=.{ width=text_content(), height=text_content() },
		});
		if signal_from_box(fileLabel).hovering {
			tooltip_begin(fileLabel.key, .{0.0, em(1.9)});
			box(ui_key(panel.document.path), .{
				flags=.DRAW_TEXT,
				layout=.{ width=text_content(), height=text_content() },
			});
			tooltip_end();
		}

		// lock icon @todo: implement for real
		if false {
			box(ui_key(style.iconLock), .{
				flags=.DRAW_TEXT,
				layout=.{ width=text_content(), height=text_content() },
				fontSize=em(0.7),
				font=fontIcons
			});
		}

		// icon for file save status
		if panel.document.unsaved {
			box(ui_key(style.iconCircle), .{
				flags=.DRAW_TEXT,
				layout=.{ width=text_content(), height=text_content() },
				fontSize=em(0.7),
				font=fontIcons
			});
		}

		spacer(.X, grow());

		// pending keys
		pendingKeys := string.{keyMap.pendingKeyString.count, keyMap.pendingKeyString.data};
		box(ui_key(pendingKeys), .{
			flags=.DRAW_TEXT,
			layout=.{ width=text_content(), height=text_content() },
		});

		spacer(.X, fixed(em(2.0)));

		// location
		cursorCoordinate := document_cursor_get_coordinate(*panel.cursor.head);
		box(ui_key("Ln: % Col: % Byte: %", cursorCoordinate.line+1, cursorCoordinate.col, panel.cursor.head.documentOffset), .{
			flags=.DRAW_TEXT,
			layout=.{ width=text_content(), height=text_content() },
		});

		spacer(.X, fixed(em(2.0)));

		// line endings
		lineEndingText := "[Mixed]";
		if panel.document.lineEndings == .LF {
			lineEndingText = "LF";
		}
		else if panel.document.lineEndings == .CRLF {
			lineEndingText = "CRLF";
		}
		else if panel.document.lineEndings == .MIXED_MAJORITY_LF {
			lineEndingText = "[Mixed]";
		}
		box(ui_key(lineEndingText), .{
			flags=.DRAW_TEXT,
			layout=.{ width=text_content(), height=text_content() },
		});

		spacer(.X, fixed(em(2.0)));

		// file type
		box(ui_key("Jai"), .{
			flags=.DRAW_TEXT,
			layout=.{ width=text_content(), height=text_content() },
		});

		spacer(.X, fixed(em(2.0)));

		// panel options button
		panelOptsKey := ui_key("panelopts");
		if is_context_menu_open(panelOptsKey) { 
			button := box(ui_key(style.iconVerticalEllipsis), .{
				flags=.DRAW_BACKGROUND | .DRAW_TEXT | .MOUSE_CLICKABLE,
				layout=.{ width=fixed(em(1.5)), height=text_content() },
				palette=.{background=style.activeHighlight},
				font=fontIcons,
				textAlignment=.CENTER,
				cornerRadius=corner_rad_all(em(0.3))
			});
			if signal_from_box(button).pressed {
				context_menu_close();
			}
		}
		else {
			button := box(ui_key(style.iconVerticalEllipsis), .{
				flags=.DRAW_BACKGROUND | .DRAW_TEXT | .DRAW_HOT_EFFECTS | .MOUSE_CLICKABLE,
				layout=.{ width=fixed(em(1.5)), height=text_content() },
				font=fontIcons,
				textAlignment=.CENTER,
				cornerRadius=corner_rad_all(em(0.3))
			});
			if signal_from_box(button).pressed {
				context_menu_open(panelOptsKey);
			}
		}

		if context_menu_begin(key=panelOptsKey,
								width=fixed(em(12.0)),
								anchorBoxKey=ui_key(style.iconVerticalEllipsis),
								anchorOffset=.{0.0, em(1.9)}) {

			if context_menu_item("Line Numbers", style.iconNumList).pressed {
				lineNumbers = !lineNumbers;
			}
			context_menu_item("View Line Endings", "");
			context_menu_item("Line Wrapping", style.iconAlignLeft);
			context_menu_end();
		}
	}

	build_ui_panel_dialogs(panel);

	// Draw the main code screen
	codeContainer := box(ui_key_nil, .{
		flags=.DRAW_BACKGROUND,
		layout=.{childLayoutAxis = .X, width=grow(), height=grow()},
	});
	{
		push_parent(codeContainer); defer pop_parent();

		codeBox := box(ui_key("code"), .{
			flags=.CLIP_CONTENTS,
			layout=.{width=grow(), height=grow()},
			font=fontCode
		});
		codeBox.customDrawFunction = custom_draw_code;
		codeBox.customDrawUdata = cast(*void) panel;

		numDocumentLines := document_get_num_lines(panel.document);
		metrics := get_font_metrics(codeBox.font, xx codeBox.fontSize);
		codeBox.viewBounds.y = cast(float, -(metrics.lineSpacing * numDocumentLines) + metrics.lineSpacing * 5);
		signal_from_box(codeBox);

		// @todo: find a way to not rely on this codebox rect
		dragDelta := scroll_bar(ui_key("codeScroll"), codeBox.viewOffset.y, codeBox.viewBounds.y, codeBox.rect.h);

		dragRange := (1.0 - max(abs(codeBox.rect.h/(codeBox.viewBounds.y-codeBox.rect.h)), 0.05))*codeBox.rect.h;
		scaleRatio := ifx dragRange != 0.0 then abs(codeBox.viewBounds.y)/dragRange else 1.0;
		codeBox.viewOffset -= dragDelta * scaleRatio;
		codeBox.viewOffset.y = clamp(codeBox.viewOffset.y, codeBox.viewBounds.y, 0);
		codeBox.viewOffset.x = clamp(codeBox.viewOffset.x, codeBox.viewBounds.x, 0);

		codeBox.viewOffsetTarget -= dragDelta * scaleRatio;
		codeBox.viewOffsetTarget.y = clamp(codeBox.viewOffsetTarget.y, codeBox.viewBounds.y, 0);
		codeBox.viewOffsetTarget.x = clamp(codeBox.viewOffsetTarget.x, codeBox.viewBounds.x, 0);

		// move to line visual to keep within visible range
		// This doesn't feel amazing, I'm more inclined to go with a more VSCode style
		// where it snaps you to the cursor, but you can click to move the cursor, but we can't do that yet
		currentLine := document_cursor_get_line(*panel.cursor.head);
		startVisibleLine, range := panel_calculate_visible_lines(panel, true);
		if currentLine < startVisibleLine {
			move_to_line_visual(panel, currentLine, startVisibleLine);
			panel.cursor.anchor = panel.cursor.head;
		}
		else if currentLine > startVisibleLine+range {
			move_to_line_visual(panel, currentLine, startVisibleLine+range);
			panel.cursor.anchor = panel.cursor.head;
		}
	}

	// Draw the search dialog
	if panel.activeDialog == .SEARCH {
		searchContainer := box(ui_key_nil, .{
			flags=.DRAW_BACKGROUND | .DRAW_SIDE_TOP,
			layout=.{ 
				childLayoutAxis = .X,
				width=grow(),
				height=fit(),
				padding= padding_all(em(0.4))
			},
			palette=.{ background=style.backgroundLight },
			borderThickness=1.0
		});
		{
			push_parent(searchContainer); defer pop_parent();

			fontMetrics := get_font_metrics(uiState.defaultFont, xx uiState.defaultFontSize);
			inputBox := box(ui_key("search_input"), .{
				flags=.DRAW_BACKGROUND,
				layout=.{
					width=grow(),
					height=fixed(fontMetrics.lineSpacing+em(0.8)),
				},
				cornerRadius=corner_rad_all(em(0.2)),
				palette=.{ background=style.backgroundLighter },
				font=fontCode,
				textPadding=em(0.5)
			});
			inputBox.customDrawFunction = custom_draw_input_field;
			inputBox.customDrawUdata = cast(*void, *panel.searchInput);

			// @todo: buttons for regex mode, caps, whole word search etc
		}
	}
}

build_ui_panel_dialogs :: (panel: *Panel) {
	if panel.activeDialog == .COMMAND_PICKER {
		commandPickerContainer := box(ui_key_nil, .{
			flags=.DRAW_BACKGROUND,
			layout=.{ 
				childLayoutAxis = .Y,
				width=fixed(panel.layoutRect.w / 2),
				height=fit(),
				padding= padding_all(em(0.4)),
			},
			palette=.{ background=style.backgroundLight },
			cornerRadius=corner_rad_all(em(0.5)),
			fixedX=panel.layoutRect.x+(panel.layoutRect.w-(panel.layoutRect.w/2))/2,
			fixedY=em(3.0)
		});
		{
			push_parent(commandPickerContainer); defer pop_parent();

			fontMetrics := get_font_metrics(uiState.defaultFont, xx uiState.defaultFontSize);
			inputBox := box(ui_key("commandPickerInput"), .{
				flags=.DRAW_BACKGROUND,
				layout=.{
					width=grow(),
					height=fixed(fontMetrics.lineSpacing+em(0.8)),
				},
				cornerRadius=corner_rad_all(em(0.2)),
				palette=.{ background=style.backgroundLighter },
				textPadding=em(0.5)
			});

			inputBox.customDrawFunction = custom_draw_input_field;
			inputBox.customDrawUdata = cast(*void, *panel.commandPicker.input);

			elementHeight := cast(float, fontMetrics.characterHeight*2);
			rangeStart, rangeEnd := scroll_list_begin(ui_key("commandList"),
								panel.layoutRect.h/2,
								elementHeight,
								panel.commandPicker.numToDisplay,
								panel.commandPicker.selectedCommand,
								panel.commandPicker.selectedCommandChange);

			if panel.commandPicker.selectedCommandChange then panel.commandPicker.selectedCommandChange = false;

			for rangeStart..rangeEnd {
				commandEntry := panel.commandPicker.filteredCommandList[it];

				if commandEntry.sortKey == 0 continue;

				// @todo: may be desirable to use the UI focus (hot/active) system for this?
				entryFlags:UIBoxFlags = 0;
				if it == panel.commandPicker.selectedCommand {
					entryFlags |= .DRAW_BACKGROUND;
				}

				entryBox := box(ui_key("commandEntry##%", it), .{
					flags=entryFlags, layout=.{ width=grow(), height=fixed(elementHeight), padding=padding_all(em(0.2)), childAlignment=.CENTER },
					palette=.{ background=style.backgroundLighter },
				});
				{
					push_parent(entryBox); defer pop_parent();

					// find the normal mode mapping
					// @todo: should we show bindings for all modes?
					mappingStr := "";
					for commandEntry.command.mappings {
						if it.mode == .NORMAL then mappingStr = it.keys;
					}

					commandLabel := box(ui_key("%", commandEntry.command.name), .{
						flags=.DRAW_TEXT_HIGHLIGHTS,
						layout=.{ width=text_content(), height=text_content() },
					});
					commandLabel.textHighlights = commandEntry.fuzzyMatches;

					box(ui_key_nil, .{ layout=.{width=grow()}});

					if mappingStr {
						box(ui_key("%", mappingStr), .{
							flags=.DRAW_TEXT | .DRAW_BACKGROUND,
							layout=.{ width=text_content(), height=text_content() },
							palette=.{ background=style.backgroundMid },
							textPadding=em(0.3)
						});
					}
				}
			}

			scroll_list_end(ui_key("commandListScroller")); 

			hintsBox := box(ui_key("hintsBox"), .{
				flags=.DRAW_SIDE_TOP,
				layout=.{ 
					childLayoutAxis = .X,
					width=grow(),
					height=fit(),
				},
				borderThickness=1.0
			});
			{
				push_parent(hintsBox); defer pop_parent();

				spacer(.X, grow());

				textCol := uiState.defaultPalette.text;
				textCol.w = 0.6;
				box(ui_key("<up><down> to navigate <enter> to use <escape> to dismiss"), .{
					flags=.DRAW_TEXT,
					layout=.{ width=text_content(), height=text_content() },
					textAlignment=.CENTER,
					textPadding=em(0.5),
					palette=.{text = textCol}
				});

				spacer(.X, grow());
			}
		}
	}

	if panel.activeDialog == .FILESYSTEM_NAVIGATOR {
		fileNavContainer := box(ui_key_nil, .{
			flags=.DRAW_BACKGROUND,
			layout=.{ 
				childLayoutAxis = .Y,
				width=fixed(panel.layoutRect.w / 2),
				height=fit(),
				padding= padding_all(em(0.4)),
			},
			palette=.{ background=style.backgroundLight },
			cornerRadius=corner_rad_all(em(0.5)),
			fixedX=panel.layoutRect.x+(panel.layoutRect.w-(panel.layoutRect.w/2))/2,
			fixedY=em(3.0)
		});
		{
			push_parent(fileNavContainer); defer pop_parent();

			fontMetrics := get_font_metrics(uiState.defaultFont, xx uiState.defaultFontSize);
			inputBox := box(ui_key_nil, .{
				flags=.DRAW_BACKGROUND,
				layout=.{
					width=grow(),
					height=fixed(fontMetrics.lineSpacing+em(0.8)),
					childLayoutAxis=.X,
					padding=padding_all(em(0.4)),
					childGap=em(0.2)
				},
				cornerRadius=corner_rad_all(em(0.2)),
				palette=.{ background=style.backgroundLighter },
				textPadding=em(0.5)
			});

			// draw existing path sections
			{
				push_parent(inputBox); defer pop_parent();

				for panel.filesystemNav.currentPath {
					pathSectionLabel := box(ui_key("%", it), .{
						flags=.DRAW_TEXT | .DRAW_BACKGROUND,
						layout=.{ width=text_content(), height=text_content() },
					});
				}

				inputArea := box(ui_key("fileNavInput"), .{
					flags=0,
					layout=.{
						width=grow(),
						height=fixed(xx fontMetrics.lineSpacing),
						childLayoutAxis=.X
					},
				});

				inputArea.customDrawFunction = custom_draw_input_field;
				inputArea.customDrawUdata = cast(*void, *panel.filesystemNav.input);
			}

			elementHeight := cast(float, fontMetrics.characterHeight*2);
			rangeStart, rangeEnd := scroll_list_begin(ui_key("fileNav_fileList"),
								panel.layoutRect.h/2,
								elementHeight,
								panel.filesystemNav.numToDisplay,
								panel.filesystemNav.selectedItem,
								panel.filesystemNav.selectedItemChanged);

			if panel.filesystemNav.selectedItemChanged then panel.filesystemNav.selectedItemChanged = false;

			for rangeStart..rangeEnd {
				directoryItem := panel.filesystemNav.itemList[it];
				if directoryItem.sortKey == 0 continue;

				if directoryItem.saveItem == true {
					builder: String_Builder;
					builder.allocator = temp;
					init_string_builder(*builder);

					append(*builder, "Save As - ");
					for panel.filesystemNav.currentPath {
						append(*builder, it);
						if (it_index != panel.filesystemNav.currentPath.count-1)  append(*builder, "/");
					}
					append(*builder, "/");
					append(*builder, input_field_get_text(*panel.filesystemNav.input));

					entryBox := box(ui_key("savefileItem"), .{
						flags=.DRAW_BACKGROUND,
						layout=.{
							width=grow(),
							height=fixed(elementHeight),
							padding=padding_all(em(0.2)),
							childAlignment=.CENTER
						},
						palette=.{ background=style.backgroundLighter },
					});
					{
						push_parent(entryBox); defer pop_parent();
						itemLabel := box(ui_key("%", builder_to_string(*builder,,temp)), .{
							flags=.DRAW_TEXT_HIGHLIGHTS,
							layout=.{ width=text_content(), height=text_content() },
						});
					}
				}
				else {

					// @todo: may be desirable to use the UI focus (hot/active) system for this?
					entryFlags:UIBoxFlags = 0;
					if it == panel.filesystemNav.selectedItem {
						entryFlags |= .DRAW_BACKGROUND;
					}

					entryBox := box(ui_key("directoryItem##%", it), .{
						flags=entryFlags, layout=.{ width=grow(), height=fixed(elementHeight), padding=padding_all(em(0.2)) },
						palette=.{ background=style.backgroundLighter },
					});
					{
						push_parent(entryBox); defer pop_parent();

						box(ui_key("%##%", ifx directoryItem.isDirectory then style.iconFolder else style.iconFile, it), .{
							flags=.DRAW_TEXT,
							layout=.{ width=text_content(), height=text_content() },
							font=fontIcons
						});

						itemLabel := box(ui_key("%##commandEntry%", directoryItem.name, it), .{
							flags=.DRAW_TEXT_HIGHLIGHTS,
							layout=.{ width=text_content(), height=text_content() },
						});
						itemLabel.textHighlights = directoryItem.fuzzyMatches;
					}
				}
			}

			scroll_list_end(ui_key("filesystemNavScroller")); 

			hintsBox := box(ui_key("hintsBox"), .{
				flags=.DRAW_SIDE_TOP,
				layout=.{ 
					childLayoutAxis = .X,
					width=grow(),
					height=fit(),
				},
				borderThickness=1.0
			});
			{
				push_parent(hintsBox); defer pop_parent();

				spacer(.X, grow());

				textCol := uiState.defaultPalette.text;
				textCol.w = 0.6;
				box(ui_key("<up><down> to navigate <enter> to open file/directory <escape> to dismiss"), .{
					flags=.DRAW_TEXT,
					layout=.{ width=text_content(), height=text_content() },
					textAlignment=.CENTER,
					textPadding=em(0.5),
					palette=.{text = textCol}
				});

				spacer(.X, grow());
			}
		}
	}


	
	if panel.activeDialog == .FILE_FINDER {
		fileFinderContainer := box(ui_key_nil, .{
			flags=.DRAW_BACKGROUND,
			layout=.{ 
				childLayoutAxis = .Y,
				width=fixed(panel.layoutRect.w / 2),
				height=fit(),
				padding= padding_all(em(0.4)),
			},
			palette=.{ background=style.backgroundLight },
			cornerRadius=corner_rad_all(em(0.5)),
			fixedX=panel.layoutRect.x+(panel.layoutRect.w-(panel.layoutRect.w/2))/2,
			fixedY=em(3.0)
		});
		{
			push_parent(fileFinderContainer); defer pop_parent();

			fontMetrics := get_font_metrics(uiState.defaultFont, xx uiState.defaultFontSize);
			inputBox := box(ui_key("fileFinderInput"), .{
				flags=.DRAW_BACKGROUND,
				layout=.{
					width=grow(),
					height=fixed(fontMetrics.lineSpacing+em(0.8)),
				},
				cornerRadius=corner_rad_all(em(0.2)),
				palette=.{ background=style.backgroundLighter },
				textPadding=em(0.5)
			});

			inputBox.customDrawFunction = custom_draw_input_field;
			inputBox.customDrawUdata = cast(*void, *panel.fileFinder.input);

			elementHeight := cast(float, fontMetrics.characterHeight*3);
			rangeStart, rangeEnd := scroll_list_begin(ui_key("fileList"),
								panel.layoutRect.h/2,
								elementHeight,
								panel.fileFinder.numToDisplay,
								panel.fileFinder.selectedEntry,
								panel.fileFinder.selectedEntryChanged);

			if panel.fileFinder.selectedEntryChanged then panel.fileFinder.selectedEntryChanged = false;

			for rangeStart..rangeEnd {
				entry := panel.fileFinder.fileList[it];

				if entry.sortKey == 0 continue;

				// @todo: may be desirable to use the UI focus (hot/active) system for this?
				entryFlags:UIBoxFlags = 0;
				if it == panel.fileFinder.selectedEntry {
					entryFlags |= .DRAW_BACKGROUND;
				}

				entryBox := box(ui_key("entry##%", it), .{
					flags=entryFlags, layout=.{
						width=grow(),
						height=fixed(elementHeight),
						padding=padding_all(em(0.2)),
						childLayoutAxis=.Y
					},
					palette=.{ background=style.backgroundLighter },
				});
				{
					push_parent(entryBox); defer pop_parent();

					fileLabel := box(ui_key("%##fileListEntryLabel", path_filename(entry.doc.path)), .{
						flags=.DRAW_TEXT_HIGHLIGHTS,
						layout=.{ width=text_content(), height=text_content() },
					});
					fileLabel.textHighlights = entry.fuzzyMatches;

					pathLabel := box(ui_key("%##fileListPathLabel", entry.doc.path), .{
						flags=.DRAW_TEXT,
						fontSize=em(0.7),
						layout=.{ width=text_content(), height=text_content() },
					});
				}
			}

			scroll_list_end(ui_key("fileFinderScroller")); 

			hintsBox := box(ui_key("hintsBox"), .{
				flags=.DRAW_SIDE_TOP,
				layout=.{ 
					childLayoutAxis = .X,
					width=grow(),
					height=fit(),
				},
				borderThickness=1.0
			});
			{
				push_parent(hintsBox); defer pop_parent();

				spacer(.X, grow());

				textCol := uiState.defaultPalette.text;
				textCol.w = 0.6;
				box(ui_key("<up><down> to navigate <enter> to open file <escape> to dismiss"), .{
					flags=.DRAW_TEXT,
					layout=.{ width=text_content(), height=text_content() },
					textAlignment=.CENTER,
					textPadding=em(0.5),
					palette=.{text = textCol}
				});

				spacer(.X, grow());
			}
		}
	}
}

custom_draw_input_field :: (box: *UIBox, udata: *void) {
	inputField:*InputField = cast(*InputField)udata;

	// draw the input field text
	box.textRun = generate_text_run(string.{inputField.text.count, inputField.text.data}, xx box.fontSize, box.font,,temp);
	metrics := get_font_metrics(box.font, xx box.fontSize);
	yPos := floor(box.rect.y + box.rect.h/2.0) + floor(box.fontSize/2.0) - 1.0;
	xPos := box.rect.x;

	xPos += box.textPadding;
	xPos = floor(xPos);
	draw_text_run(box.textRun, xPos, yPos, box.palette.text);

	// calculate cursor position
	cursorOffsetX := generate_text_run(string.{inputField.cursor, inputField.text.data}, xx box.fontSize, box.font,,temp).width;

	// draw cursor
	cursorHeight:float = metrics.typicalAscender-metrics.typicalDescender + metrics.characterHeight*0.2;
	submit_instance(.{
		dstRect = .{
			xPos + cursorOffsetX,
			yPos-metrics.typicalDescender-cursorHeight,
			2,
			cursorHeight
		},
		color = ifx editorMode == .INSERT then .{1.0, 1.0, 1.0, 1.0} else style.textPrimary,
		shader = .RECTS
	});
}

// @todo: probably want to move this somewhere else?
custom_draw_code :: (box: *UIBox, udata: *void) {
	panel:*Panel = cast(*Panel)udata;

	if panel.document {
		metrics := get_font_metrics(box.font, xx box.fontSize);
		documentLines := document_get_num_lines(panel.document);
		cursorLine := document_cursor_get_line(*panel.cursor.head);

		startVisibleLines : s64;
		endVisibleLines : s64;
		visibleLines: [..]string;
		visibleLines.allocator = temp;

		startVisibleLines = clamp(cast(s64) (-box.viewOffset.y / metrics.lineSpacing) - 1, 0, documentLines - 1);
		endVisibleLines = clamp(startVisibleLines + cast(s64)box.rect.h / metrics.lineSpacing + 2, 0, documentLines - 1);

		startOffset := (startVisibleLines+2) * metrics.lineSpacing - metrics.lineSpacing;

		// Draw line numbers
		gutterWidth := 0;
		if lineNumbers {
			y :float = box.rect.y + startOffset + box.viewOffset.y;
			maxLinesRun := generate_text_run(tprint(" % ", documentLines), xx box.fontSize, box.font,,temp);
			gutterWidth = xx maxLinesRun.width;

			for startVisibleLines..endVisibleLines {
				lineNoRun := generate_text_run(tprint("% ", it+1), xx box.fontSize, box.font,,temp);
				draw_text_run(lineNoRun, box.rect.x + (gutterWidth - lineNoRun.width), y, style.textSecondary);
				y += metrics.lineSpacing;
			}
		}

		textAreaX := box.rect.x + gutterWidth;
		textAreaY := box.rect.y + startOffset + box.viewOffset.y;

		// @todo: refactor to use document cursors to walk through text rather than get_line_content for every line
		linesOnScreen: [..]string;
		linesOnScreen.allocator = temp;
		for startVisibleLines..endVisibleLines {
			array_add(*linesOnScreen, document_get_line_content(panel.document, xx it));
		}

		// Draw cursor selection
		if panel.activeDialog != .SEARCH && cursorLine >= startVisibleLines && cursorLine <= endVisibleLines {
			if panel.cursor.head.documentOffset != panel.cursor.anchor.documentOffset {
				draw_cursor_range(box.font,
									xx box.fontSize,
									textAreaX,
									textAreaY,
									panel.cursor.head,
									panel.cursor.anchor,
									linesOnScreen,
									startVisibleLines,
									true);
			}
		}

		// draw search results
		if panel.activeDialog == .SEARCH {
			for panel.results {
				draw_cursor_range(box.font,
									xx box.fontSize,
									textAreaX,
									textAreaY,
									it.start,
									it.end,
									linesOnScreen,
									startVisibleLines,
									false);
			}
		}

		// Draw the text
		x :float = textAreaX;
		y :float = textAreaY;
		for line: linesOnScreen {
			run := generate_text_run(line, xx box.fontSize, box.font,,temp);
			draw_text_run(run, x, y, style.textPrimary);
			y += metrics.lineSpacing;
		}

		// Draw cursor
		if panel.activeDialog != .SEARCH && cursorLine >= startVisibleLines && cursorLine <= endVisibleLines {
			line := linesOnScreen[cursorLine - startVisibleLines];
			line.count = panel.cursor.head.documentOffset - document_get_line_start(panel.document, cursorLine);

			// figuring out the width of the cursor requires knowing which vertical column of text
			// we're in, including previous tabs
			col:=0;
			for line {
				if it != #char "\t" {
					col += 1;
				} else {
					charsToTabstop := box.font.tabSize - col % box.font.tabSize;
					col += charsToTabstop;
				}
			}
			cursorChar := document_cursor_get_char(*panel.cursor.head);
			cursorRun := generate_text_run(cast(string) u8.[cursorChar], xx box.fontSize, box.font, col,,temp);

			cursorX := textAreaX + generate_text_run(line, xx box.fontSize, box.font,,temp).width;
			cursorY := textAreaY - metrics.typicalDescender + metrics.lineSpacing * (cursorLine-startVisibleLines-1);

			submit_instance(.{
				dstRect = .{
					cursorX,
					cursorY,
					cursorRun.width,
					xx metrics.lineSpacing
				},
				color = ifx editorMode == .INSERT then .{1.0, 1.0, 1.0, 1.0} else style.textPrimary,
				shader = .RECTS
			});

			if cursorChar != 0 {
				draw_text_run(cursorRun, cursorX, textAreaY + metrics.lineSpacing * (cursorLine-startVisibleLines), style.backgroundMid);
			}
		}
	}
}

draw_cursor_range :: (font: *Font, fontSize: int, textAreaX: float, textAreaY: float, cursor1: DocumentCursor, cursor2: DocumentCursor, linesOnScreen: []string, startVisibleLine: s64, includeCursor := false) {
	metrics := get_font_metrics(font, fontSize);
	rangeStart, rangeEnd := convert_cursors_to_coordinate_range(cursor1, cursor2, includeCursor);
	lineWidths: [..] s32;
	lineWidths.allocator = temp;
	endVisibleLine := startVisibleLine + linesOnScreen.count;
	if rangeStart.line < startVisibleLine || rangeEnd.line > endVisibleLine {
		return;
	}
	for rangeStart.line..rangeEnd.line {
		lineIndex := it - startVisibleLine; 
		if 0 > lineIndex || lineIndex >= linesOnScreen.count then continue;

		line := linesOnScreen[it - startVisibleLine];
		lineWidth := generate_text_run(line, fontSize, font,,temp).width;

		isFirstLine:= it == rangeStart.line;
		isLastLine:= it == rangeEnd.line;

		selectionX := 0;
		selectionW := lineWidth;
		if isFirstLine {
			selectionX = xx generate_text_run(string.{rangeStart.col,line.data}, fontSize, font,,temp).width;
			selectionW = lineWidth - selectionX;
		}
		if isLastLine {
			selectionW = generate_text_run(string.{rangeEnd.col,line.data}, fontSize, font,,temp).width - selectionX;
		}

		submit_instance(.{
			dstRect = .{
				cast(float)(textAreaX + selectionX),
				cast(float)(textAreaY - metrics.typicalDescender + metrics.lineSpacing * (it-startVisibleLine-1)),
				cast(float)selectionW,
				cast(float)metrics.lineSpacing
			},
			color = style.textSelection,
			shader = .RECTS
		});
	}
}

do_backup_callback :: () {
	for * open_documents {
		if it.unsaved {
			builder : String_Builder;
			builder.allocator = temp;
			init_string_builder(*builder);

			append(*builder, path_strip_filename(get_path_of_running_executable()));
			append(*builder, "\\backups\\");
			append(*builder, path_filename(it.path));

			document_save(it, builder_to_string(*builder,,temp), true);
		}
	}
}

file_change_callback :: (watcher: *File_Watcher(void), change: *File_Change, userdata: *void) {
	found := array_find(watchedFiles, change.full_path);
	if found {
		success, doc := document_get_by_path(change.full_path);
		if change.events & .MODIFIED {
			modtime, size, success := file_modtime_and_size(doc.path);
			if modtime > doc.diskLastModtime {
				// reload file
				if doc.unsaved == false {
					document_load_from_disk(doc);
					panel_refresh_cursors(*focusedPanel);
				}
				else {
					// @todo: when we have nicer UI this should give a popup or something more explicit
					doc.unsaved = true;
					push_notification("File on disk changed, but you have unsaved edits");
				}
			}
		}
		if change.events & .REMOVED {
			doc.unsaved = true;
		}
	}
}

write_register :: (name: u8, value: string) {
	if name == DEFAULT_REGISTER {
		os_clipboard_set_text(value);
	}

	// we write to the default yank
	registerData := find_or_add(*registers.table, name,,registers.registerAllocator); 
	array_reset_keeping_memory(registerData);

	array_reserve(registerData, value.count,,registers.registerAllocator);
	memcpy(registerData.data, value.data, value.count * size_of(u8));
	registerData.count = value.count;
}

read_register :: (name: u8) -> string {
	if name == DEFAULT_REGISTER {
		return os_clipboard_get_text();
	}
	else {
		registerData := table_find_pointer(*registers.table, name); 
		if registerData {
			return string.{registerData.count, registerData.data};
		}
	}
	return string.{};
}

load_fonts :: () {
	fontUI,_ = load_font("segoeui.ttf");

	// attempt to load my personal font, then fallback to consolas
	// @todo: ideally my font would be in a config file somewhere not in here
	success: bool;
	fontCode,success = load_font("FiraMonoNerdFontMono-Regular.ttf");
	if !success { 
		fontCode,_ = load_font("consola.ttf");
	}

	fontIcons = load_font_from_memory(#run read_entire_file("fonts/Font Awesome 6 Free-Solid-900.otf"));
}

// color stuff
hex_to_color_vec4 :: (src_hex: string) -> Vector4 {
    hex := src_hex;
    if hex.count == 6 then hex = tprint("%FF", hex);
    if hex.count != 8 return Vector4.{};

    r := slice(hex, 0, 2);
    g := slice(hex, 2, 2);
    b := slice(hex, 4, 2);
    a := slice(hex, 6, 2);

    to_float :: (byte_str: string) -> float {
        hex_digit_to_int :: (char: u8) -> int {
            char = to_upper(char);
            if #char "0" <= char && char <= #char "9" return char - #char "0";
            if #char "A" <= char && char <= #char "F" return 10 + char - #char "A";
            return -1;
        }

        d1, d0 := cast(float)hex_digit_to_int(byte_str[0]), cast(float) hex_digit_to_int(byte_str[1]);
        if d1 < 0 || d0 < 0 return -1;

        return (16 * d1 + d0) / 255;
    }

    c := Vector4.{ to_float(r), to_float(g), to_float(b), to_float(a) };

    return c;
}

// utilities 
convert_cursors_to_coordinate_range :: (cursor1: DocumentCursor, cursor2: DocumentCursor, includeCursor: bool = true) -> start: Coordinate, end: Coordinate {
	rangeStart: Coordinate;
	rangeEnd: Coordinate;
	cursorBonus := ifx includeCursor then 1 else 0;

	coordinate1 := document_cursor_get_coordinate(*cursor1);
	coordinate2 := document_cursor_get_coordinate(*cursor2);

	if coordinate1.line < coordinate2.line {
		// coordinate1 is clearly earlier than coordinate2
		rangeStart.line = coordinate1.line;
		rangeStart.col = coordinate1.col;
		rangeEnd.line = coordinate2.line;
		rangeEnd.col = coordinate2.col+cursorBonus;
	}
	else if coordinate1.line > coordinate2.line { 
		// coordinate2 is clearly earlier than the coordinate1
		rangeStart.line = coordinate2.line;
		rangeStart.col = coordinate2.col;
		rangeEnd.line = coordinate1.line;
		rangeEnd.col = coordinate1.col+cursorBonus; // cursor itself is considered part of the selection
	}
	else {
		// they are on the same line, pick based on column
		if coordinate1.col <= coordinate2.col {
			rangeStart.line = coordinate1.line;
			rangeStart.col = coordinate1.col;
			rangeEnd.line = coordinate2.line;
			rangeEnd.col = coordinate2.col+cursorBonus;
		}
		else {
			rangeStart.line = coordinate2.line;
			rangeStart.col = coordinate2.col;
			rangeEnd.line = coordinate1.line;
			rangeEnd.col = coordinate1.col+cursorBonus;
		}
	}
	return rangeStart, rangeEnd;
}

round :: (f: float) -> float {
	diff := f - floor(f);
	if diff >= 0.5{
		return ceil(f);
	}
	else {
		return floor(f);
	}
}

// fuzzy searching
Highlight :: struct {
	start: s32;
	end: s32;
}

fuzzy_search :: (stringToSearch: string, filter: string) -> score: s32, highlights: [..]Highlight {
	MAX_CHARS :: 200;

	highlights: [..]Highlight;

	if filter.count == 0 return 1, highlights;

	// search for the full string first
	{
		i := find_index_from_left_nocase(stringToSearch, filter);
		if i >= 0 {
			// match!
			score := (200 + cast(s32, filter.count)) * (MAX_CHARS - i);
			array_add(*highlights, Highlight.{xx i, cast(s32, i + filter.count)});
			return xx score, highlights; 
		}
	}

	// search for individual (utf8) characters
	score := 0;
	pos := 0;
	str := filter.data;
	while str < filter.data+filter.count {
		// iterate per unicode character, rather than literal scan of bytes
		substr: string = ---;
		substr.data = str;
		str = unicode_next_character(str);
		substr.count = str - substr.data;

		// search 
		i := find_index_from_left_nocase(stringToSearch, substr, pos);
		if i < 0 { score = -1; break; }; 

		// found a match!
		score += 5 * (MAX_CHARS - i); 
		array_add(*highlights, Highlight.{xx i, cast(s32, i + substr.count)});

		// start the next search after this one, so we find ordered highlights of chars
		pos = i + substr.count;
	}
	return xx score, highlights;
}

find_index_from_left_nocase :: (s: string, substring: string, start_index := 0) -> s64 {
    if !substring return -1;

    for i: start_index..s.count-substring.count {
        t := slice(s, i, substring.count);
        if equal_nocase(t, substring) return i;
    }

    return -1;
}

// notifications

// this function will not copy the string
push_notification :: (message: string) {
	if numActiveNotifications < 10 {
		notifications[numActiveNotifications] = Notification.{message, notificationTime}; 
		numActiveNotifications += 1;
	}
	else {
		// we'll delete the oldest element to make space for this one, so no notifications get missed
		memcpy(notifications.data, notifications.data+1, size_of(Notification));
		notifications[9] = Notification.{message, 20}; 
	}
	requestRedraw = true;
}


// unicode stuff
convert_utf32_to_utf8 :: (ch: u32) -> Utf8_Char {
    UNI_MAX_LEGAL_UTF32 :: 0x0010FFFF;
    UNI_REPLACEMENT_CHAR :: 0x0000FFFD;

    count := 0;
    if ch < 0x80                        count = 1;
    else if ch < 0x800                  count = 2;
    else if ch < 0x10000                count = 3;
    else if ch <= UNI_MAX_LEGAL_UTF32   count = 4;
    else {
        count = 3;
        ch = UNI_REPLACEMENT_CHAR;
    }

    byteMask :: 0xBF;
    byteMark :: 0x80;

    bytes: [4] u8 = ---;

    if count == {
        case 4; bytes[3] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 3; bytes[2] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 2; bytes[1] = xx (ch | byteMark) & byteMask; ch = ch >> 6; #through;
        case 1; bytes[0] = xx (ch | firstByteMark[count]);
    }

    result: Utf8_Char = ---;
    result.bytes = bytes;
    result.count = xx count;
    return result;
}

to_string :: (utf8_char: *Utf8_Char) -> string {
    str: string = ---;
    str.data  = *utf8_char.bytes[0];
    str.count = utf8_char.count;
    return str;
}

// simple input field

InputField :: struct {
	text: [..]u8;
	cursor: s32;
	onEditCallback: (*void, string);
	userData: *void;
}

input_field_reset :: (inputField: *InputField) {
	array_reset(*inputField.text);
	inputField.cursor = 0;
}

input_field_reset_keeping_memory :: (inputField: *InputField) {
	inputField.text.count = 0;
	inputField.cursor = 0;
}

input_field_get_text :: (inputField: *InputField) -> string {
	return string.{inputField.text.count, inputField.text.data};
}

Utf8_Char :: struct {
    bytes: [4] u8;
    count: s32;
}

Grammar :: struct {
	name: string;
	url: string;
	revision: string;
}
grammars :: Grammar.[
	.{name="jai", url="https://github.com/constantitus/tree-sitter-jai.git", revision="e15938a94c931662aa3e38cc07dfb98cf7436a90"},
	.{name="cpp", url="https://github.com/tree-sitter/tree-sitter-cpp.git", revision="56455f4245baf4ea4e0881c5169de69d7edd5ae7"},
];

LanguageFunc :: #type () -> *TSLanguage #c_call;
loadedGrammars: Table(string, LanguageFunc);

get_grammar :: (language: string) -> LanguageFunc {
	success, func := table_find_new(*loadedGrammars, language);
	if success {
		return func;
	}

	// @todo: In packaged builds this should be the base directory of the exe
	// @todo: windows specific code here, need to move to platform_windows
	exePath := path_strip_filename(get_path_of_running_executable());
	libPath := tprint("%../../grammars/%.dll", exePath, language);
	grammarLib := LoadLibraryA(libPath.data);

	functionName := tprint("tree_sitter_%", language);
    loadFunc := cast(LanguageFunc, GetProcAddress(grammarLib, temp_c_string(functionName)));
	table_add(*loadedGrammars, language, loadFunc);
	return loadFunc;
}

fetch_grammars :: () {
	// Have a list of grammar repositories
	// Clone them at a certain revision

	verboseOutput := false;

	// @todo: check that git actually exists on this machine
	// @todo: error if not on windows

	for grammars {
		log("Fetching %", it.name);
		directory := tprint("grammars/sources/%", it.name);
		make_directory_if_it_does_not_exist(directory);
		result, output, error := run_command("git", "clone", "--no-checkout", it.url, directory, capture_and_return_output=true);
		if verboseOutput {
			log("%", output);
		}
		if result.exit_code != 0 {
			log_error("Error!");
			log_error("Output:\n%", output);
			log_error("Errors:\n%", error);
		}

		result, output, error = run_command("git", "-C", directory, "checkout", it.revision, capture_and_return_output=true);
		if verboseOutput {
			log("%", output);
		}
		if result.exit_code != 0 {
			log_error("Error!");
			log_error("Output:\n%", output);
			log_error("Errors:\n%", error);
		}
	}
}

build_grammars :: () {
	// set up compile environment
    vcPath, linkerPath := find_visual_studio_in_a_ridiculous_garbage_way();
    compiler := join(linkerPath, "\\", "cl.exe");
    windowsKit := find_windows_kit_root();
    vcIncludePath := join(vcPath, "\\..\\..\\include");
    windowsKitInclude := replace(windowsKit, "Lib", "Include");

	// @todo: error if you can't find visual studio

	verboseOutput := false;
	for grammars {
		log("Compiling %..", it.name);
		directory := tprint("grammars/sources/%", it.name);

	    args: [..] string;
	    array_add(*args, compiler);
	    defer array_free(args);

		array_add(*args, "src\\parser.c");
		if file_exists(tprint("%\\src\\scanner.c", directory)) {
			array_add(*args, "src\\scanner.c");
		}
        array_add(*args,
            "/O2",                      // Maximize speed.
            "/Oi",                      // Enable intrinsics.
            "/Zi",                      // Enable intrinsics.
        );

        array_add(*args,
            tprint("/I%", vcIncludePath),
            tprint("/I%\\um", windowsKitInclude),
            tprint("/I%\\ucrt", windowsKitInclude),
            tprint("/I%\\shared", windowsKitInclude),
        );
		
		array_add(*args, "/link");
		array_add(*args, "/DLL");
		array_add(*args, "/MACHINE:AMD64");
		array_add(*args, tprint("/OUT:%.dll", it.name));
		array_add(*args,
            tprint("/libpath:%", vcPath),
            tprint("/libpath:%\\um\\x64", windowsKit),
            tprint("/libpath:%\\ucrt\\x64", windowsKit),
		);
		
		result, output, error := run_command(..args, capture_and_return_output=true, working_directory=directory);
		if verboseOutput {
			log("%", output);
		}
		if result.exit_code != 0 {
			log_error("Error!");
			log_error("Output:\n%", output);
			log_error("Errors:\n%", error);
			return;
		}
		copy_file(tprint("%/%.dll", directory, it.name), tprint("grammars/%.dll", it.name));
	}
}

Input :: #import "Input";
#import "Window_Creation";
#import "Process";
#import "Basic";
#import "Math";
#import "System";
#import "String";
#import "File";
#import "Hash";
#import "File_Utilities";
#import "Unicode";
#import "Sort";
#import "Flat_Pool";
#import "Hash_Table";
#import "Clipboard";
#import "Command_Line";
#import "File_Watcher";
#import "Bucket_Array";
#import "treesitter";

#load "rect.jai";
#load "command_picker.jai";
#load "filesystem_navigator.jai";
#load "file_finder.jai";
#load "keymap.jai";
#load "document.jai";
#load "commands.jai";
#load "panel.jai";
#load "ui.jai";
#load "renderer.jai";
#load "font.jai";
#load "uniform/module.jai";

#if OS == .WINDOWS {
	#load "platform_windows.jai";
	#import "Windows_Resources";
}


