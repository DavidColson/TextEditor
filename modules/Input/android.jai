Android_Pointer_Info :: struct {
    state: Key_Current_State;
    window_position_x: float;
    window_position_y: float;
}

android_generate_mouse_clicks_for_touch_events := true;

// There is no limit in Android api, it seems to be down to the device. I think my phone is limited to 10.
// Almost no reason to even allow more than 2 for this, but there you go!
android_pointers : [10] Android_Pointer_Info;
android_num_pointers := 0;

update_window_events :: () {
    if !initted {
        defer initted = true;

        // Bit of a @Hack. It is common for desktop apps to have window width/height variables set at start up
        // and request a window of that size. On android this doesn't make any sense and we ignore the
        // width/height passed to create_window, but then we need to update the programs variables.
        // Just triggering a window resize event here will make existing apps just work, but maybe it's not
        // so smart!
        assert(context.android_app != null && context.android_app.window != null);
        add_resize_record(context.android_app.window);
    }

    input_per_frame_event_and_flag_update();

    android_process_events();
}

android_process_events :: () {
    while true {
        ident, events: s32;
        source: *Native_App.Android_Poll_Source;
        // Read all pending events. If app is not in focus we block here (timeout == -1) as we don't want to tick
        // till we have a window!
        timeout := ifx android_in_focus  0 else -1;
        ident = ALooper_pollAll(xx timeout, null, *events, cast(**void)*source);
        if ident < 0 break;

        // Process this event.
        assert(source != null, "android_poll_source for identifier % was null. This is no good!", ident);
        source.process(context.android_app, source);

        // Check if we are exiting.
        if context.android_app.destroyRequested {
            log("Destroy requested"); // @Incomplete!
            event: Event;
            event.type = .QUIT;
            array_add(*events_this_frame, event);
            break;
        }
    }
}

set_custom_cursor_handling :: (is_custom: bool) {}

//
// @Incomplete :AndroidLifeCycle
//
// For an android app to be well behaved additional command handling is required. Eg, when an app goes in/out out of
// focus you are required to create/destroy it's egl context, see example at https://github.com/android/ndk-samples/blob/master/native-activity/app/src/main/cpp/main.cpp
//
// It is unclear how much should be handled in this module vs leaving it up to the user's app.
android_handle_command :: (app: *Native_App.Android_App, cmd: s32) {
    command := cast(Native_App.APP_CMD) cmd;
    log("Command received: %", command);

    if #complete command == {
        // The window is being shown, get it ready.
        case .INIT_WINDOW;
            android_in_focus = true;
            w := ANativeWindow_getWidth(app.window);
            h := ANativeWindow_getHeight(app.window);
            log("Window inited. It's size is (%, %).", w, h);

        // The window is being hidden or closed, clean it up.
        case .TERM_WINDOW;
            android_in_focus = false;
            // deinit_window();

        case .GAINED_FOCUS;
            android_in_focus = true;

        case .LOST_FOCUS;
            android_in_focus = false;

        case .CONTENT_RECT_CHANGED;
            log("Content rect is now: %", app.contentRect);

        case .INPUT_CHANGED; #through;
        case .WINDOW_RESIZED; #through;
        case .WINDOW_REDRAW_NEEDED; #through;
        case .CONFIG_CHANGED; #through;
        case .LOW_MEMORY; #through;
        case .START; #through;
        case .RESUME; #through;
        case .SAVE_STATE; #through;
        case .PAUSE; #through;
        case .STOP; #through;
        case .DESTROY;
            log("Command % not currently handled!", command, flags = .WARNING);
    }
}

android_handle_input_event :: (event: *AInputEvent) -> handled: bool {
    handled := false;

    if AInputEvent_getType(event) == .MOTION {
        action_and_pointer_index := cast(AMOTION_EVENT_ACTION) AMotionEvent_getAction(event);
        action        := action_and_pointer_index & AMOTION_EVENT_ACTION.MASK;
        pointer_index := cast(u64) (action_and_pointer_index) >> AMOTION_EVENT_ACTION_POINTER_INDEX_SHIFT;
        pointer_id    := AMotionEvent_getPointerId(event, pointer_index);
        num_pointers  := AMotionEvent_getPointerCount(event);

        primary_x := AMotionEvent_getX(event, pointer_index);
        primary_y := AMotionEvent_getY(event, pointer_index);

        window_height := ANativeWindow_getHeight(context.android_app.window);
        mouse_event_y := window_height - AMotionEvent_getY(event, 0);

        do_mouse := android_generate_mouse_clicks_for_touch_events;
        if do_mouse {
            // If less than zero we weren't touching last frame => delta is zero.
            // Negating y because right now mouse coordinates are right-handed,
            // though I thought we let people adjust that now?
            if last_touch_x >= 0 {
                mouse_delta_x = xx  (primary_x - last_touch_x);
                mouse_delta_y = xx -(primary_y - last_touch_y);
            }
        }
        
        last_touch_x = primary_x;
        last_touch_y = primary_y;

        // The first touch is a down/up. Subsequent touches (while still holding first) will be pointer_up/down
        if action == {
          case .DOWN; #through;
          case .POINTER_DOWN;
            // log_error("Touched by id % at (%, %)", pointer_id, primary_x, primary_y);
            android_pointers[pointer_id].state = .DOWN | .START;
            android_pointers[pointer_id].window_position_x = primary_x;
            android_pointers[pointer_id].window_position_y = primary_y;

            handled = true;

            if do_mouse {
                e := array_add(*events_this_frame);
                e.type = .KEYBOARD;
                e.key_pressed = 1;
                e.key_code = .MOUSE_BUTTON_LEFT;

                input_button_states[Key_Code.MOUSE_BUTTON_LEFT] = .DOWN | .START;
            }

            e := array_add(*events_this_frame);
            e.type        = .TOUCH;
            e.touch_type  = .PRESSED;
            e.touch_index = pointer_id;

            input_button_states[Key_Code.TOUCH] = .DOWN | .START;
            

          case .UP; #through;
          case .POINTER_UP;
            // log_error("Released by id % at (%, %)", pointer_id, primary_x, primary_y);
            android_pointers[pointer_id].state = .END;
            handled = true;

            if do_mouse {
                e := array_add(*events_this_frame);
                e.type = .KEYBOARD;
                e.key_pressed = 0;
                e.key_code = .MOUSE_BUTTON_LEFT;

                input_button_states[Key_Code.MOUSE_BUTTON_LEFT] = .END;

                last_touch_x, last_touch_y = -1.0;
            }
            
            e := array_add(*events_this_frame);
            e.type        = .TOUCH;
            e.touch_type  = .RELEASED;
            e.touch_index = pointer_id;
            
            input_button_states[Key_Code.TOUCH] = .END;
            
          case .MOVE;
            // Move gives us the position of every touching pointer so we have to loop and look at them.
            for 0..num_pointers-1 {
                pointer_id = AMotionEvent_getPointerId(event, it);

                pointer := *android_pointers[pointer_id];
                assert((pointer.state & .DOWN) != 0, "Pointer with id % is received a move event in an unexpected state - %", pointer_id, pointer.state);

                // Android also gives you a history of positions inbetween motion events if you want, I am
                // just using current position.
                // history_size := AMotionEvent_getHistorySize(event);

                pointer.window_position_x = AMotionEvent_getX(event, it);
                pointer.window_position_y = AMotionEvent_getY(event, it);
            }
            
            handled = true;

            e := array_add(*events_this_frame);
            e.type        = .TOUCH;
            e.touch_type  = .MOVED;
            e.touch_index = pointer_id;

          case;
            log("Unhandled motion event of type %", action, flags = .WARNING);
        }
    }

    return handled;
}

android_in_focus: bool;
window_minimized :: false;

#scope_file

// @CopyPasta from Input/windows.jai
add_resize_record :: (window: *ANativeWindow) {
    record: *Window_Resize_Record;
    for * pending_resizes {
        if it.window == window {
            record = it;
            break;
        }
    }

    if !record {
        record = array_add(*pending_resizes);
        this_allocation_is_not_a_leak(pending_resizes.data); // :ScanGlobalData
    }

    width  := ANativeWindow_getWidth(window);
    height := ANativeWindow_getHeight(window);

    record.window = window;
    record.width  = width;
    record.height = height;
}

initted := false;

#import "Android";
Native_App :: #import "Android/Native_App";

last_touch_x, last_touch_y := -1.0;

// @Tmp allows skel anim to do different things for 2 finger touch. Will probably want something more general for
// touch input.
#scope_export
