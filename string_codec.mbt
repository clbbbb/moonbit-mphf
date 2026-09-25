///|
/// Deterministically encode an exact static string set as Unicode scalar words.
/// Strings remain in MPHF slot order, so decoding can verify both the original
/// text and its stable-hash routing.
///
/// Format: `[13, mphf_word_count, mphf_words..., scalar_count, scalars..., ...]`.
pub fn StaticStringSet::encode_words(self : StaticStringSet) -> Array[Int] {
  let mphf_words = self.mphf.encode_words()
  let words : Array[Int] = [13, mphf_words.length()]
  words.append(mphf_words)
  append_slot_strings(words, self.keys_by_slot)
  words
}

///|
/// Decode a static string set, rejecting malformed Unicode scalars, trailing
/// words, duplicate routing, and any key whose hash no longer agrees with its
/// recorded MPHF slot.
pub fn decode_static_string_set_words(
  words : Array[Int],
) -> Result[StaticStringSet, MphfError] {
  let (mphf, cursor) = match decode_string_codec_header(words, 13) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (keys_by_slot, stop) = match
    decode_slot_strings(words, cursor, mphf.key_count) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if stop != words.length() {
    return Err(InvalidPayloadLength(stop, words.length()))
  }
  match validate_string_slot_keys(mphf, keys_by_slot) {
    Ok(_) => Ok({ mphf, keys_by_slot })
    Err(error) => Err(error)
  }
}

///|
/// Deterministically encode an exact string-to-integer map. Values follow the
/// scalar-encoded strings in the same MPHF slot order.
///
/// Format: `[14, mphf_word_count, mphf_words..., scalar_count, scalars..., values...]`.
pub fn StaticStringIntMap::encode_words(
  self : StaticStringIntMap,
) -> Array[Int] {
  let mphf_words = self.mphf.encode_words()
  let words : Array[Int] = [14, mphf_words.length()]
  words.append(mphf_words)
  append_slot_strings(words, self.keys_by_slot)
  words.append(self.values_by_slot)
  words
}

///|
/// Decode a static string map and validate scalar text, exact key routing, and
/// the final value-array length.
pub fn decode_static_string_int_map_words(
  words : Array[Int],
) -> Result[StaticStringIntMap, MphfError] {
  let (mphf, cursor) = match decode_string_codec_header(words, 14) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (keys_by_slot, value_start) = match
    decode_slot_strings(words, cursor, mphf.key_count) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if mphf.key_count > words.length() - value_start {
    return Err(InvalidMetadata)
  }
  if mphf.key_count != words.length() - value_start {
    return Err(
      InvalidPayloadLength(value_start + mphf.key_count, words.length()),
    )
  }
  let values_by_slot : Array[Int] = []
  for index in value_start..<words.length() {
    values_by_slot.push(words[index])
  }
  match validate_string_slot_keys(mphf, keys_by_slot) {
    Ok(_) => Ok({ mphf, keys_by_slot, values_by_slot })
    Err(error) => Err(error)
  }
}

///|
/// Append each source string as a scalar count followed by Unicode scalar
/// values. `String::to_array` gives scalar characters rather than UTF-8 bytes,
/// keeping the representation stable across MoonBit backends.
fn append_slot_strings(words : Array[Int], keys : Array[String]) -> Unit {
  for key in keys {
    let characters = key.to_array()
    words.push(characters.length())
    for character in characters {
      words.push(character.to_int())
    }
  }
}

///|
/// Parse the common versioned MPHF prefix after proving its declared length is
/// available, so an untrusted length cannot overflow cursor arithmetic.
fn decode_string_codec_header(
  words : Array[Int],
  version : Int,
) -> Result[(Mphf, Int), MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != version {
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
  Ok((mphf, 2 + mphf_length))
}

///|
/// Decode exactly one scalar-encoded string for each known MPHF slot.
fn decode_slot_strings(
  words : Array[Int],
  start : Int,
  key_count : Int,
) -> Result[(Array[String], Int), MphfError] {
  let keys : Array[String] = []
  let mut cursor = start
  for _ in 0..<key_count {
    if cursor >= words.length() {
      return Err(InvalidPayloadLength(cursor + 1, words.length()))
    }
    let scalar_count = words[cursor]
    cursor += 1
    if scalar_count < 0 || scalar_count > words.length() - cursor {
      return Err(InvalidMetadata)
    }
    let characters : Array[Char] = []
    for index in cursor..<(cursor + scalar_count) {
      let scalar = words[index]
      if !is_unicode_scalar(scalar) {
        return Err(InvalidMetadata)
      }
      characters.push(scalar.unsafe_to_char())
    }
    keys.push(String::from_iter(characters.iter()))
    cursor += scalar_count
  }
  Ok((keys, cursor))
}

///|
/// Reject negative values, values above Unicode's scalar limit, and surrogate
/// code points, which cannot occur in `String::to_array` output.
fn is_unicode_scalar(value : Int) -> Bool {
  value >= 0 && value <= 0x10ffff && !(value >= 0xd800 && value <= 0xdfff)
}

///|
/// Check that every decoded string is routed by its stable hash to its own
/// slot. This also rules out duplicate strings and stable-hash collisions.
fn validate_string_slot_keys(
  mphf : Mphf,
  keys_by_slot : Array[String],
) -> Result[Unit, MphfError] {
  if keys_by_slot.length() != mphf.key_count {
    return Err(InvalidPayloadLength(mphf.key_count, keys_by_slot.length()))
  }
  for slot in 0..<keys_by_slot.length() {
    let key = keys_by_slot[slot]
    if mphf.slot_of_hash(stable_string_hash(key)) != Some(slot) {
      return Err(InvalidMetadata)
    }
  }
  Ok(())
}
