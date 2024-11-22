
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

document_open :: (path: string) {
	doc := *mainDocument;
	doc.documentMemory.alignment = 1; // @Todo, check this is okay, but it should be fine, we just want an endless char array
	doc.documentAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *doc.documentMemory };
	doc.pieceChainAlloc = Allocator.{ proc = flat_pool_allocator_proc, data = *doc.pieceChainMemory };

	doc.path = copy_string(path,,doc.documentAlloc);
    file := read_entire_file(path,,doc.documentAlloc);

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


	// find the target node where we will insert this new text
	// plus the buffer cursor in said node
	nodeToEdit: *PieceChainNode;
	insertPos: BufferCursor;
	{
		linesRemaining := location.line;
		columnsRemaining  := location.col;
		node: *PieceChainNode = doc.pieceChainHead;
		while node != null {
			buffer : *Buffer;
			ifx node.added then buffer = *doc.addedData else buffer = *doc.originalData;

			// here we are searching for a node with the column we want (having already found the line)
			if linesRemaining == 0 {
				if node.length > columnsRemaining {
					if node.length > columnsRemaining {
						// found the node
						nodeToEdit = node;
						insertPos.line = node.start.line;
						insertPos.offset = node.start.offset + columnsRemaining;
						break;
					}
					else {
						columnsRemaining -= node.length;
						node = node.next;
					}
				}
				else {
					columnsRemaining -= node.length;
					node = node.next;
				}
			}
			// here we are searching for a node with the line we want
			else {
				// @todo: this may need revisiting now we've done the line feed count change
				if node.lineFeedCount > linesRemaining {
					// how many columns for the target line are in this node?
					remainderColumns := node.length - buffer.lineStarts[linesRemaining];
					if remainderColumns > columnsRemaining {
						// found the node
						nodeToEdit = node;
						insertPos.line = linesRemaining;
						insertPos.offset = columnsRemaining;
						break;
					}
				}
				else {
					linesRemaining -= node.lineFeedCount;
					node = node.next;
				}
			}
		}
	}



	// now we know the node where we want to insert, and the cursor inside that node
	// deal with our three cases:

	// case 1: splitting a node

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

	// update the node next/prev
	nodeToEdit.next = newPiece;
	newPiece.prev = nodeToEdit;
	newPiece.next = newPieceRight;
	newPieceRight.prev = newPiece;


	// case 2: insert at end of node

	// case 3: insert at start of node

}

document_replace_text :: (doc: *Document, index: s64, text: string) {
}

document_delete_text :: (doc: *Document, index: s64, count: s64) {
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


	// consider a situation where buffer {0,0} always pointed to the base of the buffer
	// but line 1 of the document was considered a line
	// so lineStarts[0] = 0
	// and in original data you'd have
	// lineStarts[1] = 0 as well

	// it seems that VS code also always has a 0 value in the lineStarts array
	// it doesn't add a second line start

	// My feeling is that we really need to re-evaluate all our code
	// under the assumption that we store the start of our buffer
	// as a line start 0, and then the nodes store a line feed count instead
	// then redesign the algorithms in getlinecontent and insert to cope with this fact


	while node != null {
		buffer : *Buffer;
		ifx node.added then buffer = *doc.addedData else buffer = *doc.originalData;

		// step 1:
		// find the node which contains the target line
			// what constitutes the line starting here?

			// consider first situation node for whole doc 
			// linesRemaining = 0, lfc = 80
			// then buffercursor for the line is {linesRemaining, 0} to {linesRemaining+1, 0}

			// consider we want the final line 80
			// linesRemaining 80, lfc = 80
			// then buffercursor for the line is {linesRemaining, 0}, to node.end

			// consider a line does not end in this node because of an insert
			// linesRemaining = 2, lfc=2 
			// then buffercursor for the line is {linesRemaining, 0} to node.end

			// next node is a 1 char edit with no lines
			// linesRemaining = 0, lfc = 0
			// since linesRemaining = 0, we've found the start
			// since lfc is zero, copy everything

			// next node is the rest of the file
			// linesRemaining = 0, lfc = 79
			// since lfc > linesRemaining copy up until lineStarts[start.line]

			// what about linesRemaining = 70, but lfc = 2
			// then skip the node entirely
		// step 2:
		// if there is another line in this node, then copy up to that
		// if there is not, move on to the next node
		// if copy full nodes until you reach a node with a line feed count of 1 or more

		// assumptions:
		// the lineStarts array always has a start at 0
		// this is the start of the document in the original buffer, but in the added buffer it is not a real line start
		// lineNum is zero indexed
		// nodes store linefeedcount, not line starts

		// YOU DID IT!!!
		// this works and it's much cleaner!!!!
		// you need to move the cursor after an edit now to make it feel good
		// then do the other two insert cases

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
			startOffset:= buffer_cursor_to_offset(buffer, .{linesRemaining, 0});
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

// Find the actual offset into the given buffer from a cursor for that buffer
buffer_cursor_to_offset :: (buffer: *Buffer, cursor: BufferCursor) -> s64 {
	return buffer.lineStarts[cursor.line] + cursor.offset;
}

// figure out how many linestarts are between start and length in the given buffer
buffer_line_start_count :: (start: BufferCursor, end: BufferCursor) -> s64 {
	// ??? not 100% sure this is correct

	// for left node, we want 3
	// we have {0, 0} to {2, 3} 
	// diff = 2
	// for middle node, we want 0 as the num line starts
	// we have {0, 0} to {0, 1}
	// diff 0
	// for last node we want 79
	// we have {2, 3} to {80, 13}
	// diff 78

	// I think it's obvious that in the middle case
	// the difference is 0 cause we don't traverse more than one line
	// why do we want + 1 in the other cases?

	return (end.line - start.line);
}
