
// @todo explain what this data structure is and some context for how it works

Document :: struct {
	// all the actual text in the document goes into document memory
	// such that it'll never have to be moved as we reserve loads of address space
	// All the supporting data such as the piece chain and line start arrays go in
	// pieceChainMemory
	documentMemory: Flat_Pool;
	pieceChainMemory: Flat_Pool;
	documentAlloc: Allocator;
	pieceChainAlloc : Allocator;

	originalData: Buffer;
	addedData: Buffer;

	pieceChainHead: *PieceChainNode;
	pieceChainTail: *PieceChainNode;
	
	// @todo: this should be a tree at some point
	// @todo: undo stack items should know whether
	// they are saved to disk, to update the unsaved status of the file
	undoStack: [..]PieceChainSpan;
	redoStack: [..]PieceChainSpan;

	locator: Bucket_Locator;
	size: s64;
	lineEndings: LineEndingMode;
	path: string;
	addedBufferEnd: Coordinate;
	unsaved: bool;
	lastDeletionOffset: s64;
}

DocumentCursor :: struct {
	doc: *Document;
	node: *PieceChainNode;
	documentOffset: s64;
	// these are both document relative
	// they are the document coordinates at the start of the current node
	nodeStartOffset: s64;
	nodeStartLine: s64;
}

DocumentRange :: struct {
	start: DocumentCursor;
	end: DocumentCursor;
}

Coordinate :: struct {
	line: s64;
	col: s64;
}

Buffer :: struct {
	text: []u8;
	lineStarts: [..]s64;
}

LineEndingMode :: enum {
	LF;
	CRLF;
	MIXED_MAJORITY_LF;
	MIXED_MAJORITY_CRLF;
}

PieceChainNode :: struct {
	next: *PieceChainNode;
	prev: *PieceChainNode;

	added: bool;
	start: Coordinate;
	end: Coordinate;
	length: s64;
	lineFeedCount: s64;
}

PieceChainSpan :: struct {
	first: *PieceChainNode;
	last: *PieceChainNode;
	boundary: bool;
	documentOffset: s64;
	documentSize: s64;
	size: s64;
}

open_documents: Bucket_Array(Document, 128); // might want more when we load full projects in?
open_document_table: Table(string, Bucket_Locator);

document_open :: (path: string) -> *Document {
	// check if this file is already open
	existinglocator, success := table_find(*open_document_table, path);
	if success {
		bucket := open_documents.all_buckets[existinglocator.bucket_index];
		assert(bucket.occupied[existinglocator.slot_index] == true);
		return *bucket.data[existinglocator.slot_index];
	}

	doc, locator := find_and_occupy_empty_slot(*open_documents);

	doc.documentMemory.alignment = 1;
	doc.documentAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *doc.documentMemory };
	doc.pieceChainAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *doc.pieceChainMemory };

	if is_absolute_path(path) {
		doc.path = copy_string(path);
	}
	else {
		doc.path = copy_string(get_absolute_path(path));
	}
	path_overwrite_separators(doc.path, #char "/");

	doc.locator = locator;
	table_add(*open_document_table, doc.path, doc.locator); 

	document_load_from_disk(doc);

	// add to file watcher
	parentPath := path_strip_filename(doc.path);
	if parentPath.count > 1 && parentPath[parentPath.count-1] == #char "/" then parentPath.count -= 1;
	add_directories(*watcher, parentPath);
	array_add_if_unique(*watchedFiles, doc.path);

	push_notification("Document Opened");
	return doc;
}

document_load_from_disk :: (doc: *Document) {
	// if this fails, we have not reset any memory yet, so the existing document will persist in memory
	f, success := file_open(doc.path);
	if !success {
		push_notification("File open failed");
		return;
	}

	// if the file read fails, we must leave the document in a valid state with no content, so intialize it as such
	doc.pieceChainHead = New(PieceChainNode,, doc.pieceChainAlloc);
	doc.pieceChainTail = New(PieceChainNode,, doc.pieceChainAlloc);
	doc.pieceChainHead.next = doc.pieceChainTail;
	doc.pieceChainTail.prev = doc.pieceChainHead;
	doc.size = 0;
	doc.unsaved = false;
	doc.lastDeletionOffset = 0;
	array_reset(*doc.undoStack);
	array_reset(*doc.redoStack);
	array_reset(*doc.originalData.lineStarts);
	array_reset(*doc.addedData.lineStarts);
	reset(*doc.documentMemory, overwrite_memory=true);
	reset(*doc.pieceChainMemory, overwrite_memory=true);

	fileSize := file_length(f);
	if (fileSize > (256*1024*1024)) {
		// this is a large file, so reserve space for the file plus 30% for additions
		init(*doc.documentMemory, cast(int)(fileSize * 1.3));
		// @todo: better heuristic for guessing how much space you need for line endings and the piece chain
		init(*doc.pieceChainMemory, 512 * 1024 * 1024);
	}

	// now actually read in the file data
	file: string;
    file, success = read_entire_file(f,,doc.documentAlloc);
	if !success {
		push_notification("File read failed");
		return;
	}
	file_close(*f);

	doc.size = file.count;
	doc.unsaved = false;

	// setup original data buffer
	doc.originalData.text.data = file.data;
	doc.originalData.text.count = file.count;

	// find and count linestarts
	doc.originalData.lineStarts.allocator = doc.pieceChainAlloc;
	array_add(*doc.originalData.lineStarts, 0);
	lfCount := 0;
	crCount := 0;
	crlfCount := 0;
	i := 0;
	while i < doc.originalData.text.count {
		byte := doc.originalData.text[i];
		if byte == #char "\r" {
			if i < file.count-1 && doc.originalData.text[i+1] == #char "\n" {
				crlfCount += 1;
				array_add(*doc.originalData.lineStarts, xx (i+2));
				i += 1; // skip \n
			}
			else {
				crCount += 1;
			}
		}
		else if byte == #char "\n" {
			lfCount += 1;
			array_add(*doc.originalData.lineStarts, xx (i+1));
		}
		i += 1;
	}
	if lfCount > 0 && crlfCount == 0 && crCount == 0 {
		doc.lineEndings = .LF;
	}
	else if lfCount == 0 && crlfCount > 0 && crCount == 0 {
		doc.lineEndings = .CRLF;
	}
	else if lfCount > 0 && crlfCount > 0 && crCount == 0 {
		if lfCount > crlfCount {
			doc.lineEndings = .MIXED_MAJORITY_LF;
		}
		else {
			doc.lineEndings = .MIXED_MAJORITY_CRLF;
		}
	}
	else if crCount > 0 {
		push_notification("File has CR line endings, undefined behaviour will occur");
	}

	// setup added data buffer
	doc.addedData.text.data = file.data + file.count;
	doc.addedData.lineStarts.allocator = doc.pieceChainAlloc;
	array_add(*doc.addedData.lineStarts, 0);
	doc.addedBufferEnd = Coordinate.{0,0};
	doc.lastDeletionOffset = -1;

	// setup undo stack
	doc.undoStack.allocator = doc.pieceChainAlloc;
	doc.redoStack.allocator = doc.pieceChainAlloc;

	// create the nill head/tail nodes (means we never have to null check the prev/next ptrs)
	doc.pieceChainHead = New(PieceChainNode,, doc.pieceChainAlloc);
	doc.pieceChainTail = New(PieceChainNode,, doc.pieceChainAlloc);

	// create the main node of the piece chain
	node := New(PieceChainNode,, doc.pieceChainAlloc);
	node.start = Coordinate.{0,0}; 
	node.end = Coordinate.{
		doc.originalData.lineStarts.count - 1,
		doc.originalData.text.count - doc.originalData.lineStarts[doc.originalData.lineStarts.count - 1]}; 
	node.length = doc.originalData.text.count; 
	node.lineFeedCount = doc.originalData.lineStarts.count-1; 
	node.added = false;

	// place the main node into the linked list
	doc.pieceChainHead.next = node;
	node.prev = doc.pieceChainHead;
	node.next = doc.pieceChainTail;
	doc.pieceChainTail.prev = node;
}

document_close :: (doc: *Document) {
	array_unordered_remove_by_value(*watchedFiles, doc.path);

	table_remove(*open_document_table, doc.path);
	locator := doc.locator;

	free(doc.path);
	fini(*doc.documentMemory);
	fini(*doc.pieceChainMemory);
	initializer_of(Document)(doc);

	bucket_array_remove(*open_documents, locator);
}

document_save :: (doc: *Document, path: string, backup := false) {
	if doc.lineEndings == .MIXED_MAJORITY_LF {
		document_normalize_line_endings(doc, .LF);
	}
	else if doc.lineEndings == .MIXED_MAJORITY_CRLF {
		document_normalize_line_endings(doc, .CRLF);
	}

	directory_make_success := make_directory_if_it_does_not_exist(path_strip_filename(path), recursive = true);
    if !directory_make_success push_notification("Failed to make directory for file save");

	fileHandle, success := file_open(path, true, false);
	if success {
		cursor: DocumentCursor;
		cursor.doc = doc;
		cursor.node = doc.pieceChainHead;

		while cursor.node != null {
			buffer: = ifx cursor.node.added then *cursor.doc.addedData else *cursor.doc.originalData;
			bufferStartOffset := buffer_cursor_to_offset(buffer, cursor.node.start);

			success := file_write(*fileHandle, buffer.text.data + bufferStartOffset, cursor.node.length);

			// move cursor to next node
			cursor.documentOffset += cursor.node.length;
			cursor.nodeStartOffset += cursor.node.length;
			cursor.nodeStartLine += cursor.node.lineFeedCount;
			cursor.node = cursor.node.next;
		}

		file_close(*fileHandle);
	}
	else {
		push_notification("Failed to save file");
	}
	if !backup {
		doc.path = copy_string(path,,doc.documentAlloc);
		doc.unsaved = false;
		push_notification("Document Saved");
	}
	else {
		push_notification("Backup Saved");
	}
}

document_get_by_path :: (path: string) -> bool, *Document {
	locator, success := table_find(*open_document_table, path);
	if success {
		bucket := open_documents.all_buckets[locator.bucket_index];
		assert(bucket.occupied[locator.slot_index] == true);
		result := *bucket.data[locator.slot_index];
		return true, result;
	}
	return false, null;
}

document_insert_text :: (doc: *Document, at: DocumentCursor, t: string) -> DocumentCursor {
	if t.count == 0 return at;

	doc.unsaved = true;
	// actually add the new text to a buffer, updating linestarts and what not
	text := copy_string(t,, doc.documentAlloc);
	currentBufferEnd := doc.addedData.text.count;
	doc.addedData.text.count = doc.addedData.text.count + text.count;
	for byte, i: text {
		if byte == #char "\n" {
			array_add(*doc.addedData.lineStarts, xx (currentBufferEnd + i + 1));
		}
	}
	doc.size += text.count;

	insertBuffer: = ifx at.node.added then *doc.addedData else *doc.originalData;
	insertPos := buffer_offset_to_cursor(insertBuffer, at.node, at.documentOffset - at.nodeStartOffset);

	newspan: PieceChainSpan;

	array_reset_keeping_memory(*doc.redoStack);

	if insertPos == at.node.end || insertPos == at.node.start {
		// case 1: insert at boundary

		// bonus case, this node is the last insert node
		// you can just add more to the mod buffer and increase the node length
		if at.node.added == true && at.node.end == doc.addedBufferEnd {
			endOffset := doc.addedData.text.count;
			endLine := doc.addedData.lineStarts.count - 1;
			endColumn := endOffset - doc.addedData.lineStarts[endLine];
			at.node.length = at.node.length + text.count;
			at.node.end = Coordinate.{endLine, endColumn};
			at.node.lineFeedCount = buffer_line_start_count(at.node.start, at.node.end);
			doc.addedBufferEnd = at.node.end;

			lastundo := *doc.undoStack[doc.undoStack.count-1];
			lastundo.size += text.count;
			lastundo.documentSize += text.count;
			return at;
		}

		newCursor: DocumentCursor;
		oldspan := new_undo_event(doc, doc.size-text.count, at.documentOffset, text.count);

		if insertPos == at.node.end {
			span_boundary(oldspan, at.node, at.node.next);
			// place the new cursor at the end of the new node
			newCursor.nodeStartOffset = at.nodeStartOffset + at.node.length;
			newCursor.nodeStartLine = at.nodeStartLine + at.node.lineFeedCount;
		}
		else {
			span_boundary(oldspan, at.node.prev, at.node);
			// place the new cursor at the start of the new node
			newCursor.nodeStartOffset = at.nodeStartOffset;
			newCursor.nodeStartLine = at.nodeStartLine;
		}
		
		// make new piece
		endOffset := doc.addedData.text.count;
		endLine := doc.addedData.lineStarts.count - 1;
		endColumn := endOffset - doc.addedData.lineStarts[endLine];
		newPiece := New(PieceChainNode,, doc.pieceChainAlloc);
		newPiece.added = true;
		newPiece.start = doc.addedBufferEnd;
		newPiece.end = Coordinate.{endLine, endColumn};
		newPiece.length = text.count;
		newPiece.lineFeedCount = buffer_line_start_count(newPiece.start, newPiece.end);
		span_append(*newspan, newPiece);

		// actually make the edit to the linked list
		swap_spans(oldspan, *newspan);

		doc.addedBufferEnd = newPiece.end;

		// we return a new cursor that is in the same document location
		// but now points to the new node
		newCursor.doc = at.doc;
		newCursor.node = newPiece;
		newCursor.documentOffset = at.documentOffset;
		return newCursor;
	}
	else {
		// case 2: splitting a node
		oldspan := new_undo_event(doc, doc.size-text.count, at.documentOffset, text.count);
		span_append(oldspan, at.node);

		// copy the old node and then trim left and right to get the new nodes

		// Make a piece for the left split of the current node
		newPieceLeft := New(PieceChainNode,, doc.pieceChainAlloc);
		<<newPieceLeft = <<at.node;
		node_trim_right(newPieceLeft, insertBuffer, insertPos);
		span_append(*newspan, newPieceLeft);

		// Make a new piece for the added data in the middle
		endOffset := doc.addedData.text.count;
		endLine := doc.addedData.lineStarts.count - 1;
		endColumn := endOffset - doc.addedData.lineStarts[endLine];
		newPiece := New(PieceChainNode,, doc.pieceChainAlloc);
		newPiece.added = true;
		newPiece.start = doc.addedBufferEnd;
		newPiece.end = Coordinate.{endLine, endColumn};
		newPiece.length = text.count;
		newPiece.lineFeedCount = buffer_line_start_count(newPiece.start, newPiece.end);
		span_append(*newspan, newPiece);

		// Make a new piece for the right split of the current node
		newPieceRight := New(PieceChainNode,, doc.pieceChainAlloc);
		<<newPieceRight = <<at.node;
		node_trim_left(newPieceRight, insertBuffer, insertPos);
		span_append(*newspan, newPieceRight);

		// actually edit the linked list
		swap_spans(oldspan, *newspan);

		// update last insert cursor
		doc.addedBufferEnd = newPiece.end;

		// we return a new cursor that is in the same document location
		// but now points to the new node
		newCursor: DocumentCursor;
		newCursor.doc = at.doc;
		newCursor.node = newPiece;
		newCursor.nodeStartOffset = at.nodeStartOffset + newPieceLeft.length;
		newCursor.nodeStartLine = at.nodeStartLine + newPieceLeft.lineFeedCount; 
		newCursor.documentOffset = at.documentOffset;
		return newCursor;
	}
}

document_delete_text :: (doc: *Document, startAt: DocumentCursor, endAt: DocumentCursor) -> DocumentCursor {
	doc.unsaved = true;
	startBuffer: = ifx startAt.node.added then *doc.addedData else *doc.originalData;
	endBuffer: = ifx endAt.node.added then *doc.addedData else *doc.originalData;

	start := buffer_offset_to_cursor(startBuffer, startAt.node, startAt.documentOffset - startAt.nodeStartOffset);
	end := buffer_offset_to_cursor(endBuffer, endAt.node, endAt.documentOffset - endAt.nodeStartOffset);
	count := endAt.documentOffset - startAt.documentOffset;
	if count == 0 return startAt;

	doc.size -= count;

	newCursor: DocumentCursor;
	newCursor.doc = doc;
	newCursor.documentOffset = startAt.documentOffset;

	array_reset_keeping_memory(*doc.redoStack);

	toRemove := count;
	removeOffsetInNode := startAt.documentOffset - startAt.nodeStartOffset;

	// special case: The last deletion was at this location and we want to backward delete (backspace key)
	if end == endAt.node.end && doc.lastDeletionOffset == endAt.documentOffset {
		if count < endAt.node.length {
			// we'll just reduce the size of the left node
			endAt.node.length -= count;
			endAt.node.end = buffer_offset_to_cursor(endBuffer, endAt.node, (endAt.documentOffset - endAt.nodeStartOffset) - count); 
			endAt.node.lineFeedCount = buffer_line_start_count(endAt.node.start, endAt.node.end);

			// endAt and startAt are the same in this case, so we leave you at the end of said node
			newCursor.node = endAt.node;
			newCursor.nodeStartOffset = endAt.nodeStartOffset;
			newCursor.nodeStartLine = endAt.nodeStartLine;

			doc.lastDeletionOffset = startAt.documentOffset;

			lastundo := *doc.undoStack[doc.undoStack.count-1];
			lastundo.size -= count;
			lastundo.documentSize -= count;
			return newCursor;
		}
	}

	// General case
	newspan: PieceChainSpan;
	newspan.boundary = true; // by default we insert nothing
	oldspan := new_undo_event(doc, doc.size+count, startAt.documentOffset, -count);

	node := startAt.node;
	doc.lastDeletionOffset = startAt.documentOffset;

	// Deletion starts midway through the start node
	if removeOffsetInNode != 0 {
		newPieceLeft := New(PieceChainNode,, doc.pieceChainAlloc);
		<<newPieceLeft = <<node;
		node_trim_right(newPieceLeft, startBuffer, start);
		span_append(*newspan, newPieceLeft);

		newCursor.node = newPieceLeft;
		newCursor.nodeStartOffset = startAt.nodeStartOffset;
		newCursor.nodeStartLine = startAt.nodeStartLine;

		// is the deletion entirely contained in this node? In which case you will need to split the node
		// by making a right side piece with the remainder of the deletion
		if removeOffsetInNode + toRemove < startAt.node.length {
			newPieceRight := New(PieceChainNode,, doc.pieceChainAlloc);
			<<newPieceRight = <<node;
			node_trim_left(newPieceRight, startBuffer, end);
			span_append(*newspan, newPieceRight);
		}

		span_append(oldspan, node);
		toRemove -= min(toRemove, node.length - removeOffsetInNode);
		node = node.next;
	}
	else {
		// all of the start node will be removed
		// place the cursor at the previous node which will remain untouched
		newCursor.node = startAt.node.prev;
		newCursor.nodeStartOffset = startAt.nodeStartOffset - startAt.node.prev.length;
		newCursor.nodeStartLine = startAt.nodeStartLine - startAt.node.prev.lineFeedCount;
	}

	// remove all nodes until you have removed the required amount of bytes
	while (toRemove > 0 && node != doc.pieceChainTail) {
		buffer : *Buffer;
		ifx node.added then buffer = *doc.addedData else buffer = *doc.originalData;

		if (toRemove < node.length) {
			// The deletion ends in this node, so split it
			newPieceRight := New(PieceChainNode,, doc.pieceChainAlloc);
			<<newPieceRight = <<node;
			node_trim_left(newPieceRight, buffer, end);
			span_append(*newspan, newPieceRight);
		}
		// if removelen is less than a node, the left side of the node will be trimmed and removed
		toRemove -= min(toRemove, node.length);
		span_append(oldspan, node);
		node = node.next;
	}

	// actually perform the edit to the chain
	swap_spans(oldspan, *newspan);

	return newCursor;
}

document_undo :: (doc: *Document, cursor: DocumentCursor) -> DocumentCursor {
	if doc.undoStack.count == 0 {
		push_notification("Undo history empty");
		return cursor;
	}
	span := pop(*doc.undoStack);
	cursorOffset := span.documentOffset;
	restore_span(doc, *span);
	array_add(*doc.redoStack, span);

	return document_create_cursor(doc, cursorOffset); 
}

document_redo :: (doc: *Document, cursor: DocumentCursor) -> DocumentCursor  {
	if doc.redoStack.count == 0 {
		push_notification("Redo history empty");
		return cursor;
	}
	span := pop(*doc.redoStack);
	cursorOffset := span.documentOffset;
	restore_span(doc, *span);
	array_add(*doc.undoStack, span);

	return document_create_cursor(doc, cursorOffset); 
}

document_get_line_content :: (doc: *Document, lineNum: s64) -> string {
	builder: String_Builder;
	builder.allocator = temp;

	// @todo: potential optimization here is to cache the last visited nodes
	// and then search nearby, such that you can skip iterating all nodes for local queries of line content

	// additionally you can cache the last queried line, under the assumption that there
	// will be repeated queries for the line the cursor is currently sat on


	// lets optimize using document cursors
	// You don't need to do any initial searching since the cursor is where you want to be
	// Use the iterator to iterate single chars from the cursor until you hit a newline sequence
	// copy each one and that's basically all you need to do

	// another alternative is using a similar strategy to the jump to functions
	// calculate the document coordinates at the end of the cursor node
	// if the line end is less than that, then copy the whole line
	// if it's past that, then copy up to end of buffer, and go to next node
	// then repeat, if end is in this node, copy up to that, otherwise go to end of node

	// since lineNum is 0 indexed, if you give line 0, there is "1" line remaining to find
	linesRemaining := lineNum;
	node: *PieceChainNode = doc.pieceChainHead;

	while node != null {
		buffer : *Buffer;
		ifx node.added then buffer = *doc.addedData else buffer = *doc.originalData;

		if linesRemaining == 0 {
			// line has been found, so we're looking for the rest of it
			if node.lineFeedCount == 0 {
				// the line does not end here, so copy the whole node
				startOffset:= buffer_cursor_to_offset(buffer, node.start);
				endOffset := buffer_cursor_to_offset(buffer, node.end);
				append(*builder, buffer.text.data + startOffset, endOffset - startOffset);
			}
			else {
				// the line ends here, so copy up to the first line
				startOffset:= buffer_cursor_to_offset(buffer, node.start);
				endOffset := buffer_cursor_to_offset(buffer, .{node.start.line+1, 0});
				append(*builder, buffer.text.data + startOffset, endOffset - startOffset);
				break;
			}
			node = node.next;

		}
		else if linesRemaining < node.lineFeedCount {
			// the line must start and end in this node
			startOffset:= buffer_cursor_to_offset(buffer, .{node.start.line + linesRemaining, 0});
			endOffset := buffer_cursor_to_offset(buffer, .{node.start.line + linesRemaining + 1, 0});
			append(*builder, buffer.text.data + startOffset, endOffset - startOffset);
			node = node.next;
			break;
		}
		else if linesRemaining == node.lineFeedCount {
			// the line starts in this node, but does not end here (potentially the document ends too)
			startOffset:= buffer_cursor_to_offset(buffer, .{node.start.line + linesRemaining, 0});
			endOffset := buffer_cursor_to_offset(buffer, node.end);
			append(*builder, buffer.text.data + startOffset, endOffset - startOffset);
			linesRemaining -= node.lineFeedCount;
			node = node.next;
		}
		else {
			// the line is past this node so skip it
			linesRemaining -= node.lineFeedCount;
			node = node.next;
		}

	}

	return builder_to_string(*builder,,temp);
}

document_create_cursor :: (document: *Document, startOffset: s64 = 0) -> DocumentCursor {
	newCursor : DocumentCursor;
	newCursor.doc = document;
	newCursor.node = document.pieceChainHead;
	if startOffset != 0 {
		document_cursor_jump_to_offset(*newCursor, startOffset);
	}
	return newCursor;
}

document_cursor_jump_to_offset :: (cursor: *DocumentCursor, offset: s64) {
	if offset == cursor.documentOffset return;

	nodeStartOffset: s64 = cursor.nodeStartOffset;
	nodeStartLine: s64 = cursor.nodeStartLine;

	direction := ifx offset < cursor.documentOffset then -1 else 1;

	// now we loop through nodes in the desired direction
	node := cursor.node;
	while node != null {
		// we now calculate the document end coordinates
		nodeEndOffset: s64 = nodeStartOffset + node.length;
		nodeEndLine: s64 = nodeStartLine + node.lineFeedCount;

		if (offset > nodeStartOffset && offset <= nodeEndOffset) || (offset == 0 && node.prev == null) {
			// the target offset is inside this node
			cursor.node = node;
			cursor.documentOffset = offset;
			cursor.nodeStartOffset = nodeStartOffset;
			cursor.nodeStartLine = nodeStartLine;
			return;
		}

		// if this is not the desired node, update the start position and move on to next node
		if direction > 0 {
			nodeStartOffset = nodeEndOffset;
			nodeStartLine = nodeEndLine;
			node = node.next;
		}
		else {
			node = node.prev;
			nodeStartOffset = nodeStartOffset - node.length;
			nodeStartLine = nodeStartLine - node.lineFeedCount;
		}
	}
}


document_cursor_step_one_forward :: (cursor: *DocumentCursor, skipReturns := false) -> u8 {
	buffer: = ifx cursor.node.added then *cursor.doc.addedData else *cursor.doc.originalData;
	offsetInNode := cursor.documentOffset - cursor.nodeStartOffset;

	if offsetInNode >= cursor.node.length && cursor.node.next == null {
		return 0; // end of document
	}

	if offsetInNode >= cursor.node.length {
		// we're about to overflow into the next node
		cursor.nodeStartOffset += cursor.node.length;
		cursor.nodeStartLine += cursor.node.lineFeedCount;
		cursor.node = cursor.node.next;
		offsetInNode = 0;
		buffer = ifx cursor.node.added then *cursor.doc.addedData else *cursor.doc.originalData;
	}

	// read the character in the current location before we step to the next location
	bufferOffset := buffer_cursor_to_offset(buffer, cursor.node.start) + offsetInNode;
	character := buffer.text[bufferOffset];

	cursor.documentOffset += 1;

	// CRLF handling, skip over the return, pretending it's not there
	if skipReturns && character == #char "\r" {
		return document_cursor_step_one_forward(cursor);
	}
	return character;
}

document_cursor_step_one_backward :: (cursor: *DocumentCursor, skipReturns := false) -> u8 {
	cursor.documentOffset -= 1;
	buffer: = ifx cursor.node.added then *cursor.doc.addedData else *cursor.doc.originalData;
	offsetInNode := cursor.documentOffset - cursor.nodeStartOffset;
	
	if offsetInNode <= 0 && cursor.node.prev == null {
		cursor.documentOffset = 0;
		return 0; // start of document
	}

	if offsetInNode < 0 {
		// we're about to underflow to the previous node
		cursor.nodeStartOffset -= cursor.node.prev.length;
		cursor.nodeStartLine -= cursor.node.prev.lineFeedCount;
		cursor.node = cursor.node.prev;
		offsetInNode = cursor.node.length-1;
		buffer = ifx cursor.node.added then *cursor.doc.addedData else *cursor.doc.originalData;
	}

	bufferOffset := buffer_cursor_to_offset(buffer, cursor.node.start) + offsetInNode;
	character := buffer.text[bufferOffset];

	// CRLF handling, skip over the return, pretending it's not there
	if skipReturns && character == #char "\n" {
		newChar := document_cursor_step_one_backward(cursor);
		if newChar == #char "\r" {
			return character;
		}
		else {
			// if no CRLF ending, just undo what we did
			return document_cursor_step_one_forward(cursor);
		}
	}

	return character;
}

for_expansion :: (cursor: *DocumentCursor, body: Code, flags: For_Flags) #expand {
	counter := 0;
	while cursor.documentOffset <= cursor.doc.size {
		// this tells you how far you've iterated since the start
		`it_index := counter;
		`it := ifx flags & .REVERSE then document_cursor_step_one_backward(cursor) else document_cursor_step_one_forward(cursor);
		#insert body;
		counter += 1;
		if cursor.documentOffset == 0 then break;
		if cursor.documentOffset == cursor.doc.size then break;
	}
}

skip_returns :: (cursor: *DocumentCursor, body: Code, flags: For_Flags) #expand {
	counter := 0;
	while cursor.documentOffset <= cursor.doc.size {
		// this tells you how far you've iterated since the start
		`it_index := counter;
		`it := ifx flags & .REVERSE then document_cursor_step_one_backward(cursor, true) else document_cursor_step_one_forward(cursor, true);
		#insert body;
		counter += 1;
		if cursor.documentOffset == 0 then break;
		if cursor.documentOffset == cursor.doc.size then break;
	}
}

document_cursor_get_line :: (cursor: *DocumentCursor) -> s64 {
	// convert the offset to a buffer coordinate, add that to the start line
	buffer: = ifx cursor.node.added then *cursor.doc.addedData else *cursor.doc.originalData;
	bufferCursor := buffer_offset_to_cursor(buffer, cursor.node, cursor.documentOffset - cursor.nodeStartOffset);
	return cursor.nodeStartLine + (bufferCursor.line - cursor.node.start.line);
}

document_get_line_start :: (doc: *Document, line: s64) -> s64 {
	// this function is used a lot for navigating lines
	// if there was ever a function that made me want to use trees, this is the one
	// however I will resist the temptation to overcomplicate things and allow this to exist
	// until I have an actual performance issue on my hands

	// my prediction is that this algorithm will stay fast for a very high number of nodes
	if line == 0 return 0;

	nodeStartOffset := 0;
	nodeStartLine := 0;
	node := doc.pieceChainHead;
	while node != null {
		nodeEndOffset: s64 = nodeStartOffset + node.length;
		nodeEndLine: s64 = nodeStartLine + node.lineFeedCount;

		if nodeStartLine <= line && line <= nodeEndLine {
			// this node contains the line
			lineInThisNode := node.start.line + (line - nodeStartLine);
			buffer: = ifx node.added then *doc.addedData else *doc.originalData;
			offsetInThisNode := buffer.lineStarts[lineInThisNode] - buffer_cursor_to_offset(buffer, node.start);
			return nodeStartOffset + offsetInThisNode;
		}
		nodeStartOffset += node.length;
		nodeStartLine += node.lineFeedCount;
		node = node.next;
	}
	return nodeStartOffset;
}

document_get_line_range :: (doc: *Document, line: s64, excludeLineEndings := false) -> s64, s64 {
	lineStartNext := document_get_line_start(doc, line+1);

	if excludeLineEndings {
		tempCursor := document_create_cursor(doc, lineStartNext-2);
		if document_cursor_get_char(*tempCursor) == #char "\r" {
			return document_get_line_start(doc, line), lineStartNext-2;
		}
		else {
			return document_get_line_start(doc, line), lineStartNext-1;
		}
	}

	return document_get_line_start(doc, line), lineStartNext;
}

document_get_num_lines :: (doc: *Document) -> s64 {
	lines := 1;
	node: *PieceChainNode = doc.pieceChainHead;
	while node != null {
		lines = lines + node.lineFeedCount;
		node = node.next;
	}
	return lines;
}

document_cursor_get_char :: (cursor: *DocumentCursor) -> u8 {
	offsetInNode := cursor.documentOffset - cursor.nodeStartOffset;

	// we allow cursors to sit at the end of a node (for inserting), 
	// but in that case, if we're at the end of a node, the char is actually in the next buffer
	if offsetInNode == cursor.node.length {
		if cursor.node.next == null return 0; 
		buffer: = ifx cursor.node.next.added then *cursor.doc.addedData else *cursor.doc.originalData;
		bufferOffset := buffer_cursor_to_offset(buffer, cursor.node.next.start);
		char := buffer.text[bufferOffset];
		return char;
	}

	buffer: = ifx cursor.node.added then *cursor.doc.addedData else *cursor.doc.originalData;
	bufferOffset := buffer_cursor_to_offset(buffer, cursor.node.start) + offsetInNode;
	char := buffer.text[bufferOffset];
	return char;
}

document_cursor_get_coordinate :: (cursor: *DocumentCursor) -> Coordinate {
	curLine := document_cursor_get_line(cursor);
	curLineStart := document_get_line_start(cursor.doc, curLine);
	curColumn := cursor.documentOffset - curLineStart;

	return .{curLine, curColumn};
}

flip_cursors :: (cursorA: *DocumentCursor, cursorB: *DocumentCursor) {
	temp := <<cursorA;
	<<cursorA = <<cursorB;
	<<cursorB = temp;
}

document_normalize_line_endings :: (doc: *Document, desiredEndings: LineEndingMode) {
	// not valid ending options
	if desiredEndings == .MIXED_MAJORITY_LF || desiredEndings == .MIXED_MAJORITY_CRLF {
		return;
	}

	cursor := document_create_cursor(doc, 0);

	// manually implemented for_expansion so we can edit the cursor as we iterate
	counter := 0;
	while cursor.documentOffset <= cursor.doc.size {
		it := document_cursor_step_one_forward(*cursor);

		if it == #char "\r" {
			// lookahead one
			cursorCopy := cursor;
			next := document_cursor_step_one_forward(*cursorCopy);
			if next == #char "\n" {
				// crlf
				if desiredEndings == .LF {
					cursorStart := cursor;
					document_cursor_step_one_backward(*cursorStart);
					cursorEnd := cursor;
					document_cursor_step_one_forward(*cursorEnd);
					cursor = document_delete_text(doc, cursorStart, cursorEnd);
					cursor = document_insert_text(doc, cursor, "\n");
				}
				document_cursor_step_one_forward(*cursor); // step over \n
			}
			else {
				// cr
				if desiredEndings == .LF {
					cursorStart := cursor;
					document_cursor_step_one_backward(*cursorStart);
					cursor = document_delete_text(doc, cursorStart, cursor);
					cursor = document_insert_text(doc, cursor, "\n");
					document_cursor_step_one_forward(*cursor);
				}
				else if desiredEndings == .CRLF {
					cursorStart := cursor;
					document_cursor_step_one_backward(*cursorStart);
					cursor = document_delete_text(doc, cursorStart, cursor);
					cursor = document_insert_text(doc, cursor, "\r\n");
					document_cursor_step_one_forward(*cursor);
					document_cursor_step_one_forward(*cursor); // step over new newline
				}
			}
		}
		else if it == #char "\n" {
			// lf
			if desiredEndings == .CRLF {
				cursorStart := cursor;
				document_cursor_step_one_backward(*cursorStart);
				cursor = document_delete_text(doc, cursorStart, cursor);
				cursor = document_insert_text(doc, cursor, "\r\n");
				document_cursor_step_one_forward(*cursor);
				document_cursor_step_one_forward(*cursor); // step over new newline
			}
		}
		counter += 1;
		if cursor.documentOffset == cursor.doc.size then break;
	}
	doc.lineEndings = desiredEndings;
	if desiredEndings == .LF {
		push_notification("Normalized line endings to LF");
	}
	else {
		push_notification("Normalized line endings to CRLF");
	}
}

document_debug_print_piece_chain :: (doc: *Document) {
	builder: String_Builder;
	builder.allocator = temp;

	node: *PieceChainNode = doc.pieceChainHead;
	while node != null {
		buffer : *Buffer;
		ifx node.added then buffer = *doc.addedData else buffer = *doc.originalData;

		print_to_builder(*builder, "[a=%,l=%,lfc=%,s=(%,%),e=(%,%),\"",
			node.added, node.length, node.lineFeedCount, node.start.line, node.start.col, node.end.line, node.end.col);

		startOffset:= buffer_cursor_to_offset(buffer, node.start);
		endOffset := buffer_cursor_to_offset(buffer, node.end);
		text := string.{endOffset-startOffset, buffer.text.data + startOffset};
		for text {
			if it == #char "\r" {
				append(*builder, "CR");
			} 
			else if it == #char "\n" {
				append(*builder, "LF\n");
			}
			else {
				append(*builder, it);
			}
		}
		append(*builder, "\"]");
		node = node.next;
	}
	print(builder_to_string(*builder,,temp));
}

document_debug_print_undos :: (doc: *Document) {
	builder: String_Builder;
	builder.allocator = temp;

	redostack: [..]PieceChainSpan;
	redostack.allocator = temp;

	for < doc.undoStack {
		print_to_builder(*builder, "\n----- Change #% -----\n", it_index);
		span := it;

		changeOpenBracket:u8 = #char "[";
		changeCloseBracket:u8 = #char "]";

		// this span is a deletion, so we'll perform the undo, then
		// print the text, which will show us the deleted text
		if span.size < 0 {
			restore_span(doc, *span);
			array_add(*redostack, span);
			changeOpenBracket = #char "]";
			changeCloseBracket = #char "[";
		}

		cursor := document_create_cursor(doc, span.documentOffset);

		// iterate backward to get to the start of the line, and then go back one more line
		paddingLines := 2;
		paddingCount := 0;
		for < cursor {
			if it == #char "\n" {
				paddingLines -= 1;
				if paddingLines == 0 break;
			}
			paddingCount += 1;
		}

		// iterate forward building up the text to display
		paddingLines = 3;
		text: [..]u8;
		spanStart := span.documentOffset - cursor.documentOffset - 1;
		for cursor {
			array_add(*text, it,,temp);

			if it_index == spanStart {
				array_add(*text, changeOpenBracket ,,temp);
			}

			if it_index == spanStart+abs(span.size) {
				array_add(*text, changeCloseBracket ,,temp);
			}

			if it_index > (paddingCount+abs(span.size)) {
				if it == #char "\n" {
					paddingLines-=1;
				}
				if paddingLines == 0 break;
			}
		}

		// this span is an addition, so we've printed the document 
		// BEFORE doing the undo, so we can see the added text
		if span.size > 0 {
			restore_span(doc, *span);
			array_add(*redostack, span);
		}

		append(*builder, string.{text.count, text.data});
		append(*builder, "\n");
	}

	// put the document back to what it's supposed to be
	for < redostack {
		restore_span(doc, *it);
	}

	print(builder_to_string(*builder,,temp));
}

operator == :: (a: Coordinate, b: Coordinate) -> bool {
	return a.line == b.line && a.col == b.col;
}

operator < :: (a: Coordinate, b: Coordinate) -> bool {
	if a.line == b.line {
		if a.col < b.col {
			return true; // a is before b
		}
		else {
			return false; // b is before a
		}
	}
	else if a.line < b.line {
		return true; // a is before b
	}
	else {
		return false; // b is before a
	}
}
operator <= :: (a: Coordinate, b: Coordinate) -> bool {
	if a == b {
		return true;
	} 
	else {
		return a < b;
	}
}

operator > :: (a: Coordinate, b: Coordinate) -> bool {
	if a.line == b.line {
		if a.col > b.col {
			return true; // a is after b
		}
		else {
			return false; // b is after a
		}
	}
	else if a.line > b.line {
		return true; // a is after b
	}
	else {
		return false; // b is after a
	}
}
operator >= :: (a: Coordinate, b: Coordinate) -> bool {
	if a == b {
		return true;
	} 
	else {
		return a > b;
	}
}


#scope_file

// Calculate a buffer cursor for a given offset _within_ the given node,
// that is offset >= 0 && offset < node.length
buffer_offset_to_cursor :: (buffer: *Buffer, node: *PieceChainNode, offsetInNode: s64) -> Coordinate {
	// binary search for a line inside the given node
	offset := buffer_cursor_to_offset(buffer, node.start) + offsetInNode;
	low := node.start.line;
	high := node.end.line;
	mid := 0;
	midStartOffset := 0;
	midEndOffset := 0;

	// we are trying to get low and high to be equal, which implies we've found the line
	while low <= high {
		mid = low + ((high - low) / 2);
		midStartOffset = buffer.lineStarts[mid];

		if mid == high
			break;

		midEndOffset = buffer.lineStarts[mid+1];

		// target is before the mid line
		if offset < midStartOffset {
			high = mid - 1;
		}
		// offset is at or above the end of mid line
		else if offset >= midEndOffset {
			low = mid + 1;
		}
		else {
			break;
		}
	}

	return Coordinate.{mid, offset - midStartOffset};
}

// Find the actual offset into the given buffer from a cursor for that buffer
buffer_cursor_to_offset :: (buffer: *Buffer, pos: Coordinate) -> s64 {
	return buffer.lineStarts[pos.line] + pos.col;
}

// figure out how many linestarts are between start and length in the given buffer
buffer_line_start_count :: (start: Coordinate, end: Coordinate) -> s64 {
	return (end.line - start.line);
}

node_trim_left :: (node: *PieceChainNode, buffer: *Buffer, pos: Coordinate) {
	// remove the left side of node up to pos
	bufferOffsetStart := buffer_cursor_to_offset(buffer, node.start);
	bufferOffsetSplit := buffer_cursor_to_offset(buffer, pos);
	lenRight := (bufferOffsetStart + node.length) - bufferOffsetSplit;

	node.start = pos;
	node.length = lenRight;
	node.lineFeedCount = buffer_line_start_count(node.start, node.end);
}

node_trim_right :: (node: *PieceChainNode, buffer: *Buffer, pos: Coordinate) {
	// remove the right side of node from pos
	bufferOffsetStart := buffer_cursor_to_offset(buffer, node.start);
	bufferOffsetSplit := buffer_cursor_to_offset(buffer, pos);
	lenLeft := bufferOffsetSplit - bufferOffsetStart;

	node.end = pos;
	node.length = lenLeft;
	node.lineFeedCount = buffer_line_start_count(node.start, node.end);
}

span_append :: (span: *PieceChainSpan, node: *PieceChainNode) {
	if span.first == null {
		span.first = node;
	}
	else {
		span.last.next = node;
		node.prev = span.last;
	}
	span.last = node;
	span.boundary = false;
}

span_boundary :: (span: *PieceChainSpan, before: *PieceChainNode, after: *PieceChainNode) {
	span.first = before;
	span.last = after;
	span.boundary = true;
}

new_undo_event :: (doc: *Document, docSize: s64, docOffset: s64, size: s64) -> *PieceChainSpan {
	span := array_add(*doc.undoStack);
	span.documentSize = docSize;
	span.documentOffset = docOffset;
	span.size = size;
	return span;
}

swap_spans :: (src: *PieceChainSpan, dst: *PieceChainSpan) {
	if src.boundary {
		// in this case src is a gap, so we're just inserting dst in between the gap
		if !dst.boundary {
			src.first.next = dst.first;
			src.last.prev = dst.last;
			dst.first.prev = src.first;
			dst.last.next = src.last;
		}
	}
	else {
		// in this case dst is just a gap, so you need to remove
		// the whole span from src.first to src.last
		if dst.boundary {
			src.first.prev.next = src.last.next;
			src.last.next.prev = src.first.prev;
		}
		// this is the general case, a straight swap
		else {
			src.first.prev.next = dst.first;
			src.last.next.prev = dst.last;
			dst.first.prev = src.first.prev;
			dst.last.next = src.last.next;
		}
	}
}

restore_span :: (doc: *Document, span: *PieceChainSpan) {
	// the given span is something that's been pulled from the undo stack
	// and represents a section of the linked list which thinks it's linked into the real one
	// but it's actually not

	// the goal here is to grab the prev and next nodes which this span points to, and tell those nodes
	// to point to this span, effectively swapping it in

	// our edits will edit the main linked list, and the span in question will mutate into it's inverse

	if span.boundary {
		// this means the span is really an "absence" of nodes, so we want to remove the span that exists
		// between "first" and "last"

		// these are the nodes we want to remove
		first := span.first.next;
		last := span.last.prev;

		// remove from first to last
		span.first.next = span.last;
		span.last.prev = span.first;

		// store what we just removed
		span.first = first;
		span.last = last;
		span.boundary = false;
	}
	else {
		first := span.first.prev;
		last := span.last.next;

		// is this span in between two nodes that are directly connected? I.e. this is a boundary
		// and we must insert inbetween this boundary
		if first.next == last {
			first.next = span.first;
			last.prev = span.last;

			// store what we just removed
			span.first = first;
			span.last = last;
			span.boundary = true;
		}
		// general case, we need to swap one range with another
		else {
			first = first.next;
			last = last.prev;

			first.prev.next = span.first;
			last.next.prev = span.last;

			// store what we just removed
			span.first = first;
			span.last = last;
			span.boundary = false;
		}
	}

	currentSize := doc.size;
	doc.size = span.documentSize;
	span.documentSize = currentSize;
}
