///|
/// Data Segment - Binary format for storing vectors in distributed segments
/// Format: Header (8 bytes) + Records
/// Header: Magic (4 bytes "VSEG") + Version (4 bytes)
/// Record: ID (8 bytes) + AttrsLen (4 bytes) + VectorLen (4 bytes) + Attrs + Vector

///|
/// Segment magic number: "VSEG" in little-endian
pub let segment_magic : UInt = 0x47455356U

///|
/// Segment format version
pub let segment_version : UInt = 1U

///|
/// Data pointer - reference to a record within a segment
pub(all) struct DataPointer {
  segment : String // Segment name
  offset : Int // Byte offset within segment
  length : Int // Record length in bytes
} derive(Show, Eq)

///|
/// Index entry - mapping from vector ID to data location
pub(all) struct IndexEntry {
  id : @core.VectorId
  ptr : DataPointer
} derive(Show)

///|
/// Segment writer - builds a segment in memory
pub struct SegmentWriter {
  name : String
  buffer : @binary.BinaryWriter
  mut size : Int
}

///|
/// Create a new segment writer
pub fn SegmentWriter::new(name : String) -> SegmentWriter {
  let buffer = @binary.BinaryWriter::new()
  // Write header
  buffer.push_u32(segment_magic)
  buffer.push_u32(segment_version)
  { name, buffer, size: 8 }
}

///|
/// Append a record to the segment
/// Returns DataPointer to the appended record
pub fn SegmentWriter::append(
  self : SegmentWriter,
  id : @core.VectorId,
  vector : Array[Double],
  attrs : @core.Attrs,
) -> DataPointer {
  let offset = self.size
  let w = @binary.BinaryWriter::new()

  // Write ID (8 bytes)
  w.push_u64(id.to_int64().reinterpret_as_uint64())

  // Encode attrs as JSON
  let attrs_bytes = @codec.encode_attrs_json(Some(attrs))
  w.push_u32(attrs_bytes.length().reinterpret_as_uint())

  // Encode vector as Float32
  let vector_len = vector.length() * 4
  w.push_u32(vector_len.reinterpret_as_uint())

  // Write attrs
  w.push_bytes(attrs_bytes)

  // Write vector
  for val in vector {
    w.push_f32(Float::from_double(val))
  }

  let record_bytes = w.concat()
  let length = record_bytes.length()

  self.buffer.push_bytes(record_bytes)
  self.size = self.size + length

  { segment: self.name, offset, length }
}

///|
/// Get the segment data
pub fn SegmentWriter::to_bytes(self : SegmentWriter) -> Bytes {
  self.buffer.concat()
}

///|
/// Get the segment name
pub fn SegmentWriter::get_name(self : SegmentWriter) -> String {
  self.name
}

///|
/// Segment reader - reads records from a segment
pub struct SegmentReader {
  name : String
  data : Bytes
}

///|
/// Create a segment reader from bytes
pub fn SegmentReader::from_bytes(name : String, data : Bytes) -> SegmentReader? {
  if data.length() < 8 {
    return None
  }
  let r = @binary.BinaryReader::new(data)
  let magic = r.read_u32()
  let version = r.read_u32()
  if magic != segment_magic || version != segment_version {
    return None
  }
  Some({ name, data })
}

///|
/// Read record at specific offset
pub fn SegmentReader::read_at(
  self : SegmentReader,
  offset : Int,
  length : Int,
) -> (@core.VectorId, Array[Double], @core.Attrs)? {
  if offset + length > self.data.length() {
    return None
  }
  // Use reader with skip to avoid copying
  let r = @binary.BinaryReader::new(self.data)
  r.skip(offset)
  // Read ID
  let id = @core.VectorId(r.read_u64().reinterpret_as_int64())
  // Read lengths
  let attrs_len = r.read_u32().reinterpret_as_int()
  let vector_len = r.read_u32().reinterpret_as_int()
  // Read attrs
  let attrs = if attrs_len > 0 {
    let attrs_bytes = r.read_bytes(attrs_len)
    match @codec.decode_attrs_json(attrs_bytes) {
      Some(a) => a
      None => @core.empty_attrs()
    }
  } else {
    @core.empty_attrs()
  }
  // Read vector
  let count = vector_len / 4
  let vector : Array[Double] = Array::make(count, 0.0)
  for i in 0..<count {
    vector[i] = r.read_f32().to_double()
  }
  Some((id, vector, attrs))
}

///|
/// Collect all records in the segment into an array
pub fn SegmentReader::collect(
  self : SegmentReader,
) -> Array[(@core.VectorId, Array[Double], @core.Attrs)] {
  let results : Array[(@core.VectorId, Array[Double], @core.Attrs)] = []
  let r = @binary.BinaryReader::new(self.data)
  r.skip(8) // Skip header
  while r.remaining() >= 16 {
    // Read ID
    let id = @core.VectorId(r.read_u64().reinterpret_as_int64())
    // Read lengths
    let attrs_len = r.read_u32().reinterpret_as_int()
    let vector_len = r.read_u32().reinterpret_as_int()
    // Validate
    if r.remaining() < attrs_len + vector_len {
      break
    }
    // Read attrs
    let attrs = if attrs_len > 0 {
      let attrs_bytes = r.read_bytes(attrs_len)
      match @codec.decode_attrs_json(attrs_bytes) {
        Some(a) => a
        None => @core.empty_attrs()
      }
    } else {
      @core.empty_attrs()
    }
    // Read vector
    let count = vector_len / 4
    let vector : Array[Double] = Array::make(count, 0.0)
    for i in 0..<count {
      vector[i] = r.read_f32().to_double()
    }
    results.push((id, vector, attrs))
  }
  results
}

///|
/// Iterate over all records in the segment
pub fn SegmentReader::iter(
  self : SegmentReader,
) -> Iter[(@core.VectorId, Array[Double], @core.Attrs)] {
  self.collect().iter()
}
