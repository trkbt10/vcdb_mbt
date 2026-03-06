# cli

Command-line argument parsing for vcdb.

## Usage

```moonbit
let args = parse_args(["collection", "create", "--dim", "128", "--name", "test"])
// args.command == "collection"
// args.subcommand == "create"
// args.flags["dim"] == "128"
// args.flags["name"] == "test"
```

## Argument Format

```
vcdb <command> [subcommand] [--flag value] [--bool-flag] [positional...]
```

Supports:
- Positional arguments
- Key-value flags (`--flag value`)
- Boolean flags (`--verbose`)
