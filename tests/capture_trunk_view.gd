extends SceneTree
## Visual-only evidence for res://runtime/TrunkView.gd on the real baked
## Monaliza model. Run with a real renderer (not --headless).
class ProxyCar extends Node3D:
	var visual: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	root.size = Vector2i(1400, 900)
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("30363a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("aab0ad")
	environment.ambient_light_energy = 0.55
	world_environment.environment = environment
	root.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 0.9
	root.add_child(sun)

	var car := preload("res://runtime/FleetCatalog.gd").create("monaliza")
	# FleetCatalog.create() returns the visual root directly; TrunkView only
	# reads car.visual, so a tiny proxy stands in for the real Vehicle.gd.
	var proxy := ProxyCar.new()
	proxy.add_child(car)
	root.add_child(proxy)
	proxy.visual = car

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 55
	camera.near = 0.05
	camera.far = 100.0
	root.add_child(camera)
	camera.make_current()

	var trunk_view_script := preload("res://runtime/TrunkView.gd")
	var focus: Vector3 = trunk_view_script.TRAY_CENTER + Vector3(0, 0.05, 0)
	camera.global_position = focus + Vector3(2.6, 2.3, 3.1)
	camera.look_at(focus)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png("res://evidence/trunk-view-closed-reference.png") == OK)
	print("TRUNK_VIEW_CAPTURE closed-reference")

	var view = trunk_view_script.new()
	root.add_child(view)
	view.open(proxy, null)
	view.update_loadout({"curta": "pistol", "longa": "ak47", "corpo": "knife", "granada": "grenade"})
	for frame in 90: await process_frame

	# The loadout tray rises LIFT_HEIGHT clear of the car on open (see
	# TrunkView's comment on why: the baked model has no real trunk cavity to
	# reveal), so frame the risen tray, not the closed deck.
	var risen_focus: Vector3 = focus + Vector3(0, trunk_view_script.LIFT_HEIGHT, 0)
	camera.global_position = risen_focus + Vector3(0.9, 0.55, 1.15)
	camera.look_at(risen_focus)
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var out := "res://evidence/trunk-view-open-filled.png"
	assert(root.get_texture().get_image().save_png(out) == OK)
	print("TRUNK_VIEW_CAPTURE ", ProjectSettings.globalize_path(out))

	view.update_loadout({"curta": "", "longa": "", "corpo": "", "granada": ""})
	for frame in 10: await process_frame
	await RenderingServer.frame_post_draw
	var out2 := "res://evidence/trunk-view-open-empty.png"
	assert(root.get_texture().get_image().save_png(out2) == OK)
	print("TRUNK_VIEW_CAPTURE ", ProjectSettings.globalize_path(out2))

	view.close()
	for frame in 5: await process_frame
	await RenderingServer.frame_post_draw
	var out3 := "res://evidence/trunk-view-closed-after.png"
	assert(root.get_texture().get_image().save_png(out3) == OK)
	print("TRUNK_VIEW_CAPTURE ", ProjectSettings.globalize_path(out3))
	quit(0)
