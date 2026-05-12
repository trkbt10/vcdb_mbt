# cmd/native-gateway

MoonBit-native gateway execution entrypoint for vcdb.

This package executes the same `gateway` API layer used by transport adapters,
but without the JavaScript runtime. It is intended for native-side verification
and future native hosting work.

## Usage

```bash
moon run cmd/native-gateway -- healthz
moon run cmd/native-gateway -- request --method GET --path /collections
moon run cmd/native-gateway -- collections create demo --dim 3
moon run cmd/native-gateway -- points upsert demo --id 1 --vector 1,0,0
```

## Notes

- State lives in-process today via `MemoryStorage`.
- Long-lived HTTP serving remains the responsibility of transport adapters such
  as [`packages/sdk/src/server.ts`](/Users/terukichi/Workspaces/moonbit/vcdb/packages/sdk/src/server.ts).
