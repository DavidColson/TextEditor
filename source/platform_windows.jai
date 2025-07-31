
platform_enumerate_logical_drives :: () -> [] string {
    drives: [..] string;

    drives_buf: [500] u16;
    GetLogicalDriveStringsW(500, drives_buf.data);

    drive_wstr := drives_buf.data;
    for drives_buf {
        if it == 0 { // split on null terminator
            drive, success := wide_to_utf8(drive_wstr,, allocator = temp);
            if !drive || !success break;
            drive.count -= 1;  // cut off separator
            array_add(*drives, drive);
            drive_wstr = *drives_buf[it_index + 1];
        }
    }

    return drives;
}

platform_is_path_directory :: (path: string) -> bool {
    push_allocator(temp);
	attrib := GetFileAttributesW(utf8_to_wide(path));
	if attrib & FILE_ATTRIBUTE_DIRECTORY {
		return true;
	}
	return false;
}

platform_get_dpi_scale :: (window: Window_Type) -> float {
	dpi := cast(float) GetDpiForWindow(window);
	return dpi / 96.0;
}

platform_wait_message :: inline () {
	WaitMessage();
}

BackupTimerCallback :: #type ();
platform_set_backup_timer :: (window: Window_Type, callback: BackupTimerCallback) {
	backupTimerCallback = callback;
	SetTimer(window, 0, 1000*60*5, cast(*void)_windows_timer_callback);
}

platform_swap_buffers :: (window: Window_Type) {
	dc := GetDC(window);
	SwapBuffers(dc);
}

platform_set_border_color :: () {
    using DwmAttribute;
    col : u32 = 0xFFFFFFFF;
    r : u32 = cast(u32)(style.backgroundMid.x * 255.0);
    g : u32 = cast(u32)(style.backgroundMid.y * 255.0);
    b : u32 = cast(u32)(style.backgroundMid.z * 255.0);
    // COLORREF format is 0x00bbggrr
    col = 0x00000000;
    col |= b << 16;
    col |= g << 8;
    col |= r;
    DwmSetWindowAttribute(window, CAPTION_COLOR, *col, size_of(u32));
}
#scope_file 

#run {
    #if OS == .WINDOWS {
        WR :: #import "Windows_Resources";
        // WR.disable_runtime_console();
    }
}

backupTimerCallback: BackupTimerCallback;
_windows_timer_callback :: (hwnd: HWND, message: u32, timerId: u32, dwTime: DWORD) #c_call {
	push_context {
		backupTimerCallback();
	}
}

kernel32 :: #system_library "kernel32";
user32   :: #system_library "user32";
Dwmapi :: #system_library "Dwmapi";
#import "Windows";
#import "Windows_Utf8";
GetLogicalDriveStringsW :: (nBufferLength: DWORD, lpBuffer: *u16) -> DWORD #foreign kernel32;
GetDpiForWindow :: (hWnd: HWND) -> u32 #foreign user32;
WaitMessage :: () -> s32 #foreign user32;
SetTimer  :: (hWnd: HWND, nIDEvent: u64, uElapse: u32, lpTimerFunc: *void) -> s32 #foreign user32;
DwmSetWindowAttribute :: (handle: HANDLE, dwAttribute: DwmAttribute, pvAttributde :*void, cbAttribute :DWORD) -> HRESULT #foreign Dwmapi;

DwmAttribute :: enum u32 {
    NCRENDERING_ENABLED;
    NCRENDERING_POLICY;
    TRANSITIONS_FORCEDISABLED;
    ALLOW_NCPAINT;
    CAPTION_BUTTON_BOUNDS;
    NONCLIENT_RTL_LAYOUT;
    FORCE_ICONIC_REPRESENTATION;
    FLIP3D_POLICY;
    EXTENDED_FRAME_BOUNDS;
    HAS_ICONIC_BITMAP;
    DISALLOW_PEEK;
    EXCLUDED_FROM_PEEK;
    CLOAK;
    CLOAKED;
    FREEZE_REPRESENTATION;
    PASSIVE_UPDATE_MODE;
    USE_HOSTBACKDROPBRUSH;
    USE_IMMERSIVE_DARK_MODE :: 20;
    WINDOW_CORNER_PREFERENCE :: 33;
    BORDER_COLOR;
    CAPTION_COLOR;
    TEXT_COLOR;
    VISIBLE_FRAME_BORDER_THICKNESS;
    SYSTEMBACKDROP_TYPE;
    LAST;
}
