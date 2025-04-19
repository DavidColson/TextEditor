UIBox :: struct {
	rect: Rect;

	// points to sibling boxes
	next: *UIBox;
	prev: *UIBox;
}

UIState :: struct {
	arena: Flat_Pool;
	alloc: Allocator;
	frameArena: Flat_Pool;
	frameAlloc: Allocator;

	// per frame UI data
	boxListHead: *UIBox;
	boxListTail: *UIBox;

	// draw lists for renderer
}
uiState: UIState;

ui_init :: () {
	uiState.alloc = Allocator.{ proc = flat_pool_allocator_proc, data = *uiState.arena };
	uiState.frameAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *uiState.frameArena };
}

em :: (v: float) -> float {
	// @todo: get font size
	fontSize := 15.0;
	return fontSize * v;
}

ui_box :: (x: float, y: float, w: float, h: float) -> *UIBox {
	// allocate box
	box := New(UIBox,, uiState.frameAlloc);
	box.rect.x = x;
	box.rect.y = y;
	box.rect.w = w;
	box.rect.h = h;

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

	return null;
}

draw_ui :: () {
	// traverse boxlist generating draws for each
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
