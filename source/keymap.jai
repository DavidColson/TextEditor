
KeyMappingDesc :: struct {
	mode: EditorMode = .NORMAL;
	keys: string = "";
}

Command :: struct {
	name: string;
	execute: ();
	mappings: []KeyMappingDesc;
}

KeyMap :: struct {
	memory : Flat_Pool;
	allocator: Allocator;
	root: [EDITOR_MODE_NUM]KeyMapNode;
	pendingKeySequence: *KeyMapNode;
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
	.{ "Quit", quit, .[.{mode=.NORMAL, keys="Q"}]},

	// filesystem navigator
	.{ "Open Filesystem Navigator", open_file, .[.{ mode=.NORMAL, keys="ctrl+o"}]},
	.{ "Filesystem Navigator - Path Delete", filesystem_nav_delete_path, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="<backspace>"}] },
	.{ "Filesystem Navigator - Select Next", filesystem_nav_select_next, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="<down>"}] },
	.{ "Filesystem Navigator - Select Previous", filesystem_nav_select_previous, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="<up>"}] },
	.{ "Filesystem Navigator - Action Item", filesystem_nav_action_item, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="<enter>"}] },
	.{ "Filesystem Navigator - Delete Item", filesystem_nav_delete_item, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="d"}] },
	.{ "Filesystem Navigator - Rename/Move Item", filesystem_nav_rename_move_item, .[.{ mode=.FILESYSTEM_NAVIGATOR, keys="r"}] },

	// Command Picker
	.{ "Open Command Picker", command_picker_open, .[.{ mode=.NORMAL, keys=":"}] },
	.{ "Command Picker - Delete Previous Char", command_picker_delete_char, .[.{ mode=.COMMAND_PICKER, keys="<backspace>"}] },
	.{ "Command Picker - Execute Command", command_picker_execute_command, .[.{ mode=.COMMAND_PICKER, keys="<enter>"}] },
	.{ "Command Picker - Select Next", command_picker_select_next, .[.{ mode=.COMMAND_PICKER, keys="<down>"}] },
	.{ "Command Picker - Select Previous", command_picker_select_previous, .[.{ mode=.COMMAND_PICKER, keys="<up>"}] },

	.{ "Enter Normal Mode", enter_normal_mode, .[
		.{ mode=.INSERT, keys="<escape>"},
		.{ mode=.COMMAND_PICKER, keys="<escape>"},
		.{ mode=.FILESYSTEM_NAVIGATOR, keys="<escape>"},
	]},
];

rebuild_key_map :: ()  {
	keyMap.allocator = Allocator.{proc = flat_pool_allocator_proc, data = *keyMap.memory};

	for mode: 0..EDITOR_MODE_NUM-1 {
		keyMap.root[mode].children = New(Table(string, *KeyMapNode),,keyMap.allocator);
	}

	// for loop through the command list
	for * cmd : commandList {
		for mapping : cmd.mappings {
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
	keyMap.pendingKeySequence = *keyMap.root[editorMode];
}

input_handler :: (event: Input.Event) {
	keyString: string;

	if event.type == .TEXT_INPUT {
		char: Utf8_Char = convert_utf32_to_utf8(event.utf32);

		// if there are no pending key sequences allow the current mode to take the text input
		if keyMap.pendingKeySequence == *keyMap.root[editorMode] {
			if editorMode == .COMMAND_PICKER {
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

	nodePtr := table_find_pointer(keyMap.pendingKeySequence.children, keyString);
	if nodePtr {
		node := <<nodePtr;
		if node.cmd {
			// for anyone debugging, here's where the actual magic happens,
			// a command gets called, after we've figured out
			// what command we're supposed to execute
			node.cmd.execute();
			keyMap.pendingKeySequence = *keyMap.root[editorMode];
		}
		else {
			keyMap.pendingKeySequence = node;
		}
	}
}
