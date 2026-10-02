extends SceneTree
## First hit, interrupted reaction and direct fall must work without prior metadata.
const PRESENTATION := preload("res://gameplay/CharacterFallPresentation3D.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func run() -> void:
	var actor := Node3D.new()
	var visual := Node3D.new()
	actor.add_child(visual)
	root.add_child(actor)
	PRESENTATION.apply_hit(actor, visual, Vector3.BACK, 30.0)
	check(actor.has_meta("v2_hit_tween"), "First hit starts a reaction")
	var first: Tween = actor.get_meta("v2_hit_tween")
	first.custom_step(0.08)
	check(visual.rotation.x > 0.0, "First hit leans in the impact direction")
	PRESENTATION.apply_hit(actor, visual, Vector3.RIGHT, 30.0)
	check(not first.is_valid(), "Repeated hit cancels the previous reaction")
	check(visual.rotation.is_zero_approx(), "Interrupted hit restores the base pose")
	var second: Tween = actor.get_meta("v2_hit_tween")
	second.custom_step(0.4)
	check(visual.rotation.is_zero_approx(), "Completed reaction returns to rest")
	PRESENTATION.apply_fall(actor, visual, Vector3.RIGHT)
	check(not actor.has_meta("v2_hit_tween"), "Fall clears completed hit metadata")
	check(not actor.has_meta("v2_hit_base"), "Fall clears saved hit pose")
	actor.free()
	var fresh := Node3D.new()
	var fresh_visual := Node3D.new()
	fresh.add_child(fresh_visual)
	root.add_child(fresh)
	PRESENTATION.apply_fall(fresh, fresh_visual, Vector3.BACK)
	check(not fresh.has_meta("v2_hit_tween"), "Direct fall needs no previous hit")
	fresh.free()
	var civilian := preload("res://assets/CivilianModel.gd").new()
	var civilian_actor := Node3D.new()
	civilian_actor.add_child(civilian)
	root.add_child(civilian_actor)
	PRESENTATION.apply_hit(civilian_actor, civilian, Vector3.BACK, 30.0)
	PRESENTATION.apply_hit(civilian_actor, civilian, Vector3.RIGHT, 30.0)
	check(not civilian_actor.has_meta("v2_hit_tween"), "Civilian keeps its own hit spring")
	civilian_actor.free()
	await process_frame
	print("HIT_PRESENTATION checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
