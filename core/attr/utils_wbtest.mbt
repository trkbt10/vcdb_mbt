///|
/// remove_vectorid_swap utility function
test "attr/remove_vectorid_swap" {
  let arr : Array[@types.VectorId] = [
    @types.Int64Id(1L),
    @types.Int64Id(2L),
    @types.Int64Id(3L),
    @types.Int64Id(4L),
    @types.Int64Id(5L),
  ]
  inspect(remove_vectorid_swap(arr, @types.Int64Id(3L)), content="true")
  inspect(arr.length(), content="4")
  inspect(remove_vectorid_swap(arr, @types.Int64Id(99L)), content="false")
  inspect(arr.length(), content="4")
  inspect(remove_vectorid_swap(arr, @types.Int64Id(5L)), content="true")
  inspect(arr.length(), content="3")
}

///|
/// remove_num_entry_swap utility function
test "attr/remove_num_entry_swap" {
  let arr : Array[NumEntry] = [
    NumEntry::{ value: 1.0, id: @types.Int64Id(10L) },
    NumEntry::{ value: 2.0, id: @types.Int64Id(20L) },
    NumEntry::{ value: 3.0, id: @types.Int64Id(30L) },
  ]
  inspect(remove_num_entry_swap(arr, @types.Int64Id(20L)), content="true")
  inspect(arr.length(), content="2")
  inspect(remove_num_entry_swap(arr, @types.Int64Id(99L)), content="false")
  inspect(arr.length(), content="2")
}

///|
/// attr_value_to_key disambiguates types
test "attr/key_type_disambiguation" {
  let key_int = attr_value_to_key(@types.Int(1L))
  let key_float = attr_value_to_key(@types.Float(1.0))
  let key_string = attr_value_to_key(@types.String("1"))
  inspect(key_int != key_float, content="true")
  inspect(key_int != key_string, content="true")
  inspect(key_float != key_string, content="true")
  inspect(key_int.has_prefix("I:"), content="true")
  inspect(key_float.has_prefix("F:"), content="true")
  inspect(key_string.has_prefix("S:"), content="true")
  let key_bool = attr_value_to_key(@types.Bool(true))
  let key_null = attr_value_to_key(@types.Null)
  inspect(key_bool.has_prefix("B:"), content="true")
  inspect(key_null.has_prefix("N:"), content="true")
}
