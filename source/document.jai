
Document :: struct {
	// all the actual text in the document goes into document memory
	// such that it'll never have to be moved as we reserve loads of address space
	// All the supporting data such as the piece table and line start arrays go in
	// pieceTableMemory
	documentMemory: Flat_Pool;
	pieceTableMemory: Flat_Pool;
	documentAlloc: Allocator;
	pieceTableAlloc : Allocator;

	Buffer :: struct {
		text: []u8;
		lineStarts: [..]s64;
	}
	originalData: Buffer;
	addedData: Buffer;

	pieceTableHead: *PieceTableNode;
	pieceTableTail: *PieceTableNode;

	path: string;
}


PieceTableNode :: struct {
	next: *PieceTableNode;
	prev: *PieceTableNode;

	Pos :: struct {
		line: s64;
		col: s64;
	};
	added: bool;
	start: Pos;
	length: s64;
	lineStartCount: s64;
}

document_open :: (path: string) {
	doc : Document;
	documentAlloc := Allocator.{ proc = flat_pool_allocator_proc, data = *doc.documentMemory };
	pieceTableAlloc := Allocator.{ proc = flat_pool_allocator_proc, data = *doc.pieceTableMemory };

	doc.path = copy_string(path,,doc.documentAlloc);
	
    file := read_entire_file(path,,doc.documentAlloc);
	doc.originalData.text.data = file.data;
	doc.originalData.text.count = file.count;

	// for loop through the file, searching for hard line breaks
	doc.originalData.lineStarts.allocator = pieceTableAlloc;
	array_add(*doc.originalData.lineStarts, 0);
	for byte, i: doc.originalData.text {
		if byte == #char "\n" {
			// @TODO: +1 to skip over \r, if using \n line endings, don't need the +1
			array_add(*doc.originalData.lineStarts, xx (i+1));
		}
	}

	doc.pieceTableHead = New(PieceTableNode,, doc.pieceTableAlloc);
	doc.pieceTableHead.start = PieceTableNode.Pos.{0,0}; 
	doc.pieceTableHead.length = doc.originalData.text.count; 
	doc.pieceTableHead.lineStartCount = doc.originalData.lineStarts.count; 
	doc.pieceTableHead.added = false;

	// temp
	mainDocument = doc;
}

document_get_line_content :: (doc: *Document, lineNum: s64) -> string {
	builder: String_Builder;
	builder.allocator = temp;

	// @todo: potential optimization here is to cache the last visited nodes
	// and then search nearby, such that you can skip iterating all nodes for local queries of line content

	// additionally you can cache the last queried line, under the assumption that there
	// will be repeated queries for the line the cursor is currently sat on

	linesRemaining := lineNum;
	node: *PieceTableNode = doc.pieceTableHead;
	while node != null {
		buffer : *Document.Buffer;
		ifx node.added then buffer = *doc.addedData else buffer = *doc.originalData;

		// few possible cases here
		// lines remaining is 0 and there are no line starts in this node
			// copy the full node as we're after the line end
		// lines remaining is 0 and there are greater than 0 line starts in this node
			// the line ends here, so copy up to the first line start and end the loop
		// the lines remaining is cleanly less than the node line starts
			// in which case the full line is in this node
		// lines remaining is equal to the lineStarts
			// in which case the line starts in this node, but does not end in it
		// lines remaining is equal to line starts but there is no more nodes
			// it's the end of the document and the line ends in this node

		// node.lineStarts.count becomes node.lineFeedCount
		// node.offset becomes (buffer.linestarts[node.start.line] + node.start.col)
		// node.lineStarts[0] becomes buffer.lineStarts[node.start.line+1]
		// node.lineStarts[n] becomes buffer.lineStarts[node.start.line+1+n] (as long as n < node.linefeedcount)

		// Consider storing only line breaks, i.e. not offset 0 as a line start

		if linesRemaining == 0 && node.lineStartCount == 0 {
			// the line doesn't start or end in this node but the content is in the line
			offset := buffer.lineStarts[node.start.line] + node.start.col;
			start: *u8 = buffer.text.data + offset;
			len := node.length;
			append(*builder, start, len);
			node = node.next;
		}
		else if linesRemaining == 0 && node.lineStartCount > 0 {
			// the line ends in this node, but did not start here
			offset := buffer.lineStarts[node.start.line] + node.start.col;
			start: *u8 = buffer.text.data + offset;
			// We started  mid way through a line, and we want the offset to the _next_ line
			len := buffer.lineStarts[node.start.line + 1] - offset;
			append(*builder, start, len);
			break;
		}
		else if node.lineStartCount-1 == linesRemaining {
			// the target line starts in this node, and either the document ends, or the line does not end in this node
			nodeOffset := buffer.lineStarts[node.start.line] + node.start.col;
			targetLineOffset := buffer.lineStarts[node.start.line+linesRemaining];
			start: *u8 = buffer.text.data + targetLineOffset;
			len := (nodeOffset+node.length) - targetLineOffset;
			append(*builder, start, len); 
			linesRemaining = 0;
			node = node.next;
		}
		else if node.lineStartCount-1 > linesRemaining {
			// the target line is fully in this node
			targetLineOffset := buffer.lineStarts[node.start.line+linesRemaining];
			nextLineOffset := buffer.lineStarts[node.start.line+linesRemaining+1];
			start: *u8 = buffer.text.data + targetLineOffset;
			len := nextLineOffset - targetLineOffset;
			append(*builder, start, len); 
			break;
		}
		else {
			linesRemaining = linesRemaining - node.lineStartCount;
			node = node.next;
		}
	}

	return builder_to_string(*builder);
}

document_get_num_lines :: (doc: *Document) -> s64 {
	lines := 0;
	node: *PieceTableNode = doc.pieceTableHead;
	while node != null {
		lines = lines + node.lineStartCount;
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

