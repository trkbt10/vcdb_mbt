# Cross-version WAL migration fixtures

Each `wal_vN.hex` is the **real** byte output of WAL format version N's own
`encode_wal_segment`, produced by checking the matching historical commit into
an isolated git worktree and running its encoder on one fixed dataset:
`upsert(1,[1,2,3],{src:"a"})`, `upsert(2,[4,5,6],{src:"b"})`, `set_attrs(1,{src:"c"})`, `remove(2)`.

| version | wal_version | source commit | bytes | current code reads it? |
|---------|-------------|---------------|-------|------------------------|
| v2 | 0x02 | 17ef48f | 185 | yes — decode+replay+re-encode |
| v3 | 0x03 | 4db6088 | 189 | **NO — decode_wal_records returns 0 (defect)** |
| v4 | 0x04 | 0254f3c (current) | 233 | yes |

Header magic for all three is `VCDBMBT\0`; file-type byte `0x01` (Wal).

`core/persistence/wal/migration_wbtest.mbt` loads each fixture and asserts what
the current code does with it.

## v3 defect (open)

Loading the **real** v3 segment (`wal_v3.hex`) through the current
`decode_wal_records` yields **0 records instead of 4**, even though the header
and `wal_version` byte are read correctly. So genuine v3-format WAL files would
silently fail to replay under today's code. `format_v3_wbtest.mbt` does not
catch this because it hand-builds records matching the decoder's assumptions
rather than using v3's actual encoder output. The migration test pins the
current (incorrect) behavior; fixing the v3 record-decode path should flip it
to the full v2/v4-style assertions.

## v1

v1 (`0x01`) is absent: the v1-era `collection` package imports
`moonbitlang/async/js_async`, unresolved under the current async dependency, so
the historical v1 package no longer builds. v1 read/replay is already verified
against the current decoder by the real-layout segment in `format_v1_wbtest.mbt`.
