extends SceneTree

const VIEW := preload("res://world/mountain_pass/MountainStaticModelView.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var view := VIEW.new()
	view.model = Node3D.new()
	view.model.name = "StaticUnitModel"
	var visible_a := _unit("VisibleA", true)
	var visible_b := _unit("VisibleB", true)
	var authored_hidden := _unit("AuthoredHidden", false)
	view.model.add_child(visible_a)
	view.model.add_child(visible_b)
	view.model.add_child(authored_hidden)

	view._capture_prepare_units()
	_check(view._prepare_unit_total == 2, "only authored-visible VisualInstance3D nodes become warmup units")
	_check(view._prepare_unit_visibility.size() == 3, "visibility snapshot includes authored-hidden units")

	view._hide_prepare_units_except(visible_a)
	_check(visible_a.visible and not visible_b.visible and not authored_hidden.visible, "one warmup slice exposes exactly one authored-visible unit")
	view._hide_prepare_units_except(visible_b)
	_check(not visible_a.visible and visible_b.visible and not authored_hidden.visible, "next slice hides the prior unit before exposing the next")

	view._restore_prepare_visibility()
	_check(visible_a.visible and visible_b.visible, "atomic restore returns authored-visible units")
	_check(not authored_hidden.visible, "atomic restore never exposes an authored-hidden unit")
	view._clear_prepare_units(true)
	_check(view._prepare_units.is_empty() and view._prepare_unit_visibility.is_empty(), "cleanup releases unit references after restoring visibility")

	print("MOUNTAIN_STATIC_RENDER_UNIT_CONTRACT ", JSON.stringify({
		"failures": failures,
		"active_units": 2,
		"authored_hidden_preserved": not authored_hidden.visible,
		"restored_visible": visible_a.visible and visible_b.visible,
	}))
	view.model.free()
	view.model = null
	view.free()
	quit(1 if not failures.is_empty() else 0)


func _unit(unit_name: String, unit_visible: bool) -> MeshInstance3D:
	var unit := MeshInstance3D.new()
	unit.name = unit_name
	unit.mesh = BoxMesh.new()
	unit.visible = unit_visible
	return unit


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
