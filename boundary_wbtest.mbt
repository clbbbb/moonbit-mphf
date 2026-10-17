///|
test "raw decoder rejects impossible counts even with a complete payload" {
  let words = [1, 0x7fffffff, 3, 0, 1, 1000000000, 1000000000, 1000000000]
  assert_true(decode_mphf_words(words) is Err(InvalidMetadata))
}

///|
test "slot arithmetic cannot wrap before taking the modulus" {
  // A synthetic table isolates arithmetic without allocating billions of slots.
  let mphf : Mphf = {
    key_count: 0x7fffffff,
    vertex_count: 3,
    seed: 0,
    attempts: 1,
    values: [1000000000, 1000000000, 1000000000],
  }
  for key in [0, 1, 7, 0x7fffffff] {
    assert_eq(mphf.slot_of_hash(key), Some(852516353))
  }
  let near_maximum : Mphf = {
    ..mphf,
    values: [2147483646, 2147483646, 2147483646],
  }
  assert_eq(near_maximum.slot_of_hash(7), Some(2147483644))
  assert_true(mphf.validate() is Err(InvalidMetadata))
}

///|
test "construction capacity uses wide multiplication before division" {
  assert_eq(vertex_count_for(2000000, 1300).unwrap(), 2600003)
  assert_eq(vertex_count_for(536870910, 4000).unwrap(), 2147483643)
  assert_true(
    vertex_count_for(536870912, 4000) is Err(CapacityExceeded(536870912)),
  )
  assert_true(vertex_count_for(0x7fffffff, 4000) is Err(CapacityExceeded(_)))
}

///|
test "reverse assignment handles a negative sum outside Int range" {
  assert_eq(positive_mod(-4294967292L, 2147483647), 2)
  assert_eq(positive_mod(-4294967294L, 2147483647), 0)
}
