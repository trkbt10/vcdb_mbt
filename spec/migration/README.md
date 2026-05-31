# Cross-version WAL migration fixtures

Each `wal_vN.hex` is the **real** byte output of WAL format version N's own
`encode_wal_segment`, produced by checking the matching historical commit into
an isolated git worktree and running its encoder on one fixed dataset:
`upsert(1,[1,2,3],{src:"a"})`, `upsert(2,[4,5,6],{src:"b"})`, `set_attrs(1,{src:"c"})`, `remove(2)`.

| version | wal_version | source commit | bytes | current code reads it? |
|---------|-------------|---------------|-------|------------------------|
| v2 | 0x02 | 17ef48f | 185 | yes |
| v3 | 0x03 | 4db6088 | 189 | yes (after the read_wal_version fix) |
| v4 | 0x04 | 0254f3c (current) | 233 | yes |

Header magic for all three is `VCDBMBT\0`; file-type byte `0x01` (Wal).

`core/persistence/wal/migration_wbtest.mbt` loads each fixture and asserts the
current code accepts the header, decodes every field, replays into a
`CoreStore`, and re-encodes to the current (v4) format.

## v3 defect found & fixed

Loading the real v3 segment originally returned **0 records**: `read_wal_version`
omitted `wal_version_v3` from its accepted-version list, so `decode_wal_records`
bailed before decoding — although `verify_wal_header` accepted v3 and the v3
record-decode branch was correct. `format_v3_wbtest.mbt` missed it by exercising
the record decoder directly rather than a full v3 segment through
`decode_wal_records`. Fixed by adding `wal_version_v3` to `read_wal_version`.

## v1

v1 (`0x01`) is absent: the v1-era `collection` package imports
`moonbitlang/async/js_async`, unresolved under the current async dependency, so
the historical v1 package no longer builds. v1 read/replay is verified by
`format_v1_wbtest.mbt`.
