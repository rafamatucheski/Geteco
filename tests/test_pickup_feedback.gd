extends SceneTree
const LOOT := preload("res://gameplay/LootPickup.gd")
const AUDIO := preload("res://gameplay/CombatAudio.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PICKUP ","PASS " if ok else "FAIL ",label)
	if not ok: failures += 1
func run() -> void:
	for kind in ["weapon","armor"]:
		var item := LOOT.new()
		item.setup(kind,"pistol",12)
		root.add_child(item)
		item.advance(.2)
		check(item._icon.rotation.y > 0 and item.can_collect(Vector3.ZERO),kind+" rotates and remains collectable")
		check(not item.can_collect(Vector3(0,4,0)),kind+" cannot be collected from another floor")
		item.collect()
		item.collect()
		check(not item.can_collect(Vector3.ZERO),kind+" becomes unavailable immediately")
		await create_timer(.15).timeout
		check(item._disc_material.albedo_color.a < item.halo_color().a*.45,kind+" ground glow fades with absorption")
		await create_timer(.2).timeout
		check(not is_instance_valid(item),kind+" absorption frees item")
	for i in 3:
		var stream := AUDIO.wav("reward_pickup_%d.wav" % i)
		check(stream != null and stream.get_length() > 0,"V1 reward take %d imported" % i)
	print("PICKUP_RESULT failures=",failures)
	quit(1 if failures else 0)
