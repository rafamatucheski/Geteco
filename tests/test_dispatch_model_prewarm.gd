extends SceneTree
## Production prewarm helper + real fleet decorators/cache. Visual equivalence and
## runtime spawn/lighting remain required integration; this fixture does not prove FPS.
const COLD := preload("res://runtime/ProductionWorld.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const PASS := preload("res://runtime/FleetSpeedPass.gd")
const RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	print("DISPATCH_MODEL_PREWARM ", "PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("DISPATCH_MODEL_PREWARM requires --no-save")
		quit(2)
		return
	var cold = COLD.new()
	root.add_child(cold)
	cold.set_process(false)
	var child_count := cold.get_child_count()
	var helper_exists: bool = cold.has_method("_prewarm_dispatch_models")
	check(helper_exists, "production loading has explicit decorated-model warm-up")
	if not helper_exists:
		cold.free()
		quit(1)
		return
	await cold.call("_prewarm_dispatch_models")
	check(cold.get_child_count() == child_count, "prewarm leaves no live model under controller")
	for id in RULES.ARCHETYPES.values():
		check(PASS._plans.has(id), "existing merge plan is warm for %s" % id)
		var plan: Array = PASS._plans.get(id, [])
		var meshes: Array = []
		for step in plan: meshes.append(step.mesh)
		var model: Node3D = FLEET.create(str(id))
		check(model != null, "normal production fleet creation still succeeds for %s" % id)
		if model == null: continue
		var reused := true
		var parts := model.find_children("*", "MeshInstance3D", true, false)
		for mesh in meshes:
			var found := false
			for part in parts:
				if is_same(part.mesh, mesh): found = true
			reused = reused and found
		check(reused, "normal creation reuses warmed merged mesh resources/%s" % id)
		model.free()
	check(cold.get_child_count() == child_count, "fixture leaves no live dispatch vehicle")
	cold.free()
	print("DISPATCH_MODEL_PREWARM checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
