///|
/// The constructed function maps every supplied key to one distinct slot.
test "BDZ construction produces a minimal permutation" {
  let keys : Array[Int] = []
  for index in 0..<120 {
    keys.push(index * 97 + 11)
  }
  let mphf = Mphf::build(keys).unwrap()
  let slots : Array[Int] = []
  for key in keys {
    let slot = mphf.slot_of_hash(key).unwrap()
    assert_true(slot >= 0 && slot < keys.length())
    assert_true(!slots.contains(slot))
    slots.push(slot)
  }
  assert_eq(slots.length(), keys.length())
  assert_true(mphf.stats().vertex_count > keys.length())
  assert_true(mphf.is_perfect_for(keys))
  assert_true(!mphf.is_perfect_for([11, 108]))
}

///| Checked sets retain the source key at each MPHF slot, avoiding unknown-key

///|
/// false positives that an MPHF by itself cannot rule out.
test "static set performs exact membership" {
  let set = StaticSet::from_keys([101, 203, 907, 12_345]).unwrap()
  assert_true(set.contains(101))
  assert_true(set.contains(12_345))
  assert_true(!set.contains(404))
  assert_true(!set.contains(-1))
  assert_eq(set.len(), 4)
}

///|
/// Static maps preserve values by storing keys and values in the same slot order.
test "static integer map returns matching values only" {
  let table = StaticIntMap::from_entries([
    { key: 7, value: 70 },
    { key: 11, value: 110 },
    { key: 41, value: 410 },
  ]).unwrap()
  assert_eq(table.get(7), Some(70))
  assert_eq(table.get(11), Some(110))
  assert_eq(table.get(8), None)
  assert_true(table.contains_key(41))
  assert_true(!table.contains_key(-4))
}

///|
/// Input errors are rejected before the graph construction starts.
test "invalid public key sets are explicit" {
  assert_true(Mphf::build([]) is Err(EmptyInput))
  assert_true(Mphf::build([1, -2]) is Err(NegativeKey(-2)))
  assert_true(Mphf::build([1, 3, 1]) is Err(DuplicateKey(1)))
  assert_true(
    StaticIntMap::from_entries([{ key: 9, value: 1 }, { key: 9, value: 2 }])
    is Err(DuplicateKey(9)),
  )
}

///|
/// Versioned MPHF words preserve all slot assignments exactly.
test "MPHF word codec round trips" {
  let keys = [13, 37, 51, 89, 144]
  let source = Mphf::build(keys).unwrap()
  let decoded = decode_mphf_words(source.encode_words()).unwrap()
  assert_eq(decoded.stats().key_count, source.stats().key_count)
  assert_eq(decoded.stats().vertex_count, source.stats().vertex_count)
  assert_eq(decoded.stats().seed, source.stats().seed)
  for key in keys {
    assert_eq(decoded.slot_of_hash(key), source.slot_of_hash(key))
  }
}

///|
/// Checked container codecs reject truncated and mismatched representations.
test "static set and map codecs preserve exact queries" {
  let set = StaticSet::from_keys([2, 8, 32, 128]).unwrap()
  let decoded_set = decode_static_set_words(set.encode_words()).unwrap()
  assert_true(decoded_set.contains(2))
  assert_true(decoded_set.contains(128))
  assert_true(!decoded_set.contains(3))

  let table = StaticIntMap::from_entries([
    { key: 2, value: 20 },
    { key: 8, value: 80 },
    { key: 32, value: 320 },
  ]).unwrap()
  let decoded_table = decode_static_int_map_words(table.encode_words()).unwrap()
  assert_eq(decoded_table.get(2), Some(20))
  assert_eq(decoded_table.get(32), Some(320))
  assert_eq(decoded_table.get(7), None)
  assert_true(decode_mphf_words([]) is Err(MissingHeader))
  assert_true(decode_mphf_words([4]) is Err(UnsupportedVersion(4)))
  assert_true(decode_static_set_words([2]) is Err(InvalidPayloadLength(2, 1)))
}

///| A deterministic mini property corpus exercises varied graph shapes instead

///|
/// of relying on one lucky construction input.
test "multiple deterministic key corpora have no false negatives" {
  for case_id in 1..<33 {
    let keys : Array[Int] = []
    for item in 0..<(case_id + 7) {
      keys.push(case_id * 100_003 + item * (case_id * 19 + 7))
    }
    let set = StaticSet::from_keys(keys).unwrap()
    for key in keys {
      assert_true(set.contains(key))
    }
    assert_true(!set.contains(-case_id))
  }
}

///| Immutable set batches can be queried before an explicit duplicate-removing

///|
/// compaction, and their encoding preserves the same answers.
test "segmented sets support union queries and compaction" {
  let index = SegmentedSet::from_batches([[2, 5, 8], [5, 13, 21]]).unwrap()
  assert_true(index.contains(2))
  assert_true(index.contains(21))
  assert_true(!index.contains(3))
  assert_eq(index.missing([2, 3, 5, 34]), [3, 34])
  assert_eq(index.stats().segment_count, 2)
  assert_eq(index.stats().key_count, 6)
  let compacted = index.compact().unwrap()
  assert_eq(compacted.len(), 5)
  assert_true(compacted.contains(13))
  let decoded = decode_segmented_set_words(index.encode_words()).unwrap()
  assert_eq(decoded.missing([2, 5, 13, 21]), [])
}

///|
/// Later immutable map batches deliberately override prior values.
test "segmented maps implement newest-value precedence" {
  let index = SegmentedIntMap::from_batches([
    [{ key: 1, value: 10 }, { key: 2, value: 20 }],
    [{ key: 2, value: 200 }, { key: 3, value: 30 }],
  ]).unwrap()
  assert_eq(index.get(1), Some(10))
  assert_eq(index.get(2), Some(200))
  assert_eq(index.get(3), Some(30))
  assert_eq(index.get(4), None)
  assert_eq(index.stats().segment_count, 2)
  assert_true(SegmentedSet::from_batches([[]]) is Err(EmptySegment(0)))
}

///| Stable string IDs and key-set diffs let callers plan a fresh static build

///|
/// without assuming a mutable MPHF supports incremental updates.
test "string hashing and key deltas are deterministic" {
  assert_eq(
    stable_string_hash("route:/users"),
    stable_string_hash("route:/users"),
  )
  assert_true(
    stable_string_hash("route:/users") != stable_string_hash("route:/posts"),
  )
  let delta = compare_key_sets([1, 4, 8], [4, 8, 11, 13]).unwrap()
  assert_eq(delta.added, [11, 13])
  assert_eq(delta.removed, [1])
  assert_eq(delta.retained, 2)
  assert_true(!delta.is_empty())
  assert_eq(delta.changed_count(), 3)
  let before = StaticSet::from_keys([1, 4, 8]).unwrap()
  let after = StaticSet::from_keys([4, 8, 11, 13]).unwrap()
  assert_eq(before.diff_to(after).added, [11, 13])
}

///| String-facing containers retain the original string, so stable hashes are

///|
/// only a routing mechanism rather than the proof of a successful lookup.
test "static string sets and maps are exact" {
  let set = StaticStringSet::from_keys([
    "GET /health", "POST /users", "DELETE /users/:id",
  ]).unwrap()
  assert_true(set.contains("GET /health"))
  assert_true(!set.contains("GET /missing"))
  assert_eq(set.len(), 3)
  assert_true(
    StaticStringSet::from_keys(["GET /health", "GET /health"])
    is Err(DuplicateStringKey("GET /health")),
  )

  let routes = StaticStringIntMap::from_entries([
    { key: "GET /health", value: 200 },
    { key: "POST /users", value: 201 },
  ]).unwrap()
  assert_eq(routes.get("POST /users"), Some(201))
  assert_eq(routes.get("DELETE /users"), None)
  assert_true(routes.contains_key("GET /health"))
}

///|
/// String codecs use Unicode scalar words rather than platform byte layouts,
/// preserving exact text and values across a checked encode/decode round trip.
test "static string codecs preserve unicode and reject invalid scalars" {
  let set = StaticStringSet::from_keys(["MoonBit", "月亮", "🦀"]).unwrap()
  let decoded_set = decode_static_string_set_words(set.encode_words()).unwrap()
  assert_true(decoded_set.contains("MoonBit"))
  assert_true(decoded_set.contains("月亮"))
  assert_true(decoded_set.contains("🦀"))
  assert_true(!decoded_set.contains("moonbit"))

  let routes = StaticStringIntMap::from_entries([
    { key: "GET /健康", value: 200 },
    { key: "POST /用户", value: 201 },
    { key: "🦀", value: -7 },
  ]).unwrap()
  let decoded_routes = decode_static_string_int_map_words(routes.encode_words()).unwrap()
  assert_eq(decoded_routes.get("GET /健康"), Some(200))
  assert_eq(decoded_routes.get("🦀"), Some(-7))
  assert_eq(decoded_routes.get("DELETE /用户"), None)

  let malformed = set.encode_words()
  let first_string = 2 + malformed[1]
  malformed[first_string + 1] = 0xd800
  assert_true(decode_static_string_set_words(malformed) is Err(InvalidMetadata))
  assert_true(decode_static_string_int_map_words([14, 1, 1]) is Err(_))
}

///|
/// A multimap indexes distinct keys once while keeping every associated value
/// in source order, which is useful for immutable inverted indexes.
test "static multimap groups values and validates word ranges" {
  let index = StaticIntMultiMap::from_entries([
    { key: 8, value: 80 },
    { key: 3, value: 30 },
    { key: 8, value: 81 },
    { key: 3, value: 31 },
    { key: 9, value: 90 },
  ]).unwrap()
  assert_eq(index.len(), 3)
  assert_eq(index.value_count(), 5)
  assert_eq(index.get_all(3), [30, 31])
  assert_eq(index.get_all(8), [80, 81])
  assert_eq(index.get_all(4), [])
  assert_eq(index.value_count_for(9), 1)
  assert_eq(index.get_all_many([8, 7, 3]), [[80, 81], [], [30, 31]])
  assert_true(index.validate() is Ok(_))
  let decoded = decode_static_int_multimap_words(index.encode_words()).unwrap()
  assert_eq(decoded.get_all(3), [30, 31])
  let broken = index.encode_words()
  broken[broken.length() - 1] = 91
  assert_eq(decode_static_int_multimap_words(broken).unwrap().get_all(9), [91])
  assert_true(StaticIntMultiMap::from_entries([]) is Err(EmptyInput))
  assert_true(
    StaticIntMultiMap::from_entries([{ key: -1, value: 2 }])
    is Err(NegativeKey(-1)),
  )
}

///|
/// Residue sharding has one target shard per non-negative query and preserves
/// exact semantics after its nested checked representation is decoded.
test "sharded containers route and round trip" {
  let set = ShardedSet::from_keys([1, 2, 3, 6, 10, 14, 21], 4).unwrap()
  assert_true(set.contains(1))
  assert_true(set.contains(21))
  assert_true(!set.contains(22))
  assert_true(!set.contains(-1))
  assert_eq(set.stats().key_count, 7)
  assert_eq(set.stats().shard_count, 4)
  assert_true(set.validate() is Ok(_))
  let decoded_set = decode_sharded_set_words(set.encode_words()).unwrap()
  assert_true(decoded_set.contains(14))
  assert_true(!decoded_set.contains(15))

  let map = ShardedIntMap::from_entries(
    [
      { key: 1, value: 10 },
      { key: 2, value: 20 },
      { key: 6, value: 60 },
      { key: 14, value: 140 },
    ],
    4,
  ).unwrap()
  assert_eq(map.get(6), Some(60))
  assert_eq(map.get(7), None)
  assert_eq(map.stats().largest_shard, 3)
  assert_true(map.validate() is Ok(_))
  let decoded_map = decode_sharded_int_map_words(map.encode_words()).unwrap()
  assert_eq(decoded_map.get(14), Some(140))
  assert_true(ShardedSet::from_keys([1], 0) is Err(InvalidShardCount(0)))
  assert_true(
    ShardedIntMap::from_entries([{ key: -1, value: 0 }], 2)
    is Err(NegativeKey(-1)),
  )
}

///|
/// Map compaction must agree with layered newest-value lookup and retain its
/// behavior through the versioned layered-map encoding.
test "segmented maps compact and encode deterministically" {
  let layered = SegmentedIntMap::from_batches([
    [{ key: 1, value: 10 }, { key: 2, value: 20 }],
    [{ key: 2, value: 200 }, { key: 3, value: 30 }],
    [{ key: 1, value: 100 }],
  ]).unwrap()
  let compacted = layered.compact().unwrap()
  assert_eq(compacted.get(1), Some(100))
  assert_eq(compacted.get(2), Some(200))
  assert_eq(compacted.get(3), Some(30))
  assert_eq(compacted.len(), 3)
  let decoded = decode_segmented_int_map_words(layered.encode_words()).unwrap()
  assert_eq(decoded.get(1), Some(100))
  assert_eq(decoded.get(2), Some(200))
  assert_true(decode_segmented_int_map_words([9, 0]) is Err(InvalidMetadata))
}

///|
/// Patches make immutable rebuild intent explicit, while algebra methods
/// compare content rather than accidentally relying on one MPHF slot layout.
test "patches and algebra rebuild checked static snapshots" {
  let before = StaticSet::from_keys([1, 3, 5, 7]).unwrap()
  let patch = StaticSetPatch::new([9, 11], [3, 7]).unwrap()
  let after = before.apply_patch(patch).unwrap()
  assert_true(
    after.content_equals(StaticSet::from_keys([1, 5, 9, 11]).unwrap()),
  )
  assert_true(after.contains_all([1, 5, 9, 11]))
  assert_eq(after.filter_present([0, 1, 1, 9]), [1, 1, 9])
  assert_eq(after.filter_missing([0, 1, 1, 9]), [0])
  assert_eq(after.query_summary([0, 1, 9]).hit_count, 2)
  assert_true(before.overlaps(after))
  assert_true(
    before
    .intersection(after)
    .unwrap()
    .content_equals(StaticSet::from_keys([1, 5]).unwrap()),
  )
  assert_true(
    before
    .difference(after)
    .unwrap()
    .content_equals(StaticSet::from_keys([3, 7]).unwrap()),
  )
  assert_true(StaticSetPatch::new([1, 1], []) is Err(DuplicatePatchKey(1)))

  let base_map = StaticIntMap::from_entries([
    { key: 1, value: 10 },
    { key: 2, value: 20 },
  ]).unwrap()
  let map_patch = StaticIntMapPatch::new(
    [{ key: 2, value: 200 }, { key: 3, value: 30 }],
    [1],
  ).unwrap()
  let patched = base_map.apply_patch(map_patch).unwrap()
  assert_eq(patched.get_many([1, 2, 3, 4]), [None, Some(200), Some(30), None])
  assert_eq(patched.query_summary([1, 2, 3, 4]).miss_count, 2)
  assert_true(
    StaticIntMapPatch::new([{ key: 2, value: 1 }], [2])
    is Err(DuplicatePatchKey(2)),
  )
}

///|
/// Configurable construction stays bounded, and fingerprints are invariant to
/// different slot placement while observing key and value changes.
test "options validation and source fingerprints are meaningful" {
  let keys = [17, 29, 43, 71, 113, 127]
  let configured = Mphf::build_with_options(keys, {
    vertices_per_key_milli: 1500,
    max_attempts: 80,
    initial_seed: 44,
  }).unwrap()
  assert_true(configured.is_perfect_for(keys))
  assert_true(configured.validate() is Ok(_))
  assert_true(
    Mphf::build_with_options(keys, {
      vertices_per_key_milli: 1100,
      max_attempts: 2,
      initial_seed: 0,
    })
    is Err(InvalidBuildOption(1100)),
  )
  let left = StaticIntMap::from_entries([
    { key: 1, value: 10 },
    { key: 2, value: 20 },
  ]).unwrap()
  let equal = StaticIntMap::from_entries([
    { key: 2, value: 20 },
    { key: 1, value: 10 },
  ]).unwrap()
  let changed = StaticIntMap::from_entries([
    { key: 1, value: 10 },
    { key: 2, value: 21 },
  ]).unwrap()
  assert_eq(left.fingerprint().key_count, equal.fingerprint().key_count)
  assert_eq(
    left.fingerprint().key_fingerprint,
    equal.fingerprint().key_fingerprint,
  )
  assert_eq(
    left.fingerprint().value_fingerprint,
    equal.fingerprint().value_fingerprint,
  )
  assert_true(
    left.fingerprint().value_fingerprint !=
    changed.fingerprint().value_fingerprint,
  )
  assert_true(left.content_equals(equal))
  assert_true(!left.content_equals(changed))
  assert_true(left.validate() is Ok(_))
}

///|
/// Persistent cursors support checkpointing: consuming a successor must never
/// change a retained earlier cursor or expose mutable backing arrays.
test "persistent cursors scan slot ordered containers" {
  let set = StaticSet::from_keys([5, 11, 23]).unwrap()
  let first = set.cursor()
  let (first_item, after_first) = first.next()
  assert_true(first_item is Some(_))
  assert_eq(first.remaining(), 3)
  assert_eq(after_first.remaining(), 2)
  let (_, after_second) = after_first.next()
  assert_eq(after_second.remaining(), 1)
  assert_eq(after_second.collect_remaining().length(), 1)
  assert_true(set.cursor_at(4) is Err(InvalidRange(4, 3)))

  let map = StaticIntMap::from_entries([
    { key: 2, value: 20 },
    { key: 4, value: 40 },
  ]).unwrap()
  let (entry, map_after) = map.cursor().next()
  match entry {
    Some(value) => assert_eq(map.get(value.key), Some(value.value))
    None => fail("map cursor unexpectedly empty")
  }
  assert_eq(map_after.remaining(), 1)
  assert_eq(map.cursor_at(2).unwrap().remaining(), 0)

  let multi = StaticIntMultiMap::from_entries([
    { key: 1, value: 10 },
    { key: 1, value: 11 },
    { key: 3, value: 30 },
  ]).unwrap()
  let cursor = multi.cursor()
  assert_eq(cursor.remaining(), 3)
  let values = cursor.collect_remaining()
  assert_eq(values.length(), 3)
  assert_eq(values.filter(entry => entry.key == 1).length(), 2)
  assert_eq(multi.cursor().collect_remaining().length(), multi.value_count())
}

///|
/// Patches have a compact stable encoding and reject corrupted count fields or
/// semantic conflicts when decoded independently from a source snapshot.
test "patch codecs round trip and defend length fields" {
  let set_patch = StaticSetPatch::new([9, 3], [1, 7]).unwrap()
  let decoded_set_patch = decode_static_set_patch_words(
    set_patch.encode_words(),
  ).unwrap()
  assert_eq(decoded_set_patch.additions(), [3, 9])
  assert_eq(decoded_set_patch.removals(), [1, 7])
  let set = StaticSet::from_keys([1, 2, 7]).unwrap()
  assert_true(
    set
    .apply_patch(decoded_set_patch)
    .unwrap()
    .content_equals(StaticSet::from_keys([2, 3, 9]).unwrap()),
  )
  assert_true(decode_static_set_patch_words([10, 8, 1]) is Err(InvalidMetadata))

  let map_patch = StaticIntMapPatch::new(
    [{ key: 7, value: 70 }, { key: 2, value: 20 }],
    [4],
  ).unwrap()
  let decoded_map_patch = decode_static_int_map_patch_words(
    map_patch.encode_words(),
  ).unwrap()
  assert_eq(decoded_map_patch.upserts().length(), 2)
  assert_eq(decoded_map_patch.upserts()[0].key, 2)
  assert_eq(decoded_map_patch.removals(), [4])
  let map = StaticIntMap::from_entries([
    { key: 4, value: 40 },
    { key: 5, value: 50 },
  ]).unwrap()
  let rebuilt = map.apply_patch(decoded_map_patch).unwrap()
  assert_eq(rebuilt.get(4), None)
  assert_eq(rebuilt.get(5), Some(50))
  assert_eq(rebuilt.get(7), Some(70))
  assert_true(
    decode_static_int_map_patch_words([11, 9, 1]) is Err(InvalidMetadata),
  )
}

///|
/// A bimap owns two MPHFs but treats them as one artifact: decoding must reject
/// independently valid maps that fail the inverse-pair invariant.
test "bidirectional maps provide checked reverse lookup" {
  let index = StaticIntBiMap::from_entries([
    { key: 10, value: 100 },
    { key: 20, value: 200 },
    { key: 30, value: 300 },
  ]).unwrap()
  assert_eq(index.len(), 3)
  assert_eq(index.get_by_key(20), Some(200))
  assert_eq(index.get_by_value(300), Some(30))
  assert_eq(index.get_by_value(20), None)
  assert_true(index.contains_key(10))
  assert_true(index.contains_value(100))
  assert_true(index.validate() is Ok(_))
  let decoded = decode_static_int_bimap_words(index.encode_words()).unwrap()
  assert_eq(decoded.get_by_key(30), Some(300))
  assert_eq(decoded.get_by_value(100), Some(10))
  assert_true(
    StaticIntBiMap::from_entries([{ key: 1, value: 9 }, { key: 2, value: 9 }])
    is Err(DuplicateValue(9)),
  )
  assert_true(
    StaticIntBiMap::from_entries([{ key: 1, value: -9 }])
    is Err(NegativeKey(-9)),
  )
}

///|
/// Repartitioning and compaction retain content while changing only the build
/// layout, which is essential when data moves from ingestion to serving.
test "shard compaction and configurable containers preserve content" {
  let set = ShardedSet::from_keys([2, 3, 5, 7, 11, 13, 17], 3).unwrap()
  let resharded = set.reshard(5).unwrap()
  let compacted = resharded.compact().unwrap()
  assert_true(
    compacted.content_equals(
      StaticSet::from_keys([2, 3, 5, 7, 11, 13, 17]).unwrap(),
    ),
  )
  assert_eq(resharded.filter_missing([2, 4, 17, 19]), [4, 19])
  assert_eq(resharded.query_summary([2, 4, 17, 19]).hit_count, 2)

  let map = ShardedIntMap::from_entries(
    [{ key: 2, value: 20 }, { key: 7, value: 70 }, { key: 13, value: 130 }],
    2,
  ).unwrap()
  let remapped = map.reshard(5).unwrap()
  assert_eq(remapped.get_many([2, 7, 13, 99]), [
    Some(20),
    Some(70),
    Some(130),
    None,
  ])
  assert_true(
    remapped.compact().unwrap().content_equals(map.compact().unwrap()),
  )
  assert_eq(remapped.query_summary([2, 7, 99]).miss_count, 1)

  let options : MphfBuildOptions = {
    vertices_per_key_milli: 1600,
    max_attempts: 90,
    initial_seed: 9,
  }
  let tuned_set = StaticSet::from_keys_with_options(
    [4, 8, 15, 16, 23, 42],
    options,
  ).unwrap()
  let tuned_map = StaticIntMap::from_entries_with_options(
    [{ key: 4, value: 40 }, { key: 8, value: 80 }, { key: 15, value: 150 }],
    options,
  ).unwrap()
  assert_true(tuned_set.contains(42))
  assert_eq(tuned_map.get(15), Some(150))
  assert_true(
    StaticSet::from_keys_with_options([1, 2], {
      vertices_per_key_milli: 5000,
      max_attempts: 1,
      initial_seed: 0,
    })
    is Err(InvalidBuildOption(5000)),
  )
}

///|
/// This deterministic property corpus compares direct, sharded, encoded, and
/// compacted indexes over varied corpus sizes instead of testing one layout.
test "container variants agree across deterministic corpora" {
  for case_id in 1..<25 {
    let keys : Array[Int] = []
    let entries : Array[IntEntry] = []
    for offset in 0..<(case_id + 5) {
      let key = case_id * 50_021 + offset * (case_id * 7 + 3)
      keys.push(key)
      entries.push({ key, value: key + case_id })
    }
    let direct_set = StaticSet::from_keys(keys).unwrap()
    let direct_map = StaticIntMap::from_entries(entries).unwrap()
    let sharded_set = ShardedSet::from_keys(keys, case_id % 7 + 1).unwrap()
    let sharded_map = ShardedIntMap::from_entries(entries, case_id % 7 + 1).unwrap()
    let encoded_set = decode_sharded_set_words(sharded_set.encode_words()).unwrap()
    let encoded_map = decode_sharded_int_map_words(sharded_map.encode_words()).unwrap()
    for key in keys {
      assert_true(direct_set.contains(key))
      assert_true(sharded_set.contains(key))
      assert_true(encoded_set.contains(key))
      assert_eq(direct_map.get(key), Some(key + case_id))
      assert_eq(sharded_map.get(key), Some(key + case_id))
      assert_eq(encoded_map.get(key), Some(key + case_id))
    }
    let compacted_set = sharded_set.compact().unwrap()
    let compacted_map = sharded_map.compact().unwrap()
    assert_true(compacted_set.content_equals(direct_set))
    assert_true(compacted_map.content_equals(direct_map))
    let unknown = case_id * 50_021 - 1
    assert_true(!direct_set.contains(unknown))
    assert_eq(sharded_map.get(unknown), None)
  }
}

///|
/// Nested codecs must not accept a framing change that moves a valid payload
/// into a different shard or substitutes one side of a bidirectional index.
test "nested codecs reject semantic cross-payload corruption" {
  let set = ShardedSet::from_keys([1, 5, 9], 4).unwrap()
  let words = set.encode_words()
  assert_true(decode_sharded_set_words(words) is Ok(_))
  let malformed : Array[Int] = [7, 4, 0, 0, 0, 0]
  assert_true(decode_sharded_set_words(malformed) is Err(EmptyInput))

  let bimap = StaticIntBiMap::from_entries([
    { key: 1, value: 10 },
    { key: 2, value: 20 },
  ]).unwrap()
  let bimap_words = bimap.encode_words()
  assert_true(decode_static_int_bimap_words(bimap_words) is Ok(_))
  assert_true(decode_static_int_bimap_words([12, 100, 3]) is Err(_))
}

///|
/// Decoder framing uses subtraction-based remaining-length checks before every
/// untrusted addition, and multimap ranges must leave at least one value per
/// distinct source key.
test "decoders reject empty multimap ranges and extreme length fields" {
  let multi = StaticIntMultiMap::from_entries([
    { key: 4, value: 40 },
    { key: 9, value: 90 },
  ]).unwrap()
  let malformed_range = multi.encode_words()
  let mphf_length = malformed_range[1]
  let key_count = malformed_range[3]
  let offsets_start = 2 + mphf_length + key_count
  malformed_range[offsets_start + 1] = 0
  assert_true(
    decode_static_int_multimap_words(malformed_range) is Err(InvalidRange(0, 0)),
  )

  let maximum = 0x7fffffff
  assert_true(decode_mphf_words([1, 1, maximum, 0, 1]) is Err(InvalidMetadata))
  assert_true(decode_static_set_words([2, maximum]) is Err(InvalidMetadata))
  assert_true(decode_static_int_map_words([3, maximum]) is Err(InvalidMetadata))
  assert_true(
    decode_static_int_multimap_words([6, maximum]) is Err(InvalidMetadata),
  )
  assert_true(
    decode_static_int_bimap_words([12, maximum, 3]) is Err(InvalidMetadata),
  )
  assert_true(
    decode_segmented_set_words([4, 1, maximum]) is Err(InvalidMetadata),
  )
  assert_true(
    decode_segmented_int_map_words([9, 1, maximum]) is Err(InvalidMetadata),
  )
  assert_true(decode_sharded_set_words([7, 1, maximum]) is Err(InvalidMetadata))
  assert_true(
    decode_sharded_int_map_words([8, 1, maximum]) is Err(InvalidMetadata),
  )
  assert_true(
    decode_static_set_patch_words([10, 0, maximum]) is Err(InvalidMetadata),
  )
  assert_true(
    decode_static_int_map_patch_words([11, 0, maximum]) is Err(InvalidMetadata),
  )
}

///|
/// Every proper prefix of a valid nested artifact must fail decoding. This
/// exercises bounds checks at each framing layer rather than only one hand-made
/// malformed sample per codec.
test "all encoded artifact prefixes are rejected" {
  let set = StaticSet::from_keys([4, 9, 16, 25]).unwrap()
  let map = StaticIntMap::from_entries([
    { key: 4, value: 40 },
    { key: 9, value: 90 },
    { key: 16, value: 160 },
  ]).unwrap()
  let multi = StaticIntMultiMap::from_entries([
    { key: 4, value: 40 },
    { key: 4, value: 41 },
    { key: 9, value: 90 },
  ]).unwrap()
  let sharded_set = ShardedSet::from_keys([4, 9, 16, 25], 3).unwrap()
  let sharded_map = ShardedIntMap::from_entries(
    [{ key: 4, value: 40 }, { key: 9, value: 90 }, { key: 16, value: 160 }],
    3,
  ).unwrap()
  let bimap = StaticIntBiMap::from_entries([
    { key: 4, value: 40 },
    { key: 9, value: 90 },
  ]).unwrap()

  for length in 0..<set.encode_words().length() {
    let prefix : Array[Int] = []
    for index in 0..<length {
      prefix.push(set.encode_words()[index])
    }
    assert_true(decode_static_set_words(prefix) is Err(_))
  }
  for length in 0..<map.encode_words().length() {
    let prefix : Array[Int] = []
    for index in 0..<length {
      prefix.push(map.encode_words()[index])
    }
    assert_true(decode_static_int_map_words(prefix) is Err(_))
  }
  for length in 0..<multi.encode_words().length() {
    let prefix : Array[Int] = []
    for index in 0..<length {
      prefix.push(multi.encode_words()[index])
    }
    assert_true(decode_static_int_multimap_words(prefix) is Err(_))
  }
  for length in 0..<sharded_set.encode_words().length() {
    let prefix : Array[Int] = []
    for index in 0..<length {
      prefix.push(sharded_set.encode_words()[index])
    }
    assert_true(decode_sharded_set_words(prefix) is Err(_))
  }
  for length in 0..<sharded_map.encode_words().length() {
    let prefix : Array[Int] = []
    for index in 0..<length {
      prefix.push(sharded_map.encode_words()[index])
    }
    assert_true(decode_sharded_int_map_words(prefix) is Err(_))
  }
  for length in 0..<bimap.encode_words().length() {
    let prefix : Array[Int] = []
    for index in 0..<length {
      prefix.push(bimap.encode_words()[index])
    }
    assert_true(decode_static_int_bimap_words(prefix) is Err(_))
  }
}
