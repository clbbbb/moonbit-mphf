///| Hash a string deterministically into the non-negative `Int` key domain.

///|
/// This lightweight mixer is for stable identifiers, not for passwords,
/// signatures, attacker-controlled routing, or any cryptographic purpose.
pub fn stable_string_hash(value : String) -> Int {
  let mut state = 1_469_598_103
  for character in value.to_array() {
    state = ((state ^ character.to_int()) * 16_777_619) & positive_mask
  }
  mix_hash(state, 0x4a7c15)
}

///|
/// Compare two distinct key sets and return their rebuild-relevant delta.
pub fn compare_key_sets(
  before : Array[Int],
  after : Array[Int],
) -> Result[KeySetDiff, MphfError] {
  match validate_keys(before) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match validate_keys(after) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  Ok(diff_sorted_keys(sorted_copy(before), sorted_copy(after)))
}

///|
/// Compare two checked static sets without exposing their slot layout.
pub fn StaticSet::diff_to(self : StaticSet, other : StaticSet) -> KeySetDiff {
  diff_sorted_keys(
    sorted_copy(self.keys_by_slot),
    sorted_copy(other.keys_by_slot),
  )
}

///|
/// True when no rebuild work is needed for a source key-set comparison.
pub fn KeySetDiff::is_empty(self : KeySetDiff) -> Bool {
  self.added.length() == 0 && self.removed.length() == 0
}

///|
/// Number of source keys changed by this delta.
pub fn KeySetDiff::changed_count(self : KeySetDiff) -> Int {
  self.added.length() + self.removed.length()
}

///|
/// Copy and sort keys without mutating caller-owned arrays.
fn sorted_copy(keys : Array[Int]) -> Array[Int] {
  let sorted = keys.copy()
  sorted.sort()
  sorted
}

///|
/// Linear merge of two sorted, duplicate-free arrays.
fn diff_sorted_keys(before : Array[Int], after : Array[Int]) -> KeySetDiff {
  let added : Array[Int] = []
  let removed : Array[Int] = []
  let mut retained = 0
  let mut left = 0
  let mut right = 0
  while left < before.length() && right < after.length() {
    if before[left] == after[right] {
      retained += 1
      left += 1
      right += 1
    } else if before[left] < after[right] {
      removed.push(before[left])
      left += 1
    } else {
      added.push(after[right])
      right += 1
    }
  }
  while left < before.length() {
    removed.push(before[left])
    left += 1
  }
  while right < after.length() {
    added.push(after[right])
    right += 1
  }
  { added, removed, retained }
}
