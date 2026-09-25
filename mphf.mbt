///|
/// One three-vertex hyperedge used by the BDZ construction.
priv struct Edge {
  first : Int
  second : Int
  third : Int
}

///|
/// A peeled edge and the degree-one vertex that removed it.
priv struct PeelStep {
  edge : Int
  vertex : Int
}

///| A construction attempt is deliberately bounded so malformed or hostile

///|
/// input cannot turn building a static table into an unbounded retry loop.
let default_max_construction_attempts = 64

///|
/// Keep all mixer intermediates non-negative on every MoonBit backend.
let positive_mask = 0x7fffffff

///|
/// Build a minimal perfect hash function for distinct non-negative hashes.
pub fn Mphf::build(keys : Array[Int]) -> Result[Mphf, MphfError] {
  Mphf::build_with_options(keys, default_build_options())
}

///|
/// Return the conservative construction policy used by `Mphf::build`.
pub fn default_build_options() -> MphfBuildOptions {
  {
    vertices_per_key_milli: 1300,
    max_attempts: default_max_construction_attempts,
    initial_seed: 0,
  }
}

///|
/// Build an MPHF with an explicit space-versus-retry policy. Larger vertex
/// ratios make peeling more likely to succeed but produce a larger table.
pub fn Mphf::build_with_options(
  keys : Array[Int],
  options : MphfBuildOptions,
) -> Result[Mphf, MphfError] {
  match validate_keys(keys) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  match validate_build_options(options) {
    Ok(_) => ()
    Err(error) => return Err(error)
  }
  let count = keys.length()
  let vertices = vertex_count_for(count, options.vertices_per_key_milli)
  for attempt in 0..<options.max_attempts {
    let seed = seed_for_attempt(attempt, options.initial_seed)
    match construct_values(keys, vertices, seed) {
      Some(values) =>
        return Ok({
          key_count: count,
          vertex_count: vertices,
          seed,
          attempts: attempt + 1,
          values,
        })
      None => ()
    }
  }
  Err(ConstructionFailed(options.max_attempts))
}

///|
/// Return the number of keys used to construct this function.
pub fn Mphf::len(self : Mphf) -> Int {
  self.key_count
}

///|
/// Return construction diagnostics without exposing mutable internal tables.
pub fn Mphf::stats(self : Mphf) -> MphfStats {
  {
    key_count: self.key_count,
    vertex_count: self.vertex_count,
    seed: self.seed,
    attempts: self.attempts,
  }
}

///| Map a non-negative pre-hashed key into `[0, len)`. This does not prove

///|
/// membership: callers requiring that guarantee should use `StaticSet` or
/// `StaticIntMap`.
pub fn Mphf::slot_of_hash(self : Mphf, key : Int) -> Int? {
  if key < 0 || self.key_count == 0 {
    return None
  }
  let edge = edge_for(key, self.seed, self.vertex_count)
  let value_sum = self.values[edge.first] +
    self.values[edge.second] +
    self.values[edge.third]
  let slot = value_sum % self.key_count
  Some(slot)
}

///| Verify that a candidate source key set occupies every MPHF slot exactly

///|
/// once. This is useful when loading a function and its key manifest from
/// separate artifacts.
pub fn Mphf::is_perfect_for(self : Mphf, keys : Array[Int]) -> Bool {
  if keys.length() != self.key_count {
    return false
  }
  let occupied = Array::make(self.key_count, false)
  for key in keys {
    match self.slot_of_hash(key) {
      None => return false
      Some(slot) => {
        if occupied[slot] {
          return false
        }
        occupied[slot] = true
      }
    }
  }
  true
}

///| Build an exact immutable set. The MPHF selects a slot and the stored key

///|
/// confirms it, so unknown keys cannot become false positives.
pub fn StaticSet::from_keys(keys : Array[Int]) -> Result[StaticSet, MphfError] {
  StaticSet::from_keys_with_options(keys, default_build_options())
}

///|
/// Build an exact static set using an explicit MPHF construction policy.
pub fn StaticSet::from_keys_with_options(
  keys : Array[Int],
  options : MphfBuildOptions,
) -> Result[StaticSet, MphfError] {
  let mphf = match Mphf::build_with_options(keys, options) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let keys_by_slot = Array::make(keys.length(), 0)
  for key in keys {
    let slot = mphf.slot_of_hash(key).unwrap()
    keys_by_slot[slot] = key
  }
  Ok({ mphf, keys_by_slot })
}

///|
/// Test exact membership of a non-negative key.
pub fn StaticSet::contains(self : StaticSet, key : Int) -> Bool {
  match self.mphf.slot_of_hash(key) {
    Some(slot) => self.keys_by_slot[slot] == key
    None => false
  }
}

///|
/// Number of keys in this immutable set.
pub fn StaticSet::len(self : StaticSet) -> Int {
  self.keys_by_slot.length()
}

///|
/// Return the keys in MPHF slot order for diagnostics and deterministic tests.
pub fn StaticSet::keys_by_slot(self : StaticSet) -> Array[Int] {
  self.keys_by_slot.copy()
}

///|
/// Return the construction diagnostics for this set.
pub fn StaticSet::stats(self : StaticSet) -> MphfStats {
  self.mphf.stats()
}

///|
/// Construct a checked immutable map from distinct integer keys.
pub fn StaticIntMap::from_entries(
  entries : Array[IntEntry],
) -> Result[StaticIntMap, MphfError] {
  StaticIntMap::from_entries_with_options(entries, default_build_options())
}

///|
/// Build an exact static map using an explicit MPHF construction policy.
pub fn StaticIntMap::from_entries_with_options(
  entries : Array[IntEntry],
  options : MphfBuildOptions,
) -> Result[StaticIntMap, MphfError] {
  let keys : Array[Int] = []
  for entry in entries {
    keys.push(entry.key)
  }
  let mphf = match Mphf::build_with_options(keys, options) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let keys_by_slot = Array::make(entries.length(), 0)
  let values_by_slot = Array::make(entries.length(), 0)
  for entry in entries {
    let slot = mphf.slot_of_hash(entry.key).unwrap()
    keys_by_slot[slot] = entry.key
    values_by_slot[slot] = entry.value
  }
  Ok({ mphf, keys_by_slot, values_by_slot })
}

///|
/// Retrieve a value only when the queried key exactly matches its slot key.
pub fn StaticIntMap::get(self : StaticIntMap, key : Int) -> Int? {
  match self.mphf.slot_of_hash(key) {
    Some(slot) if self.keys_by_slot[slot] == key =>
      Some(self.values_by_slot[slot])
    _ => None
  }
}

///|
/// Test exact membership without exposing mapped values.
pub fn StaticIntMap::contains_key(self : StaticIntMap, key : Int) -> Bool {
  self.get(key) is Some(_)
}

///|
/// Number of entries in this immutable map.
pub fn StaticIntMap::len(self : StaticIntMap) -> Int {
  self.keys_by_slot.length()
}

///|
/// Return the construction diagnostics for this map.
pub fn StaticIntMap::stats(self : StaticIntMap) -> MphfStats {
  self.mphf.stats()
}

///|
/// Return entries in deterministic MPHF slot order. This is primarily useful
/// for snapshot rebuilding, diagnostics, and layered-map compaction.
pub fn StaticIntMap::entries_by_slot(self : StaticIntMap) -> Array[IntEntry] {
  let entries : Array[IntEntry] = []
  for slot in 0..<self.keys_by_slot.length() {
    entries.push({
      key: self.keys_by_slot[slot],
      value: self.values_by_slot[slot],
    })
  }
  entries
}

///| Validate the public pre-hash boundary and reject duplicate input before

///|
/// graph construction, keeping build failures deterministic and explainable.
fn validate_keys(keys : Array[Int]) -> Result[Unit, MphfError] {
  if keys.length() == 0 {
    return Err(EmptyInput)
  }
  for key in keys {
    if key < 0 {
      return Err(NegativeKey(key))
    }
  }
  let ordered = keys.copy()
  ordered.sort()
  for index in 1..<ordered.length() {
    if ordered[index - 1] == ordered[index] {
      return Err(DuplicateKey(ordered[index]))
    }
  }
  Ok(())
}

///|
/// Keep the 3-uniform hypergraph sparse enough that peeling normally succeeds.
fn vertex_count_for(key_count : Int, vertices_per_key_milli : Int) -> Int {
  key_count * vertices_per_key_milli / 1000 + 3
}

///| Construction retries use a deterministic stream so the same input is

///|
/// reproducible across processes and targets.
fn seed_for_attempt(attempt : Int, initial_seed : Int) -> Int {
  mix_hash(attempt + 1, initial_seed ^ 0x13579b)
}

///|
/// Reject unstable or unreasonably costly construction policies at the API
/// boundary. BDZ needs a ratio above one, and a fourfold table is already more
/// generous than this compact-index library intends to support.
fn validate_build_options(
  options : MphfBuildOptions,
) -> Result[Unit, MphfError] {
  if options.vertices_per_key_milli < 1200 ||
    options.vertices_per_key_milli > 4000 {
    return Err(InvalidBuildOption(options.vertices_per_key_milli))
  }
  if options.max_attempts <= 0 || options.max_attempts > 256 {
    return Err(InvalidBuildOption(options.max_attempts))
  }
  if options.initial_seed < 0 {
    return Err(InvalidBuildOption(options.initial_seed))
  }
  Ok(())
}

///| Construct assignment values by peeling degree-one vertices from a 3-edge

///|
/// hypergraph, then assigning values in reverse peel order.
fn construct_values(
  keys : Array[Int],
  vertex_count : Int,
  seed : Int,
) -> Array[Int]? {
  let edges : Array[Edge] = []
  for key in keys {
    let edge = edge_for(key, seed, vertex_count)
    if edge.first == edge.second ||
      edge.first == edge.third ||
      edge.second == edge.third {
      return None
    }
    edges.push(edge)
  }
  let degree = Array::make(vertex_count, 0)
  let incident = Array::make(vertex_count, 0)
  for edge_index in 0..<edges.length() {
    let edge = edges[edge_index]
    add_incident(degree, incident, edge.first, edge_index)
    add_incident(degree, incident, edge.second, edge_index)
    add_incident(degree, incident, edge.third, edge_index)
  }
  let queue : Array[Int] = []
  for vertex in 0..<vertex_count {
    if degree[vertex] == 1 {
      queue.push(vertex)
    }
  }
  let active = Array::make(edges.length(), true)
  let order : Array[PeelStep] = []
  let mut cursor = 0
  while cursor < queue.length() {
    let vertex = queue[cursor]
    cursor += 1
    if degree[vertex] == 1 {
      let edge_index = incident[vertex]
      if active[edge_index] {
        active[edge_index] = false
        order.push({ edge: edge_index, vertex })
        let edge = edges[edge_index]
        remove_incident(degree, incident, queue, edge.first, edge_index)
        remove_incident(degree, incident, queue, edge.second, edge_index)
        remove_incident(degree, incident, queue, edge.third, edge_index)
      }
    }
  }
  if order.length() != keys.length() {
    return None
  }
  let values = Array::make(vertex_count, 0)
  let mut index = order.length()
  while index > 0 {
    index -= 1
    let step = order[index]
    let edge = edges[step.edge]
    let other_sum = edge_value_sum(values, edge, step.vertex)
    values[step.vertex] = positive_mod(step.edge - other_sum, keys.length())
  }
  for edge_index in 0..<edges.length() {
    let slot = edge_value_sum(values, edges[edge_index], -1) % keys.length()
    if slot != edge_index {
      return None
    }
  }
  Some(values)
}

///|
/// Add an edge to one vertex's degree/xor incidence accumulator.
fn add_incident(
  degree : Array[Int],
  incident : Array[Int],
  vertex : Int,
  edge : Int,
) -> Unit {
  degree[vertex] += 1
  incident[vertex] = incident[vertex] ^ edge
}

///|
/// Remove an active edge and enqueue a vertex that has just become peelable.
fn remove_incident(
  degree : Array[Int],
  incident : Array[Int],
  queue : Array[Int],
  vertex : Int,
  edge : Int,
) -> Unit {
  degree[vertex] -= 1
  incident[vertex] = incident[vertex] ^ edge
  if degree[vertex] == 1 {
    queue.push(vertex)
  }
}

///|
/// Sum all assignment values except one chosen vertex; passing `-1` sums all.
fn edge_value_sum(values : Array[Int], edge : Edge, excluded : Int) -> Int {
  let mut total = 0
  if edge.first != excluded {
    total += values[edge.first]
  }
  if edge.second != excluded {
    total += values[edge.second]
  }
  if edge.third != excluded {
    total += values[edge.third]
  }
  total
}

///| Derive three candidate vertices from a deterministic, non-cryptographic

///|
/// 31-bit mixer. The caller supplies already-hashed integer keys.
fn edge_for(key : Int, seed : Int, vertices : Int) -> Edge {
  {
    first: mix_hash(key, seed ^ 0x51f15e) % vertices,
    second: mix_hash(key, seed ^ 0x6d2b79) % vertices,
    third: mix_hash(key, seed ^ 0x2c1b3d) % vertices,
  }
}

///| A small deterministic integer mixer; it is not a cryptographic hash.

///|
/// The multiplicative rounds deliberately break the linear relationship
/// between the three salted xorshift streams. Without them, small key sets can
/// repeatedly create the same cyclic hypergraph for every construction seed.
fn mix_hash(value : Int, salt : Int) -> Int {
  let mut state = (value ^ salt) & positive_mask
  state = (state * 1_597_334_677) & positive_mask
  state = (state ^ (state >> 16)) & positive_mask
  state = (state * 1_103_515_245) & positive_mask
  state = (state ^ (state >> 13)) & positive_mask
  (state * 1_013_904_223) & positive_mask
}

///|
/// Euclidean remainder for reverse assignment values.
fn positive_mod(value : Int, modulus : Int) -> Int {
  let remainder = value % modulus
  if remainder < 0 {
    remainder + modulus
  } else {
    remainder
  }
}
