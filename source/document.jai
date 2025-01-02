
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
	nodeStartOffset: s64;
	nodeStartLine: s64;
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

// proposal, use s32's instead to make this struct
// smaller so we can iterate over it faster
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

	// tell panel cursors to reset
	// @todo: should be a bit more clever than this, especially when we have a few panels
	focusedPanel.cursor = .{};
	focusedPanel.cursor.head.doc = focusedPanel.document;
	focusedPanel.cursor.head.node = mainDocument.pieceChainHead;
	focusedPanel.cursor.anchor.doc = focusedPanel.document;
	focusedPanel.cursor.anchor.node = mainDocument.pieceChainHead;
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

	insertBuffer: = ifx at.node.added then *doc.addedData else *doc.originalData;
	insertPos := buffer_offset_to_cursor(insertBuffer, at.node, at.documentOffset - at.nodeStartOffset);

	if insertPos == at.node.end || insertPos == at.node.start {
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

		newCursor: DocumentCursor;

		// insert into linked list
		if insertPos == at.node.end {
			// put at the end of at.node (the existing node)
			newCursor.nodeStartOffset = at.nodeStartOffset + at.node.length;
			newCursor.nodeStartLine = at.nodeStartLine + at.node.lineFeedCount;
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
			// put at the start of at.node
			newCursor.nodeStartOffset = at.nodeStartOffset;
			newCursor.nodeStartLine = at.nodeStartLine;
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
		newCursor.doc = at.doc;
		newCursor.node = newPiece;
		newCursor.documentOffset = at.documentOffset;
		return newCursor;
	}
	else {
		// case 2: splitting a node

		// copy the old node and then trim left and right to get the new nodes
		newPieceRight := New(PieceChainNode,, doc.pieceChainAlloc);
		<<newPieceRight = <<at.node;
		nodeTrimLeft(newPieceRight, insertBuffer, insertPos);
		nodeTrimRight(at.node, insertBuffer, insertPos);

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
		newCursor.nodeStartOffset = at.nodeStartOffset + at.node.length;
		newCursor.nodeStartLine = at.nodeStartLine + at.node.lineFeedCount; 
		newCursor.documentOffset = at.documentOffset;
		return newCursor;
	}
}

document_delete_text :: (doc: *Document, startAt: DocumentCursor, endAt: DocumentCursor) -> DocumentCursor {

	startBuffer: = ifx startAt.node.added then *doc.addedData else *doc.originalData;
	endBuffer: = ifx endAt.node.added then *doc.addedData else *doc.originalData;

	start := buffer_offset_to_cursor(startBuffer, startAt.node, startAt.documentOffset - startAt.nodeStartOffset);
	end := buffer_offset_to_cursor(endBuffer, endAt.node, endAt.documentOffset - endAt.nodeStartOffset);
	count := endAt.documentOffset - startAt.documentOffset;

	doc.size -= endAt.documentOffset - startAt.documentOffset;

	newCursor: DocumentCursor;
	newCursor.doc = doc;
	newCursor.documentOffset = startAt.documentOffset;

	remove_node_range :: (doc: *Document, first: *PieceChainNode, last: *PieceChainNode) {
		if first.prev != null {
			first.prev.next = last.next;
		}
		else {
			if first.prev == null {
				// this was the first node
				doc.pieceChainHead = last.next;
			}
			else {
				doc.pieceChainHead = first.prev;
			}
		}

		if last.next != null {
			last.next.prev = first.prev;
		}
		else {
			if last.next == null {
				doc.pieceChainTail = first.prev;
			}
			else {
				doc.pieceChainTail = last.next;
			}
		}
	}

	if startAt.node == endAt.node {
		buffer : *Buffer;
		ifx startAt.node.added then buffer = *doc.addedData else buffer = *doc.originalData;

		if start == startAt.node.start {
			if count == startAt.node.length {
				// special case where we just remove the entire node
				remove_node_range(doc, startAt.node, startAt.node);
				if startAt.node.prev != null {
					newCursor.node = startAt.node.prev;
					newCursor.nodeStartOffset = startAt.nodeStartOffset - startAt.node.prev.length;
					newCursor.nodeStartLine = startAt.nodeStartLine - startAt.node.prev.lineFeedCount;
				}
				else {
					newCursor.node = doc.pieceChainHead;
					newCursor.nodeStartOffset = 0;
					newCursor.nodeStartLine = 0;
				}
				return newCursor;
			}
			nodeTrimLeft(startAt.node, buffer, end);

			newCursor.node = startAt.node;
			deletedInThisNode := buffer_cursor_to_offset(buffer, end) - buffer_cursor_to_offset(buffer, startAt.node.start);
			linesDeletedInThisNode := buffer_line_start_count(startAt.node.start, end);
			newCursor.nodeStartOffset = startAt.nodeStartOffset + deletedInThisNode;
			newCursor.nodeStartLine = startAt.nodeStartLine + linesDeletedInThisNode;
		}
		else if end == startAt.node.end {
			nodeTrimRight(startAt.node, buffer, start);

			newCursor.node = startAt.node;
			newCursor.nodeStartOffset = startAt.nodeStartOffset;
			newCursor.nodeStartLine = startAt.nodeStartLine;
		}
		else {
			newPieceRight := New(PieceChainNode,, doc.pieceChainAlloc);
			<<newPieceRight = <<startAt.node;
			nodeTrimLeft(newPieceRight, buffer, end);
			nodeTrimRight(startAt.node, buffer, start);

			startAt.node.next = newPieceRight;
			newPieceRight.prev = startAt.node;

			newCursor.node = newPieceRight;
			newCursor.nodeStartOffset = startAt.nodeStartOffset + startAt.node.length;
			newCursor.nodeStartLine = startAt.nodeStartLine + startAt.node.lineFeedCount;
		}
	}
	else {
		firstToDelete := startAt.node.next;
		if startAt.node.start == start {
			// delete whole start node
			firstToDelete = startAt.node;

			newCursor.nodeStartOffset = startAt.nodeStartOffset;
			newCursor.nodeStartLine = startAt.nodeStartLine;
		}
		else {
			// take some of start node
			buffer : *Buffer;
			ifx startAt.node.added then buffer = *doc.addedData else buffer = *doc.originalData;
			nodeTrimRight(startAt.node, buffer, start);

			newCursor.node = startAt.node;
			newCursor.nodeStartOffset = startAt.nodeStartOffset;
			newCursor.nodeStartLine = startAt.nodeStartLine;
		}
		lastToDelete := endAt.node.prev;
		if endAt.node.end == end {
			// delete whole end node
			lastToDelete = endAt.node;

			// In the event that we deleted the whole start node, the new cursor can just be the node after the end
			if newCursor.node == null {
				newCursor.node = endAt.node.next;
			}
		}
		else {
			// take some of end node
			buffer : *Buffer;
			ifx endAt.node.added then buffer = *doc.addedData else buffer = *doc.originalData;
			nodeTrimLeft(endAt.node, buffer, end);

			if newCursor.node == null {
				newCursor.node = endAt.node;
			}
		}
		
		// delete all nodes that are no longer needed
		remove_node_range(doc, firstToDelete, lastToDelete);
	}

	return newCursor;
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


document_cursor_step_one_forward :: (cursor: *DocumentCursor) -> u8 {
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
	if character == #char "\r" {
		return document_cursor_step_one_forward(cursor);
	}
	return character;
}

document_cursor_step_one_backward :: (cursor: *DocumentCursor) -> u8 {
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
	if character == #char "\n" {
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

document_get_line_range :: (doc: *Document, line: s64) -> s64, s64 {
	return document_get_line_start(doc, line), document_get_line_start(doc, line+1)-2;
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
		// if we iterated to a carraige return, we'd skip over it, so matching that behaviour
		// with a small hack that assumes newline always comes next
		// @todo: check if we can make this assumption?
		if char == #char "\r" return #char "\n"; else return char;
	}

	buffer: = ifx cursor.node.added then *cursor.doc.addedData else *cursor.doc.originalData;
	bufferOffset := buffer_cursor_to_offset(buffer, cursor.node.start) + offsetInNode;
	char := buffer.text[bufferOffset];
	if char == #char "\r" return #char "\n"; else return char;
}

document_cursor_get_coordinate :: (cursor: *DocumentCursor) -> Coordinate {
	curLine := document_cursor_get_line(cursor);
	curLineStart := document_get_line_start(cursor.doc, curLine);
	curColumn := cursor.documentOffset - curLineStart;

	return .{curLine, curColumn};
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
	// we may not need this now that the cursors skip over carraige returns
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
	// we may not need this now that the cursors skip over carraige returns
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
