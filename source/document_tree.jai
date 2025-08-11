
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
	log("inserting stuff");

	// insert something
	tree = insert_node(tree, .{5, 3, 0, 0}, 5);
	tree = insert_node(tree, .{2, 1, 0, 0}, 10);
	tree = insert_node(tree, .{3, 1, 0, 0}, 12);
	tree = insert_node(tree, .{4, 2, 0, 0}, 15);
	tree = insert_node(tree, .{3, 2, 0, 0}, 19);
	tree = insert_node(tree, .{4, 4, 0, 0}, 22);
	tree = insert_node(tree, .{2, 1, 0, 0}, 26);
	satisfies_rb_invariants(tree);
	pretty_print_tree(tree);

	log("removing stuff");

	// remove some bits
	tree2 := remove_node(tree, 19);
	satisfies_rb_invariants(tree2);

	pretty_print_tree(tree2);
	pretty_print_tree(tree);
}

make_rb_tree :: (allocator: *Allocator, data: NodeData) -> *Node {
	return new_node(allocator, .BLACK, data, null, null);
}

insert_node :: (root: *Node, nodeData: NodeData, at: s64) -> *Node {
	t :=  internal_insert(root.allocator, root, nodeData, at, 0);
	return new_node(root.allocator, .BLACK, t.data, t.left, t.right);
}

remove_node :: (root: *Node, at: s64) -> *Node {
	t := internal_remove(root, at, 0);
	if t == null then return null;
	return new_node(root.allocator, .BLACK, t.data, t.left, t.right);
}

length :: (root: *Node) -> s64 {
	if root == null {
		return 0;
	}
	return root.data.leftSubtreeLength + root.data.length + length(root.right);
 }

lf_count :: (root: *Node) -> s64 {
	if root == null {
		return 0;
	}
	return root.data.leftSubtreeLfCount + root.data.lfCount + lf_count(root.right);
}

pretty_print_tree :: (node: *Node) {
	pretty_print_tree(node, "", false);
}

#scope_file

new_node :: (allocator: *Allocator, color: Color, data: NodeData, left: *Node, right: *Node) -> *Node {
	newNode := New(Node,,allocator);
	newNode.allocator = allocator;
	newNode.color = color;
	newNode.data = data;
	newNode.data.leftSubtreeLength = length(left);
	newNode.data.leftSubtreeLfCount = lf_count(left);
	newNode.left= left;
	newNode.right= right;
	return newNode;
}

// insertion helpers

internal_insert :: (allocator: *Allocator, root: *Node, nodeData: NodeData, at: s64, totalOffset: s64) -> *Node {
	// ending case of the recursion, just make a new leaf node
	if root == null {
		return new_node(allocator, .RED, nodeData, null, null);
	}

	// in this case we insert on the left side of the tree (modifying the left node)
	if at < (totalOffset + root.data.leftSubtreeLength + root.data.length) {
		newLeft := internal_insert(allocator, root.left, nodeData, at, totalOffset);
		return balance(allocator, root.color, root.data, newLeft, root.right);
	}

	// in this case we insert on the right side of the tree (modifying the right node)
	else {
		newRight := internal_insert(allocator, root.right, nodeData, at, totalOffset + root.data.leftSubtreeLength + root.data.length);
		return balance(allocator, root.color, root.data, root.left, newRight);
	}
}

balance :: (allocator: *Allocator, c: Color, data: NodeData, left: *Node, right: *Node) -> *Node {
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

doubled_left :: (node: *Node) -> bool {
	return node != null && node.color == .RED && node.left != null && node.left.color == .RED;
}

doubled_right :: (node: *Node) -> bool {
	return node != null && node.color == .RED && node.right != null && node.right.color == .RED;
}

paint :: (node: *Node, color: Color) -> *Node {
	assert(node != null);
	return new_node(node.allocator, color, node.data, node.left, node.right);
}

// Removal helpers

internal_remove :: (root: *Node, at: s64, totalOffset: s64) -> *Node {
	if root == null then return null;

	if at < totalOffset + root.data.leftSubtreeLength {
		return remove_left(root, at, totalOffset);
	}
	if at == totalOffset + root.data.leftSubtreeLength {
		return fuse(root.left, root.right);
	}
	return remove_right(root, at, totalOffset);
}

remove_left :: (root: *Node, at: s64, totalOffset: s64) -> *Node {
	newLeft := internal_remove(root.left, at, totalOffset);
	newNode := new_node(root.allocator, .RED, root.data, newLeft, root.right);

	if root.left && root.left.color == .BLACK {
		return balance_left(newNode);
	}
	return newNode;
}

remove_right :: (root: *Node, at: s64, totalOffset: s64) -> *Node {
	newRight := internal_remove(root.right, at, totalOffset + root.data.leftSubtreeLength + root.data.length);
	newNode := new_node(root.allocator, .RED, root.data, root.left, newRight);

	if root.right && root.right.color == .BLACK {
		return balance_right(newNode);
	}
	return newNode;
}

balance_right :: (right: *Node) -> *Node {
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

balance_left :: (left: *Node) -> *Node {
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

balance :: (node: *Node) -> *Node {
	if node.left != null && node.left.color == .RED && node.right != null && node.right.color == .RED {
		left := paint(node.left, .BLACK);
		right := paint(node.right, .BLACK);
		return new_node(node.allocator, .RED, node.data, left, right);
	}
	assert(node.color == .BLACK);
	return balance(node.allocator, node.color, node.data, node.left, node.right);
}

fuse :: (left: *Node, right: *Node) -> *Node {
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
