extends SceneTree
const PIANO := preload("res://activities/UnionPiano.gd")
var failures := 0
var heard := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var piano := PIANO.new()
	root.add_child(piano)
	piano.timer.stop()
	check(piano.key_at(Vector3(-3.675, .1, 0)) == 0, "First key must be reachable")
	check(piano.key_at(Vector3(3.675, .1, 0)) == 7, "Last key must be reachable")
	for point in [Vector3(4.3,0,0), Vector3(0,0,1.7), Vector3(0,2,0), Vector3(0,-1,0)]:
		check(piano.key_at(point) == -1, "Outside/above/below must not sound")
	piano.play_note(0, true)
	check(piano.progress == 1, "Player begins melody")
	piano.play_note(6, false)
	check(piano.progress == 1, "Residents must not spoil player melody")
	piano.play_note(5, true)
	check(piano.progress == 0, "Wrong note restarts challenge")
	for note in PIANO.MELODY: piano.play_note(note, true)
	check(piano.celebrations == 1, "Complete melody celebrates exactly once")
	check(piano.progress == 0, "Completion resets safely")
	var actor := Node3D.new()
	root.add_child(actor)
	actor.position = Vector3(-3.675,.1,0)
	piano._reset()
	var next := {}
	piano.note_played.connect(func(_index, _player): heard += 1)
	piano._visit(actor, true, next)
	piano.occupants = next
	check(piano.progress == 1, "Walking onto key plays it")
	piano._visit(actor, true, {})
	check(heard == 1, "Standing still must not retrigger")
	piano._reset()
	check(piano.occupants.is_empty() and piano.progress == 0, "Leaving clears occupancy and melody")
	for voice in piano.voices: check(not voice.playing, "Leaving stops audio")
	check(piano.find_children("*", "CollisionObject3D", true, false).is_empty(), "Flush paving must not obstruct circulation")
	check(PIANO.tones.size() == 8, "Eight cached sounds")
	actor.free()
	piano.free()
	var second := PIANO.new()
	root.add_child(second)
	check(PIANO.tones.size() == 8 and second.progress == 0, "Reload reuses audio and starts clean")
	second.free()
	print("UNION_PIANO_TEST failures=", failures)
	quit(0 if failures == 0 else 1)
