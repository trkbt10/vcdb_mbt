///|
/// Return the leftmost leaf index in a B+ tree
fn bptree_leftmost_leaf_idx(tree : BPTree) -> Int {
  let mut current = tree.root_idx
  while true {
    match tree.nodes[current] {
      Leaf(_, _) => return current
      Branch(entries, rightmost) =>
        current = if entries.is_empty() {
          rightmost
        } else {
          entries[0].child_idx
        }
    }
  }
  current
}

///|
/// Return the height of the B+ tree in nodes
fn bptree_height(tree : BPTree) -> Int {
  let mut height = 1
  let mut current = tree.root_idx
  while true {
    match tree.nodes[current] {
      Leaf(_, _) => return height
      Branch(entries, rightmost) => {
        height += 1
        current = if entries.is_empty() {
          rightmost
        } else {
          entries[0].child_idx
        }
      }
    }
  }
  height
}

///|
/// Count all leaf entries by following the leaf linked list
fn bptree_count_leaf_entries(tree : BPTree) -> Int {
  let mut total = 0
  let mut current = bptree_leftmost_leaf_idx(tree)
  while current >= 0 {
    match tree.nodes[current] {
      Leaf(entries, next) => {
        total += entries.length()
        current = next
      }
      Branch(_, _) => abort("expected leaf while counting leaf entries")
    }
  }
  total
}
