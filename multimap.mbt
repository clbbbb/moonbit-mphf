///|
/// A source item annotated with its input position. Sorting by this position
/// after the key preserves value order for equal keys without relying on the
/// implementation details of the array sort.
priv struct IndexedMultiEntry {
  key : Int
  value : Int
  input_index : Int
}

///|
/// Build an exact immutable multimap. Repeated keys are grouped, while values
/// associated with the same key retain the order in which they were supplied.
pub fn StaticIntMultiMap::from_entries(
  entries : Array[IntMultiEntry],
) -> Result[StaticIntMultiMap, MphfError] {
  if entries.length() == 0 {
    return Err(EmptyInput)
  }
  let ordered : Array[IndexedMultiEntry] = []
  for index in 0..<entries.length() {
    let entry = entries[index]
    if entry.key < 0 {
      return Err(NegativeKey(entry.key))
    }
    ordered.push({ key: entry.key, value: entry.value, input_index: index })
  }
  ordered.sort_by((left, right) => {
    let key_order = left.key.compare(right.key)
    if key_order == 0 {
      left.input_index.compare(right.input_index)
    } else {
      key_order
    }
  })
  let distinct_keys : Array[Int] = []
  let values : Array[Int] = []
  let group_offsets : Array[Int] = [0]
  let mut previous_key = -1
  for item in ordered {
    if item.key != previous_key {
      if previous_key >= 0 {
        group_offsets.push(values.length())
      }
      distinct_keys.push(item.key)
      previous_key = item.key
    }
    values.push(item.value)
  }
  group_offsets.push(values.length())
  let mphf = match Mphf::build(distinct_keys) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let keys_by_slot = Array::make(distinct_keys.length(), 0)
  let offsets_by_slot = Array::make(distinct_keys.length() + 1, 0)
  for group in 0..<distinct_keys.length() {
    let key = distinct_keys[group]
    let slot = mphf.slot_of_hash(key).unwrap()
    keys_by_slot[slot] = key
  }
  // Individual slots are not arranged by source-key order. Build one compact
  // payload in slot order and record the start of every key's value range.
  let rebuilt_values : Array[Int] = []
  for slot in 0..<distinct_keys.length() {
    let key = keys_by_slot[slot]
    let group = find_sorted_key(distinct_keys, key)
    offsets_by_slot[slot] = rebuilt_values.length()
    for index in group_offsets[group]..<group_offsets[group + 1] {
      rebuilt_values.push(values[index])
    }
  }
  offsets_by_slot[distinct_keys.length()] = rebuilt_values.length()
  Ok({ mphf, keys_by_slot, offsets_by_slot, values: rebuilt_values })
}

///|
/// Return a fresh array containing the values for one exact key. Unknown and
/// negative keys return an empty array, which makes probe-heavy clients simple.
pub fn StaticIntMultiMap::get_all(
  self : StaticIntMultiMap,
  key : Int,
) -> Array[Int] {
  match self.mphf.slot_of_hash(key) {
    Some(slot) if self.keys_by_slot[slot] == key =>
      slice_values(
        self.values,
        self.offsets_by_slot[slot],
        self.offsets_by_slot[slot + 1],
      )
    _ => []
  }
}

///|
/// Count values for one exact key without allocating an output array.
pub fn StaticIntMultiMap::value_count_for(
  self : StaticIntMultiMap,
  key : Int,
) -> Int {
  match self.mphf.slot_of_hash(key) {
    Some(slot) if self.keys_by_slot[slot] == key =>
      self.offsets_by_slot[slot + 1] - self.offsets_by_slot[slot]
    _ => 0
  }
}

///|
/// Return the number of distinct keys held by the multimap.
pub fn StaticIntMultiMap::len(self : StaticIntMultiMap) -> Int {
  self.keys_by_slot.length()
}

///|
/// Return the total number of key/value input items held by the multimap.
pub fn StaticIntMultiMap::value_count(self : StaticIntMultiMap) -> Int {
  self.values.length()
}

///|
/// Return the MPHF construction diagnostics for the distinct-key index.
pub fn StaticIntMultiMap::stats(self : StaticIntMultiMap) -> MphfStats {
  self.mphf.stats()
}

///|
/// Return all entries in deterministic slot order. Values within each key
/// retain the input order supplied to `from_entries`.
pub fn StaticIntMultiMap::entries(
  self : StaticIntMultiMap,
) -> Array[IntMultiEntry] {
  let entries : Array[IntMultiEntry] = []
  for slot in 0..<self.keys_by_slot.length() {
    for index in self.offsets_by_slot[slot]..<self.offsets_by_slot[slot + 1] {
      entries.push({ key: self.keys_by_slot[slot], value: self.values[index] })
    }
  }
  entries
}

///|
/// Deterministically encode a multimap. The representation keeps the same
/// checked MPHF and slot ranges used at runtime.
///
/// Format: `[6, mphf_word_count, mphf_words..., keys..., offsets..., values...]`.
pub fn StaticIntMultiMap::encode_words(self : StaticIntMultiMap) -> Array[Int] {
  let mphf_words = self.mphf.encode_words()
  let words : Array[Int] = [6, mphf_words.length()]
  words.append(mphf_words)
  words.append(self.keys_by_slot)
  words.append(self.offsets_by_slot)
  words.append(self.values)
  words
}

///|
/// Decode a multimap and reject malformed slot keys, malformed ranges, and
/// trailing words. Values themselves may be any MoonBit `Int`.
pub fn decode_static_int_multimap_words(
  words : Array[Int],
) -> Result[StaticIntMultiMap, MphfError] {
  if words.length() == 0 {
    return Err(MissingHeader)
  }
  if words[0] != 6 {
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
  if mphf.key_count > (remaining - 1) / 2 {
    return Err(InvalidMetadata)
  }
  let key_start = 2 + mphf_length
  let offset_start = key_start + mphf.key_count
  let value_start = offset_start + mphf.key_count + 1
  if words.length() < value_start {
    return Err(InvalidPayloadLength(value_start, words.length()))
  }
  let keys_by_slot : Array[Int] = []
  for index in key_start..<offset_start {
    keys_by_slot.push(words[index])
  }
  match validate_slot_keys(mphf, keys_by_slot) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let offsets_by_slot : Array[Int] = []
  for index in offset_start..<value_start {
    offsets_by_slot.push(words[index])
  }
  let values : Array[Int] = []
  for index in value_start..<words.length() {
    values.push(words[index])
  }
  match validate_offsets(offsets_by_slot, values.length(), mphf.key_count) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok({ mphf, keys_by_slot, offsets_by_slot, values })
}

///|
/// Copy a half-open range after the representation has already validated it.
fn slice_values(values : Array[Int], start : Int, stop : Int) -> Array[Int] {
  let result : Array[Int] = []
  for index in start..<stop {
    result.push(values[index])
  }
  result
}

///|
/// Find a known key in an ascending, distinct array. The construction path
/// calls this only for keys copied from that array, so failure is unreachable.
fn find_sorted_key(keys : Array[Int], wanted : Int) -> Int {
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
  low
}

///|
/// Validate the `n + 1` contiguous ranges used by a slot-ordered multimap.
fn validate_offsets(
  offsets : Array[Int],
  value_count : Int,
  key_count : Int,
) -> Result[Unit, MphfError] {
  if offsets.length() != key_count + 1 || offsets[0] != 0 {
    return Err(InvalidMetadata)
  }
  for index in 1..<offsets.length() {
    if offsets[index] <= offsets[index - 1] || offsets[index] > value_count {
      return Err(InvalidRange(offsets[index - 1], offsets[index]))
    }
  }
  if offsets[offsets.length() - 1] != value_count {
    return Err(InvalidPayloadLength(offsets[offsets.length() - 1], value_count))
  }
  Ok(())
}
