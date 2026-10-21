extends SceneTree

const CAMERA := preload("res://scripts/CameraRig.gd")
const MODE := preload("res://runtime/DeveloperMode.gd")
const PANEL := preload("res://ui/DeveloperPanel.gd")

class Gameplay extends Node:
	var god_mode := false
	func scope_active() -> bool: return false

class Session extends Node:
	var ready_for_play := true

class Production extends Node:
	var no_save := true
	var region: Node3D

class World extends Node3D:
	var camera: Camera3D
	var player: CharacterBody3D
	var gameplay: Node
	var session: Node
	var production: Node
	var hud: Control

var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	print("DEV_ZOOM ", "PASS " if value else "FAIL ", label)
	if not value: failures.append(label)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	create_timer(180, true).timeout.connect(func(): quit(3))
	var world := World.new()
	root.add_child(world)
	world.player = CharacterBody3D.new()
	world.gameplay = Gameplay.new()
	world.session = Session.new()
	world.production = Production.new()
	world.hud = Control.new()
	for node in [world.player, world.gameplay, world.session, world.production, world.hud]: world.add_child(node)
	world.camera = CAMERA.new()
	world.camera.target = world.player
	world.add_child(world.camera)
	var tools = MODE.new()
	tools.world = world
	world.add_child(tools)
	var camera = world.camera
	camera.set_process(false)
	await process_frame
	camera._process(1.0 / 60.0)
	var distant_mesh := MeshInstance3D.new()
	distant_mesh.mesh = BoxMesh.new()
	distant_mesh.visibility_range_end = 100.0
	world.add_child(distant_mesh)
	var normal_far: float = camera.far
	tools.set_camera_zoom(1000, 0)
	check(camera.developer_zoom == 1, "zoom requires developer mode")
	check(tools.set_active(true), "developer mode enables")
	tools.set_camera_zoom(1000, 1)
	camera._process(1.0 / 60.0)
	check(distant_mesh.visibility_range_end == 100.0, "overview preserves authored range for chunk merging")
	check(tools.overview._instances.has(distant_mesh.get_instance_id()), "overview overrides existing geometry render range")
	var late_mesh := MeshInstance3D.new()
	late_mesh.mesh = BoxMesh.new()
	late_mesh.visibility_range_end = 75.0
	world.add_child(late_mesh)
	await process_frame
	await process_frame
	check(tools.overview._instances.has(late_mesh.get_instance_id()), "newly streamed geometry inherits overview range")
	check(camera.developer_zoom == 1000, "extreme 1000x zoom")
	check(camera.size > 10000 and camera.far > camera.size, "extreme view expands framing and clipping range")
	check(camera.global_basis.z.dot(Vector3.UP) > .99, "top view looks down")
	for view in 3:
		tools.set_camera_zoom(25, view)
		camera._process(1.0 / 60.0)
		check(camera.projection == (Camera3D.PROJECTION_PERSPECTIVE if view == 2 else Camera3D.PROJECTION_ORTHOGONAL), "projection mode %d" % view)
		check(camera.global_transform.is_finite(), "finite camera transform %d" % view)
	tools.set_camera_zoom(INF, 0)
	check(camera.developer_zoom == 25, "nonfinite zoom rejected")
	tools.set_camera_zoom(2000, 0)
	check(camera.developer_zoom == 1000, "zoom upper bound")
	tools.reset_camera_zoom()
	camera._process(1.0 / 60.0)
	check(not tools.overview.is_processing() and tools.overview._instances.is_empty(), "reset releases range overrides and loop")
	check(camera.developer_zoom == 1 and is_equal_approx(camera.far, normal_far), "reset restores normal camera")
	tools.set_camera_zoom(100, 2)
	check(tools.set_active(false), "developer mode disables safely")
	camera._process(1.0 / 60.0)
	check(camera.developer_zoom == 1 and camera.projection == Camera3D.PROJECTION_ORTHOGONAL, "disable restores gameplay projection")
	var cells_script := preload("res://world/regions/DeveloperViewCells.gd")
	var selected := cells_script.select_cells(Rect2(-100000,-100000,200000,200000), Rect2(-96,-96,192,192), 96)
	check(selected.size() == 4, "extreme views stop at authored world bounds")
	for script in [preload("res://world/regions/NativeRegion.gd"), preload("res://world/desert/DesertRegion.gd")]:
		var region = script.new()
		region.records = {Vector2i.ZERO: [], Vector2i(8,2): []}
		region.current_cell = Vector2i.ZERO
		var rect := Rect2(0,0,640,192) if region.region_id != "desert" else Rect2(-960,-1152,640,192)
		region.set_developer_view(rect, true)
		check(region.developer_view_cells.size() > 9 and region.pending.size() > 9, "view queues beyond physical neighbours: " + region.region_id)
		var count: int = region.pending.size()
		region.set_developer_view(rect, true)
		check(region.pending.size() == count, "repeat view does not duplicate requests: " + region.region_id)
		region.set_developer_view(Rect2(100000,100000,1,1), true, true)
		check(region.developer_view_cells.size() > 20, "full map ignores the camera footprint: " + region.region_id)
		region.set_developer_view(Rect2(), false)
		check(region.developer_view_cells.is_empty() and region.pending.size() <= 9, "reset cancels distant requests: " + region.region_id)
		region.free()
	print("DEV_ZOOM_RESULT ", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
