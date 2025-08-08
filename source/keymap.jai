
KeyMappingDesc :: struct {
	mode: EditorMode = .NORMAL;
	keys: string = "";
}

CommandFlags :: enum_flags u8 {
	HIDDEN;
	REPEATABLE;
}

Command :: struct {
	name: string;
	flags: CommandFlags;
	execute: (*Panel, []string);
	mappings: []KeyMappingDesc;
}

KeyMap :: struct {
	memory : Flat_Pool;
	allocator: Allocator;
	root: [EDITOR_MODE_NUM]KeyMapNode;
	pendingKeyNode: *KeyMapNode;
	pendingKeyString: [..]u8;
	pendingArgs: [..]string;
	pendingCount: s32;
	textInputCount: u16;
}

KeyMapNode :: struct {
	children: *Table(string, *KeyMapNode); // null if leaf node
	cmd: *Command;
	nArgs: s32;
}

// global keymap
keyMap: KeyMap;

// keymapping syntax
// special keys will be <backspace>, <esc> etc
// modifiers will be ctrl+b, W, alt+g, ctrl+<tab>a
// for shift you can do shift+b or B, but if you use ctrl or alt, then you can't use a capital
// because of how text input works :(
// @todo: consider making certain commands only available in certain modes
// such as command picker and filesystem nav commands. They won't show up in the command picker
// if they can't be selected, filter them out when doing fuzzy filtering
commandList :: Command.[
	.{ "Quit", 0, quit, .[.{mode=.NORMAL, keys="Q"}]},
	.{ "Save File", 0, save_file, .[.{mode=.NORMAL, keys="ctrl+s"}]},
	.{ "Save File As", 0, save_file_as, .[.{mode=.NORMAL, keys="ctrl+shift+s"}]},

	// motions
	.{ "Move one char left", .REPEATABLE, move_one_char_left, .[
		.{ mode=.NORMAL, keys="h"},
		.{ mode=.INSERT, keys="<left>"},
		.{ mode=.NORMAL, keys="<left>"},
	]},
	.{ "Move one char right", .REPEATABLE, move_one_char_right, .[
		.{ mode=.NORMAL, keys="l"},
		.{ mode=.INSERT, keys="<right>"},
		.{ mode=.NORMAL, keys="<right>"},
	]},
	.{ "Move one line down", .REPEATABLE, move_one_line_down, .[
		.{ mode=.NORMAL, keys="j"},
		.{ mode=.INSERT, keys="<down>"},
		.{ mode=.NORMAL, keys="<down>"},
	]},
	.{ "Move one line up", .REPEATABLE, move_one_line_up, .[
		.{ mode=.NORMAL, keys="k"},
		.{ mode=.INSERT, keys="<up>"},
		.{ mode=.NORMAL, keys="<up>"}
	]},
	.{ "Goto document start", 0, goto_document_start, .[
		.{ mode=.NORMAL, keys="gk"},
	]},
	.{ "Goto document end", 0, goto_document_end, .[
		.{ mode=.NORMAL, keys="gj"},
	]},
	.{ "Goto line start", 0, goto_line_start, .[
		.{ mode=.NORMAL, keys="gh"},
	]},
	.{ "Goto line end", 0, goto_line_end, .[
		.{ mode=.NORMAL, keys="gl"},
	]},
	.{ "Move to next word start", .REPEATABLE, move_word_start, .[
		.{ mode=.NORMAL, keys="w"},
	]},
	.{ "Move to next word end", .REPEATABLE, move_word_end, .[
		.{ mode=.NORMAL, keys="e"},
	]},
	.{ "Move to prev word start", .REPEATABLE, move_prev_word_start, .[
		.{ mode=.NORMAL, keys="b"},
	]},
	.{ "Move to next long word start", .REPEATABLE, move_long_word_start, .[
		.{ mode=.NORMAL, keys="W"},
	]},
	.{ "Move to next long word end", .REPEATABLE, move_long_word_end, .[
		.{ mode=.NORMAL, keys="E"},
	]},
	.{ "Move to next sub word start", .REPEATABLE, move_sub_word_start, .[
		.{ mode=.NORMAL, keys="alt+w"},
	]},
	.{ "Move to next sub word end", .REPEATABLE, move_sub_word_end, .[
		.{ mode=.NORMAL, keys="alt+e"},
	]},
	.{ "Jump to first occurence of {char}", .REPEATABLE, jump_to_char, .[
		.{ mode=.NORMAL, keys="f{char}"},
	]},
	.{ "Jump to last occurence of {char}", .REPEATABLE, jump_to_last_char, .[
		.{ mode=.NORMAL, keys="F{char}"},
	]},
	.{ "Jump to just before first occurence of {char}", .REPEATABLE, jump_to_before_char, .[
		.{ mode=.NORMAL, keys="t{char}"},
	]},
	.{ "Jump to just before last occurence of {char}", .REPEATABLE, jump_to_before_last_char, .[
		.{ mode=.NORMAL, keys="T{char}"},
	]},
	.{ "Expand selection to full lines", .REPEATABLE, expand_selection_to_lines, .[
		.{ mode=.NORMAL, keys="x"},
	]},

	// view commands
	.{ "Page Up", 0, page_up, .[
		.{ mode=.NORMAL, keys="ctrl+b"},
		.{ mode=.NORMAL, keys="<pageup>"},
		.{ mode=.INSERT, keys="<pageup>"},
	]},
	.{ "Page Down", 0, page_down, .[
		.{ mode=.NORMAL, keys="ctrl+f"},
		.{ mode=.NORMAL, keys="<pagedown>"},
		.{ mode=.INSERT, keys="<pagedown>"},
	]},
	.{ "Half Page Up", 0, half_page_up, .[
		.{ mode=.NORMAL, keys="ctrl+u"}
	]},
	.{ "Half Page Down", 0, half_page_down, .[
		.{ mode=.NORMAL, keys="ctrl+d"}
	]},

	// misc normal mode
	.{ "Toggle Extend Selections", 0, toggle_extend_selections, .[
		.{ mode=.NORMAL, keys="v"}
	]},
	.{ "Select register {char}", 0, select_register, .[
		.{ mode=.NORMAL, keys="\"{char}"}
	]},
	.{ "Next search result", 0, next_search_result, .[
		.{ mode=.NORMAL, keys="n"}
	]},
	.{ "Previous search result", 0, previous_search_result, .[
		.{ mode=.NORMAL, keys="N"}
	]},

	// search
	.{ "Search Document", 0, start_document_search, .[
		.{ mode=.NORMAL, keys="/"}
	]},

	// changes
	.{ "Delete selection", 0, delete_selection, .[
		.{ mode=.NORMAL, keys="d"},
	]},
	.{ "Change selection", 0, change_selection, .[
		.{ mode=.NORMAL, keys="c"},
	]},
	.{ "Yank selection", 0, yank_selection, .[
		.{ mode=.NORMAL, keys="y"},
	]},
	.{ "Paste after selection", 0, paste_after_selection, .[
		.{ mode=.NORMAL, keys="p"},
	]},
	.{ "Paste before selection", 0, paste_before_selection, .[
		.{ mode=.NORMAL, keys="P"},
	]},
	.{ "Replace selection with {char}", 0, replace_selection, .[
		.{ mode=.NORMAL, keys="r{char}"},
	]},
	.{ "New line below selection", 0, new_line_below, .[
		.{ mode=.NORMAL, keys="o"},
	]},
	.{ "New line above selection", 0, new_line_above, .[
		.{ mode=.NORMAL, keys="O"},
	]},
	.{ "Undo", 0, undo, .[
		.{ mode=.NORMAL, keys="u"},
	]},
	.{ "Redo", 0, redo, .[
		.{ mode=.NORMAL, keys="U"},
	]},
	.{ "Visualize Undos", 0, visualize_undos, .[]},

	// insert mode stuff
	.{ "Backward Delete Char", .HIDDEN, insert_mode_backward_delete_char, .[
		.{ mode=.INSERT, keys="<backspace>"}
	]},
	.{ "Forward Delete Char", .HIDDEN, insert_mode_forward_delete_char, .[
		.{ mode=.INSERT, keys="<delete>"}
	]},
	.{ "Insert line break", .HIDDEN, insert_mode_line_break, .[
		.{ mode=.INSERT, keys="<enter>"}
	]},
	.{ "Insert tab", .HIDDEN, insert_tab_character, .[
		.{ mode=.INSERT, keys="<tab>"}
	]},

	.{ "Open Filesystem Navigator", 0, open_file, .[
		.{ mode=.NORMAL, keys="<space>o"}
	]},
	.{ "Open Filesystem Navigator At Working Directory", 0, open_file_in_working_dir, .[
		.{ mode=.NORMAL, keys="<space>O"}
	]},
	.{ "Open Command Picker", .HIDDEN, command_picker_open, .[
		.{ mode=.NORMAL, keys=":"}
	]},
	.{ "Open File Finder", 0, file_finder_open, .[
		.{ mode=.NORMAL, keys="<space>f"}
	]},

	// Dialogs
	.{ "Dialog Select Next", .HIDDEN, dialog_select_next, .[
		.{ mode=.DIALOG, keys="<down>"}
	]},
	.{ "Dialog Select Previous", .HIDDEN, dialog_select_previous, .[
		.{ mode=.DIALOG, keys="<up>"}
	]},
	.{ "Dialog Action Item", .HIDDEN, dialog_action_item, .[
		.{ mode=.DIALOG, keys="<enter>"}
	]},
	.{ "Dialog Backward Delete", .HIDDEN, dialog_backward_delete, .[
		.{ mode=.DIALOG, keys="<backspace>"}
	]},

	.{ "Enter Insert Mode Start Of Selection", 0, enter_insert_mode_start, .[
		.{ mode=.NORMAL, keys="i"}
	]},
	.{ "Enter Insert Mode End Of Selection", 0, enter_insert_mode_end, .[
		.{ mode=.NORMAL, keys="a"}
	]},
	.{ "Enter Insert Mode Start Of Line", 0, enter_insert_mode_line_start, .[
		.{ mode=.NORMAL, keys="I"}
	]},
	.{ "Enter Insert Mode End Of Line", 0, enter_insert_mode_line_end, .[
		.{ mode=.NORMAL, keys="A"}
	]},
	.{ "Enter Normal Mode", 0, enter_normal_mode, .[
		.{ mode=.NORMAL, keys="<escape>"},
		.{ mode=.INSERT, keys="<escape>"},
		.{ mode=.DIALOG, keys="<escape>"},
	]},

	// misc commands
	.{ "Print piece chain debug", 0, print_piece_chain_debug, .[]},
	.{ "Toggle draw line endings", 0, toggle_render_line_endings, .[]},

	// @todo: need command arguments to clean this up, second option box pops up to select from a dropdown
	.{ "Normalize Line Endings To LF", 0, normalize_line_endings_lf, .[]},
	.{ "Normalize Line Endings To CRLF", 0, normalize_line_endings_crlf, .[]},
];

rebuild_key_map :: ()  {
	keyMap.allocator = Allocator.{proc = flat_pool_allocator_proc, data = *keyMap.memory};
	keyMap.pendingKeyString.allocator = keyMap.allocator;

	for mode: 0..EDITOR_MODE_NUM-1 {
		keyMap.root[mode].children = New(Table(string, *KeyMapNode),,keyMap.allocator);
	}

	// for loop through the command list
	for * cmd : commandList {
		for mapping : cmd.mappings {
			if mapping.keys == "" continue;

			// Grab the mapping for each command
			// for each key in the mapping (single char, or modified key, or special key)
			keys := mapping.keys;
			curNode := *keyMap.root[mapping.mode]; 
			while keys.count > 0 {
				hashKey:= keys;
				if begins_with(keys, "ctrl+") {
					advance(*keys, 5); 
				}
				if begins_with(keys, "alt+") {
					advance(*keys, 4); 
				}
				if begins_with(keys, "shift+") {
					advance(*keys, 6); 
				}

				if begins_with(keys, "<backspace>") {
					advance(*keys, 11); 
				}
				else if begins_with(keys, "<enter>") {
					advance(*keys, 7); 
				}
				else if begins_with(keys, "<escape>") {
					advance(*keys, 8); 
				}
				else if begins_with(keys, "<left>") {
					advance(*keys, 6); 
				}
				else if begins_with(keys, "<right>") {
					advance(*keys, 7); 
				}
				else if begins_with(keys, "<up>") {
					advance(*keys, 4); 
				}
				else if begins_with(keys, "<down>") {
					advance(*keys, 6); 
				}
				else if begins_with(keys, "<tab>") {
					advance(*keys, 5); 
				}
				else if begins_with(keys, "<delete>") {
					advance(*keys, 8); 
				}
				else if begins_with(keys, "<space>") {
					advance(*keys, 7); 
				}
				else {
					advance(*keys, 1); // take just the one letter key
				}

				nArgs := 0;
				while begins_with(keys, "{char}") {
					advance(*keys, 6); 
					nArgs += 1;
				}

				// hashkey should be just what we grabbed from this loop iteration
				hashKey.count = hashKey.count - (keys.count + nArgs * 6);

				// a few possibilities
				// if keys.count == 0, this is a leaf
					// If there's already an entry in the current table, assert
					// No existing entry, add the entry now
				// if keys.count > 0 this is not a leaf
					// If there's no entry, add a new non-leaf entry set this as current table
					// if there's already a non-leaf entry, set as current and loop
					// if there's already a leaf entry, assert

				if keys.count == 0 { // leaf node
					assert(!table_contains(curNode.children, hashKey), "Mapping already exists");
					newNode := New(KeyMapNode,,keyMap.allocator);
					newNode.cmd = cmd;
					newNode.nArgs = xx nArgs;
					table_add(curNode.children, hashKey, newNode);
				}
				else if keys.count > 0 { // non-leaf node
					assert(nArgs == 0, "Arguments in a key mapping must be at the end of the sequence");
					exists, entry := table_find_new(curNode.children, hashKey);
					if !exists { 
						newNode := New(KeyMapNode,,keyMap.allocator);
						newNode.children = New(Table(string, *KeyMapNode),,keyMap.allocator);
						curNode = <<table_add(curNode.children, hashKey, newNode); 
					}
					else {
						assert(entry.cmd == null, "Start of this key sequence already exists as a direct mapping");
						curNode = entry;
					}
				}
			}
		}
	}
	keyMap.pendingKeyNode = *keyMap.root[editorMode];
}

input_handler :: (event: Input.Event) {
	keyString: string;
	keyStringIsText := false;

	if event.type == .TEXT_INPUT {
		char: Utf8_Char = convert_utf32_to_utf8(event.utf32);

		// if there are no pending key sequences give the text input to a currently focused dialog
		// otherwise normal insert mode can have it
		if keyMap.pendingKeyNode == *keyMap.root[editorMode] {
			if focusedPanel.activeDialog != .NONE {
				dialog_handle_text_input(*focusedPanel, char);
				return;
			}
			else if editorMode == .INSERT {
				insert_mode_handle_text_input(char);
				return;
			}
		}

		keyString= to_string(*char);
		keyStringIsText = true;
	}
	else if event.type == .KEYBOARD {
		keyMap.textInputCount = event.text_input_count;
		builder : String_Builder;
		builder.allocator = temp;
		init_string_builder(*builder);

		// modifiers first
		if event.ctrl_pressed {
			append(*builder, "ctrl+");
		}
		if event.shift_pressed {
			append(*builder, "shift+");
		}
		if event.alt_pressed {
			append(*builder, "alt+");
		}

		gotInput := true;
		if event.key_pressed && event.key_code == .BACKSPACE {
			append(*builder, "<backspace>");
		}
		else if event.key_pressed && event.key_code == .ESCAPE {
			append(*builder, "<escape>");
		}
		else if event.key_pressed && event.key_code == .ARROW_UP {
			append(*builder, "<up>");
		}
		else if event.key_pressed && event.key_code == .ARROW_DOWN {
			append(*builder, "<down>");
		}
		else if event.key_pressed && event.key_code == .ARROW_LEFT {
			append(*builder, "<left>");
		}
		else if event.key_pressed && event.key_code == .ARROW_RIGHT {
			append(*builder, "<right>");
		}
		else if event.key_pressed && event.key_code == .ENTER {
			append(*builder, "<enter>");
		}
		else if event.key_pressed && event.key_code == .TAB {
			append(*builder, "<tab>");
		}
		else if event.key_pressed && event.key_code == .PAGE_UP {
			append(*builder, "<pageup>");
		}
		else if event.key_pressed && event.key_code == .PAGE_DOWN {
			append(*builder, "<pagedown>");
		}
		else if event.key_pressed && event.key_code == .DELETE {
			append(*builder, "<delete>");
		}
		else if event.key_pressed && event.key_code == #char " " {
			append(*builder, "<space>");
		}
		else if event.key_pressed && event.key_code >= 33 && event.key_code <= 96 && event.modifier_flags.packed {
			// Note we only take characters as events here if there are modifiers on, otherwise we let the text
			// input case handle it
			lowered:u8 = to_lower(cast(u8)event.key_code); 
			append(*builder, lowered);
		}
		else {
			gotInput = false;
		}

		if gotInput keyString = builder_to_string(*builder,,temp);
	}

	if keyString.count == 0 return;

	// if a digit is given we take it as a count to repeat a motion
	if keyMap.pendingKeyNode == *keyMap.root[editorMode] && is_digit(keyString[0]) {
		digit, _, _ := string_to_int(keyString);
		keyMap.pendingCount = keyMap.pendingCount * 10 + cast(s32) digit;
		print("pencnt: %", keyMap.pendingCount);
	}

	nodePtr: **KeyMapNode;
	// if we're waiting for args, then potentially add it to pending and don't change the pending keynode
	if keyMap.pendingKeyNode.nArgs > keyMap.pendingArgs.count {
		if keyStringIsText {
			nodePtr = *keyMap.pendingKeyNode;
			array_add(*keyMap.pendingArgs, keyString);
		}
	}
	else {
		nodePtr = table_find_pointer(keyMap.pendingKeyNode.children, keyString);
	}

	if editorMode != .INSERT && nodePtr != null {
		for keyString {
			array_add(*keyMap.pendingKeyString, it);
		}
	}

	if nodePtr {
		node := <<nodePtr;
		if node.cmd && keyMap.pendingArgs.count == node.nArgs {
			if keyMap.pendingCount == 0 then keyMap.pendingCount = 1;
			while keyMap.pendingCount > 0 {
				// for anyone debugging, here's where the actual magic happens,
				// a command gets called, after we've figured out
				// what command we're supposed to execute
				node.cmd.execute(*focusedPanel, keyMap.pendingArgs);

				// register selection has some special behaviour as it's intended to be paired with 
				// one other action
				if node.cmd.execute != select_register {
					registers.selectedRegister = DEFAULT_REGISTER;
				}
				keyMap.pendingCount -= 1;
			}

			keyMap.pendingKeyNode = *keyMap.root[editorMode];
			array_reset_keeping_memory(*keyMap.pendingKeyString);
			array_reset_keeping_memory(*keyMap.pendingArgs);
		}
		else {
			keyMap.pendingKeyNode = node;
		}
	}
	// special handling for canceling a key sequence, not the neatest, but whatever
	else if keyString == "<escape>" {
		keyMap.pendingKeyNode = *keyMap.root[editorMode];
		array_reset_keeping_memory(*keyMap.pendingKeyString);
	}
}
