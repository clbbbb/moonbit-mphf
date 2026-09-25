///|
/// Build a read-only routing table and demonstrate an exact unknown-key miss.
fn main {
  let routes = @mphf.StaticIntMap::from_entries([
    { key: 101, value: 10 },
    { key: 203, value: 20 },
    { key: 907, value: 90 },
  ]).unwrap()
  println("route 203=" + routes.get(203).unwrap().to_string())
  println("contains 404=" + routes.contains_key(404).to_string())
  println("vertices=" + routes.stats().vertex_count.to_string())
}
