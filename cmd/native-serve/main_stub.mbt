///|
/// Stub main for non-native targets.
///
/// The real server entrypoint depends on native-only async/socket implementations.
/// This keeps the package well-formed for cross-target check/test/info runs.
fn main {
  println("cmd/native-serve is only supported on native targets")
}
