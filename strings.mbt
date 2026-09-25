///|
/// Pair a source string with its stable pre-hash during construction.
priv struct StringHash {
  key : String
  hash : Int
}

///| Build an exact static string set. Duplicate source strings and distinct

///|
/// strings that collide in the 31-bit stable hash are both rejected, rather
/// than silently constructing an ambiguous table.
pub fn StaticStringSet::from_keys(
  keys : Array[String],
) -> Result[StaticStringSet, MphfError] {
  let hashes = match unique_string_hashes(keys) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mphf = match Mphf::build(hashes) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let keys_by_slot = Array::make(keys.length(), "")
  for key in keys {
    let slot = mphf.slot_of_hash(stable_string_hash(key)).unwrap()
    keys_by_slot[slot] = key
  }
  Ok({ mphf, keys_by_slot })
}

///| Test exact string membership; a stable-hash collision is ruled out by the

///|
/// slot-resident source string comparison.
pub fn StaticStringSet::contains(self : StaticStringSet, key : String) -> Bool {
  match self.mphf.slot_of_hash(stable_string_hash(key)) {
    Some(slot) => self.keys_by_slot[slot] == key
    None => false
  }
}

///|
/// Return the number of source strings in this immutable set.
pub fn StaticStringSet::len(self : StaticStringSet) -> Int {
  self.keys_by_slot.length()
}

///|
/// Return construction details for observability.
pub fn StaticStringSet::stats(self : StaticStringSet) -> MphfStats {
  self.mphf.stats()
}

///|
/// Build a checked immutable string-to-integer map.
pub fn StaticStringIntMap::from_entries(
  entries : Array[StringIntEntry],
) -> Result[StaticStringIntMap, MphfError] {
  let source_keys : Array[String] = []
  for entry in entries {
    source_keys.push(entry.key)
  }
  let hashes = match unique_string_hashes(source_keys) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let mphf = match Mphf::build(hashes) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let keys_by_slot = Array::make(entries.length(), "")
  let values_by_slot = Array::make(entries.length(), 0)
  for entry in entries {
    let slot = mphf.slot_of_hash(stable_string_hash(entry.key)).unwrap()
    keys_by_slot[slot] = entry.key
    values_by_slot[slot] = entry.value
  }
  Ok({ mphf, keys_by_slot, values_by_slot })
}

///|
/// Retrieve a value only when both the MPHF slot and original string match.
pub fn StaticStringIntMap::get(self : StaticStringIntMap, key : String) -> Int? {
  match self.mphf.slot_of_hash(stable_string_hash(key)) {
    Some(slot) if self.keys_by_slot[slot] == key =>
      Some(self.values_by_slot[slot])
    _ => None
  }
}

///|
/// Test exact membership without exposing a value.
pub fn StaticStringIntMap::contains_key(
  self : StaticStringIntMap,
  key : String,
) -> Bool {
  self.get(key) is Some(_)
}

///|
/// Count entries in this immutable map.
pub fn StaticStringIntMap::len(self : StaticStringIntMap) -> Int {
  self.keys_by_slot.length()
}

///| Sort hashes and reject both duplicate strings and distinct hash collisions

///|
/// before the integer MPHF builder sees its input.
fn unique_string_hashes(keys : Array[String]) -> Result[Array[Int], MphfError] {
  if keys.length() == 0 {
    return Err(EmptyInput)
  }
  let pairs : Array[StringHash] = []
  for key in keys {
    pairs.push({ key, hash: stable_string_hash(key) })
  }
  pairs.sort_by((left, right) => left.hash.compare(right.hash))
  for index in 1..<pairs.length() {
    let previous = pairs[index - 1]
    let current = pairs[index]
    if previous.hash == current.hash {
      if previous.key == current.key {
        return Err(DuplicateStringKey(current.key))
      }
      return Err(HashCollision(previous.key, current.key))
    }
  }
  let hashes : Array[Int] = []
  for pair in pairs {
    hashes.push(pair.hash)
  }
  Ok(hashes)
}
