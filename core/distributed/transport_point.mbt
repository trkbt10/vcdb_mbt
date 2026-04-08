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
///   {"id":{"hi":<i32>,"lo":<i32>},"vector":[<f64>,...],"payload":{...}}
///
/// hi/lo encodes VectorId (Int64) as two i32 halves, matching the
/// MoonBit JS-target FFI convention.

///|
pub fn TransportPoint::to_jsonl(self : TransportPoint) -> String {
  let id_val = self.id.to_int64()
  let hi = (id_val >> 32).to_int()
  let lo = id_val.land(0xFFFFFFFFL).to_int()
  let m : Map[String, Json] = {}
  m["id"] = Json::object(
    { "hi": hi.to_double().to_json(), "lo": lo.to_double().to_json() },
  )
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
  let json : Json = @json.parse(line) catch {
    _ => return None
  }
  let id_obj = match json {
    { "id": id_json, .. } => id_json
    _ => return None
  }
  let (hi, lo) = match id_obj {
    { "hi": Number(h, ..), "lo": Number(l, ..), .. } => (h.to_int(), l.to_int())
    _ => return None
  }
  let vid = @types.VectorId::from_int64(
    (hi.to_int64() << 32) | lo.to_int64().land(0xFFFFFFFFL),
  )
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
  let attrs = @codec.parse_attrs_json(payload_json)
    .unwrap_or(@types.empty_attrs())
  Some(TransportPoint::{ id: vid, vector, attrs })
}
