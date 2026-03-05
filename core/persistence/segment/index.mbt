///|
/// Index File Format - Binary format for index entries and ANN state
/// Compatible with TypeScript vcdb index file format (with 64-bit ID extension)
///
/// Format:
/// - Header (16 bytes): Magic (4) + Version (4) + Reserved (8)
/// - Info (20 bytes): metricCode (4) + dim (4) + count (4) + strategyCode (4) + flags (4)
/// - If hasAnn: annLen (4) + annBytes
/// - Entries: repeated [id (8) + nameLen (4) + name + offset (4) + length (4)]

///|
/// Index file magic: 'VLIX' in little-endian
pub let index_magic : UInt = 0x58494C56U

///|
/// Index file version
pub let index_version : UInt = 1U

///|
/// Index file header
pub(all) struct IndexHeader {
  metric_code : Int // Metric encoding (0=Cosine, 1=L2, 2=Dot)
  dim : Int // Vector dimension
  count : Int // Number of entries
  strategy_code : Int // Strategy encoding (0=Bruteforce, 1=HNSW, 2=IVF)
  has_ann : Bool // Whether ANN bytes are included
} derive(Show)

///|
/// Encode metric to code
pub fn encode_metric(metric : @core.Metric) -> Int {
  match metric {
    Cosine => 0
    L2 => 1
    Dot => 2
  }
}

///|
/// Decode code to metric
pub fn decode_metric(code : Int) -> @core.Metric {
  match code {
    1 => L2
    2 => Dot
    _ => Cosine
  }
}

///|
/// Encode strategy to code
pub fn encode_strategy(strategy : @core.Strategy) -> Int {
  match strategy {
    Bruteforce => 0
    HNSW(_) => 1
    IVF(_) => 2
  }
}

///|
/// Decode code to strategy (returns Bruteforce as default, params must be set separately)
pub fn decode_strategy_type(code : Int) -> Int {
  // Returns raw code for caller to interpret
  code
}

///|
/// Encode index file to bytes
pub fn encode_index_file(
  header : IndexHeader,
  entries : Array[IndexEntry],
  ann_bytes : Bytes?,
) -> Bytes {
  let w = @binary.BinaryWriter::new()

  // Header (16 bytes)
  w.push_u32(index_magic)
  w.push_u32(index_version)
  w.push_u32(0U) // Reserved
  w.push_u32(0U) // Reserved

  // Info (20 bytes)
  w.push_u32(header.metric_code.reinterpret_as_uint())
  w.push_u32(header.dim.reinterpret_as_uint())
  w.push_u32(header.count.reinterpret_as_uint())
  w.push_u32(header.strategy_code.reinterpret_as_uint())
  let flags : UInt = if header.has_ann { 1U } else { 0U }
  w.push_u32(flags)

  // ANN bytes (if present)
  match ann_bytes {
    Some(ann) if header.has_ann => {
      w.push_u32(ann.length().reinterpret_as_uint())
      w.push_bytes(ann)
    }
    _ => ()
  }

  // Entries
  for entry in entries {
    // ID (8 bytes for 64-bit support)
    w.push_u64(entry.id.to_int64().reinterpret_as_uint64())

    // Segment name
    let name_bytes = @codec.encode_utf8(entry.ptr.segment)
    w.push_u32(name_bytes.length().reinterpret_as_uint())
    w.push_bytes(name_bytes)

    // Offset and length
    w.push_u32(entry.ptr.offset.reinterpret_as_uint())
    w.push_u32(entry.ptr.length.reinterpret_as_uint())
  }

  w.concat()
}

///|
/// Decoded index file result
pub struct DecodedIndexFile {
  header : IndexHeader
  entries : Array[IndexEntry]
  ann : Bytes?
} derive(Show)

///|
/// Decode index file from bytes
pub fn decode_index_file(data : Bytes) -> DecodedIndexFile? {
  if data.length() < 36 {
    // Minimum: header(16) + info(20)
    return None
  }

  let r = @binary.BinaryReader::new(data)

  // Header
  let magic = r.read_u32()
  let version = r.read_u32()
  let _ = r.read_u32() // Reserved
  let _ = r.read_u32() // Reserved

  if magic != index_magic || version != index_version {
    return None
  }

  // Info
  let metric_code = r.read_u32().reinterpret_as_int()
  let dim = r.read_u32().reinterpret_as_int()
  let count = r.read_u32().reinterpret_as_int()
  let strategy_code = r.read_u32().reinterpret_as_int()
  let flags = r.read_u32()
  let has_ann = (flags & 1U) == 1U

  // ANN bytes
  let ann : Bytes? = if has_ann && r.remaining() >= 4 {
    let ann_len = r.read_u32().reinterpret_as_int()
    if r.remaining() >= ann_len {
      Some(r.read_bytes(ann_len))
    } else {
      None
    }
  } else {
    None
  }

  // Entries
  let entries : Array[IndexEntry] = []
  while r.remaining() >= 20 {
    // Minimum entry: id(8) + nameLen(4) + name(0) + offset(4) + length(4)
    let id = @core.VectorId(r.read_u64().reinterpret_as_int64())
    let name_len = r.read_u32().reinterpret_as_int()

    if r.remaining() < name_len + 8 {
      break
    }

    let name_bytes = r.read_bytes(name_len)
    let segment = @codec.decode_utf8(name_bytes)
    let offset = r.read_u32().reinterpret_as_int()
    let length = r.read_u32().reinterpret_as_int()

    entries.push({ id, ptr: { segment, offset, length } })
  }

  let header : IndexHeader = { metric_code, dim, count, strategy_code, has_ann }
  Some({ header, entries, ann })
}

///|
/// Create header from store
pub fn IndexHeader::from_store(
  store : @core.CoreStore,
  strategy : @core.Strategy,
  has_ann : Bool,
) -> IndexHeader {
  {
    metric_code: encode_metric(store.metric),
    dim: store.dim,
    count: store.size(),
    strategy_code: encode_strategy(strategy),
    has_ann,
  }
}
