# cmd/native-serve

MoonBit-native HTTP server for vcdb using `moonbitlang/async/http`.

## Usage

```bash
moon run cmd/native-serve -- --host 127.0.0.1 --port 6333 --storage .local-storage
```

This serves the existing `gateway` API directly from native code.

## Notes

- Transport overhead from the JS adapter is removed.
- Filesystem persistence is available via `--storage`.
- `--in-memory` can be used for ephemeral runs.
- Browser dashboard can point directly at this server.
