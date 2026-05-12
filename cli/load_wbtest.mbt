///|
using @test {assert_eq}

///|
test "load/routing_uses_distributed_targets" {
  let (targets, target_to_shard) = load_crush_targets(4)
  let crush = @placement.CrushMap::new(4, 1, targets)
  for i in 0..<32 {
    let id = @types.VectorId::from_int(i)
    match shard_index_for_id(id, crush, target_to_shard) {
      Some(shard) => {
        assert_true(shard >= 0 && shard < 4)
        let target = @distributed.targets_for_id(id, crush)[0]
        assert_eq(
          target,
          @placement.TargetKey::new("shard-" + shard.to_string()),
        )
      }
      None => assert_true(false)
    }
  }
}
