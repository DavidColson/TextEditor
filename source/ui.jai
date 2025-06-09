UIBox :: struct {
	flags: UIBoxFlags;
	keyStr: string;
	key: UIKey;

	// tree
	next: *UIBox; // siblings
	prev: *UIBox;
	head: *UIBox; // chilren
	tail: *UIBox;
	parent: *UIBox;

	// per frame information (must be cleared in box())
	text: string;
	textRun: TextRun;
	textAlignment: UITextAlign;
	textPadding: float;
	font: *Font;
	fontSize: float;
	childCount: s32;
	childLayoutAxis: UIAxis;
	size: [UIAxis.COUNT]UISize;
	fixedPosition: [UIAxis.COUNT]float; // parent relative
	fixedSize: [UIAxis.COUNT]float;
	rect: Rect;
	palette: UIPalette;
	customDrawFunction: (*UIBox, *void);
	customDrawUdata: *void;
	cornerRadius: Vector4;
	borderThickness: float;

	// persistent data
	firstTouchedFrame: u64;
	lastTouchedFrame: u64;
	viewOffset: Vector2;
	viewOffsetTarget: Vector2;
	viewBounds: Vector2;
	hotTimer: float;
	activeTimer: float;
	dragPrevPos: Vector2;
}

UIState :: struct {
	arena: Flat_Pool;
	alloc: Allocator;
	frameArena: Flat_Pool;
	frameAlloc: Allocator;

	// Per frame UI data
	rootbox: *UIBox;
	tooltip: *UIBox;

	// Persistent UI data
	standardFontSize := 15;
	boxTable: Table(UIKey, *UIBox, given_compare_function=compare_key, given_hash_function=x=>get_hash(x.keyVal));
	freeListHead: *UIBox;
	freeListTail: *UIBox;
	contextMenu: *UIBox; // at some point it may be desirable to have a "popup" stack like imgui?
	activeContextMenu: UIKey;
	nextActiveContextMenu: UIKey;
	hotBoxKey: UIKey;
	activeBoxKey: UIKey;

	frameIndex: u64;

	events: [..]Input.Event;
}
uiState: UIState;

UISignal :: struct {
	hovering: bool;
	pressed: bool;
	released: bool;
	holding: bool;
	dragDelta: Vector2;
}

UIBoxFlags :: enum_flags {
	DRAW_BACKGROUND;
	DRAW_TEXT;
	DRAW_BORDER;
	DRAW_SIDE_BOTTOM;
	DRAW_SIDE_TOP;
	DRAW_SIDE_LEFT;
	DRAW_SIDE_RIGHT;
	DRAW_HOT_EFFECTS;
	DRAW_ACTIVE_EFFECTS;
	MOUSE_CLICKABLE;
	FLOATING_X;
	FLOATING_Y;
	FIXED_WIDTH;
	FIXED_HEIGHT;
	CLIP_CONTENTS;
}

UIAxis :: enum {
	X;
	Y;
	COUNT;
}

UISizeKind :: enum {
	NULL;
	PIXELS;
	TEXT_CONTENT;
	PERCENT_OF_PARENT;
	SUM_OF_CHILDREN;
}

UITextAlign :: enum {
	LEFT;
	CENTER;
	RIGHT;
}

UISize :: struct {
	kind: UISizeKind;
	value: float;
	strictness: float;
}

UIPalette :: struct {
	background: Vector4;
	hot: Vector4;
	active: Vector4;
	text: Vector4;
	border: Vector4;
}

UIKey :: struct {
	keyVal:u64;
	keyStr: string; // debug, @todo remove in release?
}

defaultPalette :: UIPalette.{
	background = #run hex_to_color_vec4("282c34"),
	border = #run hex_to_color_vec4("EEEEEE")
};


init_ui :: () {
	uiState.alloc = Allocator.{ proc = flat_pool_allocator_proc, data = *uiState.arena };
	uiState.frameAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *uiState.frameArena };

	uiState.boxTable.allocator = uiState.alloc;
	init(*uiState.boxTable, 4096);

	uiState.frameIndex = 0;
}

find_box :: (key: UIKey) -> bool, *UIBox {
	box,success := table_find(*uiState.boxTable, key);
	return success, box;
}


box :: (flags: UIBoxFlags, key: UIKey = ui_key_nil) -> *UIBox {
	// attempt to get the box from persistent data using it's key
	box,success := table_find(*uiState.boxTable, key);

	// if it can't be found it's new
	if !success {
		// transient box, we'll allocate in the frame allocator (cleared at the end of the frame)
		if key == ui_key_nil {
			box = New(UIBox,, uiState.frameAlloc);
		}
		else {
			if uiState.freeListTail != null {
				// there is an existing box we can reuse
				box = uiState.freeListTail;
				linked_list_remove(*uiState.freeListHead, *uiState.freeListTail, box);
			}
			else {
				box = New(UIBox,, uiState.alloc);
			}
			table_add(*uiState.boxTable, key, box);
		}
		memset(box, 0, size_of(UIBox));
		box.firstTouchedFrame = uiState.frameIndex;
	}

	// this will save your sanity
	if success {
		assert(box.lastTouchedFrame != uiState.frameIndex, "Encountered a duplicate key this frame, probably a mistake");
	}

	// setup box
	box.next = null;
	box.prev = null;
	box.head = null;
	box.tail = null;
	box.parent = null;
	box.key = key;
	box.flags = flags;
	box.customDrawFunction = null;
	box.lastTouchedFrame = uiState.frameIndex;

	// insert into parent's list of children
	if box.parent {
		linked_list_insert(*box.parent.head, *box.parent.tail, box.parent.tail, box);
		box.parent.childCount += 1;
	}

	return box;
}

signal_from_box :: (box: *UIBox) -> UISignal {
	signal: UISignal;
    x, y, success := get_mouse_pointer_position(window, false);
	box_contains_cursor := contains_point(box.rect, xx x, xx y);

	if  box_contains_cursor {
		signal.hovering = true;
		if box.flags & .MOUSE_CLICKABLE {
			uiState.hotBoxKey = box.key;
		}
	}

	for uiState.events {
		if it.type == {
			case .KEYBOARD;
				// left click press
				if box.flags & .MOUSE_CLICKABLE && it.key_pressed && it.key_code == .MOUSE_BUTTON_LEFT && box_contains_cursor { 
					uiState.activeBoxKey = box.key;
					signal.pressed = true;
					box.dragPrevPos = .{xx x,xx y};
					remove it;
				}
				// left click release inside box
				if box.flags & .MOUSE_CLICKABLE
					&& !it.key_pressed
					&& it.key_code == .MOUSE_BUTTON_LEFT
					&& uiState.activeBoxKey == box.key
					&& box_contains_cursor { 

					signal.released = true;
					uiState.activeBoxKey = ui_key_nil;
					remove it;
				}

				// left click release outside box
				if box.flags & .MOUSE_CLICKABLE
					&& !it.key_pressed
					&& it.key_code == .MOUSE_BUTTON_LEFT
					&& uiState.activeBoxKey == box.key
					&& !box_contains_cursor { 

					uiState.hotBoxKey = ui_key_nil;
					uiState.activeBoxKey = ui_key_nil;
					remove it;
				}

				// clicking somewhere outside of context menu
				if uiState.contextMenu && uiState.activeContextMenu != ui_key_nil && !contains_point(uiState.contextMenu.rect, xx x, xx y) && it.key_pressed {
					context_menu_close();
				}

			case .MOUSE_WHEEL;
                if it.wheel_delta && box_contains_cursor {
					metrics := get_font_metrics(box.font, xx box.fontSize);
					box.viewOffsetTarget.y += (it.wheel_delta/it.typical_wheel_delta)*metrics.lineSpacing*3;
					box.viewOffsetTarget.y = clamp(box.viewOffsetTarget.y, box.viewBounds.y, 0);
					box.viewOffsetTarget.x = clamp(box.viewOffsetTarget.x, box.viewBounds.x, 0);
					remove it;
				}
		}
	}

	// calculate dragging delta if we are the active box
	if box.key == uiState.activeBoxKey {
		xDist := x - box.dragPrevPos.x;
		yDist := y - box.dragPrevPos.y;
		signal.dragDelta = .{xDist, yDist};
		box.dragPrevPos = .{xx x,xx y};
	}

	return signal;
}

begin_ui :: () {
	// set_next_fixed_x(0);
	// set_next_fixed_y(0);
	// set_next_fixed_width(xx windowWidth);
	// set_next_fixed_height(xx windowHeight);
	uiState.rootbox = box(0); 
	uiState.hotBoxKey = ui_key_nil;
	uiState.tooltip = null;
	// push_parent(uiState.rootbox);
}

end_ui :: () {
	// yeet any unused boxes
	for uiState.boxTable {
		if it.lastTouchedFrame < uiState.frameIndex || it.key == ui_key_nil {
			table_remove(*uiState.boxTable, it.key);
			linked_list_insert(*uiState.freeListHead, *uiState.freeListTail, uiState.freeListTail, it);
		}
	}

	// layout all the boxes
	compute_layout(uiState.rootbox, .X);
	compute_layout(uiState.rootbox, .Y);

	// set the root box rect 
	uiState.rootbox.rect.x = uiState.rootbox.fixedPosition[0];
	uiState.rootbox.rect.y = uiState.rootbox.fixedPosition[1];
	uiState.rootbox.rect.w = uiState.rootbox.fixedSize[0];
	uiState.rootbox.rect.h = uiState.rootbox.fixedSize[1];

	// adjust position of floating popups to be within bounds (i.e. context menu/tooltips)
	floatingRoots := *UIBox.[uiState.tooltip, uiState.contextMenu];
	for floatingRoots {
		if it != null {
			// @todo: replace standard font size here with an em calculation macro
			xBounds := uiState.rootbox.rect.w - uiState.standardFontSize*0.3; // padding
			yBounds := uiState.rootbox.rect.h - uiState.standardFontSize*0.3; // padding
			xShiftDown := max(it.rect.x, 0) - it.rect.x;
			xShiftUp := min(it.rect.x+it.rect.w, xBounds) - (it.rect.x+it.rect.w);
			it.rect.x += xShiftDown + xShiftUp;
			yShiftDown := max(it.rect.x, 0) - it.rect.x;
			yShiftUp := min(it.rect.y+it.rect.h, yBounds) - (it.rect.y+it.rect.h);
			it.rect.y += yShiftDown + yShiftUp;

			compute_layout(it, .X);
			compute_layout(it, .Y);
		}
	}

	// do animations
	for :depth_first uiState.rootbox {
		box := it;

		// scroll animations
		box.viewOffset.x += cast(float) deltaTime * style.scrollAnimRate * (box.viewOffsetTarget.x - box.viewOffset.x);
		box.viewOffset.y += cast(float) deltaTime * style.scrollAnimRate * (box.viewOffsetTarget.y - box.viewOffset.y);
		if abs(box.viewOffset.x - box.viewOffsetTarget.x) < 0.001 then box.viewOffset.x = box.viewOffsetTarget.x;
		if abs(box.viewOffset.y - box.viewOffsetTarget.y) < 0.001 then box.viewOffset.y = box.viewOffsetTarget.y;

		// figure out if we need redraws because there are animations playing
		if abs(box.viewOffset.x - box.viewOffsetTarget.x) > 0.0 then requestRedraw = true;
		if abs(box.viewOffset.y - box.viewOffsetTarget.y) > 0.0 then requestRedraw = true;
	}

	render_ui_recursive(uiState.rootbox);

	if uiState.activeContextMenu != ui_key_nil && uiState.nextActiveContextMenu == ui_key_nil {
		uiState.contextMenu = null;
		uiState.activeContextMenu = ui_key_nil;
	}
	else if uiState.activeContextMenu == ui_key_nil && uiState.nextActiveContextMenu != ui_key_nil {
		uiState.activeContextMenu = uiState.nextActiveContextMenu;
	}

	reset(*uiState.frameArena, overwrite_memory=true);
	array_reset_keeping_memory(*uiState.events);
	uiState.frameIndex += 1;
}

// depth first UI tree iterator

depth_first :: (box: *UIBox, body: Code, flags: For_Flags) #expand {
	recursionStack: [32]*UIBox;
	recursionLevel := 0;
	push_parent :: (box: *UIBox) #expand { `recursionStack[`recursionLevel] = box; `recursionLevel += 1; }
	pop_parent :: () -> *UIBox #expand { `recursionLevel -= 1; return `recursionStack[`recursionLevel]; }

	counter := 0;
	push_parent(box.next);
	while box {
		`it_index := counter; defer counter += 1;
		`it := box;

		#insert body;

		// get next box
		if box.head {
			// this box has children, so traverse them
			push_parent(box.next);
			box = box.head;
		}
		else {
			box = box.next;
			if box == null && recursionLevel > 0 {
				// go up a recursion level
				box = pop_parent();
			}
		}
	}
}

// keying

ui_key_nil :: UIKey.{0,""};

ui_key :: (str: string) -> UIKey {
	if str.count == 0 then return ui_key_nil; 
	return .{fnv1a_hash(str.data, str.count), str};
}

ui_key :: (formatStr: string, args: ..Any) -> UIKey {
	keyString := tprint(formatStr, ..args);
	return ui_key(keyString);
}

operator== :: (key1: UIKey, key2: UIKey) -> bool {
	return key1.keyVal == key2.keyVal;
}
compare_key :: (key1: UIKey, key2: UIKey) -> bool {
	return key1.keyVal == key2.keyVal;
}

display_string_from_key :: (str: string) -> string {
    index := find_index_from_left(str, "##");
	if index < 0
		return str;
	return slice(str, 0, index);
}

// Basic widgets

label :: (text: string) -> UISignal, *UIBox {
	label := box(.DRAW_TEXT, ui_key(text));
	return signal_from_box(label), label;
}

label :: (textFormat: string, args: ..Any) -> UISignal, *UIBox {
	label := box(.DRAW_TEXT, ui_key(textFormat, ..args));
	return signal_from_box(label), label;
}

button :: (text: string) -> UISignal {
	button := box(.DRAW_BACKGROUND | .DRAW_TEXT | .DRAW_HOT_EFFECTS | .DRAW_ACTIVE_EFFECTS | .MOUSE_CLICKABLE, ui_key(text));
	return signal_from_box(button);
}

tooltip_begin :: (anchorBoxKey:UIKey = ui_key_nil, anchorOffset: Vector2 = .{0.0,0.0}) {
	// push_parent(uiState.rootbox);
	//
	// anchor,success := table_find(*uiState.boxTable, anchorBoxKey);
	// if success {
	// 	set_next_fixed_x(xx (anchor.rect.x + anchorOffset.x));
	// 	set_next_fixed_y(xx (anchor.rect.y + anchorOffset.y));
	// }
	// else {
	// 	x, y, success := get_mouse_pointer_position(window, false);
	// 	set_next_fixed_x(xx (x + 20));
	// 	set_next_fixed_y(xx (y + 20));
	// }
	//
	// set_next_width(child_sum(1.0));
	// set_next_height(child_sum(1.0));
	// set_next_child_layout_axis(.Y);
	// cornerRad := top_font_size()*0.4;
	// set_next_corner_radius(.{cornerRad, cornerRad, cornerRad, cornerRad});
	// uiState.tooltip = box(.DRAW_BACKGROUND | .DRAW_BORDER, "tooltip");
	// push_parent(uiState.tooltip);
	// spacer(em(0.5, 1.0));
	//
	// set_next_width(child_sum(1.0));
	// set_next_height(child_sum(1.0));
	// row_begin();
	// spacer(em(0.5, 1.0));
}

tooltip_end :: () {
	// spacer(em(0.5, 1.0));
	// row_end();
	// spacer(em(0.5, 1.0));
	// pop_parent(); // tooltip box
	// pop_parent(); // rootbox parent
}

is_context_menu_open :: (key: UIKey) -> bool {
	return uiState.activeContextMenu == key;
}

context_menu_open :: (key: UIKey) {
	uiState.nextActiveContextMenu = key;
}

context_menu_close :: () {
	uiState.nextActiveContextMenu = ui_key_nil;
}

context_menu_begin :: (key: UIKey, anchorBoxKey:UIKey = .{0,""}, anchorOffset: Vector2 = .{0.0,0.0}) -> bool {
	// if uiState.activeContextMenu == key {
	// 	push_parent(uiState.rootbox);
	// 	anchor,success := table_find(*uiState.boxTable, anchorBoxKey);
	// 	if success {
	// 		set_next_fixed_x(xx (anchor.rect.x + anchorOffset.x));
	// 		set_next_fixed_y(xx (anchor.rect.y + anchorOffset.y));
	// 	}
	// 	else {
	// 		x, y, success := get_mouse_pointer_position(window, false);
	// 		set_next_fixed_x(xx (x + 20));
	// 		set_next_fixed_y(xx (y + 20));
	// 	}
	// 	set_next_width(child_sum(1.0));
	// 	set_next_height(child_sum(1.0));
	// 	set_next_child_layout_axis(.Y);
	// 	cornerRad := top_font_size()*0.4;
	// 	set_next_corner_radius(.{cornerRad, cornerRad, cornerRad, cornerRad});
	// 	uiState.contextMenu = box(.DRAW_BACKGROUND | .DRAW_BORDER, "context");
	// 	push_parent(uiState.contextMenu);
	// 	spacer(em(0.5, 1.0));
	//
	// 	set_next_width(child_sum(1.0));
	// 	set_next_height(child_sum(1.0));
	// 	row_begin();
	// 	spacer(em(0.5, 1.0));
	// 	return true;
	// }
	return false;
}

context_menu_end :: () {
	// spacer(em(0.5, 1.0));
	// row_end();
	// spacer(em(0.5, 1.0));
	// pop_parent(); // context menu box
	// pop_parent(); // rootbox parent
}

row_begin :: (key := "") {
	// set_next_child_layout_axis(.X);
	// row := box(0, key);
	// push_parent(row);
}

row_end :: () -> UISignal {
	// box := pop_parent();
	// return signal_from_box(box);
	return .{};
}

column_begin :: (key := "") {
	// set_next_child_layout_axis(.Y);
	// col := box(0, key);
	// push_parent(col);
}

column_end :: () -> UISignal {
	// box := pop_parent();
	// return signal_from_box(box);
	return .{};
}

spacer :: (size: UISize) {
	// if top_parent().childLayoutAxis == .X {
	// 	set_next_width(size);
	// 	box(0); 
	// }
	// else {
	// 	set_next_height(size);
	// 	box(0); 
	// }
}

// scope_padding :: (size: UISize) #expand { spacer(size); `defer spacer(size); }

scroll_bar :: (scrollOffset: float, scrollRegionSize:float, visibleRange: float) -> Vector2 {
	// scope_height(parent_pct(1.0, 0.0));
	// scope_width(parent_pct(1.0, 0.0));
	//
	// // padding
	// surroundPadding := em(0.3, 1.0); 
	// set_next_width(em(1.2, 0.0));
	// column_begin(); defer column_end();
	// spacer(surroundPadding); defer spacer(surroundPadding);
	// set_next_height(px(visibleRange-top_font_size()*0.6, 0.0));
	// row_begin(); defer row_end();
	// spacer(surroundPadding); defer spacer(surroundPadding);
	// 
	// // background bar
	// palette := top_palette();
	// palette.background = style.backgroundLight;
	// set_next_palette(palette);
	// cornerRad := top_font_size()*0.3;
	// set_next_corner_radius(.{cornerRad, cornerRad, cornerRad, cornerRad});
	// set_next_child_layout_axis(.Y);
	// scrollbarOuter := box(.DRAW_BACKGROUND, "scrollback");
	//
	// handleSizePct := max(abs(visibleRange/scrollRegionSize), 0.05);
	// spaceBeforePct := (1.0-handleSizePct) * abs(scrollOffset/scrollRegionSize);
	//
	// // space before handle
	// set_next_parent(scrollbarOuter);
	// set_next_height(parent_pct(spaceBeforePct, 1.0));
	// box(0);
	//
	// // scroll handle
	// set_next_parent(scrollbarOuter);
	// palette.background = style.backgroundLighter;
	// set_next_palette(palette);
	// set_next_height(parent_pct(handleSizePct, 1.0));
	// set_next_corner_radius(.{cornerRad, cornerRad, cornerRad, cornerRad});
	// scrollbarInner := box(.DRAW_BACKGROUND | .MOUSE_CLICKABLE | .DRAW_HOT_EFFECTS | .DRAW_ACTIVE_EFFECTS, "todokey");
	//
	// return signal_from_box(scrollbarInner).dragDelta;
	return .{0.0, 0.0};
}

// @todo: widgets:
// [ ] - context menu item
// [ ] - Table stuff
// [ ] - Text input box
// [ ] - Checkbox
// [ ] - 

// Size helpers

px :: (value: float, strictness: float) -> UISize #expand { return .{ .PIXELS, value, strictness }; }
em :: (value: float, strictness: float) -> UISize #expand { return .{ .PIXELS, value * top_font_size(), strictness }; }
text_dim :: (padding: float, strictness: float) -> UISize #expand { return .{ .TEXT_CONTENT, padding, strictness }; }
parent_pct :: (value: float, strictness: float) -> UISize #expand { return .{ .PERCENT_OF_PARENT, value, strictness }; }
child_sum :: (strictness: float) -> UISize #expand { return .{ .SUM_OF_CHILDREN, 0.0, strictness }; }


#scope_file

// rendering the tree

render_ui_recursive :: (box: *UIBox) {
	if box.flags & .DRAW_BACKGROUND {
		color := box.palette.background;

		if box.flags & .DRAW_HOT_EFFECTS && uiState.hotBoxKey != ui_key_nil && box.key == uiState.hotBoxKey {
			color = box.palette.hot;
		}
		if box.flags & .DRAW_ACTIVE_EFFECTS && uiState.activeBoxKey != ui_key_nil && box.key == uiState.activeBoxKey {
			color = box.palette.active;
		}

		submit_instance(.{
			dstRect = box.rect,
			color = color,
			cornerRadii = box.cornerRadius,
		});
	}

	if box.flags & .CLIP_CONTENTS {
		set_scissor(box.rect);
	}

	if box.flags & .DRAW_TEXT {
		// find position of text?
		box.textRun = generate_text_run(box.text, xx box.fontSize, box.font,,temp);
		metrics := get_font_metrics(box.font, xx box.fontSize);
		yPos := floor(box.rect.y + box.rect.h/2.0) + floor(box.fontSize/2.0) - 1.0;
		xPos := box.rect.x;

		if box.textAlignment == {
			case .LEFT;
				xPos += box.textPadding;
			case .CENTER;
				xPos = box.rect.x + Min((box.rect.w/2.0) - box.textRun.width/2.0, box.rect.w);
			case .RIGHT;
				xPos = box.rect.x + Min(box.rect.w - box.textRun.width - box.textPadding, box.rect.w);
		}
		xPos = floor(xPos);
		draw_text_run(box.textRun, xPos, yPos, box.palette.text);
	}

	if box.customDrawFunction {
		box.customDrawFunction(box, box.customDrawUdata);
	}

	// draw children
	child := box.head;
	while child {
		render_ui_recursive(child);
		child = child.next;
	}

	if box.flags & .CLIP_CONTENTS {
		clear_scissor();
	}

	if box.flags & .DRAW_BORDER {
		submit_instance(.{
			dstRect = box.rect,
			color = box.palette.border,
			cornerRadii = box.cornerRadius,
			borderThickness = box.borderThickness
		});
	}

	if box.flags & .DRAW_SIDE_TOP {
		submit_instance(.{
			dstRect = .{box.rect.x, box.rect.y - floor(box.borderThickness/2), box.rect.w, box.borderThickness},
			color = box.palette.border,
		});
	}
	if box.flags & .DRAW_SIDE_BOTTOM {
		submit_instance(.{
			dstRect = .{box.rect.x, box.rect.y + box.rect.h - floor(box.borderThickness/2), box.rect.w, box.borderThickness},
			color = box.palette.border,
		});
	}
	if box.flags & .DRAW_SIDE_LEFT {
		submit_instance(.{
			dstRect = .{box.rect.x - floor(box.borderThickness/2), box.rect.y, box.borderThickness, box.rect.h},
			color = box.palette.border,
		});
	}
	if box.flags & .DRAW_SIDE_RIGHT {
		submit_instance(.{
			dstRect = .{box.rect.x + box.rect.w - floor(box.borderThickness/2), box.rect.y, box.borderThickness, box.rect.h},
			color = box.palette.border,
		});
	}
}

// Layout algorithm

compute_layout :: (root: *UIBox, axis: UIAxis) {	
	// @TODO: layout elements
}

// Linked list functions

linked_list_insert :: (head: **$T, tail: **T, insertAfter: *T, toInsert: *T) {
	if <<head == null {
		// empty linked list
		<<head = toInsert;
		<<tail = toInsert;
		toInsert.next = null;
		toInsert.prev = null;
	}
	else if insertAfter == null {
		// insert at front
		toInsert.next = <<head;
		(<<head).prev = toInsert;
		<<head = toInsert;
		toInsert.prev = null;
	}
	else if insertAfter == <<tail {
		// insert at end
		(<<tail).next = toInsert;
		toInsert.prev = <<tail;
		toInsert.next = null;
		(<<tail) = toInsert;
	}
	else {
		// insert in middle
		toInsert.next = insertAfter.next;
		toInsert.prev = insertAfter;
		if insertAfter.next != null {
			insertAfter.next.prev = toInsert;
		}
		insertAfter.next = toInsert;
	}
}

linked_list_remove :: (head: **$T, tail: **T, toRemove: *T) {
	if toRemove.prev != null {
		toRemove.prev.next = toRemove.next;
	}
	else {
		<<head = toRemove.next; // toRemove was first
	}

	if toRemove.next != null {
		toRemove.next.prev = toRemove.prev;
	}
	else {
		<<tail = toRemove.prev; // toRemove was last
	}
}
