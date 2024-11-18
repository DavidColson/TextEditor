
Document :: struct {
	// all the actual text in the document goes into document memory
	// such that it'll never have to be moved as we reserve loads of address space
	// All the supporting data such as the piece table and line start arrays go in
	// pieceTableMemory
	documentMemory: Flat_Pool;
	pieceTableMemory: Flat_Pool;
	documentAlloc: Allocator;
	pieceTableAlloc : Allocator;

	originalData: []u8;
	addedData: []u8;

	pieceTableHead: *PieceTableNode;
	pieceTableTail: *PieceTableNode;

	path: string;
}


PieceTableNode :: struct {
	next: *PieceTableNode;
	prev: *PieceTableNode;

	added: bool;
	offset: s64;
	length: s64;
	lineStarts: [..]s64;
}

document_open :: (path: string) {
	doc : Document;
	documentAlloc := Allocator.{ proc = flat_pool_allocator_proc, data = *doc.documentMemory };
	pieceTableAlloc := Allocator.{ proc = flat_pool_allocator_proc, data = *doc.pieceTableMemory };

	doc.path = copy_string(path,,doc.documentAlloc);
	
    file := read_entire_file(path,,doc.documentAlloc);
	doc.originalData.data = file.data;
	doc.originalData.count = file.count;

	doc.pieceTableHead = New(PieceTableNode,, doc.pieceTableAlloc);
	doc.pieceTableHead.offset = 0; 
	doc.pieceTableHead.length = doc.originalData.count; 
	doc.pieceTableHead.lineStarts.allocator = doc.pieceTableAlloc;

	// for loop through the file, searching for hard line breaks
	array_add(*doc.pieceTableHead.lineStarts, 0);
	for byte, i: doc.originalData {
		if byte == #char "\n" {
			// @TODO: +1 to skip over \r, if using \n line endings, don't need the +1
			array_add(*doc.pieceTableHead.lineStarts, xx (i+1));
		}
	}

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

	linesRemaining := lineNum+1;
	node: *PieceTableNode = doc.pieceTableHead;
	while node != null {
		buffer : *[]u8;
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

		if linesRemaining == 0 && node.lineStarts.count == 0 {
			// the line doesn't start or end in this node but the content is in the line

			// start would become buffer.data + (buffer.linestarts[node.start.line] + node.start.col)
			start: *u8 = buffer.data + node.offset;
			len := node.length;
			append(*builder, start, len);
			node = node.next;
		}
		else if linesRemaining == 0 && node.lineStarts.count > 0 {
			// the line ends in this node, but did not start here
			start: *u8 = buffer.data + node.offset;
			// We started  mid way through a line, and we want the offset to the _next_ line
			// you want buffer.lineStarts[node.start.line+1] - node.offset (above)
			len := node.lineStarts[0] - node.offset;
			append(*builder, start, len);
			break;
		}
		else if node.lineStarts.count == linesRemaining {
			// the target line starts in this node, and either the document ends, or the line does not end in this node
			start: *u8 = buffer.data + node.lineStarts[linesRemaining-1];
			len := (node.offset+node.length) - node.lineStarts[linesRemaining-1];
			append(*builder, start, len); 
			linesRemaining = 0;
			node = node.next;
		}
		else if node.lineStarts.count > linesRemaining {
			// the target line is fully in this node
			start: *u8 = buffer.data + node.lineStarts[linesRemaining-1];
			len := node.lineStarts[linesRemaining] - node.lineStarts[linesRemaining-1];
			append(*builder, start, len); 
			break;
		}
		else {
			linesRemaining = linesRemaining - node.lineStarts.count;
			node = node.next;
		}
	}

	return builder_to_string(*builder);
}

document_get_num_lines :: (doc: *Document) -> s64 {
	lines := 0;
	node: *PieceTableNode = doc.pieceTableHead;
	while node != null {
		lines = lines + node.lineStarts.count;
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

