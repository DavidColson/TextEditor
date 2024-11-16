#import "Basic";
#import "Compiler";
#import "File";

BUILD_DEBUG_DIR :: "run/debug";
BUILD_OPTIMIZED_DIR :: "run/optimized";
BUILD_RELEASE_DIR :: "run/release";

Build :: ()
{
    w := compiler_create_workspace();

	// todo, create build output when it does not exist

    target_options := get_build_options(w);
    args := target_options.compile_time_command_line;
    
    set_working_directory(#filepath);
    build_optimized := false;
    build_release := false;
    
    for arg: args
    {
    	if arg ==
    	{
    		case "optimized";
    			build_optimized = true;
    		case "release";
    			build_release = true;
    	}
    }
    
    target_options.output_executable_name = "TextEditor";
	set_build_options(target_options, w);
    
    // There are 3 target types in this program :
    // 	- Debug : Not optimized and has debug info
    // 	- Optimized : Optimized and has debug info
    // 	- Release : Very optimized and doesn't have debug info
    if build_release then BuildRelease(w);
    else if build_optimized then BuildOptimized(w);
    else BuildDebug(w);
    
    add_build_file("source/main.jai", w);
    
    set_build_options_dc(.{do_output=false});
}

BuildDebug :: (w: Workspace)
{
    target_options := get_build_options(w);
    target_options.backend =.X64; 
    target_options.output_path = BUILD_DEBUG_DIR;
    set_optimization(*target_options, Optimization_Type.DEBUG, true);
    set_build_options(target_options, w);
    add_build_string("BUILD_TYPE :: BuildType.DEBUG;", w);
}

BuildOptimized :: (w: Workspace)
{
    target_options := get_build_options(w);
    target_options.backend = .X64;
    target_options.output_path = BUILD_OPTIMIZED_DIR;
    set_optimization(*target_options, Optimization_Type.OPTIMIZED);   
    set_build_options(target_options, w);
    add_build_string("BUILD_TYPE :: BuildType.OPTIMIZED;", w);
}

BuildRelease :: (w: Workspace)
{
    target_options := get_build_options(w);
    target_options.backend = .LLVM;
    target_options.output_path = BUILD_RELEASE_DIR;
    target_options.emit_debug_info=.NONE;
    target_options.enable_bytecode_inliner = true;
    set_optimization(*target_options, Optimization_Type.VERY_OPTIMIZED);   
    set_build_options(target_options, w);
    add_build_string("BUILD_TYPE :: BuildType.RELEASE;", w);
}

#run Build();