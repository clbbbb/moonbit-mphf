///|
/// Reproducible static key corpus used by release benchmarks.
fn benchmark_keys() -> Array[Int] {
  let keys : Array[Int] = []
  for index in 0..<4_000 {
    keys.push(index * 131 + 17)
  }
  keys
}

///|
/// Build a value corpus with a deliberate many-to-one relationship for the
/// multimap benchmarks. Key order is non-monotone to avoid benchmarking a
/// sorted-input-only construction path.
fn benchmark_multi_entries() -> Array[IntMultiEntry] {
  let entries : Array[IntMultiEntry] = []
  for index in 0..<8_000 {
    entries.push({ key: index * 17 % 1_003, value: index * 31 + 7 })
  }
  entries
}

///|
/// Build a reversible corpus for comparing two-index bimap construction.
fn benchmark_bimap_entries() -> Array[IntEntry] {
  let entries : Array[IntEntry] = []
  for index in 0..<2_000 {
    entries.push({ key: index * 43 + 5, value: index * 47 + 11 })
  }
  entries
}

///|
/// Benchmark construction separately from the read-heavy query path.
test (b : @bench.T) {
  let keys = benchmark_keys()
  let set = StaticSet::from_keys(keys).unwrap()
  let sharded = ShardedSet::from_keys(keys, 32).unwrap()
  let multi_entries = benchmark_multi_entries()
  let multi = StaticIntMultiMap::from_entries(multi_entries).unwrap()
  let bimap_entries = benchmark_bimap_entries()
  let bimap = StaticIntBiMap::from_entries(bimap_entries).unwrap()
  b.bench(name="build_4000_key_mphf", fn() {
    b.keep(Mphf::build(keys).unwrap().stats().attempts)
  })
  b.bench(name="exact_static_set_hit", fn() { b.keep(set.contains(262_017)) })
  b.bench(name="encode_checked_static_set", fn() {
    b.keep(set.encode_words().length())
  })
  b.bench(name="sharded_static_set_hit", fn() {
    b.keep(sharded.contains(262_017))
  })
  b.bench(name="build_1003_key_multimap", fn() {
    b.keep(
      StaticIntMultiMap::from_entries(multi_entries).unwrap().value_count(),
    )
  })
  b.bench(name="static_multimap_group_read", fn() {
    b.keep(multi.get_all(17).length())
  })
  b.bench(name="build_2000_pair_bimap", fn() {
    b.keep(StaticIntBiMap::from_entries(bimap_entries).unwrap().len())
  })
  b.bench(name="bimap_reverse_exact_hit", fn() {
    b.keep(bimap.get_by_value(93_964))
  })
}
