
KeyMappingDesc :: struct {
	mode: EditorMode = .NORMAL;
	keys: string = "";
}

CommandFlags :: enum_flags u8 {
	HIDDEN;
	COMMAND_PICKER_ONLY;
	FILESYSTEM_NAVIGATOR_ONLY;
}

Command :: struct {
	name: string;
	flags: CommandFlags;
	execute: (*Panel);
	mappings: []KeyMappingDesc;
}

KeyMap :: struct {
	memory : Flat_Pool;
	allocator: Allocator;
	root: [EDITOR_MODE_NUM]KeyMapNode;
	pendingKeyNode: *KeyMapNode;
	pendingKeyString: [..]u8;
}

KeyMapNode :: struct {
	children: *Table(string, *KeyMapNode); // null if leaf node
	cmd: *Command;
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

	// motions
	.{ "Move one char left", 0, move_one_char_left, .[
		.{ mode=.NORMAL, keys="h"},
		.{ mode=.INSERT, keys="<left>"},
	]},
	.{ "Move one char right", 0, move_one_char_right, .[
		.{ mode=.NORMAL, keys="l"},
		.{ mode=.INSERT, keys="<right>"},
	]},
	.{ "Move one line down", 0, move_one_line_down, .[
		.{ mode=.NORMAL, keys="j"},
		.{ mode=.INSERT, keys="<down>"},
	]},
	.{ "Move one line up", 0, move_one_line_up, .[
		.{ mode=.NORMAL, keys="k"},
		.{ mode=.INSERT, keys="<up>"}
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
	.{ "Move to next word start", 0, move_word_start, .[
		.{ mode=.NORMAL, keys="w"},
	]},
	.{ "Move to next word end", 0, move_word_end, .[
		.{ mode=.NORMAL, keys="e"},
	]},
	.{ "Move to prev word start", 0, move_prev_word_start, .[
		.{ mode=.NORMAL, keys="b"},
	]},
	.{ "Move to next long word start", 0, move_long_word_start, .[
		.{ mode=.NORMAL, keys="W"},
	]},
	.{ "Move to next long word end", 0, move_long_word_end, .[
		.{ mode=.NORMAL, keys="E"},
	]},
	.{ "Move to next sub word start", 0, move_sub_word_start, .[
		.{ mode=.NORMAL, keys="alt+w"},
	]},
	.{ "Move to next sub word end", 0, move_sub_word_end, .[
		.{ mode=.NORMAL, keys="alt+e"},
	]},

	// misc normal mode
	.{ "Toggle Extend Selections", 0, toggle_extend_selections, .[
		.{ mode=.NORMAL, keys="v"}
	]},

	// changes
	.{ "Delete selection", 0, delete_selection, .[
		.{ mode=.NORMAL, keys="d"},
	]},

	// insert mode stuff
	// @todo, may be able to unify this with some other commands?
	.{ "Delete left char", 0, insert_mode_delete_left_char, .[
		.{ mode=.INSERT, keys="<backspace>"}
	]},
	.{ "Insert line break", 0, insert_mode_line_break, .[
		.{ mode=.INSERT, keys="<enter>"}
	]},


	// filesystem navigator
	.{ "Open Filesystem Navigator", 0, open_file, .[
		.{ mode=.NORMAL, keys="ctrl+o"}
	]},
	.{ "Path Delete", .HIDDEN | .FILESYSTEM_NAVIGATOR_ONLY, filesystem_nav_delete_path, .[
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="<backspace>"}
	]},
	.{ "Select Next", .HIDDEN | .FILESYSTEM_NAVIGATOR_ONLY, filesystem_nav_select_next, .[
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="<down>"}
	]},
	.{ "Select Previous", .HIDDEN | .FILESYSTEM_NAVIGATOR_ONLY, filesystem_nav_select_previous, .[
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="<up>"}
	]},
	.{ "Action Item", .HIDDEN | .FILESYSTEM_NAVIGATOR_ONLY, filesystem_nav_action_item, .[
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="<enter>"}
	]},
	.{ "Delete Item", .HIDDEN | .FILESYSTEM_NAVIGATOR_ONLY, filesystem_nav_delete_item, .[
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="d"}
	]},
	.{ "Rename/Move Item", .HIDDEN | .FILESYSTEM_NAVIGATOR_ONLY, filesystem_nav_rename_move_item, .[
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="r"}
	]},

	// Command Picker
	.{ "Open Command Picker", .HIDDEN, command_picker_open, .[
		.{ mode=.NORMAL, keys=":"}
	]},
	.{ "Delete Previous Char", .HIDDEN | .COMMAND_PICKER_ONLY, command_picker_delete_char, .[
		.{ mode=.COMMAND_PICKER, keys="<backspace>"}
	]},
	.{ "Execute Command", .HIDDEN | .COMMAND_PICKER_ONLY, command_picker_execute_command, .[
		.{ mode=.COMMAND_PICKER, keys="<enter>"}
	]},
	.{ "Select Next", .HIDDEN | .COMMAND_PICKER_ONLY, command_picker_select_next, .[
		.{ mode=.COMMAND_PICKER, keys="<down>"}
	]},
	.{ "Select Previous", .HIDDEN | .COMMAND_PICKER_ONLY, command_picker_select_previous, .[
		.{ mode=.COMMAND_PICKER, keys="<up>"}
	]},


	.{ "Enter Insert Mode", 0, enter_insert_mode, .[
		.{ mode=.NORMAL, keys="i"}
	]},
	.{ "Enter Normal Mode", 0, enter_normal_mode, .[
		.{ mode=.INSERT, keys="<escape>"},
		.{ mode=.COMMAND_PICKER, keys="<escape>"},
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="<escape>"},
	]},

	// misc commands
	.{ "Print piece chain debug", 0, print_piece_chain_debug, .[]},
	.{ "Toggle line endings", 0, toggle_render_line_endings, .[]},
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
				else {
					advance(*keys, 1); // take just the one letter key
				}

				// hashkey should be just what we grabbed from this loop iteration
				hashKey.count = hashKey.count - keys.count;

				// a few possibilities
				// if keys.count == 0, this is a leaf
				// If there's already an entry in the current table, assert
				// No existing entry, add the entry now
				// if keys.count > 0 this is not a leaf
				// If there's no entry, add a new non-leaf entry set this as current table
				// if there's already a non-leaf entry, set as current and loop
				// if there's already a leaf entry, assert

				if keys.count == 0 {
					assert(!table_contains(curNode.children, hashKey), "Mapping already exists");
					newNode := New(KeyMapNode,,keyMap.allocator);
					newNode.cmd = cmd;
					table_add(curNode.children, hashKey, newNode);
				}
				else if keys.count > 0 {
					entry, exists := table_find(curNode.children, hashKey);
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

	if event.type == .TEXT_INPUT {
		char: Utf8_Char = convert_utf32_to_utf8(event.utf32);

		// if there are no pending key sequences allow the current mode to take the text input
		if keyMap.pendingKeyNode == *keyMap.root[editorMode] {
			if editorMode == .INSERT {
				insert_mode_handle_text_input(char);
				return;
			}
			else if editorMode == .COMMAND_PICKER {
				command_picker_handle_text_input(*focusedPanel.commandPicker, char);
				return;
			}
			else if editorMode == .FILESYSTEM_NAVIGATOR {
				filesystem_nav_handle_text_input(*focusedPanel.filesystemNav, char);
				return;
			}
		}

		keyString= to_string(*char);
	}
	else if event.type == .KEYBOARD {
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

	nodePtr := table_find_pointer(keyMap.pendingKeyNode.children, keyString);
	if nodePtr {
		node := <<nodePtr;
		if node.cmd  {
			// for anyone debugging, here's where the actual magic happens,
			// a command gets called, after we've figured out
			// what command we're supposed to execute
			block:= false;
			if editorMode != .COMMAND_PICKER && node.cmd.flags & .COMMAND_PICKER_ONLY block = true;
			if editorMode != .FILESYSTEM_NAVIGATOR && node.cmd.flags & .FILESYSTEM_NAVIGATOR_ONLY block = true;

			if !block node.cmd.execute(*focusedPanel);

			keyMap.pendingKeyNode = *keyMap.root[editorMode];
			array_reset_keeping_memory(*keyMap.pendingKeyString);
		}
		else {
			keyMap.pendingKeyNode = node;
			for keyString {
				array_add(*keyMap.pendingKeyString, it);
			}
		}
	}
}
