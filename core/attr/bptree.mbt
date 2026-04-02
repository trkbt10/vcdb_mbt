///|
/// B+ Tree Attribute Index
/// Balanced tree for efficient read/write operations with range query support.

///|
/// Helper to create a single-byte Bytes
fn make_exists_key() -> Bytes {
  let w = @binary.BinaryWriter::new()
  w.push_byte(b'\x01')
  w.concat()
}

///|
/// B+ Tree leaf entry
priv struct BPLeafEntry {
  key : Bytes
  value : Array[Int64]
}

///|
/// B+ Tree branch entry
priv struct BPBranchEntry {
  key : Bytes
  child_idx : Int // Index into nodes array
}

///|
/// B+ Tree node
priv enum BPNode {
  Leaf(Array[BPLeafEntry], Int) // entries, next_leaf_idx (-1 if none)
  Branch(Array[BPBranchEntry], Int) // entries, rightmost_idx
}

///|
/// B+ Tree structure
struct BPTree {
  nodes : Array[BPNode]
  mut root_idx : Int
  order : Int // Max entries per node
}

///|
/// B+ Tree Attribute Index container
pub struct BPTreeAttrIndex {
  field_trees : Map[String, BPTree] // Per-field B+ trees
  exists_trees : Map[String, BPTree] // Existence B+ trees
  data : Map[Int64, @types.Attrs] // Direct storage for attrs
  order : Int // Node order (default 128)
}

///|
/// Create a new B+ tree
fn BPTree::new(order : Int) -> BPTree {
  // Start with empty leaf as root
  { nodes: [Leaf([], -1)], root_idx: 0, order }
}

///|
/// Compare two byte arrays lexicographically
fn bytes_compare(a : Bytes, b : Bytes) -> Int {
  let min_len = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<min_len {
    let diff = a[i].to_int() - b[i].to_int()
    if diff != 0 {
      return diff
    }
  }
  a.length() - b.length()
}

///|
/// Check if two byte arrays are equal
fn bytes_equal(a : Bytes, b : Bytes) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Encode AttrValue to order-preserving bytes
fn encode_attr_value(value : @types.AttrValue) -> Bytes {
  let w = @binary.BinaryWriter::new()
  match value {
    Null => w.push_byte(b'\x00')
    Bool(v) => {
      w.push_byte(b'\x01')
      w.push_byte(if v { b'\x01' } else { b'\x00' })
    }
    Int(n) => {
      // Order-preserving encoding for signed integers
      // Flip sign bit for correct ordering
      w.push_byte(b'\x02') // type tag
      let u = n.reinterpret_as_uint64() ^ 0x8000000000000000UL
      // Write big-endian for order preservation
      for i = 7; i >= 0; i = i - 1 {
        let shift = i * 8
        w.push_byte(((u >> shift) & 0xFFUL).to_byte())
      }
    }
    Float(f) => {
      // Order-preserving encoding for floats
      w.push_byte(b'\x03') // type tag
      let bits = f.reinterpret_as_uint64()
      // Flip bits for negative numbers, flip sign for positive
      let u = if (bits & 0x8000000000000000UL) != 0UL {
        bits ^ 0xFFFFFFFFFFFFFFFFUL
      } else {
        bits ^ 0x8000000000000000UL
      }
      for i = 7; i >= 0; i = i - 1 {
        let shift = i * 8
        w.push_byte(((u >> shift) & 0xFFUL).to_byte())
      }
    }
    String(s) => {
      w.push_byte(b'\x04') // type tag
      // Encode full UTF-8 to preserve Unicode
      w.push_bytes(s.to_bytes())
    }
  }
  w.concat()
}

///|
/// Write a String in a backend-stable format
fn write_string(w : @binary.BinaryWriter, value : String) -> Unit {
  let chars = value.to_array()
  w.push_u32(chars.length().reinterpret_as_uint())
  for c in chars {
    w.push_u32(c.to_uint())
  }
}

///|
/// Read a String written by write_string
fn read_string(r : @binary.BinaryReader) -> String {
  let len = r.read_u32().reinterpret_as_int()
  let chars : Array[Char] = []
  for _ in 0..<len {
    chars.push(r.read_u32().reinterpret_as_int().unsafe_to_char())
  }
  String::from_array(chars[:])
}

///|
/// Write length-prefixed raw bytes
fn write_prefixed_bytes(w : @binary.BinaryWriter, data : Bytes) -> Unit {
  w.push_u32(data.length().reinterpret_as_uint())
  w.push_bytes(data)
}

///|
/// Read length-prefixed raw bytes
fn read_prefixed_bytes(r : @binary.BinaryReader) -> Bytes {
  let len = r.read_u32().reinterpret_as_int()
  r.read_bytes(len)
}

///|
/// Write a typed attribute value
fn write_attr_value(w : @binary.BinaryWriter, value : @types.AttrValue) -> Unit {
  match value {
    Null => w.push_u32(0U)
    Bool(b) => {
      w.push_u32(1U)
      w.push_u32(if b { 1U } else { 0U })
    }
    Int(n) => {
      w.push_u32(2U)
      w.push_i64(n)
    }
    Float(f) => {
      w.push_u32(3U)
      w.push_f64(f)
    }
    String(s) => {
      w.push_u32(4U)
      write_string(w, s)
    }
  }
}

///|
/// Read a typed attribute value
fn read_attr_value(r : @binary.BinaryReader) -> @types.AttrValue {
  match r.read_u32() {
    0U => @types.Null
    1U => @types.Bool(r.read_u32() != 0U)
    2U => @types.Int(r.read_i64())
    3U => @types.Float(r.read_f64())
    _ => @types.String(read_string(r))
  }
}

///|
/// Write attrs payload
fn write_attrs(w : @binary.BinaryWriter, attrs : @types.Attrs) -> Unit {
  let keys = attrs.keys()
  w.push_u32(keys.length().reinterpret_as_uint())
  for key in keys {
    write_string(w, key)
    match attrs.get(key) {
      Some(value) => write_attr_value(w, value)
      None => write_attr_value(w, @types.Null)
    }
  }
}

///|
/// Read attrs payload
fn read_attrs(r : @binary.BinaryReader) -> @types.Attrs {
  let attrs = @types.empty_attrs()
  let count = r.read_u32().reinterpret_as_int()
  for _ in 0..<count {
    let key = read_string(r)
    let value = read_attr_value(r)
    attrs.set(key, value)
  }
  attrs
}

///|
/// Serialize a B+ tree node graph directly
fn serialize_bptree(tree : BPTree) -> Bytes {
  let w = @binary.BinaryWriter::new()
  w.push_u32(tree.order.reinterpret_as_uint())
  w.push_i32(tree.root_idx)
  w.push_u32(tree.nodes.length().reinterpret_as_uint())
  for node in tree.nodes {
    match node {
      Leaf(entries, next) => {
        w.push_u32(0U)
        w.push_u32(entries.length().reinterpret_as_uint())
        for entry in entries {
          write_prefixed_bytes(w, entry.key)
          w.push_u32(entry.value.length().reinterpret_as_uint())
          for id in entry.value {
            w.push_i64(id)
          }
        }
        w.push_i32(next)
      }
      Branch(entries, rightmost) => {
        w.push_u32(1U)
        w.push_u32(entries.length().reinterpret_as_uint())
        for entry in entries {
          write_prefixed_bytes(w, entry.key)
          w.push_i32(entry.child_idx)
        }
        w.push_i32(rightmost)
      }
    }
  }
  w.concat()
}

///|
/// Deserialize a B+ tree node graph
fn deserialize_bptree(data : Bytes) -> BPTree {
  let r = @binary.BinaryReader::new(data)
  let order = r.read_u32().reinterpret_as_int()
  let root_idx = r.read_i32()
  let node_count = r.read_u32().reinterpret_as_int()
  let nodes : Array[BPNode] = []
  for _ in 0..<node_count {
    let tag = r.read_u32()
    let entry_count = r.read_u32().reinterpret_as_int()
    if tag == 0U {
      let entries : Array[BPLeafEntry] = []
      for _ in 0..<entry_count {
        let key = read_prefixed_bytes(r)
        let posting_count = r.read_u32().reinterpret_as_int()
        let value : Array[Int64] = []
        for _ in 0..<posting_count {
          value.push(r.read_i64())
        }
        entries.push({ key, value })
      }
      let next = r.read_i32()
      nodes.push(Leaf(entries, next))
    } else {
      let entries : Array[BPBranchEntry] = []
      for _ in 0..<entry_count {
        let key = read_prefixed_bytes(r)
        let child_idx = r.read_i32()
        entries.push({ key, child_idx })
      }
      let rightmost = r.read_i32()
      nodes.push(Branch(entries, rightmost))
    }
  }
  { nodes, root_idx, order }
}

///|
/// Select child index from a branch node for a search key
fn select_branch_child(
  entries : Array[BPBranchEntry],
  rightmost : Int,
  key : Bytes,
) -> Int {
  if entries.is_empty() {
    return rightmost
  }
  for i in 0..<entries.length() {
    if bytes_compare(key, entries[i].key) < 0 {
      return entries[i].child_idx
    }
  }
  rightmost
}

///|
/// Find insertion position in a branch node for a split key
fn find_branch_insert_pos(entries : Array[BPBranchEntry], key : Bytes) -> Int {
  for i in 0..<entries.length() {
    if bytes_compare(key, entries[i].key) < 0 {
      return i
    }
  }
  entries.length()
}

///|
/// Find the path from root to the leaf containing key
fn find_leaf_path(tree : BPTree, key : Bytes) -> Array[Int] {
  let path : Array[Int] = []
  let mut current = tree.root_idx
  while true {
    path.push(current)
    match tree.nodes[current] {
      Leaf(_, _) => break
      Branch(entries, rightmost) =>
        current = select_branch_child(entries, rightmost, key)
    }
  }
  path
}

///|
/// Find leaf node containing key
fn find_leaf(tree : BPTree, key : Bytes) -> Int {
  let path = find_leaf_path(tree, key)
  path[path.length() - 1]
}

///|
/// Find entry in leaf
fn find_entry(entries : Array[BPLeafEntry], key : Bytes) -> Int {
  for i in 0..<entries.length() {
    if bytes_equal(entries[i].key, key) {
      return i
    }
  }
  -1
}

///|
/// Insert ID into posting list (deduped)
fn insert_into_posting(list : Array[Int64], id : Int64) -> Unit {
  for existing in list {
    if existing == id {
      return
    }
  }
  list.push(id)
}

///|
/// Remove ID from posting list
fn remove_from_posting(list : Array[Int64], id : Int64) -> Unit {
  let _ = remove_int64_swap(list, id)
}

///|
/// Check whether a node exceeds the configured order
fn is_overflow(tree : BPTree, node_idx : Int) -> Bool {
  match tree.nodes[node_idx] {
    Leaf(entries, _) => entries.length() > tree.order
    Branch(entries, _) => entries.length() > tree.order
  }
}

///|
/// Split an overflowing leaf node and return the new right leaf and separator key
fn split_leaf(tree : BPTree, leaf_idx : Int) -> (Int, Bytes) {
  match tree.nodes[leaf_idx] {
    Leaf(entries, next) => {
      let split_at = entries.length() / 2
      let right_entries : Array[BPLeafEntry] = []
      for i in split_at..<entries.length() {
        right_entries.push(entries[i])
      }
      while entries.length() > split_at {
        let _ = entries.pop()
      }
      let split_key = right_entries[0].key
      let new_leaf_idx = tree.nodes.length()
      tree.nodes.push(Leaf(right_entries, next))
      tree.nodes[leaf_idx] = Leaf(entries, new_leaf_idx)
      (new_leaf_idx, split_key)
    }
    _ => abort("split_leaf expects a leaf node")
  }
}

///|
/// Insert a promoted separator into a branch node
fn insert_into_branch(
  tree : BPTree,
  branch_idx : Int,
  key : Bytes,
  child_idx : Int,
) -> Unit {
  match tree.nodes[branch_idx] {
    Branch(entries, rightmost) => {
      let insert_pos = find_branch_insert_pos(entries, key)
      let new_entries : Array[BPBranchEntry] = []
      let mut new_rightmost = rightmost
      if insert_pos == entries.length() {
        for entry in entries {
          new_entries.push(entry)
        }
        new_entries.push({ key, child_idx: rightmost })
        new_rightmost = child_idx
      } else {
        for i in 0..<entries.length() {
          if i == insert_pos {
            let left_child_idx = entries[i].child_idx
            new_entries.push({ key, child_idx: left_child_idx })
            new_entries.push({ key: entries[i].key, child_idx })
          } else {
            new_entries.push(entries[i])
          }
        }
      }
      tree.nodes[branch_idx] = Branch(new_entries, new_rightmost)
    }
    _ => abort("insert_into_branch expects a branch node")
  }
}

///|
/// Split an overflowing branch node and return the new right branch and promoted key
fn split_branch(tree : BPTree, branch_idx : Int) -> (Int, Bytes) {
  match tree.nodes[branch_idx] {
    Branch(entries, rightmost) => {
      let mid = entries.length() / 2
      let promoted = entries[mid].key
      let left_rightmost = entries[mid].child_idx
      let right_entries : Array[BPBranchEntry] = []
      for i in (mid + 1)..<entries.length() {
        right_entries.push(entries[i])
      }
      while entries.length() > mid {
        let _ = entries.pop()
      }
      let new_branch_idx = tree.nodes.length()
      tree.nodes.push(Branch(right_entries, rightmost))
      tree.nodes[branch_idx] = Branch(entries, left_rightmost)
      (new_branch_idx, promoted)
    }
    _ => abort("split_branch expects a branch node")
  }
}

///|
/// Create a new root after splitting the previous root
fn split_root(
  tree : BPTree,
  left_idx : Int,
  right_idx : Int,
  split_key : Bytes,
) -> Unit {
  let new_root_idx = tree.nodes.length()
  tree.nodes.push(Branch([{ key: split_key, child_idx: left_idx }], right_idx))
  tree.root_idx = new_root_idx
}

///|
/// Propagate node splits up the insertion path
fn handle_overflow(tree : BPTree, path : Array[Int]) -> Unit {
  if path.is_empty() {
    return
  }
  let mut level = path.length() - 1
  let mut current_idx = path[level]
  while is_overflow(tree, current_idx) {
    let (new_idx, split_key) = match tree.nodes[current_idx] {
      Leaf(_, _) => split_leaf(tree, current_idx)
      Branch(_, _) => split_branch(tree, current_idx)
    }
    if level == 0 {
      split_root(tree, current_idx, new_idx, split_key)
      return
    }
    let parent_idx = path[level - 1]
    insert_into_branch(tree, parent_idx, split_key, new_idx)
    current_idx = parent_idx
    level = level - 1
  }
}

///|
/// Insert posting into B+ tree
fn bptree_insert(tree : BPTree, key : Bytes, id : Int64) -> Unit {
  let path = find_leaf_path(tree, key)
  let leaf_idx = path[path.length() - 1]
  match tree.nodes[leaf_idx] {
    Leaf(entries, next) => {
      // Find existing entry
      let entry_idx = find_entry(entries, key)
      if entry_idx >= 0 {
        // Add to existing posting list
        insert_into_posting(entries[entry_idx].value, id)
      } else {
        // Create new entry
        let new_list : Array[Int64] = [id]
        entries.push({ key, value: new_list })
        // Sort entries by key
        entries.sort_by(fn(a, b) { bytes_compare(a.key, b.key) })
        if is_overflow(tree, leaf_idx) {
          handle_overflow(tree, path)
        }
      }
      let _ = next
    }
    _ => ()
  }
}

///|
/// Remove posting from B+ tree
fn bptree_remove(tree : BPTree, key : Bytes, id : Int64) -> Unit {
  let leaf_idx = find_leaf(tree, key)
  match tree.nodes[leaf_idx] {
    Leaf(entries, _) => {
      let entry_idx = find_entry(entries, key)
      if entry_idx >= 0 {
        remove_from_posting(entries[entry_idx].value, id)
        // Remove entry if posting list is empty
        if entries[entry_idx].value.is_empty() {
          // Swap with last and pop
          let last = entries.length() - 1
          if entry_idx != last {
            entries[entry_idx] = entries[last]
          }
          let _ = entries.pop()
          // Re-sort after removal
          entries.sort_by(fn(a, b) { bytes_compare(a.key, b.key) })
        }
      }
    }
    _ => ()
  }
}

///|
/// Lookup posting list for key
fn bptree_lookup(tree : BPTree, key : Bytes) -> Array[Int64]? {
  let leaf_idx = find_leaf(tree, key)
  match tree.nodes[leaf_idx] {
    Leaf(entries, _) => {
      let entry_idx = find_entry(entries, key)
      if entry_idx >= 0 {
        Some(entries[entry_idx].value)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Range query in B+ tree
fn bptree_range(
  tree : BPTree,
  lo : Bytes?,
  hi : Bytes?,
  range : @types.NumericRange,
) -> Array[Int64] {
  let result : Array[Int64] = []
  let mut current = match lo {
    Some(start_key) => find_leaf(tree, start_key)
    None => {
      let mut leftmost = tree.root_idx
      while true {
        match tree.nodes[leftmost] {
          Leaf(_, _) => break
          Branch(entries, rightmost) =>
            leftmost = if entries.is_empty() {
              rightmost
            } else {
              entries[0].child_idx
            }
        }
      }
      leftmost
    }
  }
  // Scan through linked leaves
  while current >= 0 {
    match tree.nodes[current] {
      Leaf(entries, next) => {
        for entry in entries {
          // Check lower bound
          match lo {
            Some(l) => if bytes_compare(entry.key, l) < 0 { continue }
            None => ()
          }
          // Check upper bound
          match hi {
            Some(h) => if bytes_compare(entry.key, h) > 0 { break }
            None => ()
          }
          // Extract numeric value and check range
          if entry.key.length() > 1 && entry.key[0] == b'\x02' {
            // Int type
            let mut u = 0UL
            for i in 1..<9 {
              u = (u << 8) | entry.key[i].to_uint64()
            }
            u = u ^ 0x8000000000000000UL
            let n = u.reinterpret_as_int64().to_double()
            if range.matches(n) {
              for id in entry.value {
                result.push(id)
              }
            }
          } else if entry.key.length() > 1 && entry.key[0] == b'\x03' {
            // Float type
            let mut bits = 0UL
            for i in 1..<9 {
              bits = (bits << 8) | entry.key[i].to_uint64()
            }
            // Reverse the order-preserving transformation
            bits = if (bits & 0x8000000000000000UL) != 0UL {
              bits ^ 0x8000000000000000UL
            } else {
              bits ^ 0xFFFFFFFFFFFFFFFFUL
            }
            let f = bits.reinterpret_as_double()
            if range.matches(f) {
              for id in entry.value {
                result.push(id)
              }
            }
          }
        }
        current = next
      }
      _ => break
    }
  }
  result
}

///|
/// Create a new BPTreeAttrIndex
pub fn BPTreeAttrIndex::new(order? : Int = 128) -> BPTreeAttrIndex {
  { field_trees: {}, exists_trees: {}, data: {}, order }
}

///|
/// Get or create field tree
fn get_or_create_field_tree(index : BPTreeAttrIndex, field : String) -> BPTree {
  match index.field_trees.get(field) {
    Some(tree) => tree
    None => {
      let tree = BPTree::new(index.order)
      index.field_trees.set(field, tree)
      tree
    }
  }
}

///|
/// Get or create exists tree
fn get_or_create_exists_tree(index : BPTreeAttrIndex, field : String) -> BPTree {
  match index.exists_trees.get(field) {
    Some(tree) => tree
    None => {
      let tree = BPTree::new(index.order)
      index.exists_trees.set(field, tree)
      tree
    }
  }
}

///|
/// Set attributes for an ID
pub fn BPTreeAttrIndex::set_attrs(
  self : BPTreeAttrIndex,
  id : @types.VectorId,
  attrs : @types.Attrs,
) -> Unit {
  let id_val = id.to_int64()
  // Remove old attrs from trees
  match self.data.get(id_val) {
    None => ()
    Some(old_attrs) =>
      for_each_attr(old_attrs, fn(key, value) {
        // Remove from field tree
        match self.field_trees.get(key) {
          None => ()
          Some(tree) => bptree_remove(tree, encode_attr_value(value), id_val)
        }
        // Remove from exists tree
        match self.exists_trees.get(key) {
          None => ()
          Some(tree) => {
            let exists_key = make_exists_key()
            bptree_remove(tree, exists_key, id_val)
          }
        }
      })
  }
  // Add new attrs to trees
  for_each_attr(attrs, fn(key, value) {
    // Add to field tree
    let field_tree = get_or_create_field_tree(self, key)
    bptree_insert(field_tree, encode_attr_value(value), id_val)
    // Add to exists tree
    let exists_tree = get_or_create_exists_tree(self, key)
    let exists_key = make_exists_key()
    bptree_insert(exists_tree, exists_key, id_val)
  })
  // Store attrs (defensive copy to prevent external mutation)
  self.data.set(id_val, attrs.copy())
}

///|
/// Get attributes for an ID
pub fn BPTreeAttrIndex::get_attrs(
  self : BPTreeAttrIndex,
  id : @types.VectorId,
) -> @types.Attrs? {
  self.data.get(id.to_int64())
}

///|
/// Remove an ID from the index
pub fn BPTreeAttrIndex::remove_id(
  self : BPTreeAttrIndex,
  id : @types.VectorId,
) -> Unit {
  let id_val = id.to_int64()
  match self.data.get(id_val) {
    None => ()
    Some(old_attrs) => {
      for_each_attr(old_attrs, fn(key, value) {
        match self.field_trees.get(key) {
          None => ()
          Some(tree) => bptree_remove(tree, encode_attr_value(value), id_val)
        }
        match self.exists_trees.get(key) {
          None => ()
          Some(tree) => {
            let exists_key = make_exists_key()
            bptree_remove(tree, exists_key, id_val)
          }
        }
      })
      self.data.remove(id_val)
    }
  }
}

///|
/// Find IDs where key equals value
pub fn BPTreeAttrIndex::eq(
  self : BPTreeAttrIndex,
  key : String,
  value : @types.AttrValue,
) -> Array[@types.VectorId] {
  match self.field_trees.get(key) {
    None => []
    Some(tree) => {
      let encoded = encode_attr_value(value)
      match bptree_lookup(tree, encoded) {
        None => []
        Some(list) => ids_to_vector_ids(list)
      }
    }
  }
}

///|
/// Find IDs where key exists
pub fn BPTreeAttrIndex::exists(
  self : BPTreeAttrIndex,
  key : String,
) -> Array[@types.VectorId] {
  match self.exists_trees.get(key) {
    None => []
    Some(tree) => {
      let exists_key = make_exists_key()
      match bptree_lookup(tree, exists_key) {
        None => []
        Some(list) => ids_to_vector_ids(list)
      }
    }
  }
}

///|
/// Find IDs matching a numeric range
pub fn BPTreeAttrIndex::range(
  self : BPTreeAttrIndex,
  key : String,
  range : @types.NumericRange,
) -> Array[@types.VectorId]? {
  match self.field_trees.get(key) {
    None => Some([])
    Some(tree) => {
      let list = bptree_range(tree, None, None, range)
      Some(ids_to_vector_ids(list))
    }
  }
}

///|
/// Serialize a B+ tree attribute index, including node graphs and stored attrs
pub fn BPTreeAttrIndex::serialize(self : BPTreeAttrIndex) -> Bytes {
  let w = @binary.BinaryWriter::new()
  w.push_u32(1U)
  w.push_u32(self.order.reinterpret_as_uint())
  let data_count = self.data.length()
  w.push_u32(data_count.reinterpret_as_uint())
  for id_val, attrs in self.data {
    w.push_i64(id_val)
    write_attrs(w, attrs)
  }
  let field_tree_count = self.field_trees.length()
  w.push_u32(field_tree_count.reinterpret_as_uint())
  for field, tree in self.field_trees {
    write_string(w, field)
    write_prefixed_bytes(w, serialize_bptree(tree))
  }
  let exists_tree_count = self.exists_trees.length()
  w.push_u32(exists_tree_count.reinterpret_as_uint())
  for field, tree in self.exists_trees {
    write_string(w, field)
    write_prefixed_bytes(w, serialize_bptree(tree))
  }
  w.concat()
}

///|
/// Deserialize a B+ tree attribute index from serialized bytes
pub fn BPTreeAttrIndex::deserialize(data : Bytes) -> BPTreeAttrIndex {
  let r = @binary.BinaryReader::new(data)
  let _version = r.read_u32()
  let order = r.read_u32().reinterpret_as_int()
  let data_map : Map[Int64, @types.Attrs] = {}
  let data_count = r.read_u32().reinterpret_as_int()
  for _ in 0..<data_count {
    let id_val = r.read_i64()
    data_map.set(id_val, read_attrs(r))
  }
  let field_trees : Map[String, BPTree] = {}
  let field_tree_count = r.read_u32().reinterpret_as_int()
  for _ in 0..<field_tree_count {
    let field = read_string(r)
    field_trees.set(field, deserialize_bptree(read_prefixed_bytes(r)))
  }
  let exists_trees : Map[String, BPTree] = {}
  let exists_tree_count = r.read_u32().reinterpret_as_int()
  for _ in 0..<exists_tree_count {
    let field = read_string(r)
    exists_trees.set(field, deserialize_bptree(read_prefixed_bytes(r)))
  }
  { field_trees, exists_trees, data: data_map, order }
}

///|
/// Get the number of indexed IDs
pub fn BPTreeAttrIndex::size(self : BPTreeAttrIndex) -> Int {
  self.data.length()
}

///|
/// Return every indexed ID (from the data map).
pub fn BPTreeAttrIndex::all_ids(
  self : BPTreeAttrIndex,
) -> Array[@types.VectorId] {
  let result : Array[@types.VectorId] = []
  for id_val, _ in self.data {
    result.push(@types.VectorId(id_val))
  }
  result
}
