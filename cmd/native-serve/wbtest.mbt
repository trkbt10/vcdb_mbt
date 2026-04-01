///|
test "method_name maps request methods" {
  assert_eq(method_name(@async_http.RequestMethod::Get), "GET")
  assert_eq(method_name(@async_http.RequestMethod::Post), "POST")
  assert_eq(method_name(@async_http.RequestMethod::Options), "OPTIONS")
}
