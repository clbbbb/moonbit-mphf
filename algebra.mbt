///|
/// Rebuild the exact union of two static sets. The output has one MPHF, which
/// is generally cheaper to query than retaining two independent segments.
pub fn StaticSet::union(
  self : StaticSet,
  other : StaticSet,
) -> Result[StaticSet, MphfError] {
  let keys = self.keys_by_slot()
  keys.append(other.keys_by_slot())
  keys.sort()
  keys.dedup()
  StaticSet::from_keys(keys)
}

///|
/// Rebuild keys common to both static sets. An empty intersection returns
/// `EmptyInput`, because an MPHF has no valid zero-key representation.
pub fn StaticSet::intersection(
  self : StaticSet,
  other : StaticSet,
) -> Result[StaticSet, MphfError] {
  let keys : Array[Int] = []
  for key in self.keys_by_slot {
    if other.contains(key) {
      keys.push(key)
    }
  }
  if keys.length() == 0 {
    return Err(EmptyInput)
  }
  StaticSet::from_keys(keys)
}

///|
/// Rebuild keys owned by `self` but absent from `other`.
pub fn StaticSet::difference(
  self : StaticSet,
  other : StaticSet,
) -> Result[StaticSet, MphfError] {
  let keys : Array[Int] = []
  for key in self.keys_by_slot {
    if !other.contains(key) {
      keys.push(key)
    }
  }
  if keys.length() == 0 {
    return Err(EmptyInput)
  }
  StaticSet::from_keys(keys)
}

///|
/// Rebuild keys appearing in exactly one source set.
pub fn StaticSet::symmetric_difference(
  self : StaticSet,
  other : StaticSet,
) -> Result[StaticSet, MphfError] {
  let keys : Array[Int] = []
  for key in self.keys_by_slot {
    if !other.contains(key) {
      keys.push(key)
    }
  }
  for key in other.keys_by_slot {
    if !self.contains(key) {
      keys.push(key)
    }
  }
  if keys.length() == 0 {
    return Err(EmptyInput)
  }
  StaticSet::from_keys(keys)
}

///|
/// Return whether at least one key belongs to both exact static sets.
pub fn StaticSet::overlaps(self : StaticSet, other : StaticSet) -> Bool {
  let (smaller, larger) = if self.len() <= other.len() {
    (self, other)
  } else {
    (other, self)
  }
  for key in smaller.keys_by_slot {
    if larger.contains(key) {
      return true
    }
  }
  false
}

///|
/// Return whether every key in `self` is also present in `other`.
pub fn StaticSet::is_subset_of(self : StaticSet, other : StaticSet) -> Bool {
  if self.len() > other.len() {
    return false
  }
  other.contains_all(self.keys_by_slot())
}

///|
/// Return all map keys in deterministic MPHF slot order.
pub fn StaticIntMap::keys_by_slot(self : StaticIntMap) -> Array[Int] {
  self.keys_by_slot.copy()
}

///|
/// Merge two maps into a new static map. Values in `other` take precedence for
/// equal keys; this is the one-segment equivalent of a two-layer map lookup.
pub fn StaticIntMap::merge_prefer_right(
  self : StaticIntMap,
  other : StaticIntMap,
) -> Result[StaticIntMap, MphfError] {
  let entries : Array[IntEntry] = []
  for entry in self.entries_by_slot() {
    if !other.contains_key(entry.key) {
      entries.push(entry)
    }
  }
  entries.append(other.entries_by_slot())
  StaticIntMap::from_entries(entries)
}

///|
/// Return whether both maps contain the same key/value pairs, independent of
/// the different MPHF layouts they may have selected during construction.
pub fn StaticIntMap::content_equals(
  self : StaticIntMap,
  other : StaticIntMap,
) -> Bool {
  if self.len() != other.len() {
    return false
  }
  for entry in self.entries_by_slot() {
    if other.get(entry.key) != Some(entry.value) {
      return false
    }
  }
  true
}

///|
/// Compare set contents without observing construction seeds or slot order.
pub fn StaticSet::content_equals(self : StaticSet, other : StaticSet) -> Bool {
  self.len() == other.len() && self.is_subset_of(other)
}
