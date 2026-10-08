extends SceneTree
const TRANSIT = preload("res://runtime/railway/RailwayTransit.gd")
const LOOK = preload("res://world/city_look/CityLook.gd")
class ActorStub extends CharacterBody3D:
	var input_locked := false
class CameraStub extends Camera3D:
	var target: Node3D
	var offset := Vector3(0,25,25)
	var heading := 0.0
	var target_size := 28.0
	var locked := false
	var initialized := false
class WorldStub extends Node3D:
	var player: ActorStub
	var camera: CameraStub
	var driving := {"occupied":false,"car":null,"transition":null}
	var gameplay := {"health":100.0}
class StateStub extends RefCounted:
	var equipped_weapon := "pistol"
	func equip_weapon(id: String) -> bool:
		equipped_weapon = id
		return true
class SessionStub extends Node:
	var world: WorldStub
	var state := StateStub.new()
	var ready_for_play := false
	var door_transition: Node
var failures := 0
func _initialize() -> void:
	create_timer(10.0).timeout.connect(func(): push_error("RAILWAY_DEPTH_TIMEOUT"); quit(3))
	call_deferred("run")
func depth_value(camera: Camera3D) -> Variant:
	return camera.get_meta("uses_interior_depth") if camera.has_meta("uses_interior_depth") else null
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures += 1
func run() -> void:
	var session := SessionStub.new()
	root.add_child(session)
	var world := WorldStub.new()
	session.world = world
	session.add_child(world)
	world.player = ActorStub.new()
	world.add_child(world.player)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	world.player.add_child(mesh)
	var accessory := MeshInstance3D.new()
	accessory.mesh = BoxMesh.new()
	var unrelated := StandardMaterial3D.new()
	accessory.material_overlay = unrelated
	world.player.add_child(accessory)
	world.camera = CameraStub.new()
	world.camera.target = world.player
	world.add_child(world.camera)
	world.camera.current = true
	var look := LOOK.new()
	look.controller = {"world":world,"state":{"place_id":""},"session":null,"environment":null}
	world.add_child(look)
	look.set_process(false)
	var transit := TRANSIT.new()
	transit.session = session
	world.add_child(transit)
	for original in [null, false, true]:
		var label := "absent" if original == null else str(original)
		if original == null: world.camera.remove_meta("uses_interior_depth")
		else: world.camera.set_meta("uses_interior_depth", original)
		look._refresh_silhouette()
		check((mesh.material_overlay != null) == (original != true), label + ": normal pre-ride overlay follows existing depth state")
		transit._snapshot_passenger()
		transit.riding = true
		transit._set_passenger_depth(true)
		check(world.camera.get_meta("uses_interior_depth") == true and mesh.material_overlay == null and world.player.visible, label + ": ride removes only xray while retaining actual actor")
		transit._restore_passenger()
		transit.riding = false
		check(world.camera.has_meta("uses_interior_depth") == (original != null) and depth_value(world.camera) == original, label + ": arrival restores exact metadata presence and value")
		check((mesh.material_overlay != null) == (original != true) and accessory.material_overlay == unrelated, label + ": arrival restores exterior xray and preserves unrelated overlay")
		transit._snapshot_passenger()
		transit.riding = true
		transit._set_passenger_depth(true)
		transit.cancel_for_transition()
		check(not transit.busy() and depth_value(world.camera) == original and world.camera.has_meta("uses_interior_depth") == (original != null), label + ": cancellation restores exact metadata and releases ownership")
		check((mesh.material_overlay != null) == (original != true) and accessory.material_overlay == unrelated, label + ": cancellation restores depth presentation without removing other overlays")
	print("RAILWAY_DEPTH_RESULT checks=18 failures=", failures)
	session.free()
	quit(1 if failures else 0)
