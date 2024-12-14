
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
	lastInsert: Coordinate;
}

DocumentCursor :: struct {
	doc: *Document;
	node: *PieceChainNode;
	bufferPos: Coordinate;
	documentPos: Coordinate;
	documentOffset: s64;
}

Coordinate :: struct {
	line: s64;
	col: s64;
}

Buffer :: struct {
	text: []u8;
	lineStarts: [..]s64;
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


document_free :: (doc: *Document) {
	fini(*doc.documentMemory);
	fini(*doc.pieceChainMemory);
	initializer_of(Document)(doc);
}

document_open :: (path: string) {
	// @todo hack until we have multi buffer support
	doc := *mainDocument;
	document_free(doc);

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
			array_add(*doc.originalData.lineStarts, xx (i+1));
		}
	}

	// setup added data buffer
	doc.addedData.text.data = file.data + file.count;
	doc.addedData.lineStarts.allocator = doc.pieceChainAlloc;
	array_add(*doc.addedData.lineStarts, 0);
	doc.lastInsert = Coordinate.{0,0};

	// create the starting node of the piece chain
	doc.pieceChainHead = New(PieceChainNode,, doc.pieceChainAlloc);
	doc.pieceChainHead.start = Coordinate.{0,0}; 
	doc.pieceChainHead.end = Coordinate.{
		doc.originalData.lineStarts.count - 1,
		doc.originalData.text.count - doc.originalData.lineStarts[doc.originalData.lineStarts.count - 1]}; 
	doc.pieceChainHead.length = doc.originalData.text.count; 
	doc.pieceChainHead.lineFeedCount = doc.originalData.lineStarts.count-1; 
	doc.pieceChainHead.added = false;
	doc.pieceChainTail = doc.pieceChainHead;
}

document_insert_text :: (doc: *Document, at: DocumentCursor, t: string) -> DocumentCursor {

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

	if at.bufferPos == at.node.end || at.bufferPos == at.node.start {
		// case 1: insert at boundary

		// bonus case, this node is the last insert node
		// you can just add more to the mod buffer and increase the node length
		if at.node.added == true && at.node.end == doc.lastInsert {
			endOffset := doc.addedData.text.count;
			endLine := doc.addedData.lineStarts.count - 1;
			endColumn := endOffset - doc.addedData.lineStarts[endLine];
			at.node.length = at.node.length + text.count;
			at.node.end = Coordinate.{endLine, endColumn};
			at.node.lineFeedCount = buffer_line_start_count(at.node.start, at.node.end);

			doc.lastInsert = at.node.end;
			return at;
		}

		// make new piece, and just put in between existing nodes
		endOffset := doc.addedData.text.count;
		endLine := doc.addedData.lineStarts.count - 1;
		endColumn := endOffset - doc.addedData.lineStarts[endLine];
		newPiece := New(PieceChainNode,, doc.pieceChainAlloc);
		newPiece.added = true;
		newPiece.start = doc.lastInsert;
		newPiece.end = Coordinate.{endLine, endColumn};
		newPiece.length = text.count;
		newPiece.lineFeedCount = buffer_line_start_count(newPiece.start, newPiece.end);

		// insert into linked list
		if at.bufferPos == at.node.end {
			newPiece.next = at.node.next;
			newPiece.prev = at.node;
			at.node.next = newPiece;
			if newPiece.next != null {
				newPiece.next.prev = newPiece;
			}
			else {
				doc.pieceChainTail = newPiece;
			}
		}
		else {
			newPiece.prev = at.node.prev;
			newPiece.next = at.node;
			at.node.prev = newPiece;
			if newPiece.prev != null {
				newPiece.prev.next = newPiece;
			}
			else {
				doc.pieceChainHead = newPiece;
			}
		}

		doc.lastInsert = newPiece.end;

		// we return a new cursor that is in the same document location
		// but now points to the new node
		newCursor: DocumentCursor;
		newCursor.doc = at.doc;
		newCursor.node = newPiece;
		newCursor.bufferPos = newPiece.start;
		newCursor.documentPos = at.documentPos;
		newCursor.documentOffset = at.documentOffset;
		return newCursor;
	}
	else {
		// case 2: splitting a node

		nodeBuffer : *Buffer;
		ifx at.node.added then nodeBuffer = *doc.addedData else nodeBuffer = *doc.originalData;

		// copy the old node and then trim left and right to get the new nodes
		newPieceRight := New(PieceChainNode,, doc.pieceChainAlloc);
		<<newPieceRight = <<at.node;
		nodeTrimLeft(newPieceRight, nodeBuffer, at.bufferPos);
		nodeTrimRight(at.node, nodeBuffer, at.bufferPos);

		// create a new piece with the appended text data
		endOffset := doc.addedData.text.count;
		endLine := doc.addedData.lineStarts.count - 1;
		endColumn := endOffset - doc.addedData.lineStarts[endLine];
		newPiece := New(PieceChainNode,, doc.pieceChainAlloc);
		newPiece.added = true;
		newPiece.start = doc.lastInsert;
		newPiece.end = Coordinate.{endLine, endColumn};
		newPiece.length = text.count;
		newPiece.lineFeedCount = buffer_line_start_count(newPiece.start, newPiece.end);

		// update last insert cursor
		doc.lastInsert = newPiece.end;

		// update the chain pointers 
		at.node.next = newPiece;
		newPiece.prev = at.node;
		newPiece.next = newPieceRight;
		newPieceRight.prev = newPiece;
		if newPieceRight.next != null {
			newPieceRight.next.prev = newPieceRight;
		}
		else {
			doc.pieceChainTail = newPieceRight;
		}

		// we return a new cursor that is in the same document location
		// but now points to the new node
		newCursor: DocumentCursor;
		newCursor.doc = at.doc;
		newCursor.node = newPiece;
		newCursor.bufferPos = newPiece.start;
		newCursor.documentPos = at.documentPos;
		newCursor.documentOffset = at.documentOffset;
		return newCursor;
	}
}

document_delete_text :: (doc: *Document, startAt: DocumentCursor, endAt: DocumentCursor) {
	document_delete_text_internal(doc, 	startAt.node, startAt.bufferPos, startAt.documentOffset,
										endAt.node, startAt.bufferPos, endAt.documentOffset);
}
document_delete_text :: (doc: *Document, startAt: DocumentCursor, count: s64) {
	endAt := startAt;
	document_cursor_jump_to_offset(*endAt, startAt.documentOffset + count);
	document_delete_text_internal(doc, 	startAt.node, startAt.bufferPos, startAt.documentOffset,
										endAt.node, startAt.bufferPos, endAt.documentOffset);
}

document_delete_text_internal :: (doc: *Document, startNode: *PieceChainNode, start: Coordinate, startOffset: s64,
												  endNode: *PieceChainNode, end: Coordinate, endOffset: s64) {
	if startNode == endNode {
		buffer : *Buffer;
		ifx startNode.added then buffer = *doc.addedData else buffer = *doc.originalData;

		if start == startNode.start {
			nodeTrimLeft(startNode, buffer, end);
		}
		else if end == startNode.end {
			nodeTrimRight(startNode, buffer, start);
		}
		else {
			newPieceRight := New(PieceChainNode,, doc.pieceChainAlloc);
			<<newPieceRight = <<startNode;
			nodeTrimLeft(newPieceRight, buffer, end);
			nodeTrimRight(startNode, buffer, start);

			startNode.next = newPieceRight;
			newPieceRight.prev = startNode;
		}
	}
	else {
		remove_node_range :: (doc: *Document, first: *PieceChainNode, last: *PieceChainNode) {
			if first.prev != null {
				first.prev.next = last.next;
			}
			else {
				doc.pieceChainHead = first.prev;
			}

			if last.next != null {
				last.next.prev = first.prev;
			}
			else {
				doc.pieceChainTail = last.next;
			}
		}

		firstToDelete := startNode.next;
		if startNode.start == start {
			// delete whole start node
			firstToDelete = startNode;
		}
		else {
			// take some of start node
			buffer : *Buffer;
			ifx startNode.added then buffer = *doc.addedData else buffer = *doc.originalData;
			nodeTrimRight(startNode, buffer, start);
		}
		lastToDelete := endNode.prev;
		if endNode.end == end {
			// delete whole end node
			lastToDelete = endNode;
		}
		else {
			// take some of end node
			buffer : *Buffer;
			ifx endNode.added then buffer = *doc.addedData else buffer = *doc.originalData;
			nodeTrimLeft(endNode, buffer, end);
		}
		
		// delete all nodes that are no longer needed
		remove_node_range(doc, firstToDelete, lastToDelete);
	}

	doc.size -= endOffset - startOffset;
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

document_cursor_jump_to_offset :: (cursor: *DocumentCursor, offset: s64) {
	node: = cursor.node;

	docPosAtNodeStart: Coordinate;
	docPosAtNodeStart.line = cursor.documentPos.line - buffer_line_start_count(node.start, cursor.bufferPos);
	docPosAtNodeStart.col = node.start.col;

	buffer : *Buffer;
	ifx node.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;
	docOffsetAtNodeStart:s64 = cursor.documentOffset - (buffer_cursor_to_offset(buffer, cursor.bufferPos) - buffer_cursor_to_offset(buffer, node.start));

	direction := ifx offset < cursor.documentOffset then -1 else 1;

	// now we loop through nodes in the desired direction
	while node != null {
		ifx node.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;

		// we now calculate the document end coordinates
		docPosAtNodeEnd: Coordinate;
		docPosAtNodeEnd.line = docPosAtNodeStart.line + node.lineFeedCount;
		docPosAtNodeEnd.col = node.end.col;
		docOffsetAtNodeEnd := docOffsetAtNodeStart + node.length;

		if (offset > docOffsetAtNodeStart && offset <= docOffsetAtNodeEnd) || (offset == 0 && node.prev == null) {
			// the target offset is inside this node
			cursor.node = node;
			cursor.documentOffset = offset;
			cursor.bufferPos = buffer_offset_to_cursor(buffer, node, offset - docOffsetAtNodeStart);
			cursor.documentPos = Coordinate.{
				line = docPosAtNodeStart.line + cursor.bufferPos.line,
				col = cursor.bufferPos.col
			};
			return;
		}

		// if this is not the desired node, update the start position and move on to next node
		if direction > 0 {
			docPosAtNodeStart.line = docPosAtNodeEnd.line;
			docPosAtNodeStart.col = docPosAtNodeEnd.col;
			docOffsetAtNodeStart = docOffsetAtNodeEnd;
			node = node.next;
		}
		else {
			node = node.prev;
			docPosAtNodeStart.line = docPosAtNodeStart.line - node.lineFeedCount;
			docPosAtNodeStart.col = node.start.col;
			docOffsetAtNodeStart = docOffsetAtNodeStart - node.length;
		}
	}
}

document_cursor_jump_to_position :: (cursor: *DocumentCursor, pos: Coordinate) {
	// first calculate the document coordinates at the base of the node
	node: = cursor.node;

	docPosAtNodeStart: Coordinate;
	docPosAtNodeStart.line = cursor.documentPos.line - buffer_line_start_count(node.start, cursor.bufferPos);
	docPosAtNodeStart.col = node.start.col;

	buffer : *Buffer;
	ifx node.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;
	docOffsetAtNodeStart:s64 = cursor.documentOffset - (buffer_cursor_to_offset(buffer, cursor.bufferPos) - buffer_cursor_to_offset(buffer, node.start));

	direction := ifx pos < cursor.documentPos then -1 else 1;

	// now we loop through nodes in the desired direction
	while node != null {
		ifx node.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;

		// we now calculate the document end coordinates
		docPosAtNodeEnd: Coordinate;
		docPosAtNodeEnd.line = docPosAtNodeStart.line + node.lineFeedCount;
		docPosAtNodeEnd.col = node.end.col;
		docOffsetAtNodeEnd := docOffsetAtNodeStart + node.length;

		if (pos > docPosAtNodeStart && pos <= docPosAtNodeEnd) || (pos == .{0,0} && node.prev == null) {
			// the target pos is inside this node
			cursor.node = node;
			cursor.bufferPos.line = node.start.line + (pos.line - docPosAtNodeStart.line);

			// need to work out the line length to cap the column here
			lineStartOffset := buffer_cursor_to_offset(buffer, .{cursor.bufferPos.line, 0});
			nextLineStartOffset := 0;
			if cursor.bufferPos.line+1 >= buffer.lineStarts.count {
				nextLineStartOffset = buffer.text.count;
			}
			else {
				nextLineStartOffset = buffer_cursor_to_offset(buffer, .{cursor.bufferPos.line+1, 0});
			}

			// @todo: assumes crlf
			lineLength := (nextLineStartOffset - lineStartOffset) - 2;
			cursor.bufferPos.col = min(pos.col, lineLength);
			cursor.documentPos = .{pos.line, cursor.bufferPos.col};
			cursor.documentOffset = docOffsetAtNodeStart + buffer_cursor_to_offset(buffer, cursor.bufferPos);
			return;
		}

		// if this is not the desired node, update the start position and move on to next node
		if direction > 0 {
			docPosAtNodeStart.line = docPosAtNodeEnd.line;
			docPosAtNodeStart.col = docPosAtNodeEnd.col;
			docOffsetAtNodeStart = docOffsetAtNodeEnd;
			node = node.next;
		}
		else {
			node = node.prev;
			docPosAtNodeStart.line = docPosAtNodeStart.line - node.lineFeedCount;
			docPosAtNodeStart.col = node.start.col;
			docOffsetAtNodeStart = docOffsetAtNodeStart - node.length;
		}
	}
}

document_cursor_step_one_forward :: (cursor: *DocumentCursor) -> u8 {
	buffer : *Buffer;
	ifx cursor.node.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;

	// cannot increment as we're at the end of the document
	if cursor.documentOffset+1 >= cursor.doc.size {
		return buffer.text[buffer_cursor_to_offset(buffer, cursor.node.end)-1];
	}

	// documentoffset will just increment as long as < documentsize
	cursor.documentOffset = cursor.documentOffset + 1;

	character := document_cursor_get_char(cursor);

	// in this case we overflow into a new node
	if cursor.bufferPos == cursor.node.end {
		// if incrementing would push offset above node.length, then go to node.next

		cursor.node = cursor.node.next;
		cursor.bufferPos = .{cursor.node.start.line, cursor.node.start.col+1};
	}
	// in this case we stay within this node
	else {
		// @todo: assumes crlf endings
		if character == #char "\r" {
			cursor.bufferPos.line += 1;
			cursor.bufferPos.col = 0;
		}
		else {
			cursor.bufferPos.col += 1;
		}
	}

	// update the document position
	if character == #char "\r" {
		cursor.documentPos.line += 1;
		cursor.documentPos.col = 0;
	}
	else {
		cursor.documentPos.col += 1;
	}

	return character;
}

document_cursor_step_one_backward :: (cursor: *DocumentCursor) -> u8 {
	buffer : *Buffer;
	ifx cursor.node.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;

	// cannot decrement as we're at the end of the document
	if cursor.documentOffset == 0 {
		return buffer.text[buffer_cursor_to_offset(buffer, cursor.node.start)];
	}

	// documentoffset will just decrement as long as > 0
	cursor.documentOffset = cursor.documentOffset - 1;

	character : u8;
	if cursor.bufferPos == cursor.node.start {
		// the character for the end of this node is actually in the previous node's buffer (due to zero indexing)
		prevNode := cursor.node.prev;
		ifx prevNode.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;
		character = buffer.text[buffer_cursor_to_offset(buffer, .{prevNode.end.line, prevNode.end.col-1})];
	}
	else {
		ifx cursor.node.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;
		character = buffer.text[buffer_cursor_to_offset(buffer, .{cursor.bufferPos.line, cursor.bufferPos.col-1})];
	}

	// in this case we underflow into a new node
	if cursor.bufferPos == cursor.node.start {
		cursor.node = cursor.node.prev;
		cursor.bufferPos = .{cursor.node.end.line, cursor.node.end.col-1};
	}
	// in this case we stay within this node
	else {
		// @todo: assumes crlf endings
		if character == #char "\n" {
			cursor.bufferPos.line -= 1;
			newLineStartOffset := buffer_cursor_to_offset(buffer, .{cursor.bufferPos.line, 0});
			oldLineStartOffset := buffer_cursor_to_offset(buffer, .{cursor.bufferPos.line+1, 0});
			cursor.bufferPos.col = (oldLineStartOffset - newLineStartOffset) - 2;
		}
		else {
			cursor.bufferPos.col -= 1;
		}
	}

	// update the document position
	if character == #char "\n" {
		cursor.documentPos.line -= 1;
		cursor.documentPos.col = cursor.bufferPos.col;
	}
	else {
		cursor.documentPos.col -= 1;
	}

	return character;
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
	if col >= lineContent.count then return 0;
	return lineContent[col];
}

document_cursor_get_char :: (cursor: *DocumentCursor) -> u8 {
	buffer : *Buffer;

	if cursor.bufferPos == cursor.node.end {
		// the character for the end of this node is actually in the next node's buffer (due to zero indexing)
		nextNode := cursor.node.next;
		ifx nextNode.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;
		return buffer.text[buffer_cursor_to_offset(buffer, nextNode.start)];
	}
	
	ifx cursor.node.added then buffer = *cursor.doc.addedData else buffer = *cursor.doc.originalData;
	return buffer.text[buffer_cursor_to_offset(buffer, cursor.bufferPos)];
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
	return max(lineContent.count, 0);
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
			// @todo: assumes crlf endings
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
// @todo: rename cursor to coord or something
buffer_cursor_to_offset :: (buffer: *Buffer, cursor: Coordinate) -> s64 {
	return buffer.lineStarts[cursor.line] + cursor.col;
}

// figure out how many linestarts are between start and length in the given buffer
buffer_line_start_count :: (start: Coordinate, end: Coordinate) -> s64 {
	return (end.line - start.line);
}

nodeTrimLeft :: (node: *PieceChainNode, buffer: *Buffer, pos: Coordinate) {
	// remove the left side of node up to pos
	bufferOffsetStart := buffer_cursor_to_offset(buffer, node.start);
	bufferOffsetSplit := buffer_cursor_to_offset(buffer, pos);
	lenRight := (bufferOffsetStart + node.length) - bufferOffsetSplit;

	// @todo crlf support, prevent splitting in the middle of a crlf
	splitPos := pos;
	if bufferOffsetSplit < buffer.text.count && buffer.text[bufferOffsetSplit] == #char "\n" {
		// we want to move right over the newline, rolling us over onto a new line
		splitPos.col = 0;
		splitPos.line += 1;
		lenRight -= 1;
	}

	node.start = splitPos;
	node.length = lenRight;
	node.lineFeedCount = buffer_line_start_count(node.start, node.end);
}

nodeTrimRight :: (node: *PieceChainNode, buffer: *Buffer, pos: Coordinate) {
	// remove the right side of node from pos
	bufferOffsetStart := buffer_cursor_to_offset(buffer, node.start);
	bufferOffsetSplit := buffer_cursor_to_offset(buffer, pos);
	lenLeft := bufferOffsetSplit - bufferOffsetStart;

	// @todo crlf support, prevent splitting in the middle of a crlf
	splitPos := pos;
	if bufferOffsetSplit < buffer.text.count && buffer.text[bufferOffsetSplit] == #char "\n" {
		// moves left of the newline, leaving it behind on the right side
		splitPos.col -= 1;
		lenLeft -= 1;
	}

	node.end = splitPos;
	node.length = lenLeft;
	node.lineFeedCount = buffer_line_start_count(node.start, node.end);
}
