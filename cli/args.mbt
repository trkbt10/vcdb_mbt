///|
/// CLI utilities for vcdb commands

///|
/// Build the vcdb CLI command definition using @argparse.
pub fn vcdb_command() -> @argparse.Command {
  @argparse.Command(
    "vcdb",
    about="Vector Database CLI",
    version="0.1.0",
    subcommand_required=true,
    subcommands=[
      @argparse.Command(
        "collections",
        about="Manage collections",
        subcommand_required=true,
        subcommands=[
          @argparse.Command("list", about="List all collections"),
          @argparse.Command(
            "create",
            about="Create a new collection",
            positionals=[@argparse.PositionArg("name", about="Collection name")],
            options=[
              @argparse.OptionArg("dim", about="Vector dimension", default_values=[
                "128",
              ]),
              @argparse.OptionArg(
                "metric",
                about="Distance metric (cosine|l2|dot)",
                default_values=["cosine"],
              ),
              @argparse.OptionArg(
                "strategy",
                about="ANN strategy (hnsw|ivf|bruteforce)",
                default_values=["hnsw"],
              ),
            ],
          ),
          @argparse.Command("delete", about="Delete a collection", positionals=[
            @argparse.PositionArg("name", about="Collection name"),
          ]),
          @argparse.Command("info", about="Get collection info", positionals=[
            @argparse.PositionArg("name", about="Collection name"),
          ]),
        ],
      ),
      @argparse.Command(
        "points",
        about="Manage points",
        subcommand_required=true,
        subcommands=[
          @argparse.Command(
            "upsert",
            about="Add/update points",
            positionals=[
              @argparse.PositionArg("collection", about="Collection name"),
            ],
            options=[
              @argparse.OptionArg("id", about="Point ID", required=true),
              @argparse.OptionArg(
                "vector",
                about="Vector values (comma-separated)",
                required=true,
              ),
              @argparse.OptionArg(
                "payload",
                about="Payload key-value pairs (k1=v1,k2=v2)",
              ),
            ],
          ),
          @argparse.Command("get", about="Get a point by ID", positionals=[
            @argparse.PositionArg("collection", about="Collection name"),
            @argparse.PositionArg("id", about="Point ID"),
          ]),
          @argparse.Command("delete", about="Delete a point", positionals=[
            @argparse.PositionArg("collection", about="Collection name"),
            @argparse.PositionArg("id", about="Point ID"),
          ]),
          @argparse.Command(
            "search",
            about="Search for similar vectors",
            positionals=[
              @argparse.PositionArg("collection", about="Collection name"),
            ],
            options=[
              @argparse.OptionArg(
                "vector",
                about="Query vector (comma-separated)",
                required=true,
              ),
              @argparse.OptionArg("k", about="Number of results", default_values=[
                "10",
              ]),
            ],
          ),
        ],
      ),
      @argparse.Command(
        "request",
        about="Execute one gateway request natively",
        options=[
          @argparse.OptionArg("method", about="HTTP method", default_values=[
            "GET",
          ]),
          @argparse.OptionArg("path", about="Gateway path", default_values=[
            "/healthz",
          ]),
          @argparse.OptionArg("body", about="Optional JSON request body"),
        ],
      ),
      @argparse.Command(
        "dump",
        about="Dump a snapshot file to JSONL (stdout)",
        positionals=[
          @argparse.PositionArg("file", about="Path to .data.bin snapshot file"),
        ],
      ),
      @argparse.Command(
        "load",
        about="Load JSONL into sharded persistent snapshots",
        positionals=[
          @argparse.PositionArg("input", about="Path to .jsonl input file"),
          @argparse.PositionArg(
            "output",
            about="Output directory for sharded snapshots",
          ),
        ],
        options=[
          @argparse.OptionArg("dim", about="Vector dimension", default_values=[
            "1024",
          ]),
          @argparse.OptionArg(
            "metric",
            about="Distance metric (cosine|l2|dot)",
            default_values=["cosine"],
          ),
          @argparse.OptionArg(
            "strategy",
            about="ANN strategy (hnsw|ivf|bruteforce)",
            default_values=["hnsw"],
          ),
          @argparse.OptionArg(
            "shards",
            about="Number of shards (CRUSH placement groups)",
            default_values=["1"],
          ),
          @argparse.OptionArg("collection", about="Collection name", default_values=[
            "db",
          ]),
        ],
      ),
      @argparse.Command("healthz", about="Health check"),
    ],
  )
}

///|
/// Get a single value from Matches by key.
pub fn get_value(matches : @argparse.Matches, key : String) -> String? {
  match matches.values.get(key) {
    Some([value, ..]) => Some(value)
    _ => None
  }
}

///|
/// Get a value from Matches with a default.
pub fn get_value_or(
  matches : @argparse.Matches,
  key : String,
  default : String,
) -> String {
  get_value(matches, key).unwrap_or(default)
}

///|
/// Get an integer value from Matches.
pub fn get_int_value(matches : @argparse.Matches, key : String) -> Int? {
  match get_value(matches, key) {
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
/// Get an integer value from Matches with a default.
pub fn get_int_value_or(
  matches : @argparse.Matches,
  key : String,
  default : Int,
) -> Int {
  get_int_value(matches, key).unwrap_or(default)
}

///|
/// Parse vector string (comma-separated doubles)
pub fn parse_vector(s : String) -> Array[Double]? {
  let parts = split_by_comma(s)
  let result : Array[Double] = []
  for part in parts {
    let trimmed = part.trim(chars=" ").to_owned()
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
pub fn parse_payload(s : String) -> Json {
  let parts = split_by_comma(s)
  let obj : Map[String, Json] = {}
  for part in parts {
    let kv = split_by_equals(part)
    if kv.length() >= 2 {
      let key = kv[0].trim(chars=" ").to_owned()
      let value = kv[1].trim(chars=" ").to_owned()
      // Try to parse as number first
      let parse_result : Result[Double, _] = try? @string.parse_double(value)
      match parse_result {
        Ok(n) => obj[key] = n.to_json()
        Err(_) =>
          // Check for boolean
          if value == "true" {
            obj[key] = true.to_json()
          } else if value == "false" {
            obj[key] = false.to_json()
          } else {
            obj[key] = value.to_json()
          }
      }
    }
  }
  Json::object(obj)
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
pub fn parse_metric(s : String) -> @types.Metric? {
  @types.Metric::from_name(s)
}

///|
pub fn parse_strategy(s : String) -> @types.Strategy? {
  @types.Strategy::from_name(s)
}
