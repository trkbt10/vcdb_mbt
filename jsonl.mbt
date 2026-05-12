///|
/// JSONL export for VectorDB.
///
/// Uses TransportPoint::to_jsonl for the shared JSONL format.

///|
/// Export all points as JSONL lines.
pub fn VectorDB::export_jsonl(self : VectorDB) -> Array[String] {
  let entries = self.scroll(limit=self.size() + 1)
  let lines : Array[String] = []
  for entry in entries {
    let (vid, record) = entry
    let point = @distributed.TransportPoint::{
      id: vid,
      vector: record.vector,
      attrs: record.attrs,
    }
    lines.push(point.to_jsonl())
  }
  lines
}
