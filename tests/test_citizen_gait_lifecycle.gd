extends SceneTree

const LIFE := preload("res://world/harbor/HarborLife.gd")
const COBRA := preload("res://world/harbor/cobras/CobraResident.gd")
const GAIT := preload("res://characters/pedestrians/CitizenGait.gd")
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func run() -> void:
	root.get_node("WantedManager").set_process(false)
	var budget := root.get_node("PresentationBudget")
	budget.set_process(false)
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var walker := LIFE.HarborWalker.new()
	walker.configure_authored_route(PackedVector2Array([Vector2.ZERO, Vector2(300, 0)]), "gait_lifecycle")
	walker.pause_at_destinations = false
	stage.add_child(walker)
	var cobra := COBRA.new()
	cobra.position = Vector2(0, 200)
	cobra.patrol = PackedVector2Array([Vector2(0, 200), Vector2(300, 200)])
	stage.add_child(cobra)
	var unbuilt_gait := GAIT.new()
	check(not unbuilt_gait.configure(walker, 0), "Unbuilt rig declines configuration without partial geometry")
	unbuilt_gait.apply_pose()
	for frame in 30: await physics_frame
	check(walker.viewport == null and walker.gait == null, "Deferred walker runs physics while awaiting presentation")
	check(cobra.viewport == null and cobra.gait == null, "Deferred Cobra runs physics while awaiting presentation")
	check(walker.position.x > 5.0 and cobra.position.x > 5.0, "Both citizens physically walk without a 3D rig")
	for actor in [walker, cobra]:
		actor.ensure_presentation()
		check(actor.gait != null and actor.gait.feet.size() == 2, "Building presentation installs complete gait: " + actor.name)
		actor.gait.advance(0.5, 1.0, false)
		actor.gait.apply_pose()
		check(absf(actor.left_lower_leg.rotation.x) > 0.01, "Real rig animates after deferred construction: " + actor.name)
		var old_foot: Node3D = actor.gait.feet[0]
		check(actor.gait.configure(actor, 1) and actor.gait.feet[0] == old_foot, "Reconfiguration reuses articulated feet: " + actor.name)
	for frame in 30: await physics_frame
	check(cobra.get_node_or_null("NPCCombatRig") != null, "Cobra keeps its role weapon after deferred presentation")
	stage.queue_free()
	await process_frame
	await process_frame
	print("CITIZEN_GAIT_LIFECYCLE failures=%d" % failures)
	quit(0 if failures == 0 else 1)
