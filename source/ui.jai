UIBox :: struct {
	flags: UIBoxFlags;

	// points to sibling boxes
	next: *UIBox;
	prev: *UIBox;

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
	// @todo: when we have a tree this will be root box
	boxListHead: *UIBox;
	boxListTail: *UIBox;

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

em :: (v: float) -> float {
	// @todo: get font size
	fontSize := 15.0;
	return fontSize * v;
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

	// @todo: eventually will want to make a macro for doing linked list insertions
	// allowing insertion at start or after specified node
	if uiState.boxListHead == null {
		// new linked list
		uiState.boxListHead = box;
		uiState.boxListTail = box;
		box.next = null;
		box.prev = null;
	}
	else {
		// insert at end
		uiState.boxListTail.next = box;
		box.prev = uiState.boxListTail;
		box.next = null;
		uiState.boxListTail = box;
	}

	auto_pop_parameter_stacks();

	return null;
}

draw_ui :: () {
	// send draw calls to renderer
	box := uiState.boxListHead;
	start_instance_group();
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

		box = box.next;
	}
	end_instance_group();

	reset_parameter_stacks();
	reset(*uiState.frameArena, overwrite_memory=true);
}


// Parameter stack functions code generation

PARAMETERS :: Parameter.[
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
