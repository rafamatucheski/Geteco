extends SceneTree
const VEHICLE := preload("res://scripts/Vehicle.gd")
const ESCAPE := preload("res://gameplay/TrafficEscape.gd")
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("TRAFFIC_DEADLINE ","PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	for kind in ["ambient","player","mission","race","armored"]:
		var car := VEHICLE.new()
		scene.add_child(car)
		car.set_physics_process(false)
		car.traffic=true
		car.speed=2.2
		car.set_meta("ambient_traffic",kind!="mission")
		if kind=="player": car.controlled=true
		if kind=="race": car.set_meta("race_owned",true)
		if kind=="armored": car.set_meta("armored_transport",true)
		var episode := ESCAPE.new()
		episode._abandon_clock=39.9
		episode._obstruction_origin=car.position+Vector3.FORWARD*8
		episode.tick(car,.2)
		check(episode.retiring==(kind=="ambient"),"movimento sem saída tem prazo; preserva "+kind)
		if episode.retiring:
			episode.tick(car,1.1)
			await process_frame
			check(not is_instance_valid(car),"retirada finita mantém fade")
	scene.free()
	print("TRAFFIC_DEADLINE failures=",failures)
	quit(0 if failures==0 else 1)
