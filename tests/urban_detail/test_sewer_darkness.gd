extends SceneTree

const DARKNESS = preload("res://world/places/sewers/SewerDarkness.gd")

class TestWorld extends Node3D:
	var session: Dictionary = {"room": null, "state": {"place_id": ""}}
	var production: Dictionary = {"sun": null}
	var gameplay: Dictionary = {"flashlight": null}

class TestRoom extends Node3D:
	var definition := {"id": "sewer_market"}

var failures := 0

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var world := TestWorld.new()
	root.add_child(world)
	var room := TestRoom.new()
	world.add_child(room)
	var model := Node3D.new()
	room.add_child(model)
	var darkness := DARKNESS.new()
	model.add_child(darkness)
	darkness.configure(model, {})
	check(not darkness.visible, "overlay starts hidden before its first frame")
	check(not darkness._room_is_current(), "preloaded sewer cannot darken the street or descent")
	world.session.room = room
	check(not darkness._room_is_current(), "room assignment alone cannot darken the street")
	world.session.state.place_id = "sewer_market"
	check(darkness._room_is_current(), "occupied sewer enables its atmosphere, including save restoration")
	world.session.state.place_id = ""
	check(not darkness._room_is_current(), "return to street disables sewer atmosphere")
	world.session.room = null
	check(not darkness._room_is_current(), "cancelled entry leaves street unaffected")
	var camera := Camera3D.new()
	world.add_child(camera)
	var original := Environment.new()
	original.ambient_light_energy = .65
	camera.environment = original
	var sun := DirectionalLight3D.new()
	world.add_child(sun)
	sun.light_cull_mask = 5
	world.production.sun = sun
	var flashlight := SpotLight3D.new()
	world.add_child(flashlight)
	world.gameplay.flashlight = flashlight
	darkness._apply_lighting(camera)
	check(camera.environment != original and is_equal_approx(camera.environment.ambient_light_energy,.025), "occupied room has independent dark environment")
	check(is_equal_approx(original.ambient_light_energy,.65), "shared exterior environment is preserved")
	check(sun.light_cull_mask == 0 and flashlight.shadow_enabled, "sun excluded and actual weapon shadows enabled")
	darkness._restore_lighting()
	check(camera.environment == original and sun.light_cull_mask == 5 and not flashlight.shadow_enabled, "exit restores exterior lighting and shadow policy")
	darkness._apply_lighting(camera)
	model.free()
	check(camera.environment == original and sun.light_cull_mask == 5 and not flashlight.shadow_enabled, "unloading active room restores exterior state")
	world.free()
	check(not is_instance_valid(darkness), "room cleanup removes overlay")
	quit(1 if failures else 0)
