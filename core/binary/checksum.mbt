///|
/// CRC32 checksum implementation (IEEE 802.3 polynomial)
/// Polynomial: 0xEDB88320 (reversed form of 0x04C11DB7)

///|
/// Compute CRC32 checksum of data
pub fn crc32(data : Bytes) -> UInt {
  let mut c = 0xFFFFFFFFU
  for i in 0..<data.length() {
    c = c ^ data[i].to_uint()
    for _ in 0..<8 {
      let mask = 0U - (c & 1U)
      c = (c >> 1) ^ (0xEDB88320U & mask)
    }
  }
  c ^ 0xFFFFFFFFU
}

///|
/// CRC32 lookup table for faster computation
let crc32_table : Array[UInt] = {
  let table = Array::make(256, 0U)
  for i in 0..<256 {
    let mut c = i.reinterpret_as_uint()
    for _ in 0..<8 {
      if (c & 1U) != 0U {
        c = (c >> 1) ^ 0xEDB88320U
      } else {
        c = c >> 1
      }
    }
    table[i] = c
  }
  table
}

///|
/// Compute CRC32 using lookup table (faster for larger data)
pub fn crc32_fast(data : Bytes) -> UInt {
  let mut c = 0xFFFFFFFFU
  for i in 0..<data.length() {
    let idx = ((c ^ data[i].to_uint()) & 0xFFU).reinterpret_as_int()
    c = (c >> 8) ^ crc32_table[idx]
  }
  c ^ 0xFFFFFFFFU
}

///|
/// Verify CRC32 checksum
pub fn crc32_verify(data : Bytes, expected : UInt) -> Bool {
  crc32(data) == expected
}
