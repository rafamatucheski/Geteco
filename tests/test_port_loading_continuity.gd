extends SceneTree
const CARGO := preload("res://gameplay/urban_v1/PortCargoOperations.gd")
var failures: Array[String] = []

class Truck:
	extends CharacterBody3D
	var speed := 0.0
	var controlled := false
	var traffic := false
	var brake_input := true

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label); push_error(label)

func run() -> void:
	var cargo := CARGO.new()
	root.add_child(cargo)
	cargo.set_process(false)
	var truck := Truck.new()
	root.add_child(truck)
	cargo.session = {"world":{"driving":{"occupied":false,"car":null}}}
	var state: Dictionary = cargo.work_trucks[0]
	state.truck = truck
	state.phase = "waiting"
	cargo.cranes[0].clock = 18.0
	cargo._tick_truck(0,0.0)
	check(state.phase == "waiting","A late truck waits for the next lift, never redirects descending cargo")
	cargo.cranes[0].clock = 0.0
	cargo._tick_truck(0,0.0)
	check(state.phase == "loading","An idle crane accepts a stationary truck")
	# A local tilt must use the same transformed bed point as attachment.
	truck.rotation.x = .08
	var mount := truck.to_global(Vector3(0,1.07,1.72))
	check(cargo._truck_mount_position(0).is_equal_approx(mount),"Descending cargo uses the tilted truck bed transform")
	truck.rotation.x = 0
	for yaw in [-PI*.5,0.0,PI*.5]:
		truck.position = Vector3(250,.06,215)
		truck.rotation.y = yaw
		state.phase = "loading"
		state.loaded = false
		cargo.cranes[0].clock = 19.999
		cargo._sync_crane(0)
		var visual: Node3D = cargo.cranes[0].visual
		var before := visual.global_transform
		cargo._finish_truck_load(0)
		check(before.origin.distance_to(visual.global_position)<.002,"No position jump on attachment at yaw %s"%yaw)
		check(before.basis.x.dot(visual.global_basis.x)>.9999,"No rotation jump on attachment at yaw %s"%yaw)
		check(visual.position.is_equal_approx(Vector3(0,1.07,1.72)),"Cargo lands at bed center behind the cab")
		cargo._reset_truck_load(0)
		check(visual.global_basis.is_equal_approx(Basis.IDENTITY),"Next crane cycle resets orientation after truck turns")
	cargo.session = null
	cargo.free()
	truck.free()
	await process_frame
	print("PORT_LOADING_CONTINUITY failures=",failures)
	quit(0 if failures.is_empty() else 1)
