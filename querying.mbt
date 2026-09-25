///|
/// Test whether every supplied key belongs to this exact static set. An empty
/// query succeeds, which makes this useful for validating optional filters.
pub fn StaticSet::contains_all(self : StaticSet, keys : Array[Int]) -> Bool {
  for key in keys {
    if !self.contains(key) {
      return false
    }
  }
  true
}

///|
/// Return all input keys that are present, preserving query order and repeated
/// probes. This is deliberately different from set algebra.
pub fn StaticSet::filter_present(
  self : StaticSet,
  keys : Array[Int],
) -> Array[Int] {
  let present : Array[Int] = []
  for key in keys {
    if self.contains(key) {
      present.push(key)
    }
  }
  present
}

///|
/// Return all input keys absent from this set, preserving query order.
pub fn StaticSet::filter_missing(
  self : StaticSet,
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
/// Count exact hit and miss outcomes for a batch of set probes.
pub fn StaticSet::query_summary(
  self : StaticSet,
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
/// Probe many map keys at once. Result positions correspond exactly to query
/// positions; misses are represented by `None`.
pub fn StaticIntMap::get_many(
  self : StaticIntMap,
  keys : Array[Int],
) -> Array[Int?] {
  let values : Array[Int?] = []
  for key in keys {
    values.push(self.get(key))
  }
  values
}

///|
/// Count exact hit and miss outcomes for a batch of map probes.
pub fn StaticIntMap::query_summary(
  self : StaticIntMap,
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
/// Probe many multimap keys at once. Each returned sub-array is independent,
/// so callers can safely mutate their own result without touching the index.
pub fn StaticIntMultiMap::get_all_many(
  self : StaticIntMultiMap,
  keys : Array[Int],
) -> Array[Array[Int]] {
  let values : Array[Array[Int]] = []
  for key in keys {
    values.push(self.get_all(key))
  }
  values
}

///|
/// Validate the internal dimensions and vertex ranges of a decoded MPHF. This
/// does not establish source membership because an MPHF intentionally stores
/// no source-key manifest.
pub fn Mphf::validate(self : Mphf) -> Result[Unit, MphfError] {
  if self.key_count <= 0 ||
    self.vertex_count < 3 ||
    self.seed < 0 ||
    self.attempts <= 0 ||
    self.values.length() != self.vertex_count {
    return Err(InvalidMetadata)
  }
  for value in self.values {
    if value < 0 || value >= self.key_count {
      return Err(InvalidVertexValue(value))
    }
  }
  Ok(())
}

///|
/// Verify every retained source key routes to its recorded set slot.
pub fn StaticSet::validate(self : StaticSet) -> Result[Unit, MphfError] {
  match self.mphf.validate() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  validate_slot_keys(self.mphf, self.keys_by_slot)
}

///|
/// Verify every retained source key routes to its recorded map slot and that
/// the key/value arrays have matching cardinality.
pub fn StaticIntMap::validate(self : StaticIntMap) -> Result[Unit, MphfError] {
  if self.values_by_slot.length() != self.keys_by_slot.length() {
    return Err(
      InvalidPayloadLength(
        self.keys_by_slot.length(),
        self.values_by_slot.length(),
      ),
    )
  }
  match self.mphf.validate() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  validate_slot_keys(self.mphf, self.keys_by_slot)
}

///|
/// Verify a multimap's MPHF slots and its contiguous value ranges.
pub fn StaticIntMultiMap::validate(
  self : StaticIntMultiMap,
) -> Result[Unit, MphfError] {
  match self.mphf.validate() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match validate_slot_keys(self.mphf, self.keys_by_slot) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  validate_offsets(
    self.offsets_by_slot,
    self.values.length(),
    self.keys_by_slot.length(),
  )
}

///|
/// Compute a reproducible source-manifest fingerprint for a set. The result is
/// intended for accidental-artifact mismatch detection, not cryptographic use.
pub fn StaticSet::fingerprint(self : StaticSet) -> StaticIndexFingerprint {
  let keys = self.keys_by_slot.copy()
  keys.sort()
  {
    key_count: keys.length(),
    key_fingerprint: fingerprint_keys(keys),
    value_fingerprint: 0,
  }
}

///|
/// Compute a reproducible source-manifest fingerprint for a map. Entries are
/// normalized by key, so its value is independent of MPHF slot placement.
pub fn StaticIntMap::fingerprint(self : StaticIntMap) -> StaticIndexFingerprint {
  let entries = self.entries_by_slot()
  entries.sort_by((left, right) => left.key.compare(right.key))
  let keys : Array[Int] = []
  let values : Array[Int] = []
  for entry in entries {
    keys.push(entry.key)
    values.push(entry.value)
  }
  {
    key_count: keys.length(),
    key_fingerprint: fingerprint_keys(keys),
    value_fingerprint: fingerprint_values(values),
  }
}

///|
/// Fold sorted source keys with an index-sensitive deterministic mixer.
fn fingerprint_keys(keys : Array[Int]) -> Int {
  let mut state = 0x2911
  for index in 0..<keys.length() {
    state = mix_hash(state ^ keys[index], index + 0x61c8)
  }
  state
}

///|
/// Fold map values independently so a key-only match cannot hide a value edit.
fn fingerprint_values(values : Array[Int]) -> Int {
  let mut state = 0x2d3f
  for index in 0..<values.length() {
    state = mix_hash(state ^ values[index], index + 0x5f37)
  }
  state
}
