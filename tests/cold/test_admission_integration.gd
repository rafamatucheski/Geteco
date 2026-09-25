extends SceneTree
const HEAT = preload("res://runtime/cold/OriginalHeatSources.gd")
var errors: Array[String] = []
var checks := 0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: errors.append(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 900:
		await physics_frame
		if world.session!=null and world.session.ready_for_play and world.session.weather!=null: break
	check(world.session!=null and world.session.ready_for_play,"Main ready")
	if not errors.is_empty(): quit(1); return
	var cold = world.session.cold
	check(cold!=null,"Main installs real ColdSurvival")
	if cold==null: quit(1); return
	check(world.production.travel("mountain"),"real mountain travel")
	# travel() só admite o pedido; a chegada acontece alguns quadros depois e coloca o
	# jogador no ponto de destino. Posicionar antes disso seria desfeito pela chegada.
	for i in 600:
		if not world.production.travel_busy: break
		await physics_frame
	cold.set_process(false)
	var at := HEAT.to_world(Vector2(5980,715))
	world.player.set_physics_process(false)
	world.player.teleport(at+Vector3(8,.08,8))
	world.production.region.set_focus(at)
	for i in 30: await physics_frame
	if cold.presentation.visuals.has("outfitters_heater"):
		cold.presentation.visuals.outfitters_heater.free()
		cold.presentation.visuals.erase("outfitters_heater")
	await physics_frame
	var car = preload("res://scripts/Vehicle.gd").new()
	car.archetype = "sport_coupe"
	car.position = at+Vector3(30,.08,30)
	world.add_child(car)
	car.set_physics_process(false)
	check(not world.production.vehicle_position_clear(car,at+Vector3.UP*.04,0),"real hook refuses newly installed source")
	check(cold.presentation.visuals.has("outfitters_heater"),"real hook installs missing source")
	for i in 3: await physics_frame
	check(not world.production.vehicle_position_clear(car,at+Vector3.UP*.04,0),"real hull refuses physical brazier after sync")
	var clear := false
	for offset in [Vector3(0,0,6),Vector3(6,0,0),Vector3(-6,0,0),Vector3(0,0,10),Vector3(10,0,6),Vector3(-10,0,6)]:
		var candidate: Vector3 = at+offset+Vector3.UP*.04
		if world.production.vehicle_position_clear(car,candidate,0):
			clear = true
			print("COLD_ADMISSION_FREE_POSE ",candidate)
			break
	check(clear,"real hook admits supported free pose nearby")
	world.queue_free()
	await create_timer(.15).timeout
	print("COLD_ADMISSION_INTEGRATION checks=",checks," failures=",errors)
	quit(0 if errors.is_empty() else 1)
