///|
/// Build a static set split into a fixed number of residue shards. Each key is
/// routed by `key % shard_count`, so exact lookup constructs no temporary key
/// and probes exactly one underlying MPHF.
pub fn ShardedSet::from_keys(
  keys : Array[Int],
  shard_count : Int,
) -> Result[ShardedSet, MphfError] {
  match validate_shard_count(shard_count) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if keys.length() == 0 {
    return Err(EmptyInput)
  }
  let batches = int_key_batches(keys, shard_count)
  let shards : Array[StaticSet?] = []
  for batch in batches {
    if batch.length() == 0 {
      shards.push(None)
    } else {
      let set = match StaticSet::from_keys(batch) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      shards.push(Some(set))
    }
  }
  Ok({ shard_count, shards })
}

///|
/// Test exact membership by routing a key to one shard. Negative keys are
/// rejected as probes rather than being allowed to index with a negative value.
pub fn ShardedSet::contains(self : ShardedSet, key : Int) -> Bool {
  if key < 0 {
    return false
  }
  match self.shards[key % self.shard_count] {
    Some(shard) => shard.contains(key)
    None => false
  }
}

///|
/// Return a copy of every key in deterministic shard then slot order.
pub fn ShardedSet::keys(self : ShardedSet) -> Array[Int] {
  let keys : Array[Int] = []
  for shard in self.shards {
    match shard {
      Some(value) => keys.append(value.keys_by_slot())
      None => ()
    }
  }
  keys
}

///|
/// Return balance statistics. Empty shards are intentionally included in the
/// minimum so callers can see whether their chosen shard count is excessive.
pub fn ShardedSet::stats(self : ShardedSet) -> ShardStats {
  shard_stats_for_sets(self.shards, self.shard_count)
}

///|
/// Rebuild all shards into one exact static set. This is useful when an
/// ingestion-time sharding policy is no longer needed by a read-mostly client.
pub fn ShardedSet::compact(self : ShardedSet) -> Result[StaticSet, MphfError] {
  StaticSet::from_keys(self.keys())
}

///|
/// Repartition this immutable set under a different residue-shard count.
pub fn ShardedSet::reshard(
  self : ShardedSet,
  shard_count : Int,
) -> Result[ShardedSet, MphfError] {
  ShardedSet::from_keys(self.keys(), shard_count)
}

///|
/// Return all query keys that are not present in their corresponding shard.
pub fn ShardedSet::filter_missing(
  self : ShardedSet,
  keys : Array[Int],
) -> Array[Int] {
  let missing : Array[Int] = []
  for key in keys {
    if !self.contains(key) {
      missing.push(key)
    }
  }
  missing
}

///|
/// Count exact hit and miss outcomes over a sharded set query batch.
pub fn ShardedSet::query_summary(
  self : ShardedSet,
  keys : Array[Int],
) -> LookupSummary {
  let mut hits = 0
  for key in keys {
    if self.contains(key) {
      hits += 1
    }
  }
  {
    query_count: keys.length(),
    hit_count: hits,
    miss_count: keys.length() - hits,
  }
}

///|
/// Verify every present set shard is structurally valid and that every stored
/// key belongs to its recorded residue class. This is useful after receiving a
/// sharded index through a transport other than `decode_sharded_set_words`.
pub fn ShardedSet::validate(self : ShardedSet) -> Result[Unit, MphfError] {
  match validate_shard_count(self.shard_count) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if self.shards.length() != self.shard_count {
    return Err(InvalidPayloadLength(self.shard_count, self.shards.length()))
  }
  let mut key_count = 0
  for index in 0..<self.shards.length() {
    match self.shards[index] {
      None => ()
      Some(shard) => {
        match shard.validate() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        for key in shard.keys_by_slot() {
          if key % self.shard_count != index {
            return Err(InvalidMetadata)
          }
        }
        key_count += shard.len()
      }
    }
  }
  if key_count == 0 {
    return Err(EmptyInput)
  }
  Ok(())
}

///|
/// Build a fixed-count sharded map. Duplicate keys are rejected in their own
/// residue shard, which is equivalent to rejecting them globally.
pub fn ShardedIntMap::from_entries(
  entries : Array[IntEntry],
  shard_count : Int,
) -> Result[ShardedIntMap, MphfError] {
  match validate_shard_count(shard_count) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if entries.length() == 0 {
    return Err(EmptyInput)
  }
  let batches = int_entry_batches(entries, shard_count)
  let shards : Array[StaticIntMap?] = []
  for batch in batches {
    if batch.length() == 0 {
      shards.push(None)
    } else {
      let map = match StaticIntMap::from_entries(batch) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      shards.push(Some(map))
    }
  }
  Ok({ shard_count, shards })
}

///|
/// Retrieve an exact key from its only possible shard.
pub fn ShardedIntMap::get(self : ShardedIntMap, key : Int) -> Int? {
  if key < 0 {
    return None
  }
  match self.shards[key % self.shard_count] {
    Some(shard) => shard.get(key)
    None => None
  }
}

///|
/// Test exact key membership without allocating a result value.
pub fn ShardedIntMap::contains_key(self : ShardedIntMap, key : Int) -> Bool {
  self.get(key) is Some(_)
}

///|
/// Return all pairs in deterministic shard then slot order.
pub fn ShardedIntMap::entries(self : ShardedIntMap) -> Array[IntEntry] {
  let entries : Array[IntEntry] = []
  for shard in self.shards {
    match shard {
      Some(value) => entries.append(value.entries_by_slot())
      None => ()
    }
  }
  entries
}

///|
/// Return the distribution of entries across map shards.
pub fn ShardedIntMap::stats(self : ShardedIntMap) -> ShardStats {
  let mut total = 0
  let mut smallest = -1
  let mut largest = 0
  for shard in self.shards {
    let count = match shard {
      Some(value) => value.len()
      None => 0
    }
    total += count
    if smallest < 0 || count < smallest {
      smallest = count
    }
    if count > largest {
      largest = count
    }
  }
  {
    shard_count: self.shard_count,
    key_count: total,
    smallest_shard: smallest,
    largest_shard: largest,
  }
}

///|
/// Rebuild all map shards into one exact static map without changing pairs.
pub fn ShardedIntMap::compact(
  self : ShardedIntMap,
) -> Result[StaticIntMap, MphfError] {
  StaticIntMap::from_entries(self.entries())
}

///|
/// Repartition an immutable map under a different residue-shard count.
pub fn ShardedIntMap::reshard(
  self : ShardedIntMap,
  shard_count : Int,
) -> Result[ShardedIntMap, MphfError] {
  ShardedIntMap::from_entries(self.entries(), shard_count)
}

///|
/// Probe many map keys at once while preserving query order.
pub fn ShardedIntMap::get_many(
  self : ShardedIntMap,
  keys : Array[Int],
) -> Array[Int?] {
  let values : Array[Int?] = []
  for key in keys {
    values.push(self.get(key))
  }
  values
}

///|
/// Count hits and misses in a sharded map query batch.
pub fn ShardedIntMap::query_summary(
  self : ShardedIntMap,
  keys : Array[Int],
) -> LookupSummary {
  let mut hits = 0
  for key in keys {
    if self.contains_key(key) {
      hits += 1
    }
  }
  {
    query_count: keys.length(),
    hit_count: hits,
    miss_count: keys.length() - hits,
  }
}

///|
/// Verify every present map shard and its residue routing. Map values are
/// unconstrained; only exact keys participate in the sharding rule.
pub fn ShardedIntMap::validate(self : ShardedIntMap) -> Result[Unit, MphfError] {
  match validate_shard_count(self.shard_count) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  if self.shards.length() != self.shard_count {
    return Err(InvalidPayloadLength(self.shard_count, self.shards.length()))
  }
  let mut key_count = 0
  for index in 0..<self.shards.length() {
    match self.shards[index] {
      None => ()
      Some(shard) => {
        match shard.validate() {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        for entry in shard.entries_by_slot() {
          if entry.key % self.shard_count != index {
            return Err(InvalidMetadata)
          }
        }
        key_count += shard.len()
      }
    }
  }
  if key_count == 0 {
    return Err(EmptyInput)
  }
  Ok(())
}

///|
/// Deterministically encode a sharded set. Empty residue classes have a zero
/// payload, which keeps the requested shard count visible after decoding.
///
/// Format: `[7, shard_count, word_count, set_words..., ...]`.
pub fn ShardedSet::encode_words(self : ShardedSet) -> Array[Int] {
  let words : Array[Int] = [7, self.shard_count]
  for shard in self.shards {
    match shard {
      None => words.push(0)
      Some(value) => {
        let payload = value.encode_words()
        words.push(payload.length())
        words.append(payload)
      }
    }
  }
  words
}

///|
/// Decode a sharded set and verify every stored key belongs to the residue
/// class that contains it.
pub fn decode_sharded_set_words(
  words : Array[Int],
) -> Result[ShardedSet, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 7 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 2 {
    return Err(InvalidPayloadLength(2, words.length()))
  }
  let shard_count = words[1]
  match validate_shard_count(shard_count) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let shards : Array[StaticSet?] = []
  let mut key_count = 0
  let mut cursor = 2
  for shard_index in 0..<shard_count {
    if cursor >= words.length() {
      return Err(InvalidPayloadLength(cursor + 1, words.length()))
    }
    let length = words[cursor]
    cursor += 1
    if length == 0 {
      shards.push(None)
    } else {
      if length < 0 || length > words.length() - cursor {
        return Err(InvalidMetadata)
      }
      let payload = word_slice(words, cursor, cursor + length)
      let shard = match decode_static_set_words(payload) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      for key in shard.keys_by_slot() {
        if key % shard_count != shard_index {
          return Err(InvalidMetadata)
        }
      }
      key_count += shard.len()
      shards.push(Some(shard))
      cursor += length
    }
  }
  if cursor != words.length() {
    return Err(InvalidPayloadLength(cursor, words.length()))
  }
  if key_count == 0 {
    return Err(EmptyInput)
  }
  Ok({ shard_count, shards })
}

///|
/// Deterministically encode a sharded map with the same empty-shard rule used
/// by `ShardedSet`.
///
/// Format: `[8, shard_count, word_count, map_words..., ...]`.
pub fn ShardedIntMap::encode_words(self : ShardedIntMap) -> Array[Int] {
  let words : Array[Int] = [8, self.shard_count]
  for shard in self.shards {
    match shard {
      None => words.push(0)
      Some(value) => {
        let payload = value.encode_words()
        words.push(payload.length())
        words.append(payload)
      }
    }
  }
  words
}

///|
/// Decode a sharded map and confirm its keys live in their recorded shards.
pub fn decode_sharded_int_map_words(
  words : Array[Int],
) -> Result[ShardedIntMap, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 8 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 2 {
    return Err(InvalidPayloadLength(2, words.length()))
  }
  let shard_count = words[1]
  match validate_shard_count(shard_count) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let shards : Array[StaticIntMap?] = []
  let mut key_count = 0
  let mut cursor = 2
  for shard_index in 0..<shard_count {
    if cursor >= words.length() {
      return Err(InvalidPayloadLength(cursor + 1, words.length()))
    }
    let length = words[cursor]
    cursor += 1
    if length == 0 {
      shards.push(None)
    } else {
      if length < 0 || length > words.length() - cursor {
        return Err(InvalidMetadata)
      }
      let payload = word_slice(words, cursor, cursor + length)
      let shard = match decode_static_int_map_words(payload) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      for entry in shard.entries_by_slot() {
        if entry.key % shard_count != shard_index {
          return Err(InvalidMetadata)
        }
      }
      key_count += shard.len()
      shards.push(Some(shard))
      cursor += length
    }
  }
  if cursor != words.length() {
    return Err(InvalidPayloadLength(cursor, words.length()))
  }
  if key_count == 0 {
    return Err(EmptyInput)
  }
  Ok({ shard_count, shards })
}

///|
/// Validate the deliberately bounded number of partitions. A very large count
/// mostly creates empty MPHFs and is an accidental memory-footgun.
fn validate_shard_count(shard_count : Int) -> Result[Unit, MphfError] {
  if shard_count <= 0 || shard_count > 65_536 {
    return Err(InvalidShardCount(shard_count))
  }
  Ok(())
}

///|
/// Partition source keys after validating their routing boundary.
fn int_key_batches(keys : Array[Int], shard_count : Int) -> Array[Array[Int]] {
  let batches : Array[Array[Int]] = []
  for _ in 0..<shard_count {
    batches.push([])
  }
  for key in keys {
    if key < 0 {
      // Let the public constructor surface the conventional error through its
      // first non-empty static set rather than indexing with a negative value.
      // It is still safe here because this branch cannot route the key.
      return [keys]
    }
    batches[key % shard_count].push(key)
  }
  batches
}

///|
/// Partition map entries while preserving their source order within a shard.
fn int_entry_batches(
  entries : Array[IntEntry],
  shard_count : Int,
) -> Array[Array[IntEntry]] {
  let batches : Array[Array[IntEntry]] = []
  for _ in 0..<shard_count {
    batches.push([])
  }
  for entry in entries {
    if entry.key < 0 {
      return [entries]
    }
    batches[entry.key % shard_count].push(entry)
  }
  batches
}

///|
/// Copy a word range while keeping malformed indexing localized in decoders.
fn word_slice(words : Array[Int], start : Int, stop : Int) -> Array[Int] {
  let result : Array[Int] = []
  for index in start..<stop {
    result.push(words[index])
  }
  result
}

///|
/// Compute set shard statistics without exposing the optional shard array.
fn shard_stats_for_sets(
  shards : Array[StaticSet?],
  shard_count : Int,
) -> ShardStats {
  let mut total = 0
  let mut smallest = -1
  let mut largest = 0
  for shard in shards {
    let count = match shard {
      Some(value) => value.len()
      None => 0
    }
    total += count
    if smallest < 0 || count < smallest {
      smallest = count
    }
    if count > largest {
      largest = count
    }
  }
  {
    shard_count,
    key_count: total,
    smallest_shard: smallest,
    largest_shard: largest,
  }
}
