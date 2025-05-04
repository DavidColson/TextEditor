UIBox :: struct {
	flags: UIBoxFlags;

	// box tree
	// siblings
	next: *UIBox;
	prev: *UIBox;
	// chilren
	head: *UIBox;
	tail: *UIBox;
	// parent
	parent: *UIBox;

	// per frame information
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
}

UIState :: struct {
	arena: Flat_Pool;
	alloc: Allocator;
	frameArena: Flat_Pool;
	frameAlloc: Allocator;

	// Per frame UI data
	rootbox: *UIBox;

	// Generated parameter stacks
	#insert -> string {
		builder: String_Builder;
		init_string_builder(*builder);
		for PARAMETERS {
			print_to_builder(*builder, "%1Stack : ParameterStack(%2);\n", it.name, it.type);
		}
		return builder_to_string(*builder);
	}
}
uiState: UIState;

UIBoxFlags :: enum_flags {
	DRAW_BACKGROUND;
	DRAW_TEXT;
	FLOATING_X;
	FLOATING_Y;
	FIXED_WIDTH;
	FIXED_HEIGHT;
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
	borders: Vector4;
}

defaultPalette :: UIPalette.{
	background = #run hex_to_color_vec4("282c34"),
	borders = #run hex_to_color_vec4("EEEEEE")
};


init_ui :: () {
	uiState.alloc = Allocator.{ proc = flat_pool_allocator_proc, data = *uiState.arena };
	uiState.frameAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *uiState.frameArena };

	reset_parameter_stacks();
}


box :: (flags: UIBoxFlags) -> *UIBox {
	// allocate box
	box := New(UIBox,, uiState.frameAlloc);
	box.flags = flags;
	box.palette = top_palette();
	box.parent = top_parent();
	box.childLayoutAxis = top_child_layout_axis();

	// insert into parent's list of children
	if box.parent {
		linked_list_insert(*box.parent.head, *box.parent.tail, box.parent.tail, box);
		box.parent.childCount += 1;
	}

	if !is_fixed_x_default() {
		box.fixedPosition[UIAxis.X] = top_fixed_x();
		box.flags |= .FLOATING_X;
	}
	if !is_fixed_y_default() {
		box.fixedPosition[UIAxis.Y] = top_fixed_y();
		box.flags |= .FLOATING_Y;
	}

	if !is_fixed_width_default() {
		box.fixedSize[UIAxis.X] = top_fixed_width();
		box.flags |= .FIXED_WIDTH;
	}
	else {
		box.size[UIAxis.X] = top_width();
	}

	if !is_fixed_height_default() {
		box.fixedSize[UIAxis.Y] = top_fixed_height();
		box.flags |= .FIXED_HEIGHT;
	}
	else {
		box.size[UIAxis.Y] = top_height();
	}

	box.textPadding = top_text_padding();
	box.textAlignment = top_text_alignment();
	box.fontSize = top_font_size();
	box.font = top_font();
	auto_pop_parameter_stacks();

	return box;
}

begin_ui :: () {
	set_next_fixed_x(0);
	set_next_fixed_y(0);
	set_next_fixed_width(xx windowWidth);
	set_next_fixed_height(xx windowHeight);
	uiState.rootbox = box(0); 
	push_parent(uiState.rootbox);
}

end_ui :: () {
	// layout all the boxes
	compute_layout(uiState.rootbox, .X);
	compute_layout(uiState.rootbox, .Y);

	// set the root box rect 
	uiState.rootbox.rect.x = uiState.rootbox.fixedPosition[0];
	uiState.rootbox.rect.y = uiState.rootbox.fixedPosition[1];
	uiState.rootbox.rect.w = uiState.rootbox.fixedSize[0];
	uiState.rootbox.rect.h = uiState.rootbox.fixedSize[1];

	// send draw calls to renderer
	recursionStack: [32]*UIBox;
	recursionLevel := 0;
	push_parent :: (box: *UIBox) #expand { `recursionStack[`recursionLevel] = box; `recursionLevel += 1; }
	pop_parent :: () -> *UIBox #expand { `recursionLevel -= 1; return `recursionStack[`recursionLevel]; }

	// @todo: you could wrap this in a depth first for expansion
	box := uiState.rootbox;
	push_parent(box.next);
	while box {

		if box.flags & .DRAW_BACKGROUND {
			submit_instance(.{
				dstRect = box.rect,
				srcRect = .{0.0, 0.0, 1.0, 1.0},
				color = box.palette.background,
				cornerRadii = .{0.0, 0.0, 0.0, 0.0},
				edgeSoftness = 0.0,
				borderThickness = 0.0
			});
		}

		if box.flags & .DRAW_TEXT {
			// find position of text?
			metrics := get_font_metrics(box.font, xx box.fontSize);
			yPos := (box.rect.y + box.rect.h/2.0) + metrics.typicalAscender/2.0 - 1.0;
			xPos := box.rect.x;

			if box.textAlignment == {
				case .LEFT;
					xPos += box.textPadding;
				case .CENTER;
					xPos = Min((box.rect.x + box.rect.w/2.0) - box.textRun.width/2.0, box.rect.w);
				case .RIGHT;
					xPos = Min((box.rect.x + box.rect.w) - box.textRun.width - box.textPadding, box.rect.w);
			}
			draw_text_run(box.textRun, xPos, yPos);
		}

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

	reset_parameter_stacks();
	reset(*uiState.frameArena, overwrite_memory=true);
}

// Size helpers

px :: (value: float, strictness: float) -> UISize #expand { return .{ .PIXELS, value, strictness }; }
em :: (value: float, strictness: float) -> UISize #expand { return .{ .PIXELS, value * top_font_size(), strictness }; }
text_dim :: (padding: float, strictness: float) -> UISize #expand { return .{ .TEXT_CONTENT, padding, strictness }; }
parent_pct :: (value: float, strictness: float) -> UISize #expand { return .{ .PERCENT_OF_PARENT, value, strictness }; }
child_sum :: (strictness: float) -> UISize #expand { return .{ .SUM_OF_CHILDREN, 0.0, strictness }; }


#scope_file

// Layout algorithm

compute_layout :: (root: *UIBox, axis: UIAxis) {
	compute_standalone_sizes(root, axis);
	compute_upward_dependant_sizes(root, axis);
	compute_downward_dependant_sizes(root, axis);
	enforce_layout_constraints(root, axis);
	compute_positions(root, axis);
}

compute_standalone_sizes :: (root: *UIBox, axis: UIAxis) {
	if root.size[axis].kind == {
		case .PIXELS;
			root.fixedSize[axis] = root.size[axis].value;
		case .TEXT_CONTENT;
			padding := root.size[axis].value;
			root.textRun = generate_text_run(root.text, xx root.fontSize, root.font,,temp);
			textSize := 0;
			if axis == .X {
				textSize = root.textRun.width;
			}
			else {
				textSize = root.textRun.height;
			}
			root.fixedSize[axis] = textSize + padding + root.textPadding * 2;
		case;
	}

	// recurse children
	first := root.head;
	while first {
		compute_standalone_sizes(first, axis);
		first = first.next;
	}
}

compute_upward_dependant_sizes :: (root: *UIBox, axis: UIAxis) {
	if root.size[axis].kind == {
		case .PERCENT_OF_PARENT;
			// go up through list of parents searching for a fixed size
			fixedParent: *UIBox;
			box := root.parent;
			while box {
				fixed := UIBoxFlags.FIXED_WIDTH;
				if axis == .Y then fixed = .FIXED_HEIGHT; 

				if box.flags & fixed ||
					box.size[axis].kind == .PIXELS || 
					box.size[axis].kind == .TEXT_CONTENT || 
					box.size[axis].kind == .PERCENT_OF_PARENT { 
					fixedParent = box;
					break;
				}
				box = box.parent;
			}
			root.fixedSize[axis] = fixedParent.fixedSize[axis] * root.size[axis].value;
		case;
	}

	// recurse the children after, since they will depend on the parent
	first := root.head;
	while first {
		compute_upward_dependant_sizes(first, axis);
		first = first.next;
	}
}

compute_downward_dependant_sizes :: (root: *UIBox, axis: UIAxis) {
	// we depend on the children's sizes, so we'll recurse the children first
	first := root.head;
	while first {
		compute_downward_dependant_sizes(first, axis);
		first = first.next;
	}

	if root.size[axis].kind == {
		case .SUM_OF_CHILDREN;
			// Sum over children sizes
			sum := 0.0;
			child := root.head;
			while child {
				floating := UIBoxFlags.FLOATING_X;
				if axis == .Y then floating = .FLOATING_Y; 

				if !(child.flags & floating) {
					if root.childLayoutAxis == axis {
						sum += child.fixedSize[axis];
					}
					else {
						sum = max(sum, child.fixedSize[axis]);
					}
				}
				child = child.next;
			}
			root.fixedSize[axis] = sum;
		case;
	}
}

enforce_layout_constraints :: (root: *UIBox, axis: UIAxis) {
	// Verify the sum of the children do not extend past the size of the parent, and if they do correct some

	// raddbg has an "allowoverflow" flag which skips these checks, might need that at some point?

	// along non layout axis
	if axis != root.childLayoutAxis {
		// simply check if the child size is larger than the parent, and if so, reduce the child size until it's correct
		allowedSize := root.fixedSize[axis];

		child := root.head;
		while child {
			floating := UIBoxFlags.FLOATING_X;
			if axis == .Y then floating = .FLOATING_Y; 

			if !(child.flags & floating) {
				violation := child.fixedSize[axis] - allowedSize;
				maxFixup := child.fixedSize[axis];
				fixup := clamp(violation, 0, maxFixup);
				if fixup > 0 {
					child.fixedSize[axis] -= fixup;
				}
			}
			child = child.next;
		}
	}

	// along layout axis
	if axis == root.childLayoutAxis {
		totalAllowedSize := root.fixedSize[axis];
		totalSize := 0.0;
		totalWeightedSize := 0.0;

		child := root.head;
		while child {
			floating := UIBoxFlags.FLOATING_X;
			if axis == .Y then floating = .FLOATING_Y; 

			if !(child.flags & floating) {
				totalSize += child.fixedSize[axis];
				totalWeightedSize += child.fixedSize[axis] * (1.0-child.size[axis].strictness);
			}
			child = child.next;
		}

		// the children go outside of the parent, need to subtract some amount from each child, 
		// weighted by the strictness of their size policies
		violation := totalSize - totalAllowedSize;
		if violation > 0 {
			childFixupSum := 0.0;
			childFixups := NewArray(root.childCount, float,, uiState.frameAlloc);

			// calculate the possible adjustment for each child based on strictness
			// if strictness is 1, then there is no fixup possible here
			childId := 0;
			child := root.head;
			while child {
				floating := UIBoxFlags.FLOATING_X;
				if axis == .Y then floating = .FLOATING_Y; 

				if !(child.flags & floating) {
					fixupSizeThisChild := child.fixedSize[axis] * (1.0-child.size[axis].strictness);
					fixupSizeThisChild = max(0.0, fixupSizeThisChild);
					childFixups[childId] = fixupSizeThisChild;
					childFixupSum += fixupSizeThisChild;
				}
				childId += 1;
				child = child.next;
			}

			childId = 0;
			child = root.head;
			while child {
				floating := UIBoxFlags.FLOATING_X;
				if axis == .Y then floating = .FLOATING_Y; 

				if !(child.flags & floating) {
					// total weighted size is the size of all the available fixup space
					// so this is what percentage of that needs to be corrected
					fixupPct := violation / totalWeightedSize;
					fixupPct = clamp(fixupPct, 0.0, 1.0);
					child.fixedSize[axis] -= childFixups[childId] * fixupPct;
				}

				childId += 1;
				child = child.next;
			}
		}
	}

	// @todo: raddbg goes back and undoes the fixups for parent percent boxes where the root allows overflow
	// you would do that here if you need that

	// do children now
	child := root.head;
	while child {
		enforce_layout_constraints(child, axis);
		child = child.next;
	}
}

compute_positions :: (root: *UIBox, axis: UIAxis) {
	// set a position value to 0
	layoutPosition := 0.0;

	// loop through the children of this box setting their position
	// along the layout axis, and increasing the position in the layout
	child := root.head;
	while child {
		floating := UIBoxFlags.FLOATING_X;
		if axis == .Y then floating = .FLOATING_Y; 

		if !(child.flags & floating) {
			child.fixedPosition[axis] = layoutPosition;
			if root.childLayoutAxis == axis {
				layoutPosition += child.fixedSize[axis];
			}
		}

		// actually set the final rect
		if axis == .X {
			child.rect.x = child.fixedPosition[axis];
			child.rect.w = child.fixedSize[axis];
		}
		else {
			child.rect.y = child.fixedPosition[axis];
			child.rect.h = child.fixedSize[axis];
		}

		child = child.next;
	}

	// give children a chance to compute positions for their children
	child = root.head;
	while child {
		compute_positions(child, axis);
		child = child.next;
	}
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

// Parameter stack functions code generation

PARAMETERS :: Parameter.[
	.{ "parent", 			"*UIBox", 		"null" },
	.{ "child_layout_axis", "UIAxis", 		"UIAxis.X" },
	.{ "fixed_x", 			"float", 		"0" },
	.{ "fixed_y", 			"float", 		"0" },
	.{ "fixed_width", 		"float", 		"0" },
	.{ "fixed_height", 		"float", 		"0" },
	.{ "width", 			"UISize", 		"px(100.0, 1.0)" },
	.{ "height", 			"UISize", 		"px(100.0, 1.0)" },
	.{ "text_padding", 		"float", 		"5" },
	.{ "text_alignment",	"UITextAlign", 	".LEFT" },
	.{ "font",		 		"*Font", 		"fontUI" },
	.{ "font_size", 		"float", 		"15" },
	.{ "palette", 			"UIPalette", 	"defaultPalette" },
	.{ "corner_radius", 	"float", 		"0" }
];

#scope_export

Parameter :: struct {
	name: string;
	type: string;
	default: string;
}

ParameterStack :: struct ($T: Type) {
	stack: [32]T;
	top: s32 = 0;
	autoPop: bool = false;
}

is_empty :: (stack: *ParameterStack($T)) -> bool { 
	return stack.top == 1; // initial value is the default, so stack is empty if it's just the initial value
}

get_top :: (stack: *ParameterStack($T)) -> T {
	return stack.stack[stack.top-1];
}

push :: (stack: *ParameterStack($T), v: T) {
	stack.stack[stack.top] = v;
	stack.top += 1;
}

pop :: (stack: *ParameterStack($T)) -> T {
	if !is_empty(stack) {
		stack.top -= 1;
		return stack.stack[stack.top];
	}
	return stack.stack[0];
}

set_next :: (stack: *ParameterStack($T), v: T) {
	stack.stack[stack.top] = v;
	stack.top += 1;
	stack.autoPop = true;
}

#insert -> string {
	builder: String_Builder;
	init_string_builder(*builder);

	for PARAMETERS {
		print_to_builder(*builder, "is_%1_default :: () -> bool { return is_empty(*uiState.%1Stack); }\n", it.name, it.type);
		print_to_builder(*builder, "top_%1 :: () -> %2 { return get_top(*uiState.%1Stack); }\n", it.name, it.type);
		print_to_builder(*builder, "pop_%1 :: () -> %2 { return pop(*uiState.%1Stack); }\n", it.name, it.type);
		print_to_builder(*builder, "push_%1 :: (%1: %2) { push(*uiState.%1Stack, %1); }\n", it.name, it.type);
		print_to_builder(*builder, "set_next_%1 :: (%1: %2) { set_next(*uiState.%1Stack, %1); }\n\n", it.name, it.type);
	}
	return builder_to_string(*builder);
}
#scope_file

reset_parameter_stacks :: () {
	#insert -> string {
		builder: String_Builder;
		init_string_builder(*builder);
		for PARAMETERS {
			print_to_builder(*builder, "uiState.%1Stack.stack[0] = %2;uiState.%1Stack.top = 1;uiState.%1Stack.autoPop = false;\n", it.name, it.default);
		}
		return builder_to_string(*builder);
	}
}

auto_pop_parameter_stacks :: () {
	#insert -> string {
		builder: String_Builder;
		init_string_builder(*builder);
		for PARAMETERS {
			print_to_builder(*builder, "if uiState.%1Stack.autoPop { pop(*uiState.%1Stack); uiState.%1Stack.autoPop = false; }\n", it.name);
		}
		return builder_to_string(*builder);
	}
}
