
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
#import "Windows";
#import "Windows_Utf8";
GetLogicalDriveStringsW :: (nBufferLength: DWORD, lpBuffer: *u16) -> DWORD #foreign kernel32;
GetDpiForWindow :: (hWnd: HWND) -> u32 #foreign user32;
WaitMessage :: () -> s32 #foreign user32;
SetTimer  :: (hWnd: HWND, nIDEvent: u64, uElapse: u32, lpTimerFunc: *void) -> s32 #foreign user32;
