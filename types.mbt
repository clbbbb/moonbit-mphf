///|
/// Errors returned while building or decoding a static hash index.
pub(all) enum MphfError {
  EmptyInput
  EmptySegment(Int)
  NegativeKey(Int)
  DuplicateKey(Int)
  DuplicateValue(Int)
  DuplicateStringKey(String)
  HashCollision(String, String)
  ConstructionFailed(Int)
  MissingHeader
  UnsupportedVersion(Int)
  InvalidPayloadLength(Int, Int)
  InvalidMetadata
  InvalidVertexValue(Int)
  InvalidBuildOption(Int)
  InvalidShardCount(Int)
  InvalidRange(Int, Int)
  DuplicatePatchKey(Int)
}

///|
/// Summary of the deterministic construction selected for a key set.
pub(all) struct MphfStats {
  key_count : Int
  vertex_count : Int
  seed : Int
  attempts : Int
}

///|
/// Controls the memory/retry trade-off made while constructing a BDZ graph.
/// `vertices_per_key_milli` is expressed in thousandths, so `1300` means
/// 1.3 graph vertices for each source key.
pub(all) struct MphfBuildOptions {
  vertices_per_key_milli : Int
  max_attempts : Int
  initial_seed : Int
}

///| A minimal perfect hash function over one validated key set.

///|
/// `slot_of_hash` maps every non-negative input to a slot. Membership must be
/// checked separately, because an MPHF alone cannot recognize an unknown key.
pub struct Mphf {
  key_count : Int
  vertex_count : Int
  seed : Int
  attempts : Int
  values : Array[Int]
}

///|
/// An exact static membership set backed by an MPHF and slot-ordered keys.
pub struct StaticSet {
  mphf : Mphf
  keys_by_slot : Array[Int]
}

///|
/// One integer key/value pair used to construct a static map.
pub(all) struct IntEntry {
  key : Int
  value : Int
}

///|
/// One key/value item for a multimap. Equal keys are intentionally allowed.
pub(all) struct IntMultiEntry {
  key : Int
  value : Int
}

///|
/// An exact immutable integer map with constant-time lookup after building.
pub struct StaticIntMap {
  mphf : Mphf
  keys_by_slot : Array[Int]
  values_by_slot : Array[Int]
}

///|
/// An exact immutable one-to-one integer mapping with independently checked
/// forward and reverse MPHF indexes.
pub struct StaticIntBiMap {
  forward : StaticIntMap
  reverse : StaticIntMap
}

///|
/// An exact immutable map from one integer key to an ordered, non-empty value
/// slice. The MPHF indexes distinct keys, while values are stored compactly in
/// one contiguous array.
pub struct StaticIntMultiMap {
  mphf : Mphf
  keys_by_slot : Array[Int]
  offsets_by_slot : Array[Int]
  values : Array[Int]
}

///|
/// One UTF-16/Unicode-scalar string key paired with an integer value.
pub(all) struct StringIntEntry {
  key : String
  value : Int
}

///| An exact static string set. Keys are retained at MPHF slots so hash

///|
/// collisions cannot produce a successful membership query.
pub struct StaticStringSet {
  mphf : Mphf
  keys_by_slot : Array[String]
}

///|
/// An exact immutable map from strings to integers.
pub struct StaticStringIntMap {
  mphf : Mphf
  keys_by_slot : Array[String]
  values_by_slot : Array[Int]
}

///|
/// Aggregate information for an immutable segmented index.
pub(all) struct SegmentStats {
  segment_count : Int
  key_count : Int
}

///|
/// Basic distribution information for a fixed-count sharded index.
pub(all) struct ShardStats {
  shard_count : Int
  key_count : Int
  smallest_shard : Int
  largest_shard : Int
}

///|
/// Aggregate result for a batch of exact membership or map probes.
pub(all) struct LookupSummary {
  query_count : Int
  hit_count : Int
  miss_count : Int
}

///|
/// A deterministic, non-cryptographic integrity summary of a static source
/// manifest. It detects accidental mismatch, not malicious tampering.
pub(all) struct StaticIndexFingerprint {
  key_count : Int
  key_fingerprint : Int
  value_fingerprint : Int
}

///|
/// Exact key-set delta used to decide whether a static index must be rebuilt.
pub(all) struct KeySetDiff {
  added : Array[Int]
  removed : Array[Int]
  retained : Int
}

///| A read-only union of independently built MPHF-backed sets.

///|
/// Segments are useful when source data arrives in immutable batches and a
/// full rebuild should be deferred to an explicit compaction step.
pub struct SegmentedSet {
  segments : Array[StaticSet]
}

///|
/// A read-only layered map. Later segments override earlier ones on lookup.
pub struct SegmentedIntMap {
  segments : Array[StaticIntMap]
}

///|
/// A static set partitioned by `key % shard_count`. Sharding keeps builds and
/// rebuilds bounded for datasets that are too large for one MPHF artifact.
pub struct ShardedSet {
  shard_count : Int
  shards : Array[StaticSet?]
}

///|
/// A static integer map partitioned by `key % shard_count`.
pub struct ShardedIntMap {
  shard_count : Int
  shards : Array[StaticIntMap?]
}

///|
/// A checked edit plan for rebuilding a static set from a previous snapshot.
pub(all) struct StaticSetPatch {
  additions : Array[Int]
  removals : Array[Int]
}

///|
/// A checked edit plan for rebuilding a static map from a previous snapshot.
pub(all) struct StaticIntMapPatch {
  upserts : Array[IntEntry]
  removals : Array[Int]
}

///|
/// A persistent cursor over slot-ordered set keys. Each `next` call returns a
/// new cursor, so callers can safely retain checkpoints for later replay.
pub struct StaticSetCursor {
  keys_by_slot : Array[Int]
  next_slot : Int
}

///|
/// A persistent cursor over slot-ordered static map entries.
pub struct StaticIntMapCursor {
  keys_by_slot : Array[Int]
  values_by_slot : Array[Int]
  next_slot : Int
}

///|
/// A persistent cursor over every entry of a static multimap. Equal-key values
/// are visited consecutively in their original input order.
pub struct StaticIntMultiMapCursor {
  keys_by_slot : Array[Int]
  offsets_by_slot : Array[Int]
  values : Array[Int]
  slot : Int
  value_index : Int
}
