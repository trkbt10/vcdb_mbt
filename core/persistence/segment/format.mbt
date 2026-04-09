///|
/// Data Segment - Binary format for storing vectors in distributed segments
/// Format: Header (12 bytes) + Records
/// Header: Magic (8 bytes "VCDBMBT\0") + Type (1) + Version (1) + Reserved (2)
/// Record: ID (8 bytes) + AttrsLen (4 bytes) + VectorLen (4 bytes) + Attrs + Vector

///|
/// Segment format version
pub let segment_version : Byte = b'\x01'

///|
/// Data pointer - reference to a record within a segment
pub(all) struct DataPointer {
  segment : String // Segment name
  offset : Int // Byte offset within segment
  length : Int // Record length in bytes
} derive(Eq)

///|
pub impl Show for DataPointer with output(self, logger) {
  logger.write_string("{ segment: ")
  Show::output(self.segment, logger)
  logger.write_string(", offset: ")
  Show::output(self.offset, logger)
  logger.write_string(", length: ")
  Show::output(self.length, logger)
  logger.write_string(" }")
}

///|
/// Index entry - mapping from vector ID to data location
pub(all) struct IndexEntry {
  id : @types.VectorId
  ptr : DataPointer
}

///|
pub impl Show for IndexEntry with output(self, logger) {
  logger.write_string("{ id: ")
  Show::output(self.id, logger)
  logger.write_string(", ptr: ")
  Show::output(self.ptr, logger)
  logger.write_string(" }")
}

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
  // Write header (12 bytes)
  @codec.encode_header(buffer, Segment, segment_version)
  { name, buffer, size: @codec.header_size }
}

///|
/// Append a record to the segment
/// Returns DataPointer to the appended record
pub fn SegmentWriter::append(
  self : SegmentWriter,
  id : @types.VectorId,
  vector : Array[Double],
  attrs : @types.Attrs,
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
  if data.length() < @codec.header_size {
    return None
  }
  let r = @binary.BinaryReader::new(data)
  match @codec.read_header(r) {
    None => None
    Some((file_type, version)) =>
      if file_type == Segment && version == segment_version {
        Some({ name, data })
      } else {
        None
      }
  }
}

///|
/// Read record at specific offset
pub fn SegmentReader::read_at(
  self : SegmentReader,
  offset : Int,
  length : Int,
) -> (@types.VectorId, Array[Double], @types.Attrs)? {
  if offset + length > self.data.length() {
    return None
  }
  // Use reader with skip to avoid copying
  let r = @binary.BinaryReader::new(self.data)
  r.skip(offset)
  // Read ID
  let id = @types.Int64Id(r.read_u64().reinterpret_as_int64())
  // Read lengths
  let attrs_len = r.read_u32().reinterpret_as_int()
  let vector_len = r.read_u32().reinterpret_as_int()
  // Read attrs
  let attrs = if attrs_len > 0 {
    let attrs_bytes = r.read_bytes(attrs_len)
    match @codec.decode_attrs_json(attrs_bytes) {
      Some(a) => a
      None => @types.empty_attrs()
    }
  } else {
    @types.empty_attrs()
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
) -> Array[(@types.VectorId, Array[Double], @types.Attrs)] {
  let results : Array[(@types.VectorId, Array[Double], @types.Attrs)] = []
  let r = @binary.BinaryReader::new(self.data)
  r.skip(@codec.header_size) // Skip header
  while r.remaining() >= 16 {
    // Read ID
    let id = @types.Int64Id(r.read_u64().reinterpret_as_int64())
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
        None => @types.empty_attrs()
      }
    } else {
      @types.empty_attrs()
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
) -> Iter[(@types.VectorId, Array[Double], @types.Attrs)] {
  self.collect().iter()
}
