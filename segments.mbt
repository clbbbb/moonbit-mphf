///|
/// Build a set index from non-empty immutable key batches.
pub fn SegmentedSet::from_batches(
  batches : Array[Array[Int]],
) -> Result[SegmentedSet, MphfError] {
  if batches.length() == 0 {
    return Err(EmptyInput)
  }
  let segments : Array[StaticSet] = []
  for index in 0..<batches.length() {
    let batch = batches[index]
    if batch.length() == 0 {
      return Err(EmptySegment(index))
    }
    let segment = match StaticSet::from_keys(batch) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    segments.push(segment)
  }
  Ok({ segments, })
}

///|
/// Test exact membership in any segment.
pub fn SegmentedSet::contains(self : SegmentedSet, key : Int) -> Bool {
  for segment in self.segments {
    if segment.contains(key) {
      return true
    }
  }
  false
}

///|
/// Return inputs that do not belong to any segment, preserving input order.
pub fn SegmentedSet::missing(
  self : SegmentedSet,
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

///| Count segments and the stored key total. Keys may intentionally overlap

///|
/// across immutable batches, so this is not a distinct-key cardinality.
pub fn SegmentedSet::stats(self : SegmentedSet) -> SegmentStats {
  let mut count = 0
  for segment in self.segments {
    count += segment.len()
  }
  { segment_count: self.segments.length(), key_count: count }
}

///|
/// Merge all segments into one exact set, eliminating duplicate keys.
pub fn SegmentedSet::compact(
  self : SegmentedSet,
) -> Result[StaticSet, MphfError] {
  let keys : Array[Int] = []
  for segment in self.segments {
    keys.append(segment.keys_by_slot())
  }
  keys.sort()
  keys.dedup()
  StaticSet::from_keys(keys)
}

///| Encode a segmented set as a sequence of independently validated set blobs.

///|
/// Format: `[4, segment_count, word_count, set_words..., ...]`.
pub fn SegmentedSet::encode_words(self : SegmentedSet) -> Array[Int] {
  let words : Array[Int] = [4, self.segments.length()]
  for segment in self.segments {
    let segment_words = segment.encode_words()
    words.push(segment_words.length())
    words.append(segment_words)
  }
  words
}

///|
/// Decode a segmented set, rejecting trailing words and empty segments.
pub fn decode_segmented_set_words(
  words : Array[Int],
) -> Result[SegmentedSet, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 4 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 2 || words[1] <= 0 {
    return Err(InvalidMetadata)
  }
  let count = words[1]
  let segments : Array[StaticSet] = []
  let mut cursor = 2
  for index in 0..<count {
    if cursor >= words.length() {
      return Err(InvalidPayloadLength(cursor + 1, words.length()))
    }
    let length = words[cursor]
    cursor += 1
    if length <= 0 || length > words.length() - cursor {
      return Err(InvalidMetadata)
    }
    let payload : Array[Int] = []
    for payload_index in cursor..<(cursor + length) {
      payload.push(words[payload_index])
    }
    let segment = match decode_static_set_words(payload) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if segment.len() == 0 {
      return Err(EmptySegment(index))
    }
    segments.push(segment)
    cursor += length
  }
  if cursor != words.length() {
    return Err(InvalidPayloadLength(cursor, words.length()))
  }
  Ok({ segments, })
}

///| Build a layered immutable map from non-empty batches. Later batches have

///|
/// lookup precedence, supporting append-only configuration or data revisions.
pub fn SegmentedIntMap::from_batches(
  batches : Array[Array[IntEntry]],
) -> Result[SegmentedIntMap, MphfError] {
  if batches.length() == 0 {
    return Err(EmptyInput)
  }
  let segments : Array[StaticIntMap] = []
  for index in 0..<batches.length() {
    let batch = batches[index]
    if batch.length() == 0 {
      return Err(EmptySegment(index))
    }
    let segment = match StaticIntMap::from_entries(batch) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    segments.push(segment)
  }
  Ok({ segments, })
}

///| Look up a key from newest to oldest segment; later values override earlier

///|
/// values without mutating previously published segments.
pub fn SegmentedIntMap::get(self : SegmentedIntMap, key : Int) -> Int? {
  let mut index = self.segments.length()
  while index > 0 {
    index -= 1
    match self.segments[index].get(key) {
      Some(value) => return Some(value)
      None => ()
    }
  }
  None
}

///|
/// Return segment and stored-entry totals for a layered map.
pub fn SegmentedIntMap::stats(self : SegmentedIntMap) -> SegmentStats {
  let mut count = 0
  for segment in self.segments {
    count += segment.len()
  }
  { segment_count: self.segments.length(), key_count: count }
}

///|
/// Return a one-segment map that preserves the newest value of every key.
/// Compaction is deterministic: ties are resolved by later source segment,
/// exactly as `get` resolves them before compaction.
pub fn SegmentedIntMap::compact(
  self : SegmentedIntMap,
) -> Result[StaticIntMap, MphfError] {
  let layered : Array[LayeredEntry] = []
  for segment_index in 0..<self.segments.length() {
    let entries = self.segments[segment_index].entries_by_slot()
    for entry in entries {
      layered.push({ key: entry.key, value: entry.value, segment_index })
    }
  }
  layered.sort_by((left, right) => {
    let key_order = left.key.compare(right.key)
    if key_order == 0 {
      left.segment_index.compare(right.segment_index)
    } else {
      key_order
    }
  })
  let retained : Array[IntEntry] = []
  let mut index = 0
  while index < layered.length() {
    let mut final_entry = layered[index]
    index += 1
    while index < layered.length() && layered[index].key == final_entry.key {
      final_entry = layered[index]
      index += 1
    }
    retained.push({ key: final_entry.key, value: final_entry.value })
  }
  StaticIntMap::from_entries(retained)
}

///|
/// Encode a layered map as independently checked map blobs.
///
/// Format: `[9, segment_count, word_count, map_words..., ...]`.
pub fn SegmentedIntMap::encode_words(self : SegmentedIntMap) -> Array[Int] {
  let words : Array[Int] = [9, self.segments.length()]
  for segment in self.segments {
    let payload = segment.encode_words()
    words.push(payload.length())
    words.append(payload)
  }
  words
}

///|
/// Decode a layered map while rejecting empty segments and trailing words.
pub fn decode_segmented_int_map_words(
  words : Array[Int],
) -> Result[SegmentedIntMap, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 9 {
    return Err(UnsupportedVersion(words[0]))
  }
  if words.length() < 2 || words[1] <= 0 {
    return Err(InvalidMetadata)
  }
  let count = words[1]
  let segments : Array[StaticIntMap] = []
  let mut cursor = 2
  for index in 0..<count {
    if cursor >= words.length() {
      return Err(InvalidPayloadLength(cursor + 1, words.length()))
    }
    let length = words[cursor]
    cursor += 1
    if length <= 0 || length > words.length() - cursor {
      return Err(InvalidMetadata)
    }
    let payload = segmented_word_slice(words, cursor, cursor + length)
    let segment = match decode_static_int_map_words(payload) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if segment.len() == 0 {
      return Err(EmptySegment(index))
    }
    segments.push(segment)
    cursor += length
  }
  if cursor != words.length() {
    return Err(InvalidPayloadLength(cursor, words.length()))
  }
  Ok({ segments, })
}

///|
/// One source pair and the precedence used during layered compaction.
priv struct LayeredEntry {
  key : Int
  value : Int
  segment_index : Int
}

///|
/// Copy a decoder payload without exposing array slicing in the public API.
fn segmented_word_slice(
  words : Array[Int],
  start : Int,
  stop : Int,
) -> Array[Int] {
  let result : Array[Int] = []
  for index in start..<stop {
    result.push(words[index])
  }
  result
}
