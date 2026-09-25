///|
/// Construct a validated set edit plan. Additions and removals are each
/// deduplicated by rejection, and a key cannot belong to both sides.
pub fn StaticSetPatch::new(
  additions : Array[Int],
  removals : Array[Int],
) -> Result[StaticSetPatch, MphfError] {
  let sorted_additions = match sorted_patch_keys(additions) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let sorted_removals = match sorted_patch_keys(removals) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for key in sorted_additions {
    if sorted_contains(sorted_removals, key) {
      return Err(DuplicatePatchKey(key))
    }
  }
  Ok({ additions: sorted_additions, removals: sorted_removals })
}

///|
/// Return the number of inserted keys recorded by this patch.
pub fn StaticSetPatch::addition_count(self : StaticSetPatch) -> Int {
  self.additions.length()
}

///|
/// Return the number of deleted keys recorded by this patch.
pub fn StaticSetPatch::removal_count(self : StaticSetPatch) -> Int {
  self.removals.length()
}

///|
/// Rebuild a static set after applying this edit plan. Removing an absent key
/// and adding an existing key are intentionally idempotent operations.
pub fn StaticSet::apply_patch(
  self : StaticSet,
  patch : StaticSetPatch,
) -> Result[StaticSet, MphfError] {
  let target : Array[Int] = []
  for key in self.keys_by_slot {
    if !sorted_contains(patch.removals, key) {
      target.push(key)
    }
  }
  for key in patch.additions {
    if !self.contains(key) {
      target.push(key)
    }
  }
  target.sort()
  if target.length() == 0 {
    return Err(EmptyInput)
  }
  StaticSet::from_keys(target)
}

///|
/// Construct a validated map edit plan. Upserts replace values by key, while
/// removals delete keys; an ambiguous key on both sides is rejected.
pub fn StaticIntMapPatch::new(
  upserts : Array[IntEntry],
  removals : Array[Int],
) -> Result[StaticIntMapPatch, MphfError] {
  if upserts.length() == 0 && removals.length() == 0 {
    return Err(EmptyInput)
  }
  let ordered_upserts = upserts.copy()
  ordered_upserts.sort_by((left, right) => left.key.compare(right.key))
  for index in 0..<ordered_upserts.length() {
    let entry = ordered_upserts[index]
    if entry.key < 0 {
      return Err(NegativeKey(entry.key))
    }
    if index > 0 && ordered_upserts[index - 1].key == entry.key {
      return Err(DuplicatePatchKey(entry.key))
    }
  }
  let sorted_removals = match sorted_patch_keys(removals) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  for entry in ordered_upserts {
    if sorted_contains(sorted_removals, entry.key) {
      return Err(DuplicatePatchKey(entry.key))
    }
  }
  Ok({ upserts: ordered_upserts, removals: sorted_removals })
}

///|
/// Return the number of upserts recorded by this patch.
pub fn StaticIntMapPatch::upsert_count(self : StaticIntMapPatch) -> Int {
  self.upserts.length()
}

///|
/// Return the number of removals recorded by this patch.
pub fn StaticIntMapPatch::removal_count(self : StaticIntMapPatch) -> Int {
  self.removals.length()
}

///|
/// Rebuild a map after applying deletions and replacement/insert operations.
/// Existing values are retained only for keys absent from both patch parts.
pub fn StaticIntMap::apply_patch(
  self : StaticIntMap,
  patch : StaticIntMapPatch,
) -> Result[StaticIntMap, MphfError] {
  let target : Array[IntEntry] = []
  for entry in self.entries_by_slot() {
    if !sorted_contains(patch.removals, entry.key) &&
      !contains_upsert(patch.upserts, entry.key) {
      target.push(entry)
    }
  }
  target.append(patch.upserts)
  if target.length() == 0 {
    return Err(EmptyInput)
  }
  StaticIntMap::from_entries(target)
}

///|
/// Return a sorted defensive copy of a patch's added keys.
pub fn StaticSetPatch::additions(self : StaticSetPatch) -> Array[Int] {
  self.additions.copy()
}

///|
/// Return a sorted defensive copy of a patch's removed keys.
pub fn StaticSetPatch::removals(self : StaticSetPatch) -> Array[Int] {
  self.removals.copy()
}

///|
/// Return sorted defensive copies of map upserts in key order.
pub fn StaticIntMapPatch::upserts(self : StaticIntMapPatch) -> Array[IntEntry] {
  self.upserts.copy()
}

///|
/// Return a sorted defensive copy of map removals.
pub fn StaticIntMapPatch::removals(self : StaticIntMapPatch) -> Array[Int] {
  self.removals.copy()
}

///|
/// Validate non-negative, distinct edit keys and preserve a sorted copy for
/// linear-time downstream membership checks.
fn sorted_patch_keys(keys : Array[Int]) -> Result[Array[Int], MphfError] {
  let ordered = keys.copy()
  ordered.sort()
  for index in 0..<ordered.length() {
    if ordered[index] < 0 {
      return Err(NegativeKey(ordered[index]))
    }
    if index > 0 && ordered[index - 1] == ordered[index] {
      return Err(DuplicatePatchKey(ordered[index]))
    }
  }
  Ok(ordered)
}

///|
/// Binary-search one integer in a sorted patch key array.
fn sorted_contains(keys : Array[Int], wanted : Int) -> Bool {
  let mut low = 0
  let mut high = keys.length()
  while low < high {
    let middle = low + (high - low) / 2
    if keys[middle] < wanted {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low < keys.length() && keys[low] == wanted
}

///|
/// Binary-search an upsert array whose constructor guarantees key ordering.
fn contains_upsert(upserts : Array[IntEntry], wanted : Int) -> Bool {
  let mut low = 0
  let mut high = upserts.length()
  while low < high {
    let middle = low + (high - low) / 2
    if upserts[middle].key < wanted {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low < upserts.length() && upserts[low].key == wanted
}
