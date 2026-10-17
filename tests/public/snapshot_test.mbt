///|
test "map inputs exports and decoder buffers cannot change snapshots" {
  let input : Array[@mphf.IntEntry] = [{ key: 7, value: 70, }]
  let map = @mphf.StaticIntMap::from_entries(input).unwrap()
  input[0] = { key: 7, value: 999, }
  let entries = map.entries_by_slot()
  entries[0] = { key: 7, value: 999, }
  let keys = map.keys_by_slot()
  keys[0] = 999
  let words = map.encode_words()
  let loaded = @mphf.decode_static_int_map_words(words).unwrap()
  words[words.length() - 1] = 999
  assert_eq(map.get(7), Some(70))
  assert_eq(loaded.get(7), Some(70))
  assert_eq(map.get(999), None)
}

///|
test "retained set and map checkpoints replay the same entries" {
  let map = @mphf.StaticIntMap::from_entries([
    { key: 7, value: 70, },
    { key: 13, value: 130, },
  ]).unwrap()
  let checkpoint = map.cursor()
  let original = checkpoint.collect_remaining()
  let (item, successor) = checkpoint.next()
  let (_, branch) = successor.next()
  let exported = checkpoint.collect_remaining()
  exported[0] = { key: 999, value: 999, }
  assert_eq(checkpoint.remaining(), 2)
  assert_eq(successor.remaining(), 1)
  assert_eq(branch.remaining(), 0)
  let replay = checkpoint.collect_remaining()
  for index in 0..<original.length() {
    assert_eq(replay[index].key, original[index].key)
    assert_eq(replay[index].value, original[index].value)
  }
  match item {
    Some(entry) => assert_eq(map.get(entry.key), Some(entry.value))
    None => fail("missing checkpoint entry")
  }
  let set = @mphf.StaticSet::from_keys([7, 13]).unwrap()
  let start = set.cursor()
  let expected = start.collect_remaining()
  let (_, after) = start.next()
  let copy = after.collect_remaining()
  copy[0] = 999
  assert_eq(start.collect_remaining(), expected)
  assert_eq(set.len(), 2)
  assert_eq(set.contains(999), false)
}

///|
test "multimap checkpoints and returned groups are independent" {
  let multi = @mphf.StaticIntMultiMap::from_entries([
    { key: 7, value: 70, },
    { key: 7, value: 71, },
    { key: 13, value: 130, },
  ]).unwrap()
  let checkpoint = multi.cursor()
  let original = checkpoint.collect_remaining()
  let (_, successor) = checkpoint.next()
  let groups = multi.get_all(7)
  groups[0] = 999
  let exported = successor.collect_remaining()
  exported[0] = { key: 999, value: 999, }
  let replay = checkpoint.collect_remaining()
  for index in 0..<original.length() {
    assert_eq(replay[index].key, original[index].key)
    assert_eq(replay[index].value, original[index].value)
  }
  assert_eq(checkpoint.remaining(), 3)
  assert_eq(successor.remaining(), 2)
  assert_eq(multi.get_all(7), [70, 71])
}

///|
test "nested segment and shard snapshots isolate source and exported arrays" {
  let entries : Array[@mphf.IntEntry] = [{ key: 7, value: 70, }]
  let batches = [entries]
  let segmented = @mphf.SegmentedIntMap::from_batches(batches).unwrap()
  let sharded = @mphf.ShardedIntMap::from_entries(entries, 4).unwrap()
  let bimap = @mphf.StaticIntBiMap::from_entries(entries).unwrap()
  entries[0] = { key: 7, value: 999, }
  batches[0] = [{ key: 999, value: 999, }]
  let exported = sharded.entries()
  exported[0] = { key: 999, value: 999, }
  let inverse_entries = bimap.entries_by_key()
  inverse_entries[0] = { key: 999, value: 999, }
  let words = segmented.encode_words()
  let loaded = @mphf.decode_segmented_int_map_words(words).unwrap()
  words[words.length() - 1] = 999
  assert_eq(segmented.get(7), Some(70))
  assert_eq(loaded.get(7), Some(70))
  assert_eq(sharded.get(7), Some(70))
  assert_eq(bimap.get_by_value(70), Some(7))
  let keys = [7, 13]
  let set = @mphf.SegmentedSet::from_batches([keys]).unwrap()
  let shards = @mphf.ShardedSet::from_keys(keys, 4).unwrap()
  keys[0] = 999
  let exported_keys = shards.keys()
  exported_keys[0] = 999
  assert_eq(set.contains(7), true)
  assert_eq(shards.contains(7), true)
  assert_eq(shards.contains(999), false)
}

///|
test "string snapshots and patch plans isolate caller owned arrays" {
  let strings : Array[@mphf.StringIntEntry] = [{ key: "token", value: 70, }]
  let map = @mphf.StaticStringIntMap::from_entries(strings).unwrap()
  strings[0] = { key: "token", value: 999, }
  let words = map.encode_words()
  let loaded = @mphf.decode_static_string_int_map_words(words).unwrap()
  words[words.length() - 1] = 999
  assert_eq(map.get("token"), Some(70))
  assert_eq(loaded.get("token"), Some(70))
  let keys = ["token"]
  let set = @mphf.StaticStringSet::from_keys(keys).unwrap()
  keys[0] = "changed"
  assert_eq(set.contains("token"), true)
  assert_eq(set.contains("changed"), false)
  let upserts : Array[@mphf.IntEntry] = [{ key: 7, value: 70, }]
  let removals = [13]
  let patch = @mphf.StaticIntMapPatch::new(upserts, removals).unwrap()
  upserts[0] = { key: 7, value: 999, }
  removals[0] = 7
  let copy = patch.upserts()
  copy[0] = { key: 7, value: 999, }
  let removed = patch.removals()
  removed[0] = 7
  let source = @mphf.StaticIntMap::from_entries([
    { key: 7, value: 1, },
    { key: 13, value: 130, },
  ]).unwrap()
  let after = source.apply_patch(patch).unwrap()
  assert_eq(after.get(7), Some(70))
  assert_eq(after.get(13), None)
  assert_eq(source.get(7), Some(1))
  let additions = [7]
  let set_patch = @mphf.StaticSetPatch::new(additions, [13]).unwrap()
  additions[0] = 999
  let added_copy = set_patch.additions()
  added_copy[0] = 999
  let set_source = @mphf.StaticSet::from_keys([13]).unwrap()
  let patched_set = set_source.apply_patch(set_patch).unwrap()
  assert_eq(patched_set.contains(7), true)
  assert_eq(patched_set.contains(999), false)
  assert_eq(set_source.contains(13), true)
}

///|
test "multimap remaining counts cross every group boundary and exhaustion" {
  let entries : Array[@mphf.IntMultiEntry] = []
  for key in 0..<200 {
    for offset in 0..<(key % 5 + 1) {
      entries.push({ key, value: key * 10 + offset, })
    }
  }
  let index = @mphf.StaticIntMultiMap::from_entries(entries).unwrap()
  let start = index.cursor()
  let mut cursor = start
  let mut count = 0
  let seen = Array::make(200, 0)
  while cursor.remaining() > 0 {
    assert_eq(cursor.remaining(), entries.length() - count)
    let (item, successor) = cursor.next()
    let entry = item.unwrap()
    assert_eq(entry.value, entry.key * 10 + seen[entry.key])
    seen[entry.key] += 1
    count += 1
    cursor = successor
  }
  for key in 0..<200 {
    assert_eq(seen[key], key % 5 + 1)
  }
  let (empty, exhausted) = cursor.next()
  assert_true(empty is None)
  assert_eq(exhausted.remaining(), 0)
  assert_eq(exhausted.collect_remaining().length(), 0)
  assert_eq(start.collect_remaining().length(), entries.length())
}

///|
test "perfect slots and exact maps agree with source keys at integer boundaries" {
  // The size-256 residue shards exhausted the old default 64-seed budget.
  for size in [1, 2, 3, 31, 256, 1024] {
    let keys : Array[Int] = []
    let entries : Array[@mphf.IntEntry] = []
    for index in 0..<size {
      let key = if index == 0 {
        0
      } else if index == 1 {
        0x7fffffff
      } else {
        (index - 1) * 1000003
      }
      keys.push(key)
      entries.push({ key, value: -key, })
    }
    let source = @mphf.Mphf::build(keys).unwrap()
    let mphf = @mphf.decode_mphf_words(source.encode_words()).unwrap()
    let occupied = Array::make(size, false)
    for key in keys {
      let slot = mphf.slot_of_hash(key).unwrap()
      assert_true(slot >= 0 && slot < size)
      assert_eq(occupied[slot], false)
      occupied[slot] = true
    }
    let direct = match @mphf.StaticIntMap::from_entries(entries) {
      Ok(value) => value
      Err(_) => fail("direct map failed for size " + size.to_string())
    }
    let loaded = match
      @mphf.decode_static_int_map_words(direct.encode_words()) {
      Ok(value) => value
      Err(_) => fail("decoded map failed for size " + size.to_string())
    }
    let sharded = match @mphf.ShardedIntMap::from_entries(entries, 7) {
      Ok(value) => value
      Err(@mphf.ConstructionFailed(attempts)) =>
        fail(
          "sharded construction exhausted " +
          attempts.to_string() +
          " attempts for size " +
          size.to_string(),
        )
      Err(_) => fail("sharded map failed for size " + size.to_string())
    }
    for key in keys {
      assert_eq(direct.get(key), Some(-key))
      assert_eq(loaded.get(key), Some(-key))
      assert_eq(sharded.get(key), Some(-key))
    }
    for unknown in [-1, 1, 2147483646] {
      assert_eq(direct.get(unknown), None)
      assert_eq(loaded.get(unknown), None)
      assert_eq(sharded.get(unknown), None)
    }
  }
}
