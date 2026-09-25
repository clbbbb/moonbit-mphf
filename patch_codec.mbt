///|
/// Encode a validated set patch in sorted key order.
///
/// Format: `[10, addition_count, additions..., removal_count, removals...]`.
pub fn StaticSetPatch::encode_words(self : StaticSetPatch) -> Array[Int] {
  let words : Array[Int] = [10, self.additions.length()]
  words.append(self.additions)
  words.push(self.removals.length())
  words.append(self.removals)
  words
}

///|
/// Decode a set patch using the same duplicate and overlap checks as direct
/// construction. This makes patches safe to store beside a static snapshot.
pub fn decode_static_set_patch_words(
  words : Array[Int],
) -> Result[StaticSetPatch, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 10 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 3 || words[1] < 0 {
    return Err(InvalidMetadata)
  }
  let addition_count = words[1]
  if addition_count > words.length() - 3 {
    return Err(InvalidMetadata)
  }
  let removal_count_position = 2 + addition_count
  if removal_count_position >= words.length() {
    return Err(InvalidPayloadLength(removal_count_position + 1, words.length()))
  }
  let removal_count = words[removal_count_position]
  if removal_count < 0 {
    return Err(InvalidMetadata)
  }
  if removal_count > words.length() - removal_count_position - 1 {
    return Err(InvalidMetadata)
  }
  let expected = removal_count_position + 1 + removal_count
  if words.length() != expected {
    return Err(InvalidPayloadLength(expected, words.length()))
  }
  let additions = patch_word_slice(words, 2, removal_count_position)
  let removals = patch_word_slice(words, removal_count_position + 1, expected)
  StaticSetPatch::new(additions, removals)
}

///|
/// Encode a validated map patch. Upserts are stored in ascending key order so
/// the byte-for-byte word representation is independent of caller order.
///
/// Format: `[11, upsert_count, key, value..., removal_count, removals...]`.
pub fn StaticIntMapPatch::encode_words(self : StaticIntMapPatch) -> Array[Int] {
  let words : Array[Int] = [11, self.upserts.length()]
  for entry in self.upserts {
    words.push(entry.key)
    words.push(entry.value)
  }
  words.push(self.removals.length())
  words.append(self.removals)
  words
}

///|
/// Decode a map patch, rejecting inconsistent declared lengths before any
/// source map is rebuilt.
pub fn decode_static_int_map_patch_words(
  words : Array[Int],
) -> Result[StaticIntMapPatch, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 11 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 3 || words[1] < 0 {
    return Err(InvalidMetadata)
  }
  let upsert_count = words[1]
  if upsert_count > (words.length() - 3) / 2 {
    return Err(InvalidMetadata)
  }
  let removal_count_position = 2 + upsert_count * 2
  if removal_count_position >= words.length() {
    return Err(InvalidPayloadLength(removal_count_position + 1, words.length()))
  }
  let removal_count = words[removal_count_position]
  if removal_count < 0 {
    return Err(InvalidMetadata)
  }
  if removal_count > words.length() - removal_count_position - 1 {
    return Err(InvalidMetadata)
  }
  let expected = removal_count_position + 1 + removal_count
  if words.length() != expected {
    return Err(InvalidPayloadLength(expected, words.length()))
  }
  let upserts : Array[IntEntry] = []
  let mut cursor = 2
  for _ in 0..<upsert_count {
    upserts.push({ key: words[cursor], value: words[cursor + 1] })
    cursor += 2
  }
  let removals = patch_word_slice(words, removal_count_position + 1, expected)
  StaticIntMapPatch::new(upserts, removals)
}

///|
/// Copy a checked patch payload range into a standalone public input array.
fn patch_word_slice(words : Array[Int], start : Int, stop : Int) -> Array[Int] {
  let result : Array[Int] = []
  for index in start..<stop {
    result.push(words[index])
  }
  result
}
