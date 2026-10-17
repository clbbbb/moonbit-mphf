# MoonBit MPHF

MoonBit MPHF is a pure-MoonBit library for deterministic minimal perfect hash
functions and checked, immutable integer sets/maps. It is designed for a key
set known at build time: protocol tokens, compiled rule tables, embedded
configuration, or immutable data segments.

An MPHF maps the original `n` keys to exactly the slots `[0, n)` without
collisions. An MPHF alone cannot recognise an unknown key, so this package
also provides `StaticSet` and `StaticIntMap`; they retain the slot-ordered key
and perform an exact equality check before returning a hit.

`StaticStringSet` and `StaticStringIntMap` provide the same checked behavior
for UTF-16/Unicode-scalar strings. They use `stable_string_hash` for routing,
retain the original strings, and reject a construction-time hash collision.

## Use

```moonbit
let routes = @mphf.StaticIntMap::from_entries([
  { key: 101, value: 10 },
  { key: 203, value: 20 },
]).unwrap()
assert_eq(routes.get(203), Some(20))
assert_eq(routes.get(404), None)
```

Run the local checks and example:

```text
moon check --deny-warn
moon test --deny-warn
moon bench --release --deny-warn
moon run cmd/main
python scripts/check_encapsulation.py
```

## Guarantees and boundaries

- Input keys are non-negative MoonBit `Int` values and must be unique. They
  are already-hashed identifiers; the package intentionally does not impose a
  string or cryptographic hashing policy.
- Construction uses a deterministic, bounded-retry BDZ-style three-vertex
  hypergraph. It either returns a function or `ConstructionFailed`; it never
  loops indefinitely. The default policy allows up to 256 seeds; callers can
  choose a smaller retry budget through `MphfBuildOptions`.
- `Mphf::slot_of_hash` is only a slot function. Use `StaticSet::contains` or
  `StaticIntMap::get` when a query may contain unknown keys.
- Word encodings are versioned and validate lengths, metadata, assignment
  bounds, duplicate keys, and key/slot agreement on decode.
- `SegmentedSet` and `SegmentedIntMap` support immutable batches. Set
  compaction removes duplicates; map lookup gives later batches precedence;
  both representations have checked word encodings.
- `StaticIntMultiMap` indexes distinct keys once and retains each key's values
  in input order. `StaticIntBiMap` provides checked forward and reverse exact
  lookup for one-to-one non-negative integer mappings.
- `StaticStringSet` and `StaticStringIntMap` have versioned Unicode-scalar
  word encodings. Decoding validates every scalar and reruns exact MPHF-slot
  routing checks before exposing a loaded string index.
- `ShardedSet` and `ShardedIntMap` route `key % shard_count` to one MPHF,
  supporting bounded builds, deterministic re-sharding, compaction, and
  checked nested encodings. Their `validate` methods also verify a received
  in-memory shard layout and every key's residue routing.
- Static set/map patches model immutable rebuilds explicitly and can be stored
  as validated word streams. Persistent cursors support checkpointed scans
  without mutating a published index.
- Indexes, cursors, and validated patches hide their backing arrays and state.
  Exported arrays are independent copies. Cursor successors share storage that
  callers cannot mutate, so retaining a checkpoint preserves its remaining scan.
  Creating a cursor and querying its remaining count take O(1); collecting a
  suffix takes time proportional to the number of returned entries.
- Slot sums, reverse assignments, and vertex-capacity calculations use 64-bit
  intermediates. An unrepresentable vertex count returns `CapacityExceeded`;
  decoding rejects MPHF metadata with more keys than vertices.
- Build options expose the vertex-ratio/retry trade-off; `validate` and
  deterministic fingerprints provide artifact-integrity checks. Fingerprints
  detect accidental mismatch and are not cryptographic authentication.
- This library deliberately does not support insertion, deletion, resizing,
  cryptographic hashing, or a network/database layer. Rebuild when the key
  set changes.

## Compatibility of the snapshot fixes

Internal struct fields are now private, including validated patch fields.
Use `stats`, `keys_by_slot()`, `entries_by_slot()`, the patch accessors, and
cursor methods instead of reading representation fields. Those accessors
return scalar summaries or independent arrays. `MphfError` has a new
`CapacityExceeded(Int)` variant for unrepresentable construction sizes.
Existing word-format versions and artifacts produced by the builders remain
compatible. These fixes are included starting with `0.2.0`; the older `0.1.0`
package does not include them.
See [the regression and resubmission notes](docs/acceptance-fixes.md).

## Provenance

The implementation is independently written in MoonBit, using the public
minimal-perfect-hashing approach as a reference. It does not copy source,
tests, or generated tables from upstream projects. Relevant references are
[rust-phf](https://github.com/rust-phf/rust-phf) and
[BBHash](https://github.com/relab/bbhash), both MIT licensed.

The project itself is licensed under Apache-2.0; see [LICENSE](LICENSE).

## Publishing note

The MoonBit package is `clbbbb/moon-mphf@0.2.0` on Mooncakes. The
source repository is `https://github.com/clbbbb/moonbit-mphf`.
