UIBox :: struct {
	flags: UIBoxFlags;

	// siblings
	next: *UIBox;
	prev: *UIBox;
	// chilren
	head: *UIBox;
	tail: *UIBox;
	// parent
	parent: *UIBox;

	// per build information
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
}

UIPalette :: struct {
	background: Vector4;
	borders: Vector4;
}

defaultPalette :: UIPalette.{
	background = #run hex_to_color_vec4("4D4D4D"),
	borders = #run hex_to_color_vec4("EEEEEE")
};


init_ui :: () {
	uiState.alloc = Allocator.{ proc = flat_pool_allocator_proc, data = *uiState.arena };
	uiState.frameAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *uiState.frameArena };

	reset_parameter_stacks();
}


box :: (x: float, y: float, w: float, h: float, flags: UIBoxFlags) -> *UIBox {
	// allocate box
	box := New(UIBox,, uiState.frameAlloc);
	box.rect.x = x;
	box.rect.y = y;
	box.rect.w = w;
	box.rect.h = h;
	box.flags = flags;
	box.palette = top_palette();
	box.parent = top_parent();

	// insert into parent's list of children
	if box.parent {
		linked_list_insert(*box.parent.head, *box.parent.tail, box.parent.tail, box);
	}

	auto_pop_parameter_stacks();

	return box;
}

begin_ui :: () {
	uiState.rootbox = box(0, 0, xx windowWidth, xx windowHeight, 0); 
	push_parent(uiState.rootbox);
}

end_ui :: () {
	// send draw calls to renderer

	recursionStack: [32]*UIBox;
	recursionLevel := 0;
	push_parent :: (box: *UIBox) #expand { `recursionStack[`recursionLevel] = box; `recursionLevel += 1; }
	pop_parent :: () -> *UIBox #expand { `recursionLevel -= 1; return `recursionStack[`recursionLevel]; }

	start_instance_group();

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

	end_instance_group();

	reset_parameter_stacks();
	reset(*uiState.frameArena, overwrite_memory=true);
}

// Helpers

// macro?
em :: (v: float) -> float {
	// @todo: get font size
	fontSize := 15.0;
	return fontSize * v;
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
	.{ "parent", "*UIBox", "null" },
	.{ "palette", "UIPalette", "defaultPalette" },
	.{ "corner_radius", "float", "0" }
];

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
		print_to_builder(*builder, "top_%1 :: () -> %2 { return get_top(*uiState.%1Stack); }\n", it.name, it.type);
		print_to_builder(*builder, "pop_%1 :: () -> %2 { return pop(*uiState.%1Stack); }\n", it.name, it.type);
		print_to_builder(*builder, "push_%1 :: (%1: %2) { push(*uiState.%1Stack, %1); }\n", it.name, it.type);
		print_to_builder(*builder, "set_next_%1 :: (%1: %2) { set_next(*uiState.%1Stack, %1); }\n", it.name, it.type);
	}
	return builder_to_string(*builder);
}

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



// for later
// push_timed :: (s: string) #expand {
//     print("%", s);
//
//     t0 := current_time_consensus();
//
//     `defer {
//         t1 := current_time_consensus();
//         delta := t1 - t0;
//
//         print("Elapsed: %\n", to_float64_seconds(delta));
//     }
// }
