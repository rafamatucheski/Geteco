extends SceneTree
## Rendered functional contract, no gameplay simulation or saved-state writes.
const WARM = preload("res://gameplay/emergency/PoliceVisualPrewarm.gd")
const APPEARANCES = preload("res://gameplay/PoliceAppearance.gd")
var failures: Array[String] = []
var checks := 0
var output := "user://police-visual-prewarm-functional.json"

class LoadingProduction extends RefCounted:
	var ready_for_play := false

class Host extends Node3D:
	var camera: Camera3D
	var production := LoadingProduction.new()

class Cover extends CanvasLayer:
	var stage_only := false
	var _root: Control
	func _ready() -> void:
		layer = 120
		var ink := ColorRect.new()
		ink.color = Color.BLACK
		_root = ink
		_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_root)

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func identity_and_groups() -> Dictionary:
	return {"identity": APPEARANCES.next_model, "police": get_nodes_in_group("v2_police_officers").size(),
		"damageable": get_nodes_in_group("v2_damageable").size()}

func tree_nodes() -> Array[int]:
	var ids: Array[int] = []
	for node in root.find_children("*", "Node", true, false): ids.append(node.get_instance_id())
	ids.sort()
	return ids

func assert_clean(host: Node, expected: Dictionary, nodes: Array[int], label: String) -> void:
	check(identity_and_groups() == expected, label + " preserves appearance sequence and gameplay groups")
	check(host.get_node_or_null("PoliceVisualPrewarm") == null, label + " removes temporary presentation")
	check(tree_nodes() == nodes, label + " leaves no new scene-tree nodes")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out-path="): output = arg.trim_prefix("--out-path=")
	if DisplayServer.get_name() == "headless" or not ClassDB.class_exists(&"CSharpScript"):
		push_error("Requires rendered Godot .NET")
		quit(2)
		return
	create_timer(30.0).timeout.connect(func(): push_error("Warmer functional timeout"); quit(3))
	var host := Host.new()
	root.add_child(host)
	host.camera = Camera3D.new()
	host.add_child(host.camera)
	host.camera.position = Vector3(0, 4, 9)
	host.camera.look_at(Vector3(0, 1, 0))
	host.camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	host.camera.size = 20.030914
	host.camera.make_current()
	var cover := Cover.new()
	root.add_child(cover)
	await process_frame
	var expected := identity_and_groups()
	var nodes := tree_nodes()
	var initial_draw_connections := RenderingServer.frame_post_draw.get_connections().size()
	WARM._drawn = false
	cover.hide()
	await WARM.run(host, cover)
	check(not WARM._drawn, "uncovered scene is not marked prepared")
	assert_clean(host, expected, nodes, "uncovered skip")
	cover.show()
	var other_camera := Camera3D.new()
	root.add_child(other_camera)
	other_camera.make_current()
	var camera_nodes := tree_nodes()
	await WARM.run(host, cover)
	check(not WARM._drawn, "non-current production camera is not marked prepared")
	assert_clean(host, expected, camera_nodes, "camera skip")
	other_camera.free()
	host.camera.make_current()
	# Cancela no primeiro yield real, depois que os modelos temporários foram criados.
	process_frame.connect(cover.hide, CONNECT_ONE_SHOT)
	await WARM.run(host, cover)
	check(not WARM._drawn, "losing coverage cancels preparation")
	assert_clean(host, expected, nodes, "coverage cancellation")
	cover.show()
	var destroyed_host := Host.new()
	root.add_child(destroyed_host)
	destroyed_host.camera = Camera3D.new()
	destroyed_host.add_child(destroyed_host.camera)
	destroyed_host.camera.position = Vector3(0, 4, 9)
	destroyed_host.camera.look_at(Vector3(0, 1, 0))
	destroyed_host.camera.make_current()
	process_frame.connect(destroyed_host.free, CONNECT_ONE_SHOT)
	await WARM.run(destroyed_host, cover)
	check(not is_instance_valid(destroyed_host), "cancellation fixture actually deletes its host")
	check(not WARM._drawn, "deleted host is not marked prepared")
	check(identity_and_groups() == expected, "deleted host preserves identity and gameplay groups")
	check(tree_nodes() == nodes, "deleted host leaves no new scene-tree nodes")
	check(RenderingServer.frame_post_draw.get_connections().size() == initial_draw_connections, "cancelled warmer disconnects draw callback")
	host.camera.make_current()
	# No other fixture actor consumes global randomness; never reseed production.
	seed(771992)
	var expected_next := randi()
	seed(771992)
	await WARM.run(host, cover)
	var actual_next := randi()
	check(actual_next == expected_next, "covered preparation preserves global RNG state")
	check(WARM._drawn, "covered active-camera preparation completes actual draws")
	check(WARM._flash_material != null, "retains only required flash material")
	assert_clean(host, expected, nodes, "successful preparation")
	seed(991227)
	expected_next = randi()
	seed(991227)
	var started := Time.get_ticks_usec()
	await WARM.run(host, cover)
	var reentry_usec := Time.get_ticks_usec()-started
	check(randi() == expected_next, "prepared reentry preserves global RNG state")
	check(WARM._drawn, "prepared reentry preserves completion")
	assert_clean(host, expected, nodes, "prepared reentry")
	var final_identity := APPEARANCES.next_model
	host.free()
	cover.free()
	await process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: push_error("Could not save functional result"); quit(4); return
	file.store_string(JSON.stringify({"checks": checks, "failures": failures, "identity_before": expected.identity,
		"identity_after": final_identity, "reentry_usec": reentry_usec, "renderer": RenderingServer.get_current_rendering_method(),
		"msaa": root.msaa_3d, "scope": "Guard, RNG, identity, scene-tree cleanup and actual-draw contract in a controlled rendered host; not an FPS or flicker certification."}, "\t"))
	print("POLICE_VISUAL_PREWARM ", checks, " checks failures=", failures, " output=", output)
	quit(0 if failures.is_empty() else 1)
