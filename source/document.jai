
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
	
	size: s64;

	path: string;
	lastInsert: BufferCursor;
}

Position :: struct {
	line: s64;
	col: s64;
}

Buffer :: struct {
	text: []u8;
	lineStarts: [..]s64;
}

// This looks like a document position, but it's not
// and the distinction is really important, this is linebased location
// within one of the text buffers, rather than the real document
// the line numbers do not match real lines
BufferCursor :: struct {
	line: s64; // this indexes the lineStarts in a particular buffer
	offset: s64;
}

PieceChainNode :: struct {
	next: *PieceChainNode;
	prev: *PieceChainNode;

	added: bool;
	start: BufferCursor;
	end: BufferCursor;
	length: s64;
	lineFeedCount: s64;
}

operator == :: (a: BufferCursor, b: BufferCursor) -> bool {
	return a.line == b.line && a.offset == b.offset;
}

document_open :: (path: string) {
	doc := *mainDocument;
	doc.documentMemory.alignment = 1; // @Todo, check this is okay, but it should be fine, we just want an endless char array
	doc.documentAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *doc.documentMemory };
	doc.pieceChainAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *doc.pieceChainMemory };

	doc.path = copy_string(path,,doc.documentAlloc);
    file := read_entire_file(path,,doc.documentAlloc);
	doc.size = file.count;

	// setup original data buffer
	doc.originalData.text.data = file.data;
	doc.originalData.text.count = file.count;
	doc.originalData.lineStarts.allocator = doc.pieceChainAlloc;
	array_add(*doc.originalData.lineStarts, 0);
	for byte, i: doc.originalData.text {
		if byte == #char "\n" {
			// @TODO: +1 to skip over \r, if using \n line endings, don't need the +1
			array_add(*doc.originalData.lineStarts, xx (i+1));
		}
	}

	// setup added data buffer
	doc.addedData.text.data = file.data + file.count;
	doc.addedData.lineStarts.allocator = doc.pieceChainAlloc;
	array_add(*doc.addedData.lineStarts, 0);
	doc.lastInsert = BufferCursor.{0,0};

	// create the starting node of the piece chain
	doc.pieceChainHead = New(PieceChainNode,, doc.pieceChainAlloc);
	doc.pieceChainHead.start = BufferCursor.{0,0}; 
	doc.pieceChainHead.end = BufferCursor.{
		doc.originalData.lineStarts.count - 1,
		doc.originalData.text.count - doc.originalData.lineStarts[doc.originalData.lineStarts.count - 1]}; 
	doc.pieceChainHead.length = doc.originalData.text.count; 
	doc.pieceChainHead.lineFeedCount = doc.originalData.lineStarts.count-1; 
	doc.pieceChainHead.added = false;
	doc.pieceChainTail = doc.pieceChainHead;
}

document_insert_text :: (doc: *Document, location: Position, t: string) {

	// actually add the new text to a buffer, updating linestarts and what not
	text := copy_string(t,, doc.documentAlloc);
	doc.addedData.text.count = doc.addedData.text.count + text.count;
	lineIndex := doc.addedData.lineStarts.count - 1;
	for byte, i: text {
		if byte == #char "\n" {
			// @TODO: +1 to skip over \r, if using \n line endings, don't need the +1
			array_add(*doc.addedData.lineStarts, xx (lineIndex + i + 1));
		}
	}
	doc.size += text.count;

	// figure out where to put the insertion
	nodeToEdit, insertPos := document_query_at_position(doc, location);

	// now we know the node where we want to insert, and the cursor inside that node
	// deal with our two cases:

	if insertPos == nodeToEdit.end || insertPos == nodeToEdit.start {
		// case 1: insert at boundary

		// bonus case, this node is the last insert node
		// you can just add more to the mod buffer and increase the node length
		if nodeToEdit.added == true && nodeToEdit.end == doc.lastInsert {
			endOffset := doc.addedData.text.count;
			endLine := doc.addedData.lineStarts.count - 1;
			endColumn := endOffset - doc.addedData.lineStarts[endLine];
			nodeToEdit.length = nodeToEdit.length + text.count;
			nodeToEdit.end = BufferCursor.{endLine, endColumn};
			nodeToEdit.lineFeedCount = buffer_line_start_count(nodeToEdit.start, nodeToEdit.end);

			doc.lastInsert = nodeToEdit.end;
			return;
		}

		// make new piece, and just put in between existing nodes
		endOffset := doc.addedData.text.count;
		endLine := doc.addedData.lineStarts.count - 1;
		endColumn := endOffset - doc.addedData.lineStarts[endLine];
		newPiece := New(PieceChainNode,, doc.pieceChainAlloc);
		newPiece.added = true;
		newPiece.start = doc.lastInsert;
		newPiece.end = BufferCursor.{endLine, endColumn};
		newPiece.length = text.count;
		newPiece.lineFeedCount = buffer_line_start_count(newPiece.start, newPiece.end);

		// insert into linked list
		if insertPos == nodeToEdit.end {
			newPiece.next = nodeToEdit.next;
			newPiece.prev = nodeToEdit;
			nodeToEdit.next = newPiece;
			if newPiece.next != null {
				newPiece.next.prev = newPiece;
			}
			else {
				doc.pieceChainTail = newPiece;
			}
		}
		else {
			newPiece.prev = nodeToEdit.prev;
			newPiece.next = nodeToEdit;
			nodeToEdit.prev = newPiece;
			if newPiece.prev != null {
				newPiece.prev.next = newPiece;
			}
			else {
				doc.pieceChainHead = newPiece;
			}
		}

		doc.lastInsert = newPiece.end;
	}
	else {
		// case 2: splitting a node

		nodeBuffer : *Buffer;
		ifx nodeToEdit.added then nodeBuffer = *doc.addedData else nodeBuffer = *doc.originalData;

		// calculate the left and right side split nodes using the insertPos
		bufferOffsetStart := buffer_cursor_to_offset(nodeBuffer, nodeToEdit.start);
		bufferOffsetSplit := buffer_cursor_to_offset(nodeBuffer, insertPos);
		lenLeft := bufferOffsetSplit - bufferOffsetStart;
		lenRight := (bufferOffsetStart + nodeToEdit.length) - bufferOffsetSplit;

		// copy the left node to make the right, updating start and length and line count
		newPieceRight := New(PieceChainNode,, doc.pieceChainAlloc);
		newPieceRight.next = nodeToEdit.next;
		newPieceRight.added = nodeToEdit.added;
		newPieceRight.start = insertPos;
		newPieceRight.end = nodeToEdit.end;
		newPieceRight.length = lenRight;
		newPieceRight.lineFeedCount = buffer_line_start_count(newPieceRight.start, newPieceRight.end);

		// update the left node
		nodeToEdit.end = insertPos;
		nodeToEdit.length = lenLeft;
		nodeToEdit.lineFeedCount = buffer_line_start_count(nodeToEdit.start, nodeToEdit.end);

		// create a new piece with the appended text data
		endOffset := doc.addedData.text.count;
		endLine := doc.addedData.lineStarts.count - 1;
		endColumn := endOffset - doc.addedData.lineStarts[endLine];
		newPiece := New(PieceChainNode,, doc.pieceChainAlloc);
		newPiece.added = true;
		newPiece.start = doc.lastInsert;
		newPiece.end = BufferCursor.{endLine, endColumn};
		newPiece.length = text.count;
		newPiece.lineFeedCount = buffer_line_start_count(newPiece.start, newPiece.end);

		// update last insert cursor
		doc.lastInsert = newPiece.end;

		// update the chain pointers 
		if doc.pieceChainTail == nodeToEdit {
			doc.pieceChainTail = newPieceRight;
		}
		nodeToEdit.next = newPiece;
		newPiece.prev = nodeToEdit;
		newPiece.next = newPieceRight;
		newPieceRight.prev = newPiece;
	}
}

document_replace_text :: (doc: *Document, index: s64, text: string) {
}

document_delete_text :: (doc: *Document, index: s64, count: s64) {
}

// given a coordinate position in the document (line, column), find the absolute offset in the document (inverse of below)
document_query_at_position :: (doc: *Document, pos: Position) -> *PieceChainNode, BufferCursor, s64 {
	// this is a fairly hair algorithm, but basically we'll iterate through the chain
	// until we find the line start we are interested in, then we swap to iterating
	// until we find enough columns for the given position, this gives us the node and cursor
	// the whole time we are summing offsets in each node

	offset := 0;
	linesRemaining := pos.line;
	columnsRemaining := pos.col;
	node: *PieceChainNode = doc.pieceChainHead;
	while node != null {
		buffer : *Buffer;
		ifx node.added then buffer = *doc.addedData else buffer = *doc.originalData;

		if linesRemaining == 0 {
			if node.length >= columnsRemaining {
				// this is the node
				offset += pos.col;
				return node, .{node.start.line, node.start.offset + columnsRemaining}, offset;
			}
			else {
				// this is not the node
				offset += node.length;
				columnsRemaining -= node.length;
				node = node.next;
			}
		}
		else if linesRemaining < node.lineFeedCount {
			// the line must start and end in this node, so this node is what we want
			nodeStartOffset := buffer_cursor_to_offset(buffer, node.start); 
			lineStartOffset := buffer_cursor_to_offset(buffer, .{node.start.line + linesRemaining, 0});
			offset += (lineStartOffset - nodeStartOffset) + pos.col;
			return node, .{node.start.line + linesRemaining, pos.col}, offset;
		}
		else if linesRemaining == node.lineFeedCount {
			// the line starts in this node, but does not end here (potentially the document ends too)
			nodeStartOffset := buffer_cursor_to_offset(buffer, node.start); 
			lineStartOffset := buffer_cursor_to_offset(buffer, .{node.start.line + linesRemaining, 0});
			nodeEndOffset := buffer_cursor_to_offset(buffer, node.end);
			offset += (lineStartOffset - nodeStartOffset);
			
			columnsInThisNode := nodeEndOffset - lineStartOffset;
			if columnsInThisNode > pos.col {
				// yep this is definitely the node
				offset += pos.col;
				return node, .{node.start.line + linesRemaining, pos.col}, offset;
			}
			else {
				// our desired column is past the line
				offset += columnsInThisNode;
				linesRemaining -= node.lineFeedCount;
				columnsRemaining -= columnsInThisNode;
				node = node.next;
			}
		}
		else {
			// the line is past this node so skip it
			linesRemaining -= node.lineFeedCount;
			offset += node.length;
			node = node.next;
		}	
	}
	// @todo, unsure if this is even possible to reach, if so, give back a nill node, rather than a null
	return null, BufferCursor.{}, 0;
}

// given an offset in the document, get the piece chain node, and coordinates, in buffer space and document space
document_query_at_offset :: (doc: *Document, offset: s64) -> *PieceChainNode, BufferCursor, Position {
	// this is relatively simple, just iterate the nodes subtracting their lengths
	// until you find a node that is longer than the remaining, this is the node you want
	// we calculate the coordinates with a binary search of lines in the node

	lineCounter := 0;
	remainingOffset := offset;
	node: *PieceChainNode = doc.pieceChainHead;
	while node != null {
		buffer : *Buffer;
		ifx node.added then buffer = *doc.addedData else buffer = *doc.originalData;

		if remainingOffset <= node.length {
			// here is the target node
			foundNode := node;
			cursor := buffer_offset_to_cursor(buffer, node, remainingOffset);
			pos := Position.{lineCounter + (cursor.line - node.start.line), cursor.offset};
			return foundNode, cursor, pos;
		}
		else {
			remainingOffset -= node.length;
			lineCounter += node.lineFeedCount;
		}
	}
	// @todo, unsure if this is even possible to reach, if so, give back a nill node, rather than a null
	return null, BufferCursor.{}, Position.{};
}

document_get_line_content :: (doc: *Document, lineNum: s64) -> string {
	builder: String_Builder;
	builder.allocator = temp;

	// @todo: potential optimization here is to cache the last visited nodes
	// and then search nearby, such that you can skip iterating all nodes for local queries of line content

	// additionally you can cache the last queried line, under the assumption that there
	// will be repeated queries for the line the cursor is currently sat on

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

	return builder_to_string(*builder);
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

document_get_char_at_location :: (doc: *Document, line: s64, col: s64) -> u8 {
	lineContent := document_get_line_content(doc, line,, temp);
	return lineContent[col];
}

document_get_line_length :: (doc: *Document, lineNum: s64, excludeEnding: bool = true) -> s64 {
	lineContent := document_get_line_content(doc, lineNum,, temp);
	if excludeEnding {
		if lineContent[lineContent.count-1] == #char "\n" {
			lineContent.count = lineContent.count - 1;
		}
		if lineContent[lineContent.count-1] == #char "\r" {
			lineContent.count = lineContent.count - 1;
		}
	}
	return max(lineContent.count - 1, 0);
}

#scope_file

// Calculate a buffer cursor for a given offset _within_ the given node,
// that is offset >= 0 && offset < node.length
buffer_offset_to_cursor :: (buffer: *Buffer, node: *PieceChainNode, offsetInNode: s64) -> BufferCursor {
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

	return BufferCursor.{mid, offset - midStartOffset};
}

// Find the actual offset into the given buffer from a cursor for that buffer
buffer_cursor_to_offset :: (buffer: *Buffer, cursor: BufferCursor) -> s64 {
	return buffer.lineStarts[cursor.line] + cursor.offset;
}

// figure out how many linestarts are between start and length in the given buffer
buffer_line_start_count :: (start: BufferCursor, end: BufferCursor) -> s64 {
	return (end.line - start.line);
}
