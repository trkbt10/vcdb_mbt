///|
/// CLI argument parsing for vcdb commands

///|
/// Parsed command-line arguments
pub struct ParsedArgs {
  mut command : String
  mut subcommand : String
  positional : Array[String]
  flags : Map[String, String]
  bool_flags : Map[String, Bool]
} derive(Show)

///|
/// Create empty parsed args
pub fn ParsedArgs::empty() -> ParsedArgs {
  { command: "", subcommand: "", positional: [], flags: {}, bool_flags: {} }
}

///|
/// Parse command-line arguments
/// Format: vcdb <command> [subcommand] [--flag value] [--bool-flag] [positional...]
pub fn parse_args(args : Array[String]) -> ParsedArgs {
  let result : ParsedArgs = ParsedArgs::empty()

  if args.length() == 0 {
    return result
  }

  let mut i = 0

  // First non-flag argument is the command
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("--") {
      break
    }
    if result.command == "" {
      result.command = arg
    } else if result.subcommand == "" {
      result.subcommand = arg
    } else {
      result.positional.push(arg)
    }
    i = i + 1
  }

  // Parse flags
  while i < args.length() {
    let arg = args[i]
    if arg.has_prefix("--") {
      let flag_name = arg.unsafe_substring(start=2, end=arg.length())
      // Check if this is a boolean flag (no value) or a key-value flag
      if i + 1 < args.length() && !args[i + 1].has_prefix("--") {
        // Key-value flag
        result.flags[flag_name] = args[i + 1]
        i = i + 2
      } else {
        // Boolean flag
        result.bool_flags[flag_name] = true
        i = i + 1
      }
    } else {
      // Positional argument after flags
      result.positional.push(arg)
      i = i + 1
    }
  }

  result
}

///|
/// Get a string flag value
pub fn ParsedArgs::get_flag(self : ParsedArgs, name : String) -> String? {
  self.flags.get(name)
}

///|
/// Get a string flag value with default
pub fn ParsedArgs::get_flag_or(
  self : ParsedArgs,
  name : String,
  default : String,
) -> String {
  self.flags.get(name).unwrap_or(default)
}

///|
/// Get an integer flag value
pub fn ParsedArgs::get_int_flag(self : ParsedArgs, name : String) -> Int? {
  match self.flags.get(name) {
    Some(s) => {
      let result : Result[Int64, _] = try? @string.parse_int64(s)
      match result {
        Ok(n) => Some(n.to_int())
        Err(_) => None
      }
    }
    None => None
  }
}

///|
/// Get an integer flag value with default
pub fn ParsedArgs::get_int_flag_or(
  self : ParsedArgs,
  name : String,
  default : Int,
) -> Int {
  self.get_int_flag(name).unwrap_or(default)
}

///|
/// Check if a boolean flag is set
pub fn ParsedArgs::has_flag(self : ParsedArgs, name : String) -> Bool {
  self.bool_flags.get(name).unwrap_or(false)
}

///|
/// Get a positional argument by index
pub fn ParsedArgs::get_positional(self : ParsedArgs, index : Int) -> String? {
  if index >= 0 && index < self.positional.length() {
    Some(self.positional[index])
  } else {
    None
  }
}

///|
/// Parse vector string (comma-separated doubles)
pub fn parse_vector(s : String) -> Array[Double]? {
  let parts = split_by_comma(s)
  let result : Array[Double] = []
  for part in parts {
    let trimmed = part.trim(chars=" ").to_string()
    if trimmed.length() == 0 {
      continue
    }
    let parse_result : Result[Double, _] = try? @string.parse_double(trimmed)
    match parse_result {
      Ok(n) => result.push(n)
      Err(_) => return None
    }
  }
  if result.length() == 0 {
    None
  } else {
    Some(result)
  }
}

///|
/// Split string by comma
fn split_by_comma(s : String) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  for c in s {
    if c == ',' {
      parts.push(String::from_array(current))
      current.clear()
    } else {
      current.push(c)
    }
  }
  parts.push(String::from_array(current))
  parts
}

///|
/// Parse key=value pairs (e.g., "name=test,count=42")
pub fn parse_payload(s : String) -> @gateway.JsonValue {
  let parts = split_by_comma(s)
  let obj : Map[String, @gateway.JsonValue] = {}
  for part in parts {
    let kv = split_by_equals(part)
    if kv.length() >= 2 {
      let key = kv[0].trim(chars=" ").to_string()
      let value = kv[1].trim(chars=" ").to_string()
      // Try to parse as number first
      let parse_result : Result[Double, _] = try? @string.parse_double(value)
      match parse_result {
        Ok(n) => obj[key] = @gateway.JNumber(n)
        Err(_) =>
          // Check for boolean
          if value == "true" {
            obj[key] = @gateway.JBool(true)
          } else if value == "false" {
            obj[key] = @gateway.JBool(false)
          } else {
            obj[key] = @gateway.JString(value)
          }
      }
    }
  }
  @gateway.JObject(obj)
}

///|
/// Split string by equals sign
fn split_by_equals(s : String) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  let mut found_equals = false
  for c in s {
    if c == '=' && !found_equals {
      parts.push(String::from_array(current))
      current.clear()
      found_equals = true
    } else {
      current.push(c)
    }
  }
  parts.push(String::from_array(current))
  parts
}

///|
/// Print usage help
pub fn print_help() -> String {
  let lines = [
    "vcdb - Vector Database CLI", "", "Usage: vcdb <command> [subcommand] [options]",
    "", "Commands:", "  collections list              List all collections", "  collections create <name>     Create a new collection",
    "    --dim <n>                   Vector dimension (default: 128)", "    --metric <cosine|l2|dot>    Distance metric (default: cosine)",
    "    --strategy <hnsw|ivf|bruteforce>  ANN strategy (default: hnsw)", "  collections delete <name>     Delete a collection",
    "  collections info <name>       Get collection info", "", "  points upsert <collection>    Add/update points",
    "    --id <n>                    Point ID", "    --vector <v1,v2,...>        Vector values (comma-separated)",
    "    --payload <k1=v1,k2=v2>     Payload key-value pairs", "  points get <collection> <id>  Get a point by ID",
    "  points delete <collection> <id>  Delete a point", "  points search <collection>    Search for similar vectors",
    "    --vector <v1,v2,...>        Query vector", "    --k <n>                     Number of results (default: 10)",
    "", "  request                       Execute one gateway request natively", "    --method <verb>             HTTP method (default: GET)",
    "    --path </path>              Gateway path (default: /healthz)", "    --body <json>               Optional JSON request body",
    "", "Options:", "  --help                        Show this help message", "  --version                     Show version",
  ]
  lines.iter().intersperse("\n").fold(init="", fn(acc, s) { acc + s })
}

///|
/// Print version
pub fn print_version() -> String {
  "vcdb version 0.1.0"
}
