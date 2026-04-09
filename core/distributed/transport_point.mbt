///|
/// A single point for transport between shards.

///|
pub(all) struct TransportPoint {
  id : @types.VectorId
  vector : Array[Double]
  attrs : @types.Attrs
}

///|
/// JSONL format (SoT — both to_jsonl and from_jsonl use this definition):
///
/// Int64Id:   {"id":{"hi":<i32>,"lo":<i32>},"vector":[<f64>,...],"payload":{...}}
/// Bytes16Id: {"id":{"uuid":"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"},"vector":[<f64>,...],"payload":{...}}
///
/// hi/lo encodes Int64 as two i32 halves (MoonBit JS-target FFI convention).
/// uuid encodes 128-bit IDs as standard UUID string for interoperability.
///
/// from_jsonl accepts both formats for backward compatibility.

///|
pub fn TransportPoint::to_jsonl(self : TransportPoint) -> String {
  let id_json = match self.id {
    @types.Int64Id(v) => {
      let hi = (v >> 32).to_int()
      let lo = v.land(0xFFFFFFFFL).to_int()
      Json::object({
        "hi": hi.to_double().to_json(),
        "lo": lo.to_double().to_json(),
      })
    }
    @types.Bytes16Id(b) =>
      Json::object({ "uuid": b.to_uuid_string().to_json() })
  }
  let m : Map[String, Json] = {}
  m["id"] = id_json
  let vec_json : Array[Json] = []
  for v in self.vector {
    vec_json.push(v.to_json())
  }
  m["vector"] = Json::array(vec_json)
  m["payload"] = @codec.attrs_to_json_value(self.attrs)
  Json::object(m).stringify()
}

///|
pub fn TransportPoint::from_jsonl(line : String) -> TransportPoint? {
  let json : Json = @json.parse(line) catch { _ => return None }
  let id_obj = match json {
    { "id": id_json, .. } => id_json
    _ => return None
  }
  let vid = match id_obj {
    // Bytes16Id: {"uuid": "..."}
    { "uuid": String(s), .. } =>
      match @types.VectorId::from_uuid_string(s) {
        Some(id) => id
        None => return None
      }
    // Int64Id: {"hi": <number>, "lo": <number>}
    { "hi": Number(h, ..), "lo": Number(l, ..), .. } => {
      let hi = h.to_int()
      let lo = l.to_int()
      @types.VectorId::from_int64(
        (hi.to_int64() << 32) | lo.to_int64().land(0xFFFFFFFFL),
      )
    }
    _ => return None
  }
  let vector : Array[Double] = []
  match json {
    { "vector": Array(arr), .. } =>
      for v in arr {
        match v {
          Number(n, ..) => vector.push(n)
          _ => ()
        }
      }
    _ => return None
  }
  if vector.is_empty() {
    return None
  }
  let payload_json = match json {
    { "payload": payload, .. } => payload.stringify()
    _ => "{}"
  }
  let attrs = @codec.parse_attrs_json(payload_json).unwrap_or(
    @types.empty_attrs(),
  )
  Some(TransportPoint::{ id: vid, vector, attrs })
}
