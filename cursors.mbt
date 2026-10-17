///|
/// Create a persistent cursor positioned at the first slot-ordered set key.
/// The index has private immutable storage, so creating a cursor is O(1).
pub fn StaticSet::cursor(self : StaticSet) -> StaticSetCursor {
  { keys_by_slot: self.keys_by_slot, next_slot: 0, }
}

///|
/// Create a persistent cursor at one set slot. This is useful for checkpointed
/// scans after an external consumer has durably processed a prefix.
pub fn StaticSet::cursor_at(
  self : StaticSet,
  slot : Int,
) -> Result[StaticSetCursor, MphfError] {
  if slot < 0 || slot > self.keys_by_slot.length() {
    return Err(InvalidRange(slot, self.keys_by_slot.length()))
  }
  Ok({ keys_by_slot: self.keys_by_slot, next_slot: slot, })
}

///|
/// Consume at most one set key. The original cursor is unchanged; `None`
/// signals exhaustion and returns an equivalent exhausted cursor.
pub fn StaticSetCursor::next(self : StaticSetCursor) -> (Int?, StaticSetCursor) {
  if self.next_slot >= self.keys_by_slot.length() {
    return (None, self)
  }
  let key = self.keys_by_slot[self.next_slot]
  (
    Some(key),
    { keys_by_slot: self.keys_by_slot, next_slot: self.next_slot + 1, },
  )
}

///|
/// Return the number of unread keys in this set cursor.
pub fn StaticSetCursor::remaining(self : StaticSetCursor) -> Int {
  self.keys_by_slot.length() - self.next_slot
}

///|
/// Return whether the cursor has no unread key.
pub fn StaticSetCursor::is_exhausted(self : StaticSetCursor) -> Bool {
  self.remaining() == 0
}

///|
/// Materialize the unread suffix of a set cursor in slot order.
pub fn StaticSetCursor::collect_remaining(self : StaticSetCursor) -> Array[Int] {
  let keys : Array[Int] = []
  for index in self.next_slot..<self.keys_by_slot.length() {
    keys.push(self.keys_by_slot[index])
  }
  keys
}

///|
/// Create a persistent cursor positioned at the first slot-ordered map entry.
pub fn StaticIntMap::cursor(self : StaticIntMap) -> StaticIntMapCursor {
  {
    keys_by_slot: self.keys_by_slot,
    values_by_slot: self.values_by_slot,
    next_slot: 0,
  }
}

///|
/// Create a persistent map cursor at an entry slot.
pub fn StaticIntMap::cursor_at(
  self : StaticIntMap,
  slot : Int,
) -> Result[StaticIntMapCursor, MphfError] {
  if slot < 0 || slot > self.keys_by_slot.length() {
    return Err(InvalidRange(slot, self.keys_by_slot.length()))
  }
  Ok({
    keys_by_slot: self.keys_by_slot,
    values_by_slot: self.values_by_slot,
    next_slot: slot,
  })
}

///|
/// Consume at most one map entry and return the successor cursor.
pub fn StaticIntMapCursor::next(
  self : StaticIntMapCursor,
) -> (IntEntry?, StaticIntMapCursor) {
  if self.next_slot >= self.keys_by_slot.length() {
    return (None, self)
  }
  let entry : IntEntry = {
    key: self.keys_by_slot[self.next_slot],
    value: self.values_by_slot[self.next_slot],
  }
  (
    Some(entry),
    {
      keys_by_slot: self.keys_by_slot,
      values_by_slot: self.values_by_slot,
      next_slot: self.next_slot + 1,
    },
  )
}

///|
/// Return the number of unread map entries in this cursor.
pub fn StaticIntMapCursor::remaining(self : StaticIntMapCursor) -> Int {
  self.keys_by_slot.length() - self.next_slot
}

///|
/// Materialize all unread map entries in deterministic slot order.
pub fn StaticIntMapCursor::collect_remaining(
  self : StaticIntMapCursor,
) -> Array[IntEntry] {
  let entries : Array[IntEntry] = []
  for index in self.next_slot..<self.keys_by_slot.length() {
    entries.push({
      key: self.keys_by_slot[index],
      value: self.values_by_slot[index],
    })
  }
  entries
}

///|
/// Create a persistent cursor positioned before the first multimap value.
pub fn StaticIntMultiMap::cursor(
  self : StaticIntMultiMap,
) -> StaticIntMultiMapCursor {
  {
    keys_by_slot: self.keys_by_slot,
    offsets_by_slot: self.offsets_by_slot,
    values: self.values,
    slot: 0,
    value_index: 0,
  }
}

///|
/// Consume at most one multimap key/value item. A multimap always has at least
/// one value per key when built through the public constructor or decoder.
pub fn StaticIntMultiMapCursor::next(
  self : StaticIntMultiMapCursor,
) -> (IntMultiEntry?, StaticIntMultiMapCursor) {
  let mut slot = self.slot
  let mut value_index = self.value_index
  while slot < self.keys_by_slot.length() {
    let start = self.offsets_by_slot[slot]
    let stop = self.offsets_by_slot[slot + 1]
    if value_index < start {
      value_index = start
    }
    if value_index < stop {
      let entry : IntMultiEntry = {
        key: self.keys_by_slot[slot],
        value: self.values[value_index],
      }
      return (
        Some(entry),
        {
          keys_by_slot: self.keys_by_slot,
          offsets_by_slot: self.offsets_by_slot,
          values: self.values,
          slot,
          value_index: value_index + 1,
        },
      )
    }
    slot += 1
    value_index = 0
  }
  (None, self)
}

///|
/// Count unread values in O(1). Returned cursors retain the global flattened
/// value offset, including when the last value of a group has been consumed.
pub fn StaticIntMultiMapCursor::remaining(
  self : StaticIntMultiMapCursor,
) -> Int {
  self.values.length() - self.value_index
}

///|
/// Materialize every unread multimap entry by advancing a local cursor.
pub fn StaticIntMultiMapCursor::collect_remaining(
  self : StaticIntMultiMapCursor,
) -> Array[IntMultiEntry] {
  let entries : Array[IntMultiEntry] = []
  let mut cursor = self
  while cursor.remaining() > 0 {
    let (item, successor) = cursor.next()
    match item {
      Some(entry) => entries.push(entry)
      None => return entries
    }
    cursor = successor
  }
  entries
}
