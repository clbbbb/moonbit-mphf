///|
/// Build a checked immutable one-to-one map. Both source keys and values must
/// be non-negative because each becomes an MPHF key in one direction.
pub fn StaticIntBiMap::from_entries(
  entries : Array[IntEntry],
) -> Result[StaticIntBiMap, MphfError] {
  if entries.length() == 0 {
    return Err(EmptyInput)
  }
  let reverse_entries : Array[IntEntry] = []
  let values : Array[Int] = []
  for entry in entries {
    if entry.value < 0 {
      return Err(NegativeKey(entry.value))
    }
    reverse_entries.push({ key: entry.value, value: entry.key })
    values.push(entry.value)
  }
  values.sort()
  for index in 1..<values.length() {
    if values[index - 1] == values[index] {
      return Err(DuplicateValue(values[index]))
    }
  }
  let forward = match StaticIntMap::from_entries(entries) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let reverse = match StaticIntMap::from_entries(reverse_entries) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ forward, reverse })
}

///|
/// Look up the unique value associated with one source key.
pub fn StaticIntBiMap::get_by_key(self : StaticIntBiMap, key : Int) -> Int? {
  self.forward.get(key)
}

///|
/// Look up the unique source key associated with one value.
pub fn StaticIntBiMap::get_by_value(self : StaticIntBiMap, value : Int) -> Int? {
  self.reverse.get(value)
}

///|
/// Test whether a source key exists.
pub fn StaticIntBiMap::contains_key(self : StaticIntBiMap, key : Int) -> Bool {
  self.forward.contains_key(key)
}

///|
/// Test whether a mapped value exists.
pub fn StaticIntBiMap::contains_value(
  self : StaticIntBiMap,
  value : Int,
) -> Bool {
  self.reverse.contains_key(value)
}

///|
/// Return the number of one-to-one pairs.
pub fn StaticIntBiMap::len(self : StaticIntBiMap) -> Int {
  self.forward.len()
}

///|
/// Return source pairs in deterministic forward-slot order.
pub fn StaticIntBiMap::entries_by_key(self : StaticIntBiMap) -> Array[IntEntry] {
  self.forward.entries_by_slot()
}

///|
/// Verify both maps are individually valid and mutually inverse. This catches
/// a cross-payload substitution that ordinary nested map decoding cannot see.
pub fn StaticIntBiMap::validate(
  self : StaticIntBiMap,
) -> Result[Unit, MphfError] {
  if self.forward.len() != self.reverse.len() {
    return Err(InvalidMetadata)
  }
  match self.forward.validate() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match self.reverse.validate() {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  for entry in self.forward.entries_by_slot() {
    if self.reverse.get(entry.value) != Some(entry.key) {
      return Err(InvalidMetadata)
    }
  }
  for entry in self.reverse.entries_by_slot() {
    if self.forward.get(entry.value) != Some(entry.key) {
      return Err(InvalidMetadata)
    }
  }
  Ok(())
}

///|
/// Return forward construction diagnostics. Reverse diagnostics can differ
/// because values produce a different hypergraph, so callers can inspect the
/// reverse map explicitly through its validated serialized form.
pub fn StaticIntBiMap::stats(self : StaticIntBiMap) -> MphfStats {
  self.forward.stats()
}

///|
/// Encode a bidirectional map as two independently checked static map blobs.
///
/// Format: `[12, forward_word_count, forward_words..., reverse_words...]`.
pub fn StaticIntBiMap::encode_words(self : StaticIntBiMap) -> Array[Int] {
  let forward_words = self.forward.encode_words()
  let reverse_words = self.reverse.encode_words()
  let words : Array[Int] = [12, forward_words.length()]
  words.append(forward_words)
  words.append(reverse_words)
  words
}

///|
/// Decode a bidirectional map and verify that the two nested payloads describe
/// inverse mappings, not merely two individually valid static maps.
pub fn decode_static_int_bimap_words(
  words : Array[Int],
) -> Result[StaticIntBiMap, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 12 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 3 || words[1] <= 0 {
    return Err(InvalidMetadata)
  }
  let forward_length = words[1]
  if forward_length > words.length() - 3 {
    return Err(InvalidMetadata)
  }
  let reverse_start = 2 + forward_length
  if reverse_start >= words.length() {
    return Err(InvalidPayloadLength(reverse_start + 1, words.length()))
  }
  let forward_words = bimap_word_slice(words, 2, reverse_start)
  let reverse_words = bimap_word_slice(words, reverse_start, words.length())
  let forward = match decode_static_int_map_words(forward_words) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let reverse = match decode_static_int_map_words(reverse_words) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let bimap = { forward, reverse }
  match bimap.validate() {
    Ok(_) => Ok(bimap)
    Err(error) => Err(error)
  }
}

///|
/// Copy one nested map payload while validating the outer framing separately.
fn bimap_word_slice(words : Array[Int], start : Int, stop : Int) -> Array[Int] {
  let result : Array[Int] = []
  for index in start..<stop {
    result.push(words[index])
  }
  result
}
