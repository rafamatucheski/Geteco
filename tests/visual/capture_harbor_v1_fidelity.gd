extends SceneTree

## Productive V1 visual reference for the authored centres used by the V2
## fidelity capture. HarborPreview avoids loading any personal save.

const OUTPUT_ROOT := "C:/Users/rafae/.codex/visualizations/2026/09/21/01a0c5d4-0aa6-7ba0-819f-d0c3afa28d07/harbor-fidelity"

var preview: Node2D
var camera: Camera2D
var restaurants: Node2D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(OUTPUT_ROOT)
	root.size = Vector2i(1600, 900)
	root.content_scale_size = Vector2i(1600, 900)
	preview = load("res://world/harbor/HarborPreview.tscn").instantiate()
	root.add_child(preview)
	current_scene = preview
	var cemetery := preload("res://world/harbor/HarborCemetery.gd").new()
	cemetery.name = "FidelityCemetery"
	cemetery.position = Vector2(-650, 1740)
	preview.add_child(cemetery)
	var yard := preload("res://cars/ChopShopZone.gd").new()
	yard.name = "FidelityChopShop"
	yard.position = Vector2(-750, 550)
	preview.add_child(yard)
	restaurants = preload("res://world/harbor/restaurants/HarborRestaurantLife.gd").new()
	restaurants.name = "FidelityRestaurants"
	preview.add_child(restaurants)
	var sewer := preload("res://world/harbor/sewer/HarborManholeSewer.gd").new()
	sewer.name = "FidelitySewer"
	sewer.position = Vector2(1182, 2114)
	preview.add_child(sewer)
	camera = preview.get_node("OverviewCamera")
	camera.make_current()
	for frame in 120:
		await process_frame
	var shots: Array[Dictionary] = [
		{"id":"ammunation", "center":Vector2(1550, 140), "zoom":1.20},
		{"id":"northstar", "center":Vector2(3570, 1500), "zoom":0.55},
		{"id":"south_port", "center":Vector2(4750, 4450), "zoom":0.36},
		{"id":"salvage", "center":Vector2(-750, 550), "zoom":0.80},
		{"id":"cemetery", "center":Vector2(-650, 1740), "zoom":0.70},
		{"id":"cobra", "center":Vector2(7700, 1700), "zoom":0.50},
		{"id":"access_port_boss", "center":Vector2(5515, 5870), "zoom":1.00},
		{"id":"access_sewer", "center":Vector2(1182, 2114), "zoom":1.65},
		{"id":"restaurant_anchor", "center":Vector2(620, 1132), "zoom":1.55},
		{"id":"restaurant_tideline", "center":Vector2(5790, 1644), "zoom":1.55},
		{"id":"restaurant_early_shift", "center":Vector2(6200, -1238), "zoom":1.55},
	]
	for shot in shots:
		await _capture(shot)
	quit(0)

func _capture(shot: Dictionary) -> void:
	var point: Vector2 = shot.center
	restaurants.update_context(12.25, 0.0, point, 1.0)
	camera.position = point
	camera.zoom = Vector2.ONE * float(shot.zoom)
	camera.reset_physics_interpolation()
	for frame in 8:
		restaurants.update_context(12.25, 0.0, point, 0.08)
		await process_frame
	await RenderingServer.frame_post_draw
	var path := "%s/v1-%s.png" % [OUTPUT_ROOT, str(shot.id)]
	var result := root.get_texture().get_image().save_png(path)
	assert(result == OK)
	print("HARBOR_V1_FIDELITY_CAPTURE ", path)
