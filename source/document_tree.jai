
// document tree 

NodeData :: struct {
	// standin for a "piece" of the document
	length : s64;
	lfCount :s64;

	leftSubtreeLength : s64;
	leftSubtreeLfCount : s64;
}

Node :: struct {
	allocator: *Allocator;
	color: Color;
	data: NodeData;
	left: *Node;
	right: *Node;
}

Color :: enum {
	RED;
	BLACK;
	DOUBLE_BLACK;
}

tree_test :: () {

	// new tree
	memory: Flat_Pool;
	allocator := Allocator.{proc=flat_pool_allocator_proc, data=*memory};
	tree := make_rb_tree(*allocator, .{5, 2, 0, 0});

	// insert something
	tree = rb_tree_insert(tree, .{5, 3, 0, 0}, 5);
	tree = rb_tree_insert(tree, .{2, 1, 0, 0}, 10);
	tree = rb_tree_insert(tree, .{3, 1, 0, 0}, 12);
	tree = rb_tree_insert(tree, .{4, 2, 0, 0}, 15);
	tree = rb_tree_insert(tree, .{3, 2, 0, 0}, 19);
	tree = rb_tree_insert(tree, .{4, 4, 0, 0}, 22);
	tree = rb_tree_insert(tree, .{2, 1, 0, 0}, 26);

	log("len % lfCount %", rb_tree_length(tree), rb_tree_lf_count(tree));
	pretty_print_tree(tree);
}

make_rb_tree :: (allocator: *Allocator, data: NodeData) -> *Node {
	return rb_tree_new_node(allocator, .BLACK, data, null, null);
}

rb_tree_new_node :: (allocator: *Allocator, color: Color, data: NodeData, left: *Node, right: *Node) -> *Node {
	newNode := New(Node,,allocator);
	newNode.allocator = allocator;
	newNode.color = color;
	newNode.data = data;
	newNode.data.leftSubtreeLength = rb_tree_length(left);
	newNode.data.leftSubtreeLfCount = rb_tree_lf_count(left);
	newNode.left= left;
	newNode.right= right;
	return newNode;
}

// insert
rb_tree_insert :: (treeRoot: *Node, nodeData: NodeData, at: s64) -> *Node {
	t :=  rb_tree_internal_insert(treeRoot.allocator, treeRoot, nodeData, at, 0);
	return rb_tree_new_node(treeRoot.allocator, .BLACK, t.data, t.left, t.right);
}

// removal
rb_tree_remove :: (treeRoot: *Node, at: s64) -> *Node {
	return null;
}

rb_tree_length :: (treeRoot: *Node) -> s64 {
	if treeRoot == null {
		return 0;
	}
	return treeRoot.data.leftSubtreeLength + treeRoot.data.length + rb_tree_length(treeRoot.right);
 }

rb_tree_lf_count :: (treeRoot: *Node) -> s64 {
	if treeRoot == null {
		return 0;
	}
	return treeRoot.data.leftSubtreeLfCount + treeRoot.data.lfCount + rb_tree_lf_count(treeRoot.right);
}

pretty_print_tree :: (node: *Node) {
	pretty_print_tree(node, "", false);
}

#scope_file

rb_tree_internal_insert :: (allocator: *Allocator, treeRoot: *Node, nodeData: NodeData, at: s64, totalOffset: s64) -> *Node {
	// ending case of the recursion, just make a new leaf node
	if treeRoot == null {
		return rb_tree_new_node(allocator, .RED, nodeData, null, null);
	}

	// in this case we insert on the left side of the tree (modifying the left node)
	if at < (totalOffset + treeRoot.data.leftSubtreeLength + treeRoot.data.length) {
		newLeft := rb_tree_internal_insert(allocator, treeRoot.left, nodeData, at, totalOffset);
		return rb_tree_balance(allocator, treeRoot.color, treeRoot.data, newLeft, treeRoot.right);
	}

	// in this case we insert on the right side of the tree (modifying the right node)
	else {
		newRight := rb_tree_internal_insert(allocator, treeRoot.right, nodeData, at, totalOffset + treeRoot.data.leftSubtreeLength + treeRoot.data.length);
		return rb_tree_balance(allocator, treeRoot.color, treeRoot.data, treeRoot.left, newRight);
	}
}

rb_tree_balance :: (allocator: *Allocator, c: Color, data: NodeData, left: *Node, right: *Node) -> *Node {
	// We cannot have a parent and child both be red
	// so what we are doing here is checking for that case on either the left or right side
	// and if it is doubled, we rotate to fix it up
	// see  https://bartoszmilewski.com/2013/11/25/functional-data-structures-in-c-trees/

	// each case will find a possible double red, and rotate it such that the red violation percolates
	// up to the top of the tree. Repeatedly doing this will correct the tree
	if c == .BLACK && doubled_left(left) {
		newRight := rb_tree_new_node(allocator, .BLACK, data, left.right, right);
		return rb_tree_new_node(allocator, .RED, left.data, paint(left.left, .BLACK), newRight);
	}
	else if c == .BLACK && doubled_right(left) {
		newLeft := rb_tree_new_node(allocator, .BLACK, left.data, left.left, left.right.left);
		newRight := rb_tree_new_node(allocator, .BLACK, data, left.right.right, right);
		return rb_tree_new_node(allocator, .RED, left.right.data, newLeft, newRight);
	}
	else if c == .BLACK && doubled_left(right) {
		newLeft := rb_tree_new_node(allocator, .BLACK, data, left, right.left.left);
		newRight := rb_tree_new_node(allocator, .BLACK, right.data, right.left.right, right.right);
		return rb_tree_new_node(allocator, .RED, right.left.data, newLeft, newRight);
	}
	else if c == .BLACK && doubled_right(right) {
		newLeft := rb_tree_new_node(allocator, .BLACK, data, left, right.left);
		return rb_tree_new_node(allocator, .RED, right.data, newLeft, paint(right.right, .BLACK));
	}
	// @todo: this is allocating a copy of something we just allocated above
	// Wasted memory
	return rb_tree_new_node(allocator, c, data, left, right);
}

doubled_left :: (node: *Node) -> bool {
	return node != null && node.color == .RED && node.left != null && node.left.color == .RED;
}

doubled_right :: (node: *Node) -> bool {
	return node != null && node.color == .RED && node.right != null && node.right.color == .RED;
}

paint :: (node: *Node, color: Color) -> *Node {
	assert(node != null);
	return rb_tree_new_node(node.allocator, color, node.data, node.left, node.right);
}

// debug functions
check_black_node_invariant :: (node: *Node) -> s32 {
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

satisfies_rb_invariants :: (node: *Node) {
	if node == null || (node.left == null && node.right == null)
		return;
	assert(check_black_node_invariant(node) != 0);
}

pretty_print_tree :: (node: *Node, prefix: string, isLeft: bool) {
	if node {
		print("%", prefix);

		if isLeft {
			print("|--");
		}
		else {
			print("L--");
		}

		print("(%,%)-(%,%)\n", node.data.length, node.data.lfCount, node.data.leftSubtreeLength, node.data.leftSubtreeLfCount);

		pretty_print_tree(node.right, tprint("%1%2", prefix, ifx isLeft then "|   " else "    "), true);
		pretty_print_tree(node.left, tprint("%1%2", prefix, ifx isLeft then "|   " else "    "), false);
	}
}
