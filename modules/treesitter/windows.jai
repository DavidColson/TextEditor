//
// This file was auto-generated using the following command:
//
// jai ./generate.jai
//



TREE_SITTER_LANGUAGE_VERSION :: 15;

TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION :: 13;

/*******************/
/* Section - Types */
/*******************/
TSStateId :: u16;
TSSymbol :: u16;
TSFieldId :: u16;
TSLanguage :: struct {}
TSParser :: struct {}
TSTree :: struct {}
TSQuery :: struct {}
TSQueryCursor :: struct {}
TSLookaheadIterator :: struct {}

// This function signature reads one code point from the given string,
// returning the number of bytes consumed. It should write the code point
// to the `code_point` pointer, or write -1 if the input is invalid.
DecodeFunction :: #type (_string: *u8, length: u32, code_point: *s32) -> u32 #c_call;

TSInputEncoding :: enum s32 {
    UTF8    :: 0;
    UTF16LE :: 1;
    UTF16BE :: 2;
    Custom  :: 3;

    TSInputEncodingUTF8    :: UTF8;
    TSInputEncodingUTF16LE :: UTF16LE;
    TSInputEncodingUTF16BE :: UTF16BE;
    TSInputEncodingCustom  :: Custom;
}

TSSymbolType :: enum s32 {
    Regular   :: 0;
    Anonymous :: 1;
    Supertype :: 2;
    Auxiliary :: 3;

    TSSymbolTypeRegular   :: Regular;
    TSSymbolTypeAnonymous :: Anonymous;
    TSSymbolTypeSupertype :: Supertype;
    TSSymbolTypeAuxiliary :: Auxiliary;
}

TSPoint :: struct {
    row:    u32;
    column: u32;
}

TSRange :: struct {
    start_point: TSPoint;
    end_point:   TSPoint;
    start_byte:  u32;
    end_byte:    u32;
}

TSInput :: struct {
    payload:  *void;
    read:     #type (payload: *void, byte_index: u32, position: TSPoint, bytes_read: *u32) -> *u8 #c_call;
    encoding: TSInputEncoding;
    decode:   DecodeFunction;
}

TSParseState :: struct {
    payload:             *void;
    current_byte_offset: u32;
    has_error:           bool;
}

TSParseOptions :: struct {
    payload:           *void;
    progress_callback: #type (state: *TSParseState) -> bool #c_call;
}

TSLogType :: enum s32 {
    Parse :: 0;
    Lex   :: 1;

    TSLogTypeParse :: Parse;
    TSLogTypeLex   :: Lex;
}

TSLogger :: struct {
    payload: *void;
    log:     #type (payload: *void, log_type: TSLogType, buffer: *u8) -> void #c_call;
}

TSInputEdit :: struct {
    start_byte:    u32;
    old_end_byte:  u32;
    new_end_byte:  u32;
    start_point:   TSPoint;
    old_end_point: TSPoint;
    new_end_point: TSPoint;
}

TSNode :: struct {
    _context: [4] u32;
    id:       *void;
    tree:     *TSTree;
}

TSTreeCursor :: struct {
    tree:     *void;
    id:       *void;
    _context: [3] u32;
}

TSQueryCapture :: struct {
    node:  TSNode;
    index: u32;
}

TSQuantifier :: enum s32 {
    Zero       :: 0;
    ZeroOrOne  :: 1;
    ZeroOrMore :: 2;
    One        :: 3;
    OneOrMore  :: 4;

    TSQuantifierZero       :: Zero;
    TSQuantifierZeroOrOne  :: ZeroOrOne;
    TSQuantifierZeroOrMore :: ZeroOrMore;
    TSQuantifierOne        :: One;
    TSQuantifierOneOrMore  :: OneOrMore;
}

TSQueryMatch :: struct {
    id:            u32;
    pattern_index: u16;
    capture_count: u16;
    captures:      *TSQueryCapture;
}

TSQueryPredicateStepType :: enum s32 {
    Done    :: 0;
    Capture :: 1;
    String  :: 2;

    TSQueryPredicateStepTypeDone    :: Done;
    TSQueryPredicateStepTypeCapture :: Capture;
    TSQueryPredicateStepTypeString  :: String;
}

TSQueryPredicateStep :: struct {
    type:     TSQueryPredicateStepType;
    value_id: u32;
}

TSQueryError :: enum s32 {
    None      :: 0;
    Syntax    :: 1;
    NodeType  :: 2;
    Field     :: 3;
    Capture   :: 4;
    Structure :: 5;
    Language  :: 6;

    TSQueryErrorNone      :: None;
    TSQueryErrorSyntax    :: Syntax;
    TSQueryErrorNodeType  :: NodeType;
    TSQueryErrorField     :: Field;
    TSQueryErrorCapture   :: Capture;
    TSQueryErrorStructure :: Structure;
    TSQueryErrorLanguage  :: Language;
}

TSQueryCursorState :: struct {
    payload:             *void;
    current_byte_offset: u32;
}

TSQueryCursorOptions :: struct {
    payload:           *void;
    progress_callback: #type (state: *TSQueryCursorState) -> bool #c_call;
}

/**
* The metadata associated with a language.
*
* Currently, this metadata can be used to check the [Semantic Version](https://semver.org/)
* of the language. This version information should be used to signal if a given parser might
* be incompatible with existing queries when upgrading between major versions, or minor versions
* if it's in zerover.
*/
TSLanguageMetadata :: struct {
    major_version: u8;
    minor_version: u8;
    patch_version: u8;
}

/**
* Create a new parser.
*/
ts_parser_new :: () -> *TSParser #foreign treesitter;

/**
* Delete the parser, freeing all of the memory that it used.
*/
ts_parser_delete :: (self: *TSParser) -> void #foreign treesitter;

/**
* Get the parser's current language.
*/
ts_parser_language :: (self: *TSParser) -> *TSLanguage #foreign treesitter;

/**
* Set the language that the parser should use for parsing.
*
* Returns a boolean indicating whether or not the language was successfully
* assigned. True means assignment succeeded. False means there was a version
* mismatch: the language was generated with an incompatible version of the
* Tree-sitter CLI. Check the language's ABI version using [`ts_language_abi_version`]
* and compare it to this library's [`TREE_SITTER_LANGUAGE_VERSION`] and
* [`TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION`] constants.
*/
ts_parser_set_language :: (self: *TSParser, language: *TSLanguage) -> bool #foreign treesitter;

/**
* Set the ranges of text that the parser should include when parsing.
*
* By default, the parser will always include entire documents. This function
* allows you to parse only a *portion* of a document but still return a syntax
* tree whose ranges match up with the document as a whole. You can also pass
* multiple disjoint ranges.
*
* The second and third parameters specify the location and length of an array
* of ranges. The parser does *not* take ownership of these ranges; it copies
* the data, so it doesn't matter how these ranges are allocated.
*
* If `count` is zero, then the entire document will be parsed. Otherwise,
* the given ranges must be ordered from earliest to latest in the document,
* and they must not overlap. That is, the following must hold for all:
*
* `i < count - 1`: `ranges[i].end_byte <= ranges[i + 1].start_byte`
*
* If this requirement is not satisfied, the operation will fail, the ranges
* will not be assigned, and this function will return `false`. On success,
* this function returns `true`
*/
ts_parser_set_included_ranges :: (self: *TSParser, ranges: *TSRange, count: u32) -> bool #foreign treesitter;

/**
* Get the ranges of text that the parser will include when parsing.
*
* The returned pointer is owned by the parser. The caller should not free it
* or write to it. The length of the array will be written to the given
* `count` pointer.
*/
ts_parser_included_ranges :: (self: *TSParser, count: *u32) -> *TSRange #foreign treesitter;

/**
* Use the parser to parse some source code and create a syntax tree.
*
* If you are parsing this document for the first time, pass `NULL` for the
* `old_tree` parameter. Otherwise, if you have already parsed an earlier
* version of this document and the document has since been edited, pass the
* previous syntax tree so that the unchanged parts of it can be reused.
* This will save time and memory. For this to work correctly, you must have
* already edited the old syntax tree using the [`ts_tree_edit`] function in a
* way that exactly matches the source code changes.
*
* The [`TSInput`] parameter lets you specify how to read the text. It has the
* following three fields:
* 1. [`read`]: A function to retrieve a chunk of text at a given byte offset
*    and (row, column) position. The function should return a pointer to the
*    text and write its length to the [`bytes_read`] pointer. The parser does
*    not take ownership of this buffer; it just borrows it until it has
*    finished reading it. The function should write a zero value to the
*    [`bytes_read`] pointer to indicate the end of the document.
* 2. [`payload`]: An arbitrary pointer that will be passed to each invocation
*    of the [`read`] function.
* 3. [`encoding`]: An indication of how the text is encoded. Either
*    `TSInputEncodingUTF8` or `TSInputEncodingUTF16`.
*
* This function returns a syntax tree on success, and `NULL` on failure. There
* are four possible reasons for failure:
* 1. The parser does not have a language assigned. Check for this using the
[`ts_parser_language`] function.
* 2. Parsing was cancelled due to a timeout that was set by an earlier call to
*    the [`ts_parser_set_timeout_micros`] function. You can resume parsing from
*    where the parser left out by calling [`ts_parser_parse`] again with the
*    same arguments. Or you can start parsing from scratch by first calling
*    [`ts_parser_reset`].
* 3. Parsing was cancelled using a cancellation flag that was set by an
*    earlier call to [`ts_parser_set_cancellation_flag`]. You can resume parsing
*    from where the parser left out by calling [`ts_parser_parse`] again with
*    the same arguments.
* 4. Parsing was cancelled due to the progress callback returning true. This callback
*    is passed in [`ts_parser_parse_with_options`] inside the [`TSParseOptions`] struct.
*
* [`read`]: TSInput::read
* [`payload`]: TSInput::payload
* [`encoding`]: TSInput::encoding
* [`bytes_read`]: TSInput::read
*/
ts_parser_parse :: (self: *TSParser, old_tree: *TSTree, input: TSInput) -> *TSTree #foreign treesitter;

/**
* Use the parser to parse some source code and create a syntax tree, with some options.
*
* See [`ts_parser_parse`] for more details.
*
* See [`TSParseOptions`] for more details on the options.
*/
ts_parser_parse_with_options :: (self: *TSParser, old_tree: *TSTree, input: TSInput, parse_options: TSParseOptions) -> *TSTree #foreign treesitter;

/**
* Use the parser to parse some source code stored in one contiguous buffer.
* The first two parameters are the same as in the [`ts_parser_parse`] function
* above. The second two parameters indicate the location of the buffer and its
* length in bytes.
*/
ts_parser_parse_string :: (self: *TSParser, old_tree: *TSTree, _string: *u8, length: u32) -> *TSTree #foreign treesitter;

/**
* Use the parser to parse some source code stored in one contiguous buffer with
* a given encoding. The first four parameters work the same as in the
* [`ts_parser_parse_string`] method above. The final parameter indicates whether
* the text is encoded as UTF8 or UTF16.
*/
ts_parser_parse_string_encoding :: (self: *TSParser, old_tree: *TSTree, _string: *u8, length: u32, encoding: TSInputEncoding) -> *TSTree #foreign treesitter;

/**
* Instruct the parser to start the next parse from the beginning.
*
* If the parser previously failed because of a timeout or a cancellation, then
* by default, it will resume where it left off on the next call to
* [`ts_parser_parse`] or other parsing functions. If you don't want to resume,
* and instead intend to use this parser to parse some other document, you must
* call [`ts_parser_reset`] first.
*/
ts_parser_reset :: (self: *TSParser) -> void #foreign treesitter;

/**
* @deprecated use [`ts_parser_parse_with_options`] and pass in a callback instead, this will be removed in 0.26.
*
* Set the maximum duration in microseconds that parsing should be allowed to
* take before halting.
*
* If parsing takes longer than this, it will halt early, returning NULL.
* See [`ts_parser_parse`] for more information.
*/
ts_parser_set_timeout_micros :: (self: *TSParser, timeout_micros: u64) -> void #foreign treesitter;

/**
* @deprecated use [`ts_parser_parse_with_options`] and pass in a callback instead, this will be removed in 0.26.
*
* Get the duration in microseconds that parsing is allowed to take.
*/
ts_parser_timeout_micros :: (self: *TSParser) -> u64 #foreign treesitter;

/**
* @deprecated use [`ts_parser_parse_with_options`] and pass in a callback instead, this will be removed in 0.26.
*
* Set the parser's current cancellation flag pointer.
*
* If a non-null pointer is assigned, then the parser will periodically read
* from this pointer during parsing. If it reads a non-zero value, it will
* halt early, returning NULL. See [`ts_parser_parse`] for more information.
*/
ts_parser_set_cancellation_flag :: (self: *TSParser, flag: *u64) -> void #foreign treesitter;

/**
* @deprecated use [`ts_parser_parse_with_options`] and pass in a callback instead, this will be removed in 0.26.
*
* Get the parser's current cancellation flag pointer.
*/
ts_parser_cancellation_flag :: (self: *TSParser) -> *u64 #foreign treesitter;

/**
* Set the logger that a parser should use during parsing.
*
* The parser does not take ownership over the logger payload. If a logger was
* previously assigned, the caller is responsible for releasing any memory
* owned by the previous logger.
*/
ts_parser_set_logger :: (self: *TSParser, logger: TSLogger) -> void #foreign treesitter;

/**
* Get the parser's current logger.
*/
ts_parser_logger :: (self: *TSParser) -> TSLogger #foreign treesitter;

/**
* Set the file descriptor to which the parser should write debugging graphs
* during parsing. The graphs are formatted in the DOT language. You may want
* to pipe these graphs directly to a `dot(1)` process in order to generate
* SVG output. You can turn off this logging by passing a negative number.
*/
ts_parser_print_dot_graphs :: (self: *TSParser, fd: s32) -> void #foreign treesitter;

/**
* Create a shallow copy of the syntax tree. This is very fast.
*
* You need to copy a syntax tree in order to use it on more than one thread at
* a time, as syntax trees are not thread safe.
*/
ts_tree_copy :: (self: *TSTree) -> *TSTree #foreign treesitter;

/**
* Delete the syntax tree, freeing all of the memory that it used.
*/
ts_tree_delete :: (self: *TSTree) -> void #foreign treesitter;

/**
* Get the root node of the syntax tree.
*/
ts_tree_root_node :: (self: *TSTree) -> TSNode #foreign treesitter;

/**
* Get the root node of the syntax tree, but with its position
* shifted forward by the given offset.
*/
ts_tree_root_node_with_offset :: (self: *TSTree, offset_bytes: u32, offset_extent: TSPoint) -> TSNode #foreign treesitter;

/**
* Get the language that was used to parse the syntax tree.
*/
ts_tree_language :: (self: *TSTree) -> *TSLanguage #foreign treesitter;

/**
* Get the array of included ranges that was used to parse the syntax tree.
*
* The returned pointer must be freed by the caller.
*/
ts_tree_included_ranges :: (self: *TSTree, length: *u32) -> *TSRange #foreign treesitter;

/**
* Edit the syntax tree to keep it in sync with source code that has been
* edited.
*
* You must describe the edit both in terms of byte offsets and in terms of
* (row, column) coordinates.
*/
ts_tree_edit :: (self: *TSTree, edit: *TSInputEdit) -> void #foreign treesitter;

/**
* Compare an old edited syntax tree to a new syntax tree representing the same
* document, returning an array of ranges whose syntactic structure has changed.
*
* For this to work correctly, the old syntax tree must have been edited such
* that its ranges match up to the new tree. Generally, you'll want to call
* this function right after calling one of the [`ts_parser_parse`] functions.
* You need to pass the old tree that was passed to parse, as well as the new
* tree that was returned from that function.
*
* The returned ranges indicate areas where the hierarchical structure of syntax
* nodes (from root to leaf) has changed between the old and new trees. Characters
* outside these ranges have identical ancestor nodes in both trees.
*
* Note that the returned ranges may be slightly larger than the exact changed areas,
* but Tree-sitter attempts to make them as small as possible.
*
* The returned array is allocated using `malloc` and the caller is responsible
* for freeing it using `free`. The length of the array will be written to the
* given `length` pointer.
*/
ts_tree_get_changed_ranges :: (old_tree: *TSTree, new_tree: *TSTree, length: *u32) -> *TSRange #foreign treesitter;

/**
* Write a DOT graph describing the syntax tree to the given file.
*/
ts_tree_print_dot_graph :: (self: *TSTree, file_descriptor: s32) -> void #foreign treesitter;

/**
* Get the node's type as a null-terminated string.
*/
ts_node_type :: (self: TSNode) -> *u8 #foreign treesitter;

/**
* Get the node's type as a numerical id.
*/
ts_node_symbol :: (self: TSNode) -> TSSymbol #foreign treesitter;

/**
* Get the node's language.
*/
ts_node_language :: (self: TSNode) -> *TSLanguage #foreign treesitter;

/**
* Get the node's type as it appears in the grammar ignoring aliases as a
* null-terminated string.
*/
ts_node_grammar_type :: (self: TSNode) -> *u8 #foreign treesitter;

/**
* Get the node's type as a numerical id as it appears in the grammar ignoring
* aliases. This should be used in [`ts_language_next_state`] instead of
* [`ts_node_symbol`].
*/
ts_node_grammar_symbol :: (self: TSNode) -> TSSymbol #foreign treesitter;

/**
* Get the node's start byte.
*/
ts_node_start_byte :: (self: TSNode) -> u32 #foreign treesitter;

/**
* Get the node's start position in terms of rows and columns.
*/
ts_node_start_point :: (self: TSNode) -> TSPoint #foreign treesitter;

/**
* Get the node's end byte.
*/
ts_node_end_byte :: (self: TSNode) -> u32 #foreign treesitter;

/**
* Get the node's end position in terms of rows and columns.
*/
ts_node_end_point :: (self: TSNode) -> TSPoint #foreign treesitter;

/**
* Get an S-expression representing the node as a string.
*
* This string is allocated with `malloc` and the caller is responsible for
* freeing it using `free`.
*/
ts_node_string :: (self: TSNode) -> *u8 #foreign treesitter;

/**
* Check if the node is null. Functions like [`ts_node_child`] and
* [`ts_node_next_sibling`] will return a null node to indicate that no such node
* was found.
*/
ts_node_is_null :: (self: TSNode) -> bool #foreign treesitter;

/**
* Check if the node is *named*. Named nodes correspond to named rules in the
* grammar, whereas *anonymous* nodes correspond to string literals in the
* grammar.
*/
ts_node_is_named :: (self: TSNode) -> bool #foreign treesitter;

/**
* Check if the node is *missing*. Missing nodes are inserted by the parser in
* order to recover from certain kinds of syntax errors.
*/
ts_node_is_missing :: (self: TSNode) -> bool #foreign treesitter;

/**
* Check if the node is *extra*. Extra nodes represent things like comments,
* which are not required the grammar, but can appear anywhere.
*/
ts_node_is_extra :: (self: TSNode) -> bool #foreign treesitter;

/**
* Check if a syntax node has been edited.
*/
ts_node_has_changes :: (self: TSNode) -> bool #foreign treesitter;

/**
* Check if the node is a syntax error or contains any syntax errors.
*/
ts_node_has_error :: (self: TSNode) -> bool #foreign treesitter;

/**
* Check if the node is a syntax error.
*/
ts_node_is_error :: (self: TSNode) -> bool #foreign treesitter;

/**
* Get this node's parse state.
*/
ts_node_parse_state :: (self: TSNode) -> TSStateId #foreign treesitter;

/**
* Get the parse state after this node.
*/
ts_node_next_parse_state :: (self: TSNode) -> TSStateId #foreign treesitter;

/**
* Get the node's immediate parent.
* Prefer [`ts_node_child_with_descendant`] for
* iterating over the node's ancestors.
*/
ts_node_parent :: (self: TSNode) -> TSNode #foreign treesitter;

/**
* Get the node that contains `descendant`.
*
* Note that this can return `descendant` itself.
*/
ts_node_child_with_descendant :: (self: TSNode, descendant: TSNode) -> TSNode #foreign treesitter;

/**
* Get the node's child at the given index, where zero represents the first
* child.
*/
ts_node_child :: (self: TSNode, child_index: u32) -> TSNode #foreign treesitter;

/**
* Get the field name for node's child at the given index, where zero represents
* the first child. Returns NULL, if no field is found.
*/
ts_node_field_name_for_child :: (self: TSNode, child_index: u32) -> *u8 #foreign treesitter;

/**
* Get the field name for node's named child at the given index, where zero
* represents the first named child. Returns NULL, if no field is found.
*/
ts_node_field_name_for_named_child :: (self: TSNode, named_child_index: u32) -> *u8 #foreign treesitter;

/**
* Get the node's number of children.
*/
ts_node_child_count :: (self: TSNode) -> u32 #foreign treesitter;

/**
* Get the node's *named* child at the given index.
*
* See also [`ts_node_is_named`].
*/
ts_node_named_child :: (self: TSNode, child_index: u32) -> TSNode #foreign treesitter;

/**
* Get the node's number of *named* children.
*
* See also [`ts_node_is_named`].
*/
ts_node_named_child_count :: (self: TSNode) -> u32 #foreign treesitter;

/**
* Get the node's child with the given field name.
*/
ts_node_child_by_field_name :: (self: TSNode, name: *u8, name_length: u32) -> TSNode #foreign treesitter;

/**
* Get the node's child with the given numerical field id.
*
* You can convert a field name to an id using the
* [`ts_language_field_id_for_name`] function.
*/
ts_node_child_by_field_id :: (self: TSNode, field_id: TSFieldId) -> TSNode #foreign treesitter;

/**
* Get the node's next / previous sibling.
*/
ts_node_next_sibling :: (self: TSNode) -> TSNode #foreign treesitter;
ts_node_prev_sibling :: (self: TSNode) -> TSNode #foreign treesitter;

/**
* Get the node's next / previous *named* sibling.
*/
ts_node_next_named_sibling :: (self: TSNode) -> TSNode #foreign treesitter;
ts_node_prev_named_sibling :: (self: TSNode) -> TSNode #foreign treesitter;

/**
* Get the node's first child that contains or starts after the given byte offset.
*/
ts_node_first_child_for_byte :: (self: TSNode, byte: u32) -> TSNode #foreign treesitter;

/**
* Get the node's first named child that contains or starts after the given byte offset.
*/
ts_node_first_named_child_for_byte :: (self: TSNode, byte: u32) -> TSNode #foreign treesitter;

/**
* Get the node's number of descendants, including one for the node itself.
*/
ts_node_descendant_count :: (self: TSNode) -> u32 #foreign treesitter;

/**
* Get the smallest node within this node that spans the given range of bytes
* or (row, column) positions.
*/
ts_node_descendant_for_byte_range :: (self: TSNode, start: u32, end: u32) -> TSNode #foreign treesitter;
ts_node_descendant_for_point_range :: (self: TSNode, start: TSPoint, end: TSPoint) -> TSNode #foreign treesitter;

/**
* Get the smallest named node within this node that spans the given range of
* bytes or (row, column) positions.
*/
ts_node_named_descendant_for_byte_range :: (self: TSNode, start: u32, end: u32) -> TSNode #foreign treesitter;
ts_node_named_descendant_for_point_range :: (self: TSNode, start: TSPoint, end: TSPoint) -> TSNode #foreign treesitter;

/**
* Edit the node to keep it in-sync with source code that has been edited.
*
* This function is only rarely needed. When you edit a syntax tree with the
* [`ts_tree_edit`] function, all of the nodes that you retrieve from the tree
* afterward will already reflect the edit. You only need to use [`ts_node_edit`]
* when you have a [`TSNode`] instance that you want to keep and continue to use
* after an edit.
*/
ts_node_edit :: (self: *TSNode, edit: *TSInputEdit) -> void #foreign treesitter;

/**
* Check if two nodes are identical.
*/
ts_node_eq :: (self: TSNode, other: TSNode) -> bool #foreign treesitter;

/**
* Create a new tree cursor starting from the given node.
*
* A tree cursor allows you to walk a syntax tree more efficiently than is
* possible using the [`TSNode`] functions. It is a mutable object that is always
* on a certain syntax node, and can be moved imperatively to different nodes.
*
* Note that the given node is considered the root of the cursor,
* and the cursor cannot walk outside this node.
*/
ts_tree_cursor_new :: (node: TSNode) -> TSTreeCursor #foreign treesitter;

/**
* Delete a tree cursor, freeing all of the memory that it used.
*/
ts_tree_cursor_delete :: (self: *TSTreeCursor) -> void #foreign treesitter;

/**
* Re-initialize a tree cursor to start at the original node that the cursor was
* constructed with.
*/
ts_tree_cursor_reset :: (self: *TSTreeCursor, node: TSNode) -> void #foreign treesitter;

/**
* Re-initialize a tree cursor to the same position as another cursor.
*
* Unlike [`ts_tree_cursor_reset`], this will not lose parent information and
* allows reusing already created cursors.
*/
ts_tree_cursor_reset_to :: (dst: *TSTreeCursor, src: *TSTreeCursor) -> void #foreign treesitter;

/**
* Get the tree cursor's current node.
*/
ts_tree_cursor_current_node :: (self: *TSTreeCursor) -> TSNode #foreign treesitter;

/**
* Get the field name of the tree cursor's current node.
*
* This returns `NULL` if the current node doesn't have a field.
* See also [`ts_node_child_by_field_name`].
*/
ts_tree_cursor_current_field_name :: (self: *TSTreeCursor) -> *u8 #foreign treesitter;

/**
* Get the field id of the tree cursor's current node.
*
* This returns zero if the current node doesn't have a field.
* See also [`ts_node_child_by_field_id`], [`ts_language_field_id_for_name`].
*/
ts_tree_cursor_current_field_id :: (self: *TSTreeCursor) -> TSFieldId #foreign treesitter;

/**
* Move the cursor to the parent of its current node.
*
* This returns `true` if the cursor successfully moved, and returns `false`
* if there was no parent node (the cursor was already on the root node).
*
* Note that the node the cursor was constructed with is considered the root
* of the cursor, and the cursor cannot walk outside this node.
*/
ts_tree_cursor_goto_parent :: (self: *TSTreeCursor) -> bool #foreign treesitter;

/**
* Move the cursor to the next sibling of its current node.
*
* This returns `true` if the cursor successfully moved, and returns `false`
* if there was no next sibling node.
*
* Note that the node the cursor was constructed with is considered the root
* of the cursor, and the cursor cannot walk outside this node.
*/
ts_tree_cursor_goto_next_sibling :: (self: *TSTreeCursor) -> bool #foreign treesitter;

/**
* Move the cursor to the previous sibling of its current node.
*
* This returns `true` if the cursor successfully moved, and returns `false` if
* there was no previous sibling node.
*
* Note, that this function may be slower than
* [`ts_tree_cursor_goto_next_sibling`] due to how node positions are stored. In
* the worst case, this will need to iterate through all the children up to the
* previous sibling node to recalculate its position. Also note that the node the cursor
* was constructed with is considered the root of the cursor, and the cursor cannot
* walk outside this node.
*/
ts_tree_cursor_goto_previous_sibling :: (self: *TSTreeCursor) -> bool #foreign treesitter;

/**
* Move the cursor to the first child of its current node.
*
* This returns `true` if the cursor successfully moved, and returns `false`
* if there were no children.
*/
ts_tree_cursor_goto_first_child :: (self: *TSTreeCursor) -> bool #foreign treesitter;

/**
* Move the cursor to the last child of its current node.
*
* This returns `true` if the cursor successfully moved, and returns `false` if
* there were no children.
*
* Note that this function may be slower than [`ts_tree_cursor_goto_first_child`]
* because it needs to iterate through all the children to compute the child's
* position.
*/
ts_tree_cursor_goto_last_child :: (self: *TSTreeCursor) -> bool #foreign treesitter;

/**
* Move the cursor to the node that is the nth descendant of
* the original node that the cursor was constructed with, where
* zero represents the original node itself.
*/
ts_tree_cursor_goto_descendant :: (self: *TSTreeCursor, goal_descendant_index: u32) -> void #foreign treesitter;

/**
* Get the index of the cursor's current node out of all of the
* descendants of the original node that the cursor was constructed with.
*/
ts_tree_cursor_current_descendant_index :: (self: *TSTreeCursor) -> u32 #foreign treesitter;

/**
* Get the depth of the cursor's current node relative to the original
* node that the cursor was constructed with.
*/
ts_tree_cursor_current_depth :: (self: *TSTreeCursor) -> u32 #foreign treesitter;

/**
* Move the cursor to the first child of its current node that contains or starts after
* the given byte offset or point.
*
* This returns the index of the child node if one was found, and returns -1
* if no such child was found.
*/
ts_tree_cursor_goto_first_child_for_byte :: (self: *TSTreeCursor, goal_byte: u32) -> s64 #foreign treesitter;
ts_tree_cursor_goto_first_child_for_point :: (self: *TSTreeCursor, goal_point: TSPoint) -> s64 #foreign treesitter;

ts_tree_cursor_copy :: (cursor: *TSTreeCursor) -> TSTreeCursor #foreign treesitter;

/**
* Create a new query from a string containing one or more S-expression
* patterns. The query is associated with a particular language, and can
* only be run on syntax nodes parsed with that language.
*
* If all of the given patterns are valid, this returns a [`TSQuery`].
* If a pattern is invalid, this returns `NULL`, and provides two pieces
* of information about the problem:
* 1. The byte offset of the error is written to the `error_offset` parameter.
* 2. The type of error is written to the `error_type` parameter.
*/
ts_query_new :: (language: *TSLanguage, source: *u8, source_len: u32, error_offset: *u32, error_type: *TSQueryError) -> *TSQuery #foreign treesitter;

/**
* Delete a query, freeing all of the memory that it used.
*/
ts_query_delete :: (self: *TSQuery) -> void #foreign treesitter;

/**
* Get the number of patterns, captures, or string literals in the query.
*/
ts_query_pattern_count :: (self: *TSQuery) -> u32 #foreign treesitter;
ts_query_capture_count :: (self: *TSQuery) -> u32 #foreign treesitter;
ts_query_string_count :: (self: *TSQuery) -> u32 #foreign treesitter;

/**
* Get the byte offset where the given pattern starts in the query's source.
*
* This can be useful when combining queries by concatenating their source
* code strings.
*/
ts_query_start_byte_for_pattern :: (self: *TSQuery, pattern_index: u32) -> u32 #foreign treesitter;

/**
* Get the byte offset where the given pattern ends in the query's source.
*
* This can be useful when combining queries by concatenating their source
* code strings.
*/
ts_query_end_byte_for_pattern :: (self: *TSQuery, pattern_index: u32) -> u32 #foreign treesitter;

/**
* Get all of the predicates for the given pattern in the query.
*
* The predicates are represented as a single array of steps. There are three
* types of steps in this array, which correspond to the three legal values for
* the `type` field:
* - `TSQueryPredicateStepTypeCapture` - Steps with this type represent names
*    of captures. Their `value_id` can be used with the
*   [`ts_query_capture_name_for_id`] function to obtain the name of the capture.
* - `TSQueryPredicateStepTypeString` - Steps with this type represent literal
*    strings. Their `value_id` can be used with the
*    [`ts_query_string_value_for_id`] function to obtain their string value.
* - `TSQueryPredicateStepTypeDone` - Steps with this type are *sentinels*
*    that represent the end of an individual predicate. If a pattern has two
*    predicates, then there will be two steps with this `type` in the array.
*/
ts_query_predicates_for_pattern :: (self: *TSQuery, pattern_index: u32, step_count: *u32) -> *TSQueryPredicateStep #foreign treesitter;

/*
* Check if the given pattern in the query has a single root node.
*/
ts_query_is_pattern_rooted :: (self: *TSQuery, pattern_index: u32) -> bool #foreign treesitter;

/*
* Check if the given pattern in the query is 'non local'.
*
* A non-local pattern has multiple root nodes and can match within a
* repeating sequence of nodes, as specified by the grammar. Non-local
* patterns disable certain optimizations that would otherwise be possible
* when executing a query on a specific range of a syntax tree.
*/
ts_query_is_pattern_non_local :: (self: *TSQuery, pattern_index: u32) -> bool #foreign treesitter;

/*
* Check if a given pattern is guaranteed to match once a given step is reached.
* The step is specified by its byte offset in the query's source code.
*/
ts_query_is_pattern_guaranteed_at_step :: (self: *TSQuery, byte_offset: u32) -> bool #foreign treesitter;

/**
* Get the name and length of one of the query's captures, or one of the
* query's string literals. Each capture and string is associated with a
* numeric id based on the order that it appeared in the query's source.
*/
ts_query_capture_name_for_id :: (self: *TSQuery, index: u32, length: *u32) -> *u8 #foreign treesitter;

/**
* Get the quantifier of the query's captures. Each capture is * associated
* with a numeric id based on the order that it appeared in the query's source.
*/
ts_query_capture_quantifier_for_id :: (self: *TSQuery, pattern_index: u32, capture_index: u32) -> TSQuantifier #foreign treesitter;

ts_query_string_value_for_id :: (self: *TSQuery, index: u32, length: *u32) -> *u8 #foreign treesitter;

/**
* Disable a certain capture within a query.
*
* This prevents the capture from being returned in matches, and also avoids
* any resource usage associated with recording the capture. Currently, there
* is no way to undo this.
*/
ts_query_disable_capture :: (self: *TSQuery, name: *u8, length: u32) -> void #foreign treesitter;

/**
* Disable a certain pattern within a query.
*
* This prevents the pattern from matching and removes most of the overhead
* associated with the pattern. Currently, there is no way to undo this.
*/
ts_query_disable_pattern :: (self: *TSQuery, pattern_index: u32) -> void #foreign treesitter;

/**
* Create a new cursor for executing a given query.
*
* The cursor stores the state that is needed to iteratively search
* for matches. To use the query cursor, first call [`ts_query_cursor_exec`]
* to start running a given query on a given syntax node. Then, there are
* two options for consuming the results of the query:
* 1. Repeatedly call [`ts_query_cursor_next_match`] to iterate over all of the
*    *matches* in the order that they were found. Each match contains the
*    index of the pattern that matched, and an array of captures. Because
*    multiple patterns can match the same set of nodes, one match may contain
*    captures that appear *before* some of the captures from a previous match.
* 2. Repeatedly call [`ts_query_cursor_next_capture`] to iterate over all of the
*    individual *captures* in the order that they appear. This is useful if
*    don't care about which pattern matched, and just want a single ordered
*    sequence of captures.
*
* If you don't care about consuming all of the results, you can stop calling
* [`ts_query_cursor_next_match`] or [`ts_query_cursor_next_capture`] at any point.
*  You can then start executing another query on another node by calling
*  [`ts_query_cursor_exec`] again.
*/
ts_query_cursor_new :: () -> *TSQueryCursor #foreign treesitter;

/**
* Delete a query cursor, freeing all of the memory that it used.
*/
ts_query_cursor_delete :: (self: *TSQueryCursor) -> void #foreign treesitter;

/**
* Start running a given query on a given node.
*/
ts_query_cursor_exec :: (self: *TSQueryCursor, query: *TSQuery, node: TSNode) -> void #foreign treesitter;

/**
* Start running a given query on a given node, with some options.
*/
ts_query_cursor_exec_with_options :: (self: *TSQueryCursor, query: *TSQuery, node: TSNode, query_options: *TSQueryCursorOptions) -> void #foreign treesitter;

/**
* Manage the maximum number of in-progress matches allowed by this query
* cursor.
*
* Query cursors have an optional maximum capacity for storing lists of
* in-progress captures. If this capacity is exceeded, then the
* earliest-starting match will silently be dropped to make room for further
* matches. This maximum capacity is optional — by default, query cursors allow
* any number of pending matches, dynamically allocating new space for them as
* needed as the query is executed.
*/
ts_query_cursor_did_exceed_match_limit :: (self: *TSQueryCursor) -> bool #foreign treesitter;
ts_query_cursor_match_limit :: (self: *TSQueryCursor) -> u32 #foreign treesitter;
ts_query_cursor_set_match_limit :: (self: *TSQueryCursor, limit: u32) -> void #foreign treesitter;

/**
* @deprecated use [`ts_query_cursor_exec_with_options`] and pass in a callback instead, this will be removed in 0.26.
*
* Set the maximum duration in microseconds that query execution should be allowed to
* take before halting.
*
* If query execution takes longer than this, it will halt early, returning NULL.
* See [`ts_query_cursor_next_match`] or [`ts_query_cursor_next_capture`] for more information.
*/
ts_query_cursor_set_timeout_micros :: (self: *TSQueryCursor, timeout_micros: u64) -> void #foreign treesitter;

/**
* @deprecated use [`ts_query_cursor_exec_with_options`] and pass in a callback instead, this will be removed in 0.26.
*
* Get the duration in microseconds that query execution is allowed to take.
*
* This is set via [`ts_query_cursor_set_timeout_micros`].
*/
ts_query_cursor_timeout_micros :: (self: *TSQueryCursor) -> u64 #foreign treesitter;

/**
* Set the range of bytes in which the query will be executed.
*
* The query cursor will return matches that intersect with the given point range.
* This means that a match may be returned even if some of its captures fall
* outside the specified range, as long as at least part of the match
* overlaps with the range.
*
* For example, if a query pattern matches a node that spans a larger area
* than the specified range, but part of that node intersects with the range,
* the entire match will be returned.
*
* This will return `false` if the start byte is greater than the end byte, otherwise
* it will return `true`.
*/
ts_query_cursor_set_byte_range :: (self: *TSQueryCursor, start_byte: u32, end_byte: u32) -> bool #foreign treesitter;

/**
* Set the range of (row, column) positions in which the query will be executed.
*
* The query cursor will return matches that intersect with the given point range.
* This means that a match may be returned even if some of its captures fall
* outside the specified range, as long as at least part of the match
* overlaps with the range.
*
* For example, if a query pattern matches a node that spans a larger area
* than the specified range, but part of that node intersects with the range,
* the entire match will be returned.
*
* This will return `false` if the start point is greater than the end point, otherwise
* it will return `true`.
*/
ts_query_cursor_set_point_range :: (self: *TSQueryCursor, start_point: TSPoint, end_point: TSPoint) -> bool #foreign treesitter;

/**
* Advance to the next match of the currently running query.
*
* If there is a match, write it to `*match` and return `true`.
* Otherwise, return `false`.
*/
ts_query_cursor_next_match :: (self: *TSQueryCursor, match: *TSQueryMatch) -> bool #foreign treesitter;
ts_query_cursor_remove_match :: (self: *TSQueryCursor, match_id: u32) -> void #foreign treesitter;

/**
* Advance to the next capture of the currently running query.
*
* If there is a capture, write its match to `*match` and its index within
* the match's capture list to `*capture_index`. Otherwise, return `false`.
*/
ts_query_cursor_next_capture :: (self: *TSQueryCursor, match: *TSQueryMatch, capture_index: *u32) -> bool #foreign treesitter;

/**
* Set the maximum start depth for a query cursor.
*
* This prevents cursors from exploring children nodes at a certain depth.
* Note if a pattern includes many children, then they will still be checked.
*
* The zero max start depth value can be used as a special behavior and
* it helps to destructure a subtree by staying on a node and using captures
* for interested parts. Note that the zero max start depth only limit a search
* depth for a pattern's root node but other nodes that are parts of the pattern
* may be searched at any depth what defined by the pattern structure.
*
* Set to `UINT32_MAX` to remove the maximum start depth.
*/
ts_query_cursor_set_max_start_depth :: (self: *TSQueryCursor, max_start_depth: u32) -> void #foreign treesitter;

/**
* Get another reference to the given language.
*/
ts_language_copy :: (self: *TSLanguage) -> *TSLanguage #foreign treesitter;

/**
* Free any dynamically-allocated resources for this language, if
* this is the last reference.
*/
ts_language_delete :: (self: *TSLanguage) -> void #foreign treesitter;

/**
* Get the number of distinct node types in the language.
*/
ts_language_symbol_count :: (self: *TSLanguage) -> u32 #foreign treesitter;

/**
* Get the number of valid states in this language.
*/
ts_language_state_count :: (self: *TSLanguage) -> u32 #foreign treesitter;

/**
* Get the numerical id for the given node type string.
*/
ts_language_symbol_for_name :: (self: *TSLanguage, _string: *u8, length: u32, is_named: bool) -> TSSymbol #foreign treesitter;

/**
* Get the number of distinct field names in the language.
*/
ts_language_field_count :: (self: *TSLanguage) -> u32 #foreign treesitter;

/**
* Get the field name string for the given numerical id.
*/
ts_language_field_name_for_id :: (self: *TSLanguage, id: TSFieldId) -> *u8 #foreign treesitter;

/**
* Get the numerical id for the given field name string.
*/
ts_language_field_id_for_name :: (self: *TSLanguage, name: *u8, name_length: u32) -> TSFieldId #foreign treesitter;

/**
* Get a list of all supertype symbols for the language.
*/
ts_language_supertypes :: (self: *TSLanguage, length: *u32) -> *TSSymbol #foreign treesitter;

/**
* Get a list of all subtype symbol ids for a given supertype symbol.
*
* See [`ts_language_supertypes`] for fetching all supertype symbols.
*/
ts_language_subtypes :: (self: *TSLanguage, supertype: TSSymbol, length: *u32) -> *TSSymbol #foreign treesitter;

/**
* Get a node type string for the given numerical id.
*/
ts_language_symbol_name :: (self: *TSLanguage, symbol: TSSymbol) -> *u8 #foreign treesitter;

/**
* Check whether the given node type id belongs to named nodes, anonymous nodes,
* or a hidden nodes.
*
* See also [`ts_node_is_named`]. Hidden nodes are never returned from the API.
*/
ts_language_symbol_type :: (self: *TSLanguage, symbol: TSSymbol) -> TSSymbolType #foreign treesitter;

/**
* @deprecated use [`ts_language_abi_version`] instead, this will be removed in 0.26.
*
* Get the ABI version number for this language. This version number is used
* to ensure that languages were generated by a compatible version of
* Tree-sitter.
*
* See also [`ts_parser_set_language`].
*/
ts_language_version :: (self: *TSLanguage) -> u32 #foreign treesitter;

/**
* Get the ABI version number for this language. This version number is used
* to ensure that languages were generated by a compatible version of
* Tree-sitter.
*
* See also [`ts_parser_set_language`].
*/
ts_language_abi_version :: (self: *TSLanguage) -> u32 #foreign treesitter;

/**
* Get the metadata for this language. This information is generated by the
* CLI, and relies on the language author providing the correct metadata in
* the language's `tree-sitter.json` file.
*
* See also [`TSMetadata`].
*/
ts_language_metadata :: (self: *TSLanguage) -> *TSLanguageMetadata #foreign treesitter;

/**
* Get the next parse state. Combine this with lookahead iterators to generate
* completion suggestions or valid symbols in error nodes. Use
* [`ts_node_grammar_symbol`] for valid symbols.
*/
ts_language_next_state :: (self: *TSLanguage, state: TSStateId, symbol: TSSymbol) -> TSStateId #foreign treesitter;

/**
* Get the name of this language. This returns `NULL` in older parsers.
*/
ts_language_name :: (self: *TSLanguage) -> *u8 #foreign treesitter;

/**
* Create a new lookahead iterator for the given language and parse state.
*
* This returns `NULL` if state is invalid for the language.
*
* Repeatedly using [`ts_lookahead_iterator_next`] and
* [`ts_lookahead_iterator_current_symbol`] will generate valid symbols in the
* given parse state. Newly created lookahead iterators will contain the `ERROR`
* symbol.
*
* Lookahead iterators can be useful to generate suggestions and improve syntax
* error diagnostics. To get symbols valid in an ERROR node, use the lookahead
* iterator on its first leaf node state. For `MISSING` nodes, a lookahead
* iterator created on the previous non-extra leaf node may be appropriate.
*/
ts_lookahead_iterator_new :: (self: *TSLanguage, state: TSStateId) -> *TSLookaheadIterator #foreign treesitter;

/**
* Delete a lookahead iterator freeing all the memory used.
*/
ts_lookahead_iterator_delete :: (self: *TSLookaheadIterator) -> void #foreign treesitter;

/**
* Reset the lookahead iterator to another state.
*
* This returns `true` if the iterator was reset to the given state and `false`
* otherwise.
*/
ts_lookahead_iterator_reset_state :: (self: *TSLookaheadIterator, state: TSStateId) -> bool #foreign treesitter;

/**
* Reset the lookahead iterator.
*
* This returns `true` if the language was set successfully and `false`
* otherwise.
*/
ts_lookahead_iterator_reset :: (self: *TSLookaheadIterator, language: *TSLanguage, state: TSStateId) -> bool #foreign treesitter;

/**
* Get the current language of the lookahead iterator.
*/
ts_lookahead_iterator_language :: (self: *TSLookaheadIterator) -> *TSLanguage #foreign treesitter;

/**
* Advance the lookahead iterator to the next symbol.
*
* This returns `true` if there is a new symbol and `false` otherwise.
*/
ts_lookahead_iterator_next :: (self: *TSLookaheadIterator) -> bool #foreign treesitter;

/**
* Get the current symbol of the lookahead iterator;
*/
ts_lookahead_iterator_current_symbol :: (self: *TSLookaheadIterator) -> TSSymbol #foreign treesitter;

/**
* Get the current symbol type of the lookahead iterator as a null terminated
* string.
*/
ts_lookahead_iterator_current_symbol_name :: (self: *TSLookaheadIterator) -> *u8 #foreign treesitter;

wasm_engine_t :: struct {}
/*************************************/
/* Section - WebAssembly Integration */
/************************************/
TSWasmEngine :: wasm_engine_t;
TSWasmStore :: struct {}

TSWasmErrorKind :: enum s32 {
    None        :: 0;
    Parse       :: 1;
    Compile     :: 2;
    Instantiate :: 3;
    Allocate    :: 4;

    TSWasmErrorKindNone        :: None;
    TSWasmErrorKindParse       :: Parse;
    TSWasmErrorKindCompile     :: Compile;
    TSWasmErrorKindInstantiate :: Instantiate;
    TSWasmErrorKindAllocate    :: Allocate;
}

TSWasmError :: struct {
    kind:    TSWasmErrorKind;
    message: *u8;
}

/**
* Create a Wasm store.
*/
ts_wasm_store_new :: (engine: *TSWasmEngine, error: *TSWasmError) -> *TSWasmStore #foreign treesitter;

/**
* Free the memory associated with the given Wasm store.
*/
ts_wasm_store_delete :: (unknown0: *TSWasmStore) -> void #foreign treesitter;

/**
* Create a language from a buffer of Wasm. The resulting language behaves
* like any other Tree-sitter language, except that in order to use it with
* a parser, that parser must have a Wasm store. Note that the language
* can be used with any Wasm store, it doesn't need to be the same store that
* was used to originally load it.
*/
ts_wasm_store_load_language :: (unknown0: *TSWasmStore, name: *u8, wasm: *u8, wasm_len: u32, error: *TSWasmError) -> *TSLanguage #foreign treesitter;

/**
* Get the number of languages instantiated in the given wasm store.
*/
ts_wasm_store_language_count :: (unknown0: *TSWasmStore) -> u64 #foreign treesitter;

/**
* Check if the language came from a Wasm module. If so, then in order to use
* this language with a Parser, that parser must have a Wasm store assigned.
*/
ts_language_is_wasm :: (unknown0: *TSLanguage) -> bool #foreign treesitter;

/**
* Assign the given Wasm store to the parser. A parser must have a Wasm store
* in order to use Wasm languages.
*/
ts_parser_set_wasm_store :: (unknown0: *TSParser, unknown1: *TSWasmStore) -> void #foreign treesitter;

/**
* Remove the parser's current Wasm store and return it. This returns NULL if
* the parser doesn't have a Wasm store.
*/
ts_parser_take_wasm_store :: (unknown0: *TSParser) -> *TSWasmStore #foreign treesitter;

/**
* Set the allocation functions used by the library.
*
* By default, Tree-sitter uses the standard libc allocation functions,
* but aborts the process when an allocation fails. This function lets
* you supply alternative allocation functions at runtime.
*
* If you pass `NULL` for any parameter, Tree-sitter will switch back to
* its default implementation of that function.
*
* If you call this function after the library has already been used, then
* you must ensure that either:
*  1. All the existing objects have been freed.
*  2. The new allocator shares its state with the old one, so it is capable
*     of freeing memory that was allocated by the old allocator.
*/
ts_set_allocator :: (new_malloc: #type (unknown0: u64) -> *void #c_call, new_calloc: #type (unknown0: u64, unknown1: u64) -> *void #c_call, new_realloc: #type (unknown0: *void, unknown1: u64) -> *void #c_call, new_free: #type (unknown0: *void) -> void #c_call) -> void #foreign treesitter;

#scope_file

#import "Basic"; // For assert

treesitter :: #library "windows/treesitter";

#run {
    {
        info := type_info(TSPoint);
        for info.members {
            if it.name == {
                case "row";
                    assert(it.offset_in_bytes == 0, "TSPoint.row has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSPoint.row has unexpected size % instead of 4", it.type.runtime_size);
                case "column";
                    assert(it.offset_in_bytes == 4, "TSPoint.column has unexpected offset % instead of 4", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSPoint.column has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(TSPoint) == 8, "TSPoint has size % instead of 8", size_of(TSPoint));
    }

    {
        info := type_info(TSRange);
        for info.members {
            if it.name == {
                case "start_point";
                    assert(it.offset_in_bytes == 0, "TSRange.start_point has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSRange.start_point has unexpected size % instead of 8", it.type.runtime_size);
                case "end_point";
                    assert(it.offset_in_bytes == 8, "TSRange.end_point has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSRange.end_point has unexpected size % instead of 8", it.type.runtime_size);
                case "start_byte";
                    assert(it.offset_in_bytes == 16, "TSRange.start_byte has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSRange.start_byte has unexpected size % instead of 4", it.type.runtime_size);
                case "end_byte";
                    assert(it.offset_in_bytes == 20, "TSRange.end_byte has unexpected offset % instead of 20", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSRange.end_byte has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(TSRange) == 24, "TSRange has size % instead of 24", size_of(TSRange));
    }

    {
        info := type_info(TSInput);
        for info.members {
            if it.name == {
                case "payload";
                    assert(it.offset_in_bytes == 0, "TSInput.payload has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSInput.payload has unexpected size % instead of 8", it.type.runtime_size);
                case "read";
                    assert(it.offset_in_bytes == 8, "TSInput.read has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSInput.read has unexpected size % instead of 8", it.type.runtime_size);
                case "encoding";
                    assert(it.offset_in_bytes == 16, "TSInput.encoding has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSInput.encoding has unexpected size % instead of 4", it.type.runtime_size);
                case "decode";
                    assert(it.offset_in_bytes == 24, "TSInput.decode has unexpected offset % instead of 24", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSInput.decode has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(TSInput) == 32, "TSInput has size % instead of 32", size_of(TSInput));
    }

    {
        info := type_info(TSParseState);
        for info.members {
            if it.name == {
                case "payload";
                    assert(it.offset_in_bytes == 0, "TSParseState.payload has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSParseState.payload has unexpected size % instead of 8", it.type.runtime_size);
                case "current_byte_offset";
                    assert(it.offset_in_bytes == 8, "TSParseState.current_byte_offset has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSParseState.current_byte_offset has unexpected size % instead of 4", it.type.runtime_size);
                case "has_error";
                    assert(it.offset_in_bytes == 12, "TSParseState.has_error has unexpected offset % instead of 12", it.offset_in_bytes);
                    assert(it.type.runtime_size == 1, "TSParseState.has_error has unexpected size % instead of 1", it.type.runtime_size);
            }
        }
        assert(size_of(TSParseState) == 16, "TSParseState has size % instead of 16", size_of(TSParseState));
    }

    {
        info := type_info(TSParseOptions);
        for info.members {
            if it.name == {
                case "payload";
                    assert(it.offset_in_bytes == 0, "TSParseOptions.payload has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSParseOptions.payload has unexpected size % instead of 8", it.type.runtime_size);
                case "progress_callback";
                    assert(it.offset_in_bytes == 8, "TSParseOptions.progress_callback has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSParseOptions.progress_callback has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(TSParseOptions) == 16, "TSParseOptions has size % instead of 16", size_of(TSParseOptions));
    }

    {
        info := type_info(TSLogger);
        for info.members {
            if it.name == {
                case "payload";
                    assert(it.offset_in_bytes == 0, "TSLogger.payload has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSLogger.payload has unexpected size % instead of 8", it.type.runtime_size);
                case "log";
                    assert(it.offset_in_bytes == 8, "TSLogger.log has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSLogger.log has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(TSLogger) == 16, "TSLogger has size % instead of 16", size_of(TSLogger));
    }

    {
        info := type_info(TSInputEdit);
        for info.members {
            if it.name == {
                case "start_byte";
                    assert(it.offset_in_bytes == 0, "TSInputEdit.start_byte has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSInputEdit.start_byte has unexpected size % instead of 4", it.type.runtime_size);
                case "old_end_byte";
                    assert(it.offset_in_bytes == 4, "TSInputEdit.old_end_byte has unexpected offset % instead of 4", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSInputEdit.old_end_byte has unexpected size % instead of 4", it.type.runtime_size);
                case "new_end_byte";
                    assert(it.offset_in_bytes == 8, "TSInputEdit.new_end_byte has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSInputEdit.new_end_byte has unexpected size % instead of 4", it.type.runtime_size);
                case "start_point";
                    assert(it.offset_in_bytes == 12, "TSInputEdit.start_point has unexpected offset % instead of 12", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSInputEdit.start_point has unexpected size % instead of 8", it.type.runtime_size);
                case "old_end_point";
                    assert(it.offset_in_bytes == 20, "TSInputEdit.old_end_point has unexpected offset % instead of 20", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSInputEdit.old_end_point has unexpected size % instead of 8", it.type.runtime_size);
                case "new_end_point";
                    assert(it.offset_in_bytes == 28, "TSInputEdit.new_end_point has unexpected offset % instead of 28", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSInputEdit.new_end_point has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(TSInputEdit) == 36, "TSInputEdit has size % instead of 36", size_of(TSInputEdit));
    }

    {
        info := type_info(TSNode);
        for info.members {
            if it.name == {
                case "_context";
                    assert(it.offset_in_bytes == 0, "TSNode._context has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 16, "TSNode._context has unexpected size % instead of 16", it.type.runtime_size);
                case "id";
                    assert(it.offset_in_bytes == 16, "TSNode.id has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSNode.id has unexpected size % instead of 8", it.type.runtime_size);
                case "tree";
                    assert(it.offset_in_bytes == 24, "TSNode.tree has unexpected offset % instead of 24", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSNode.tree has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(TSNode) == 32, "TSNode has size % instead of 32", size_of(TSNode));
    }

    {
        info := type_info(TSTreeCursor);
        for info.members {
            if it.name == {
                case "tree";
                    assert(it.offset_in_bytes == 0, "TSTreeCursor.tree has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSTreeCursor.tree has unexpected size % instead of 8", it.type.runtime_size);
                case "id";
                    assert(it.offset_in_bytes == 8, "TSTreeCursor.id has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSTreeCursor.id has unexpected size % instead of 8", it.type.runtime_size);
                case "_context";
                    assert(it.offset_in_bytes == 16, "TSTreeCursor._context has unexpected offset % instead of 16", it.offset_in_bytes);
                    assert(it.type.runtime_size == 12, "TSTreeCursor._context has unexpected size % instead of 12", it.type.runtime_size);
            }
        }
        assert(size_of(TSTreeCursor) == 32, "TSTreeCursor has size % instead of 32", size_of(TSTreeCursor));
    }

    {
        info := type_info(TSQueryCapture);
        for info.members {
            if it.name == {
                case "node";
                    assert(it.offset_in_bytes == 0, "TSQueryCapture.node has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 32, "TSQueryCapture.node has unexpected size % instead of 32", it.type.runtime_size);
                case "index";
                    assert(it.offset_in_bytes == 32, "TSQueryCapture.index has unexpected offset % instead of 32", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSQueryCapture.index has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(TSQueryCapture) == 40, "TSQueryCapture has size % instead of 40", size_of(TSQueryCapture));
    }

    {
        info := type_info(TSQueryMatch);
        for info.members {
            if it.name == {
                case "id";
                    assert(it.offset_in_bytes == 0, "TSQueryMatch.id has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSQueryMatch.id has unexpected size % instead of 4", it.type.runtime_size);
                case "pattern_index";
                    assert(it.offset_in_bytes == 4, "TSQueryMatch.pattern_index has unexpected offset % instead of 4", it.offset_in_bytes);
                    assert(it.type.runtime_size == 2, "TSQueryMatch.pattern_index has unexpected size % instead of 2", it.type.runtime_size);
                case "capture_count";
                    assert(it.offset_in_bytes == 6, "TSQueryMatch.capture_count has unexpected offset % instead of 6", it.offset_in_bytes);
                    assert(it.type.runtime_size == 2, "TSQueryMatch.capture_count has unexpected size % instead of 2", it.type.runtime_size);
                case "captures";
                    assert(it.offset_in_bytes == 8, "TSQueryMatch.captures has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSQueryMatch.captures has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(TSQueryMatch) == 16, "TSQueryMatch has size % instead of 16", size_of(TSQueryMatch));
    }

    {
        info := type_info(TSQueryPredicateStep);
        for info.members {
            if it.name == {
                case "type";
                    assert(it.offset_in_bytes == 0, "TSQueryPredicateStep.type has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSQueryPredicateStep.type has unexpected size % instead of 4", it.type.runtime_size);
                case "value_id";
                    assert(it.offset_in_bytes == 4, "TSQueryPredicateStep.value_id has unexpected offset % instead of 4", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSQueryPredicateStep.value_id has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(TSQueryPredicateStep) == 8, "TSQueryPredicateStep has size % instead of 8", size_of(TSQueryPredicateStep));
    }

    {
        info := type_info(TSQueryCursorState);
        for info.members {
            if it.name == {
                case "payload";
                    assert(it.offset_in_bytes == 0, "TSQueryCursorState.payload has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSQueryCursorState.payload has unexpected size % instead of 8", it.type.runtime_size);
                case "current_byte_offset";
                    assert(it.offset_in_bytes == 8, "TSQueryCursorState.current_byte_offset has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSQueryCursorState.current_byte_offset has unexpected size % instead of 4", it.type.runtime_size);
            }
        }
        assert(size_of(TSQueryCursorState) == 16, "TSQueryCursorState has size % instead of 16", size_of(TSQueryCursorState));
    }

    {
        info := type_info(TSQueryCursorOptions);
        for info.members {
            if it.name == {
                case "payload";
                    assert(it.offset_in_bytes == 0, "TSQueryCursorOptions.payload has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSQueryCursorOptions.payload has unexpected size % instead of 8", it.type.runtime_size);
                case "progress_callback";
                    assert(it.offset_in_bytes == 8, "TSQueryCursorOptions.progress_callback has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSQueryCursorOptions.progress_callback has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(TSQueryCursorOptions) == 16, "TSQueryCursorOptions has size % instead of 16", size_of(TSQueryCursorOptions));
    }

    {
        info := type_info(TSLanguageMetadata);
        for info.members {
            if it.name == {
                case "major_version";
                    assert(it.offset_in_bytes == 0, "TSLanguageMetadata.major_version has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 1, "TSLanguageMetadata.major_version has unexpected size % instead of 1", it.type.runtime_size);
                case "minor_version";
                    assert(it.offset_in_bytes == 1, "TSLanguageMetadata.minor_version has unexpected offset % instead of 1", it.offset_in_bytes);
                    assert(it.type.runtime_size == 1, "TSLanguageMetadata.minor_version has unexpected size % instead of 1", it.type.runtime_size);
                case "patch_version";
                    assert(it.offset_in_bytes == 2, "TSLanguageMetadata.patch_version has unexpected offset % instead of 2", it.offset_in_bytes);
                    assert(it.type.runtime_size == 1, "TSLanguageMetadata.patch_version has unexpected size % instead of 1", it.type.runtime_size);
            }
        }
        assert(size_of(TSLanguageMetadata) == 3, "TSLanguageMetadata has size % instead of 3", size_of(TSLanguageMetadata));
    }

    {
        info := type_info(TSWasmError);
        for info.members {
            if it.name == {
                case "kind";
                    assert(it.offset_in_bytes == 0, "TSWasmError.kind has unexpected offset % instead of 0", it.offset_in_bytes);
                    assert(it.type.runtime_size == 4, "TSWasmError.kind has unexpected size % instead of 4", it.type.runtime_size);
                case "message";
                    assert(it.offset_in_bytes == 8, "TSWasmError.message has unexpected offset % instead of 8", it.offset_in_bytes);
                    assert(it.type.runtime_size == 8, "TSWasmError.message has unexpected size % instead of 8", it.type.runtime_size);
            }
        }
        assert(size_of(TSWasmError) == 16, "TSWasmError has size % instead of 16", size_of(TSWasmError));
    }
}

