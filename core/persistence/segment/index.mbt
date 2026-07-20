///|
/// Index File Format - Binary format for index entries and ANN state
///
/// Format:
/// - Header (12 bytes): Magic (8 "VCDBMBT\0") + Type (1) + Version (1) + Reserved (2)
/// - Info (20 bytes): metricCode (4) + dim (4) + count (4) + strategyCode (4) + flags (4)
/// - If hasAnn: annLen (4) + annBytes
/// - Entries: repeated [id (8) + nameLen (4) + name + offset (4) + length (4)]

///|
/// Index file version
pub let index_version : Byte = b'\x02'

///|
/// Index file header
pub(all) struct IndexHeader {
  metric_code : Int // Metric encoding (0=Cosine, 1=L2, 2=Dot)
  dim : Int // Vector dimension
  count : Int // Number of entries
  strategy_code : Int // Strategy encoding (0=Bruteforce, 1=HNSW, 2=IVF)
  has_ann : Bool // Whether ANN bytes are included
}

///|
pub impl Show for IndexHeader with fn output(self, logger) {
  logger.write_string("{ metric_code: ")
  Show::output(self.metric_code, logger)
  logger.write_string(", dim: ")
  Show::output(self.dim, logger)
  logger.write_string(", count: ")
  Show::output(self.count, logger)
  logger.write_string(", strategy_code: ")
  Show::output(self.strategy_code, logger)
  logger.write_string(", has_ann: ")
  Show::output(self.has_ann, logger)
  logger.write_string(" }")
}

///|
/// Encode metric to code
pub fn encode_metric(metric : @types.Metric) -> Int {
  match metric {
    Cosine => 0
    L2 => 1
    Dot => 2
  }
}

///|
/// Decode code to metric
pub fn decode_metric(code : Int) -> @types.Metric {
  match code {
    1 => L2
    2 => Dot
    _ => Cosine
  }
}

///|
/// Encode strategy to code
pub fn encode_strategy(strategy : @types.Strategy) -> Int {
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

  // Header (12 bytes)
  @codec.encode_header(w, Index, index_version)

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
    // ID (wire format: length-prefixed bytes)
    let id_wire = entry.id.to_wire_bytes()
    w.push_u32(id_wire.length().reinterpret_as_uint())
    w.push_bytes(id_wire)

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
}

///|
pub impl Show for DecodedIndexFile with fn output(self, logger) {
  logger.write_string("{ header: ")
  Show::output(self.header, logger)
  logger.write_string(", entries: ")
  Show::output(self.entries, logger)
  logger.write_string(", ann: ")
  Debug::to_repr(self.ann).output(logger)
  logger.write_string(" }")
}

///|
/// Decode index file from bytes
pub fn decode_index_file(data : Bytes) -> DecodedIndexFile? {
  if data.length() < @codec.header_size + 20 {
    // Minimum: header(12) + info(20)
    return None
  }

  let r = @binary.BinaryReader::new(data)

  // Header (12 bytes)
  let idx_version : Byte = match @codec.read_header(r) {
    None => return None
    Some((file_type, version)) =>
      if file_type != Index || (version != b'\x01' && version != b'\x02') {
        return None
      } else {
        version
      }
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
  while r.remaining() >= 16 {
    let id = if idx_version == b'\x01' {
      // v1: fixed 8-byte Int64
      @types.Int64Id(r.read_u64().reinterpret_as_int64())
    } else {
      // v2+: length-prefixed wire bytes
      let id_wire_len = r.read_u32().reinterpret_as_int()
      match @types.VectorId::from_wire_bytes(r.read_bytes(id_wire_len)) {
        Some(v) => v
        None => @types.Int64Id(0L)
      }
    }
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
  store : @store.CoreStore,
  strategy : @types.Strategy,
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
