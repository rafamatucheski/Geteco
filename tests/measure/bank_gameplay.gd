extends "res://tests/measure/video_review_probe.gd"
## Current-state measurement: real Main bank, open vault, cash, blood, active
## city response. 5 s warm-up + 30 s sampling inherited from measure_full.
func run() -> void:
	scenario="bank"
	await super.run()
	if not is_instance_valid(world) or world.session==null or not world.session.ready_for_play: return
	started=0
	var heist = world.session.robberies
	for actor in heist._actors:
		if actor.guard: actor.receive_damage(200,world.player)
	heist.data.keycard_taken=true
	heist.data.vault_open=true
	heist._refresh_card()
	world.session.room.set_vault_open(1)
	var point: Vector3 = world.session.room.to_global(Vector3(0,.04,-3.65))
	world.player.teleport(point)
	route=PackedVector3Array([point,point])
	cold.clear()
	samples.clear()
	cpu.clear()
	physics.clear()
	measuring=false
	started=Time.get_ticks_usec()
	previous=started
