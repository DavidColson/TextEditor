
// @todo: once this replaces the old document system it will be renamed to just "Document"
PieceTree :: struct {

	Piece :: struct {
		start: BufferCursor;
		end: BufferCursor;
		length: s64;
		lineFeedCount: s64;
		bufferIndex: u8;
	}

	Buffer :: struct {
		text: []u8;
		lineStarts: [..]s64;
	}

	BufferCursor :: struct {
		line: s64;
		column: s64;
	}

	NodeData :: struct {
		piece: Piece;
		leftSubtreeLength : s64;
		leftSubtreeLfCount : s64;
	}

	Node :: struct {
		allocator: Allocator;
		color: Color;
		using data: NodeData;
		left: *Node;
		right: *Node;
	}

	Color :: enum {
		RED;
		BLACK;
	}

	LineEndingMode :: enum {
		CRLF;
		LF;
		MIXED_MAJORITY_LF;
		MIXED_MAJORITY_CRLF;
	}

	Iterator :: struct {
		doc: *PieceTree;
		offset: s64;
		node: *Node;
		stack: [..]*Node;
		firstChar: *u8;
		lastChar: *u8;
	}

	tree: *Node;
	buffers: [2]Buffer;
	lastInsert: BufferCursor;
	lineEndings: LineEndingMode;

	// Note it will not be threadsafe to share these pools
	// Between copies of the tree and allow any allocation
	treeMemory: Flat_Pool;
	bufferMemory: Flat_Pool;
	otherMemory: Flat_Pool;


	// What we combine tree memory and other memory as before
	// And could they be shared with a mutex? No cause we'd be sharing by copy?
	// could we just have a wholly different struct to share?
	// means we have duplicate functions or something, guess you could use some polymorphism or something
	// Not a bad idea to be honest. Means we can dictate harshly what you can and can't do with a "DocumentView"
	// The query functions will work fine, but editing will not
	// You could also make a WritableView which has a pointer to the actual document, and as such
	// can have a mutex on the memory pools, then you can make your edits
}


tree_test :: () {
	pieceTree: PieceTree;
	pieceTree.bufferMemory.alignment = 1; // important!! make this hard to miss
	
	f, success := file_open("build_shorter.jai");
	if !success {
		push_notification("File open failed");
	}
	file: string;
    file, success = read_entire_file(f,,buffer_allocator(*pieceTree));
	if !success {
		push_notification("File read failed");
	}
	file_close(*f);

	pieceTree.buffers[0].text.data = file.data;
	pieceTree.buffers[0].text.count = file.count;

	build_piece_tree(*pieceTree);

	pretty_print_tree(pieceTree.tree);

	insert(*pieceTree, 100, "hello world");
	insert(*pieceTree, 105, " my");
	pretty_print_tree(pieceTree.tree);
	insert(*pieceTree, 110, "test ");
	insert(*pieceTree, 200, "again more");

	pretty_print_tree(pieceTree.tree);

	// what is the experience of an iterator

	iterator := make_iterator(*pieceTree, 0);
	for iterator {
		print("%", string.{1, *it});
	}

	count := 0;
	iterator = make_iterator(*pieceTree, 0);
	while iterator.node != null {
		log("Index: %, nodeLen %", count, iterator.node.piece.length);
		next_node(*iterator);
		count += 1;
	}

	char1 := get_char_at(*pieceTree, 101);
	char2 := get_char_at(*pieceTree, 113);
	char3 := get_char_at(*pieceTree, 3);
	log("char1 %", string.{1, *char1});
	log("char2 %", string.{1, *char2});
	log("char3 %", string.{1, *char3});

	log("num lines %", get_number_of_lines(*pieceTree));

	// line starts
	log("line start 0, %", get_line_start(*pieceTree, 0));
	log("line start 1, %", get_line_start(*pieceTree, 1));
	log("line start 2, %", get_line_start(*pieceTree, 2));
	log("line start 3, %", get_line_start(*pieceTree, 3));

	// line ranges
	start, end := get_line_range(*pieceTree, 2, false);
	log("line range for line 2 %, %", start, end);

	line,col := get_coordinate_from_offset(*pieceTree, 100);
	log("from offset 100 we get (%,%)", line,col);
}

// Piece Tree API

build_piece_tree :: (pieceTree: *PieceTree) {
	// This assumes you've already put your initial data in the first buffer slot!!

	pieceTree.buffers[1].text.data = pieceTree.buffers[0].text.data + pieceTree.buffers[0].text.count;
	pieceTree.buffers[1].text.count = 0;

	// count line starts
	lineStarts := *pieceTree.buffers[0].lineStarts;
	lineStarts.allocator = other_allocator(pieceTree);

	array_add(lineStarts, 0);
	lfCount := 0;
	crCount := 0;
	crlfCount := 0;
	i := 0;
	while i < pieceTree.buffers[0].text.count {
		byte := pieceTree.buffers[0].text[i];
		if byte == #char "\r" {
			if i < pieceTree.buffers[0].text.count-1 && pieceTree.buffers[0].text[i+1] == #char "\n" {
				crlfCount += 1;
				array_add(lineStarts, xx (i+2));
				i += 1; // skip \n
			}
			else {
				crCount += 1;
			}
		}
		else if byte == #char "\n" {
			lfCount += 1;
			array_add(lineStarts, xx (i+1));
		}
		i += 1;
	}
	if lfCount > 0 && crlfCount == 0 && crCount == 0 {
		pieceTree.lineEndings = .LF;
	}
	else if lfCount == 0 && crlfCount > 0 && crCount == 0 {
		pieceTree.lineEndings = .CRLF;
	}
	else if lfCount > 0 && crlfCount > 0 && crCount == 0 {
		if lfCount > crlfCount {
			pieceTree.lineEndings = .MIXED_MAJORITY_LF;
		}
		else {
			pieceTree.lineEndings = .MIXED_MAJORITY_CRLF;
		}
	}
	else if crCount > 0 {
		push_notification("File has CR line endings, undefined behaviour will occur");
	}

	lineStarts2 := *pieceTree.buffers[1].lineStarts;
	lineStarts2.allocator = other_allocator(pieceTree);
	array_add(lineStarts2, 0);

	// make root rb node
	firstPiece: PieceTree.Piece;
	firstPiece.length = pieceTree.buffers[0].text.count;
	firstPiece.lineFeedCount = pieceTree.buffers[0].lineStarts.count-1;
	firstPiece.start = .{0,0};
	firstPiece.end = .{firstPiece.lineFeedCount, pieceTree.buffers[0].text.count - pieceTree.buffers[0].lineStarts[firstPiece.lineFeedCount]};
	firstPiece.bufferIndex = 0;

	pieceTree.tree = make_rb_tree(*tree_allocator(pieceTree), firstPiece);
}

insert :: (pieceTree: *PieceTree, atOffset: s64, text: string) {
	// insert text at offset in document

	node, remainder, nodeStartOffset := node_at_offset(pieceTree.tree, atOffset);
	insertCursor := buffer_offset_to_cursor(pieceTree, node.piece, remainder);

	// need the line/column in the buffer?, lets see for later
	
	// first case, inserting at the start of a node
	if atOffset == nodeStartOffset {
		// @todo: special case where the last insertion occured at the end of the previous node
		newPiece := make_piece(pieceTree, text);
		pieceTree.tree = insert_node(tree_allocator(pieceTree), pieceTree.tree, newPiece, atOffset);
		return;
	}

	// second case, inserting at end of a node
	if atOffset == nodeStartOffset+node.piece.length {
		// @todo: special case where the last insertion occured here
		newPiece := make_piece(pieceTree, text);
		pieceTree.tree = insert_node(tree_allocator(pieceTree), pieceTree.tree, newPiece, atOffset);
		return;
	}

	// final case, inserting in the middle of a node
	newPieceLeft := node_trim_right(pieceTree, node.piece, insertCursor);
	newPieceMiddle := make_piece(pieceTree, text);
	newPieceRight := node_trim_left(pieceTree, node.piece, insertCursor);

	tree := remove_node(pieceTree.tree, nodeStartOffset);

	tree = insert_node(tree_allocator(pieceTree), tree, newPieceLeft, nodeStartOffset);
	tree = insert_node(tree_allocator(pieceTree), tree, newPieceMiddle, nodeStartOffset + newPieceLeft.length);
	tree = insert_node(tree_allocator(pieceTree), tree, newPieceRight, nodeStartOffset + newPieceLeft.length + newPieceMiddle.length);

	pieceTree.tree = tree;
}

delete :: (pieceTree: *PieceTree, atOffset: s64, length: s64) {
	// delete length bytes in the document at offset
}

get_char_at :: (doc: *PieceTree, offset: s64) -> u8 {
	// get the literal char at the given offset

	node, remainder, _ := node_at_offset(doc.tree, offset);
	bufferIndex := node.piece.bufferIndex;
	startOffset := buffer_cursor_to_offset(*doc.buffers[bufferIndex], node.piece.start);
	charPtr := doc.buffers[bufferIndex].text.data + startOffset + remainder;
	return charPtr.*;
}

get_line_start :: (doc: *PieceTree, line: s64) -> s64 {
	// get the document offset of a specific line (0 indexed) via binary search
	node := doc.tree;
	lineInSubtree := line;
	nodeStartOffset: s64;
	lineFeedCount: s64;
	while node != null {
		if lineInSubtree <= node.leftSubtreeLfCount {
			// Target must be in the left side of the tree
			node = node.left;
		}
		else if lineInSubtree <= node.leftSubtreeLfCount + node.piece.lineFeedCount {
			// Target must be within this node
			nodeStartOffset += node.leftSubtreeLength;
			lineFeedCount += node.leftSubtreeLfCount;

			lineInThisNode := line - lineFeedCount;
			buffer := *doc.buffers[node.piece.bufferIndex];
			return nodeStartOffset + (buffer_cursor_to_offset(buffer, .{lineInThisNode, 0}) - buffer_cursor_to_offset(buffer, node.piece.start));
		}
		else {
			if node.right == null {
				return length(doc.tree); // at end of document, just return the length
			}
			// Target must be in the right side of the tree
			lineInSubtree -= node.leftSubtreeLfCount + node.piece.lineFeedCount;
			nodeStartOffset += node.leftSubtreeLength + node.piece.length;
			lineFeedCount += node.leftSubtreeLfCount + node.piece.lineFeedCount;
			node = node.right;
		}
	}

	return 0;
}

get_line_range :: (doc: *PieceTree, line: s64, includeLineEndings := false) -> s64, s64 {
	// find the start and end offsets of the given line, with or without line endings
	lineStart := get_line_start(doc, line);
	lineEnd := get_line_start(doc, line+1);

	if !includeLineEndings {
		rem := 0;
		if get_char_at(doc, lineEnd-1) == #char "\n" {
			rem += 1;
		}
		if get_char_at(doc, lineEnd-2) == #char "\r" {
			rem += 1;
		}
		return lineStart, lineEnd - rem;
	}
	return lineStart, lineEnd;
}

get_coordinate_from_offset :: (doc: *PieceTree, offset: s64) -> s64, s64 {
	// get line, column from a given offset
	node, remainder, nodeStart, line := node_at_offset(doc.tree, offset);
	lineStart := get_line_start(doc, line);
	return line, offset-lineStart;
}

get_offset_from_coordinate :: (doc: *PieceTree, line: s64, column: s64) -> s64 {
	// Note, if you provide a column that is off the length of the line, it will clamp
	// decide at some point if that's desirable
	lineStart, lineEnd := get_line_range(doc, line);
	column = min(lineEnd-lineStart, column);
	return lineStart + column;
}

get_line_content :: (document: *PieceTree, line: s64) -> string {
	// use iterator for this, give back copy of line data (allocate)
	return "";
}

get_content_range :: (document: *PieceTree, offset: s64, range: s64) -> string {
	// get range chars at offet (copy)
	return "";
}

get_number_of_lines :: (doc: *PieceTree) -> s64 {
	return lf_count(doc.tree);
}

// Tree iterators

make_iterator :: (document: *PieceTree, startOffset: s64 = 0) -> PieceTree.Iterator {
	// starting at some non trivial offset will require doing a binary search in the tree for that offset
	// and saving the node, as we have done with node_at
	iter: PieceTree.Iterator;
	iter.doc = document;
	iter.stack.allocator = context.allocator;

	jump_to(*iter, startOffset);
	return iter;
}

next_node :: (iterator: *PieceTree.Iterator) {
	// if you want to do a prev_node version, just flip left and right nodes in here

	node := iterator.node;
	newNode := iterator.node.right;
	if newNode != null {
		// In this first case we are dealing with the situation that the node has a right child
		// we must iterate down it's left side until we get to a leaf, which is the next node for us
		while newNode != null {
			node = newNode;
			array_add(*iterator.stack, node);
			newNode = node.left;
		}
	}
	else {
		// In this second case, we are dealing with the situation that the node has no right child
		// Therefore we must go up to a previous parent such that the current node is NOT the right
		// side of the parent. Otherwise there is nowhere else to proceed
	
		oldNode := node.right;
		while oldNode == node.right || node == oldNode {
			if iterator.stack.count == 0 {
				node = null;
				break;
			}
			oldNode = node;
			node = iterator.stack[iterator.stack.count-1];
			iterator.stack.count -= 1;
		}
	}

	// node was found, setup the range pointers
	if node != null {
		bufferIndex := node.piece.bufferIndex;
		startOffset := buffer_cursor_to_offset(*iterator.doc.buffers[bufferIndex], node.piece.start);
		endOffset := buffer_cursor_to_offset(*iterator.doc.buffers[bufferIndex], node.piece.end);

		iterator.firstChar = iterator.doc.buffers[bufferIndex].text.data + startOffset;
		iterator.lastChar = iterator.doc.buffers[bufferIndex].text.data + endOffset;
		iterator.node = node;
		return;
	}

	// if no node found
	iterator.node = null;
	iterator.firstChar = null;
	iterator.lastChar = null;
	array_reset(*iterator.stack);
}

jump_to :: (iterator: *PieceTree.Iterator, offset: s64) {
	iterator.offset = offset;
	node := iterator.doc.tree;
	remainder := 0;

	nodeStartOffset := 0;
	while node != null {
		array_add(*iterator.stack, node);
		if offset < node.leftSubtreeLength {
			// Target must be in the left side of the tree
			node = node.left;
		}
		else if offset <= node.leftSubtreeLength + node.piece.length {
			// Target must be within this node
			nodeStartOffset += node.leftSubtreeLength;
			remainder = offset - nodeStartOffset;
			break;
		}
		else {
			// Target must be in the right side of the tree
			leftSideOffset := node.leftSubtreeLength + node.piece.length;
			nodeStartOffset += leftSideOffset;
			offset -= leftSideOffset; // Our offset now must be relative to the right side of the tree
			node = node.right;
		}
	}

	// node was found
	if node != null {
		bufferIndex := node.piece.bufferIndex;
		startOffset := buffer_cursor_to_offset(*iterator.doc.buffers[bufferIndex], node.piece.start);
		endOffset := buffer_cursor_to_offset(*iterator.doc.buffers[bufferIndex], node.piece.end);

		iterator.firstChar = iterator.doc.buffers[bufferIndex].text.data + startOffset + remainder;
		iterator.lastChar = iterator.doc.buffers[bufferIndex].text.data + endOffset;
		iterator.node = node;
		return;
	}

	// if no node found
	iterator.node = null;
	iterator.firstChar = null;
	iterator.lastChar = null;
	array_reset(*iterator.stack);
}

for_expansion :: (iterator: *PieceTree.Iterator, body: Code, flags: For_Flags) #expand {
	while iterator.node != null {
		counter := 0;
		while iterator.firstChar < iterator.lastChar {
			`it_index := counter;
			`it := iterator.firstChar.*;
			#insert body;
			counter += 1;
			iterator.firstChar += 1;
		}
		next_node(iterator);
	}
}

#scope_file

// Piece Tree helpers

make_piece :: (pieceTree: *PieceTree, t: string) -> PieceTree.Piece {
	// firstly copy the text into the add buffer

	newPiece: PieceTree.Piece;
	newPiece.length = t.count;
	newPiece.bufferIndex = 1; // add buffer

	text := copy_string(t,, buffer_allocator(pieceTree));
	currentBufferEnd := pieceTree.buffers[1].text.count;
	pieceTree.buffers[1].text.count = pieceTree.buffers[1].text.count + text.count;

	// count line endings
	// @todo: might be a good location to correct bad line endings
	// @todo: otherwise mark if the line endings have changed based on something new
	lineFeedCount := 0;
	for byte, i: text {
		if byte == #char "\n" {
			array_add(*pieceTree.buffers[1].lineStarts, xx (currentBufferEnd + i + 1));
			lineFeedCount += 1;
		}
	}
	newPiece.lineFeedCount = lineFeedCount;

	newPiece.start = pieceTree.lastInsert;
	endLine := pieceTree.buffers[1].lineStarts.count-1;
	newPiece.end = .{ endLine, pieceTree.buffers[1].text.count - pieceTree.buffers[1].lineStarts[endLine] };
	pieceTree.lastInsert = newPiece.end;

	return newPiece;
}

node_at_offset :: (node: *PieceTree.Node, offset: s64) -> node: *PieceTree.Node, remainder: s64, nodeStartOffset: s64, line: s64 {
	// This is basically a binary search

	offsetInSubtree := offset;
	nodeStartOffset: s64;
	lineFeedCount: s64;
	while node != null {
		if offsetInSubtree < node.leftSubtreeLength {
			// Target must be in the left side of the tree
			node = node.left;
		}
		else if offsetInSubtree <= node.leftSubtreeLength + node.piece.length {
			// Target must be within this node
			nodeStartOffset += node.leftSubtreeLength;
			lineFeedCount += node.leftSubtreeLfCount;
			
			remainder := offset - nodeStartOffset;
			return node, remainder, nodeStartOffset, lineFeedCount;
		}
		else {
			if node.right == null {
				// end of the tree, we'll just go with the current node, at the very end
				leftSideOffset := node.leftSubtreeLength;
				nodeStartOffset += leftSideOffset;
				lineFeedCount += node.leftSubtreeLfCount + node.piece.lineFeedCount;
				remainder := node.piece.length;
				return node, remainder, nodeStartOffset, lineFeedCount;
			}

			// Target must be in the right side of the tree
			leftSideOffset := node.leftSubtreeLength + node.piece.length;
			
			offsetInSubtree -= leftSideOffset; // Our offset now must be relative to the right side of the tree

			nodeStartOffset += leftSideOffset;
			lineFeedCount += node.leftSubtreeLfCount + node.piece.lineFeedCount;
			node = node.right;
		}
	}

	return null, 0, 0, 0;
}

node_trim_left :: (pieceTree: *PieceTree, piece: PieceTree.Piece, pos: PieceTree.BufferCursor) -> PieceTree.Piece {
	buffer := *pieceTree.buffers[piece.bufferIndex];
	newPiece := piece;

	// remove the left side of piece up to pos
	bufferOffsetStart := buffer_cursor_to_offset(buffer, piece.start);
	bufferOffsetSplit := buffer_cursor_to_offset(buffer, pos);
	lenRight := (bufferOffsetStart + piece.length) - bufferOffsetSplit;

	newPiece.start = pos;
	newPiece.length = lenRight;
	newPiece.lineFeedCount = buffer_line_start_count(newPiece.start, newPiece.end);
	return newPiece;
}

node_trim_right :: (pieceTree: *PieceTree, piece: PieceTree.Piece, pos: PieceTree.BufferCursor) -> PieceTree.Piece {
	buffer := *pieceTree.buffers[piece.bufferIndex];
	newPiece := piece;

	// remove the right side of piece from pos
	bufferOffsetStart := buffer_cursor_to_offset(buffer, piece.start);
	bufferOffsetSplit := buffer_cursor_to_offset(buffer, pos);
	lenLeft := bufferOffsetSplit - bufferOffsetStart;

	newPiece.end = pos;
	newPiece.length = lenLeft;
	newPiece.lineFeedCount = buffer_line_start_count(newPiece.start, newPiece.end);
	return newPiece;
}

buffer_offset_to_cursor :: (pieceTree: *PieceTree, piece: PieceTree.Piece, offsetInNode: s64) -> PieceTree.BufferCursor {
	// Calculate a buffer cursor for a given offset _within_ the given node,
	// that is offset >= 0 && offset < node.length

	buffer := *pieceTree.buffers[piece.bufferIndex];
	offset := buffer_cursor_to_offset(buffer, piece.start) + offsetInNode;
	low := piece.start.line;
	high := piece.end.line;
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

	return .{mid, offset - midStartOffset};
}

buffer_cursor_to_offset :: (buffer: *PieceTree.Buffer, pos: PieceTree.BufferCursor) -> s64 {
	return buffer.lineStarts[pos.line] + pos.column;
}

buffer_line_start_count :: (start: PieceTree.BufferCursor, end: PieceTree.BufferCursor) -> s64 {
	return (end.line - start.line);
}

// Allocator helpers

tree_allocator :: (pieceTree: *PieceTree) -> Allocator {
	return Allocator.{ proc = flat_pool_allocator_proc, data = *pieceTree.treeMemory };
}

buffer_allocator :: (pieceTree: *PieceTree) -> Allocator {
	return Allocator.{ proc = flat_pool_allocator_proc, data = *pieceTree.bufferMemory };
}

other_allocator :: (pieceTree: *PieceTree) -> Allocator {
	return Allocator.{ proc = flat_pool_allocator_proc, data = *pieceTree.otherMemory };
}

// Basic Red Black tree API

make_rb_tree :: (allocator: Allocator, piece: PieceTree.Piece) -> *PieceTree.Node {
	return new_node(allocator, .BLACK, .{ piece, 0, 0 }, null, null);
}

insert_node :: (allocator: Allocator, root: *PieceTree.Node, piece: PieceTree.Piece, at: s64) -> *PieceTree.Node {
	if root == null then return make_rb_tree(allocator, piece);

	t :=  internal_insert(root.allocator, root, .{piece, 0, 0}, at, 0);
	return new_node(root.allocator, .BLACK, t.data, t.left, t.right);
}

remove_node :: (root: *PieceTree.Node, at: s64) -> *PieceTree.Node {
	t := internal_remove(root, at, 0);
	if t == null then return null;
	return new_node(root.allocator, .BLACK, t.data, t.left, t.right);
}

length :: (root: *PieceTree.Node) -> s64 {
	if root == null {
		return 0;
	}
	return root.leftSubtreeLength + root.piece.length + length(root.right);
 }

lf_count :: (root: *PieceTree.Node) -> s64 {
	if root == null {
		return 0;
	}
	return root.leftSubtreeLfCount + root.piece.lineFeedCount + lf_count(root.right);
}

pretty_print_tree :: (node: *PieceTree.Node) {
	pretty_print_tree(node, "", false);
}

// insertion helpers

new_node :: (allocator: Allocator, color: PieceTree.Color, data: PieceTree.NodeData, left: *PieceTree.Node, right: *PieceTree.Node) -> *PieceTree.Node {
	newNode := New(PieceTree.Node,,allocator);
	newNode.allocator = allocator;
	newNode.color = color;
	newNode.data = data;
	newNode.leftSubtreeLength = length(left);
	newNode.leftSubtreeLfCount = lf_count(left);
	newNode.left= left;
	newNode.right= right;
	return newNode;
}

internal_insert :: (allocator: Allocator, root: *PieceTree.Node, nodeData: PieceTree.NodeData, at: s64, totalOffset: s64) -> *PieceTree.Node {
	// ending case of the recursion, just make a new leaf node
	if root == null {
		return new_node(allocator, .RED, nodeData, null, null);
	}

	// in this case we insert on the left side of the tree (modifying the left node)
	if at < (totalOffset + root.leftSubtreeLength + root.piece.length) {
		newLeft := internal_insert(allocator, root.left, nodeData, at, totalOffset);
		return balance(allocator, root.color, root.data, newLeft, root.right);
	}

	// in this case we insert on the right side of the tree (modifying the right node)
	else {
		newRight := internal_insert(allocator, root.right, nodeData, at, totalOffset + root.leftSubtreeLength + root.piece.length);
		return balance(allocator, root.color, root.data, root.left, newRight);
	}
}

balance :: (allocator: Allocator, c: PieceTree.Color, data: PieceTree.NodeData, left: *PieceTree.Node, right: *PieceTree.Node) -> *PieceTree.Node {
	// We cannot have a parent and child both be red
	// so what we are doing here is checking for that case on either the left or right side
	// and if it is doubled, we rotate to fix it up
	// see  https://bartoszmilewski.com/2013/11/25/functional-data-structures-in-c-trees/

	// each case will find a possible double red, and rotate it such that the red violation percolates
	// up to the top of the tree. Repeatedly doing this will correct the tree
	if c == .BLACK && doubled_left(left) {
		newRight := new_node(allocator, .BLACK, data, left.right, right);
		return new_node(allocator, .RED, left.data, paint(left.left, .BLACK), newRight);
	}
	else if c == .BLACK && doubled_right(left) {
		newLeft := new_node(allocator, .BLACK, left.data, left.left, left.right.left);
		newRight := new_node(allocator, .BLACK, data, left.right.right, right);
		return new_node(allocator, .RED, left.right.data, newLeft, newRight);
	}
	else if c == .BLACK && doubled_left(right) {
		newLeft := new_node(allocator, .BLACK, data, left, right.left.left);
		newRight := new_node(allocator, .BLACK, right.data, right.left.right, right.right);
		return new_node(allocator, .RED, right.left.data, newLeft, newRight);
	}
	else if c == .BLACK && doubled_right(right) {
		newLeft := new_node(allocator, .BLACK, data, left, right.left);
		return new_node(allocator, .RED, right.data, newLeft, paint(right.right, .BLACK));
	}
	return new_node(allocator, c, data, left, right);
}

doubled_left :: (node: *PieceTree.Node) -> bool {
	return node != null && node.color == .RED && node.left != null && node.left.color == .RED;
}

doubled_right :: (node: *PieceTree.Node) -> bool {
	return node != null && node.color == .RED && node.right != null && node.right.color == .RED;
}

paint :: (node: *PieceTree.Node, color: PieceTree.Color) -> *PieceTree.Node {
	assert(node != null);
	return new_node(node.allocator, color, node.data, node.left, node.right);
}

// Removal helpers

internal_remove :: (root: *PieceTree.Node, at: s64, totalOffset: s64) -> *PieceTree.Node {
	if root == null then return null;

	if at < totalOffset + root.leftSubtreeLength {
		return remove_left(root, at, totalOffset);
	}
	if at == totalOffset + root.leftSubtreeLength {
		return fuse(root.left, root.right);
	}
	return remove_right(root, at, totalOffset);
}

remove_left :: (root: *PieceTree.Node, at: s64, totalOffset: s64) -> *PieceTree.Node {
	newLeft := internal_remove(root.left, at, totalOffset);
	newNode := new_node(root.allocator, .RED, root.data, newLeft, root.right);

	if root.left && root.left.color == .BLACK {
		return balance_left(newNode);
	}
	return newNode;
}

remove_right :: (root: *PieceTree.Node, at: s64, totalOffset: s64) -> *PieceTree.Node {
	newRight := internal_remove(root.right, at, totalOffset + root.leftSubtreeLength + root.piece.length);
	newNode := new_node(root.allocator, .RED, root.data, root.left, newRight);

	if root.right && root.right.color == .BLACK {
		return balance_right(newNode);
	}
	return newNode;
}

balance_right :: (right: *PieceTree.Node) -> *PieceTree.Node {
	if right.right != null && right.right.color == .RED {
		return new_node(right.allocator, .RED, right.data, right.left, paint(right.right, .BLACK));
	}
	if right.left != null && right.left.color == .BLACK {
		newRight := new_node(right.allocator, .BLACK, right.data, paint(right.left, .RED), right.right);
		return balance(newRight);
	}
	if right.left != null && right.left.color == .RED && right.left.right != null && right.left.right.color == .BLACK {
		unbalancedNewLeft := new_node(right.allocator, .BLACK, right.left.data, paint(right.left.left, .RED), right.left.right.left);

		newLeft := balance(unbalancedNewLeft);
		newRight := new_node(right.allocator, .BLACK, right.data, right.left.right.right, right.right);

		return new_node(right.allocator, .RED, right.left.right.data, newLeft, newRight);
	}
	assert(false); // should be unreachable
	return right;
}

balance_left :: (left: *PieceTree.Node) -> *PieceTree.Node {
	if left.left != null && left.left.color == .RED {
		return new_node(left.allocator, .RED, left.data, paint(left.left, .BLACK), left.right);
	}
	if left.right != null && left.right.color == .BLACK {
		newLeft := new_node(left.allocator, .BLACK, left.data, left.left, paint(left.right, .RED));
		return balance(newLeft);
	}
	if left.right != null && left.right.color == .RED && left.right.left != null && left.right.left.color == .BLACK {
		unbalancedNewRight := new_node(left.allocator, .BLACK, left.right.data, left.right.left.right, paint(left.right.right, .RED));
		
		newRight := balance(unbalancedNewRight);
		newLeft := new_node(left.allocator, .BLACK, left.data, left.left, left.right.left.left);

		return new_node(left.allocator, .RED, left.right.left.data, newLeft, newRight);
	}
	assert(false); // should be unreachable
	return left;
}

balance :: (node: *PieceTree.Node) -> *PieceTree.Node {
	if node.left != null && node.left.color == .RED && node.right != null && node.right.color == .RED {
		left := paint(node.left, .BLACK);
		right := paint(node.right, .BLACK);
		return new_node(node.allocator, .RED, node.data, left, right);
	}
	assert(node.color == .BLACK);
	return balance(node.allocator, node.color, node.data, node.left, node.right);
}

fuse :: (left: *PieceTree.Node, right: *PieceTree.Node) -> *PieceTree.Node {
	if left == null then return right;
	if right == null then return left;

	if left.color == .BLACK && right.color == .RED {
		return new_node(left.allocator, .RED, right.data, fuse(left, right.left), right.right);
	}

	if left.color == .RED && right.color == .BLACK {
		return new_node(left.allocator, .RED, left.data, left.left, fuse(left.right, right));
	}

	if left.color == .RED && right.color == .RED {
		fused := fuse(left.right, right.left);
		if fused != null && fused.color == .RED {
			newLeft := new_node(left.allocator, .RED, left.data, left.left, fused.left);
			newRight := new_node(left.allocator, .RED, right.data, fused.right, right.right);
			return new_node(left.allocator, .RED, fused.data, newLeft, newRight);
		}
		newRight := new_node(left.allocator, .RED, right.data, fused, right.right);
		return new_node(left.allocator, .RED, left.data, left.left, newRight);
	}

	assert(left.color == right.color && left.color == .BLACK);
	fused := fuse(left.right, right.left);
	if fused != null && fused.color == .RED {
		newLeft := new_node(left.allocator, .BLACK, left.data, left.left, fused.left);
		newRight := new_node(left.allocator, .BLACK, right.data, fused.right, right.right);
		return new_node(left.allocator, .RED, fused.data, newLeft, newRight);
	}
	newRight := new_node(left.allocator, .BLACK, right.data, fused, right.right);
	newNode := new_node(left.allocator, .RED, left.data, left.left, newRight);
	return balance_left(newNode);
}

// debug functions
 
check_black_node_invariant :: (node: *PieceTree.Node) -> s32 {
	if node == null then return 1;

	if node.color == .RED && ((node.left && node.left.color == .RED) || (node.right && node.right.color == .RED)) {
		return 1;
	}

	l := check_black_node_invariant(node.left);
	r := check_black_node_invariant(node.right);

	if l != 0 && r != 0 && l != r
		return 0;

	if l != 0 && r != 0
		return ifx node.color == .RED then l else l + 1; 
	return 0;
}

satisfies_rb_invariants :: (node: *PieceTree.Node) {
	if node == null || (node.left == null && node.right == null)
		return;
	assert(check_black_node_invariant(node) != 0);
}

pretty_print_tree :: (node: *PieceTree.Node, prefix: string, isLeft: bool) {
	if node {
		print("%", prefix);

		if isLeft {
			print("|--");
		}
		else {
			print("L--");
		}

		print(" %(%,%)-(%,%)\n", ifx node.color == .RED then "R" else "B", node.piece.length, node.piece.lineFeedCount, node.leftSubtreeLength, node.leftSubtreeLfCount);

		pretty_print_tree(node.right, tprint("%1%2", prefix, ifx isLeft then "|   " else "    "), true);
		pretty_print_tree(node.left, tprint("%1%2", prefix, ifx isLeft then "|   " else "    "), false);
	}
}
