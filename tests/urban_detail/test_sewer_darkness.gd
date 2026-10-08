extends SceneTree

const DARKNESS = preload("res://world/places/sewers/SewerDarkness.gd")

class TestWorld extends Node3D:
	var session: Dictionary = {"room": null, "state": {"place_id": ""}}

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
	world.free()
	check(not is_instance_valid(darkness), "room cleanup removes overlay")
	quit(1 if failures else 0)
