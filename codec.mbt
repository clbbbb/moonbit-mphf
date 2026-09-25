///| Deterministically encode an MPHF as integer words.

///|
/// Format: `[1, key_count, vertex_count, seed, attempts, g...]`.
pub fn Mphf::encode_words(self : Mphf) -> Array[Int] {
  let words : Array[Int] = [
    1,
    self.key_count,
    self.vertex_count,
    self.seed,
    self.attempts,
  ]
  words.append(self.values)
  words
}

///|
/// Decode a versioned MPHF word representation with structural validation.
pub fn decode_mphf_words(words : Array[Int]) -> Result[Mphf, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 1 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 5 {
    return Err(InvalidPayloadLength(5, words.length()))
  }
  let key_count = words[1]
  let vertex_count = words[2]
  let seed = words[3]
  let attempts = words[4]
  if key_count <= 0 || vertex_count < 3 || seed < 0 || attempts <= 0 {
    return Err(InvalidMetadata)
  }
  if vertex_count > words.length() - 5 {
    return Err(InvalidMetadata)
  }
  let expected = 5 + vertex_count
  if words.length() != expected {
    return Err(InvalidPayloadLength(expected, words.length()))
  }
  let values : Array[Int] = []
  for index in 5..<words.length() {
    let value = words[index]
    if value < 0 || value >= key_count {
      return Err(InvalidVertexValue(value))
    }
    values.push(value)
  }
  Ok({ key_count, vertex_count, seed, attempts, values })
}

///| Deterministically encode an exact static set.

///|
/// Format: `[2, mphf_word_count, mphf_words..., slot_ordered_keys...]`.
pub fn StaticSet::encode_words(self : StaticSet) -> Array[Int] {
  let mphf_words = self.mphf.encode_words()
  let words : Array[Int] = [2, mphf_words.length()]
  words.append(mphf_words)
  words.append(self.keys_by_slot)
  words
}

///|
/// Decode an exact static set and verify every stored key agrees with its slot.
pub fn decode_static_set_words(
  words : Array[Int],
) -> Result[StaticSet, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 2 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 2 {
    return Err(InvalidPayloadLength(2, words.length()))
  }
  let mphf_length = words[1]
  if mphf_length <= 0 || mphf_length > words.length() - 2 {
    return Err(InvalidMetadata)
  }
  let mphf_words : Array[Int] = []
  for index in 2..<(2 + mphf_length) {
    mphf_words.push(words[index])
  }
  let mphf = match decode_mphf_words(mphf_words) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if mphf.key_count > words.length() - 2 - mphf_length {
    return Err(InvalidMetadata)
  }
  let expected = 2 + mphf_length + mphf.key_count
  if words.length() != expected {
    return Err(InvalidPayloadLength(expected, words.length()))
  }
  let keys_by_slot : Array[Int] = []
  for index in (2 + mphf_length)..<words.length() {
    keys_by_slot.push(words[index])
  }
  match validate_slot_keys(mphf, keys_by_slot) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok({ mphf, keys_by_slot })
}

///| Deterministically encode an exact integer map.

///|
/// Format: `[3, mphf_word_count, mphf_words..., keys..., values...]`.
pub fn StaticIntMap::encode_words(self : StaticIntMap) -> Array[Int] {
  let mphf_words = self.mphf.encode_words()
  let words : Array[Int] = [3, mphf_words.length()]
  words.append(mphf_words)
  words.append(self.keys_by_slot)
  words.append(self.values_by_slot)
  words
}

///|
/// Decode an exact integer map and retain the validated MPHF slot layout.
pub fn decode_static_int_map_words(
  words : Array[Int],
) -> Result[StaticIntMap, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 3 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 2 {
    return Err(InvalidPayloadLength(2, words.length()))
  }
  let mphf_length = words[1]
  if mphf_length <= 0 || mphf_length > words.length() - 2 {
    return Err(InvalidMetadata)
  }
  let mphf_words : Array[Int] = []
  for index in 2..<(2 + mphf_length) {
    mphf_words.push(words[index])
  }
  let mphf = match decode_mphf_words(mphf_words) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let remaining = words.length() - 2 - mphf_length
  if mphf.key_count > remaining / 2 {
    return Err(InvalidMetadata)
  }
  let expected = 2 + mphf_length + mphf.key_count * 2
  if words.length() != expected {
    return Err(InvalidPayloadLength(expected, words.length()))
  }
  let keys_by_slot : Array[Int] = []
  let values_by_slot : Array[Int] = []
  let keys_end = 2 + mphf_length + mphf.key_count
  for index in (2 + mphf_length)..<keys_end {
    keys_by_slot.push(words[index])
  }
  for index in keys_end..<words.length() {
    values_by_slot.push(words[index])
  }
  match validate_slot_keys(mphf, keys_by_slot) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok({ mphf, keys_by_slot, values_by_slot })
}

///|
/// Validate that encoded slot keys are a permutation of one accepted key set.
fn validate_slot_keys(
  mphf : Mphf,
  keys_by_slot : Array[Int],
) -> Result[Unit, MphfError] {
  if keys_by_slot.length() != mphf.key_count {
    return Err(InvalidPayloadLength(mphf.key_count, keys_by_slot.length()))
  }
  let ordered = keys_by_slot.copy()
  ordered.sort()
  for index in 0..<keys_by_slot.length() {
    let key = keys_by_slot[index]
    if key < 0 {
      return Err(NegativeKey(key))
    }
    if mphf.slot_of_hash(key) != Some(index) {
      return Err(InvalidMetadata)
    }
    if index > 0 && ordered[index - 1] == ordered[index] {
      return Err(DuplicateKey(ordered[index]))
    }
  }
  Ok(())
}
