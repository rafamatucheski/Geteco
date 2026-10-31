extends SceneTree
## Seleção e recorte reais de porta; sem afirmação de Main/streaming nem de FPS renderizado.
const VEHICLE := preload("res://scripts/Vehicle.gd")
const FLEET := preload("res://gameplay/mining/MiningFleet.gd")
class ProbeWorld extends Node3D:
	var player: CharacterBody3D
	var session: Node
class ProbePlayer extends CharacterBody3D:
	var input_locked := false
class ProbeDriving extends "res://scripts/Driving.gd":
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
var failures: Array[String] = []
var checks := 0
var stage: ProbeWorld
var driving: ProbeDriving

func _initialize() -> void:
	create_timer(35).timeout.connect(func(): push_error("MINING_VEHICLE_ACCESS timeout"); quit(3))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("MINING_VEHICLE_ACCESS ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func spawn(id: String, at: Vector3) -> CharacterBody3D:
	var car := VEHICLE.new()
	car.archetype = id
	car.position = at
	stage.add_child(car)
	car.set_physics_process(false)
	return car

func run() -> void:
	stage = ProbeWorld.new()
	root.add_child(stage)
	stage.player = ProbePlayer.new()
	stage.add_child(stage.player)
	driving = ProbeDriving.new()
	driving.world = stage
	stage.add_child(driving)
	var truck := spawn("mining_haul_truck", Vector3.ZERO)
	stage.player.position = truck.driver_door_anchor(1) + Vector3(1.55, 0, 0)
	await physics_frame
	check(stage.player.position.length() > 5.0, "test approaches the truck door from outside the old centre radius")
	check(driving._entry_option().get("car") == truck, "reachable haul-truck door is offered")
	var neighbor := spawn("sedan_classic", stage.player.position + Vector3(0, 0, 3.1))
	await physics_frame
	check(neighbor.position.distance_to(stage.player.position) < truck.position.distance_to(stage.player.position), "parked neighbor has the nearer centre")
	check(driving._entry_option().get("car") == truck, "unreachable neighbor door does not hide the reachable truck")
	stage.player.position += Vector3(1, 0, 0)
	check(driving._entry_option().is_empty(), "door reach is not extended by truck size")
	neighbor.free()
	truck.free()
	for id in FLEET.IDS:
		var car := spawn(id, Vector3.ZERO)
		var authored: Array = []
		for group in ["LoaderArm", "RearExcavator", "DumpBed"]:
			var attachment: Node3D = car.visual.get_node_or_null(group)
			if attachment == null: continue
			for part in attachment.find_children("*", "MeshInstance3D", true, false): authored.append([part, part.mesh])
		car.finish_doors()
		var unchanged := not authored.is_empty()
		for pair in authored: unchanged = unchanged and pair[0].mesh == pair[1] and pair[0].visible
		check(unchanged, id + " door preparation leaves hydraulic/load geometry intact")
		check(car.door_presentation.ready_for_boarding, id + " retains working door presentation")
		car.free()
	stage.free()
	print("MINING_VEHICLE_ACCESS checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
