extends SceneTree

const RAIN := preload("res://world/harbor/HarborRainPuddles.gd")
const BUILDING := preload("res://world/harbor/HarborBuilding.gd")
var failures := 0

class Weather extends CanvasModulate:
	var intensity := 0.0
	var is_dark := false
	func get_rain_intensity() -> float: return intensity
	func is_raining() -> bool: return intensity > 0.0

class Roads extends Node2D:
	var _roads: Array[Dictionary] = [
		{"points": PackedVector2Array([Vector2(-800, 140), Vector2(20000, 140)]), "width": 96.0},
		{"points": PackedVector2Array([Vector2(-800, 320), Vector2(20000, 320)]), "width": 62.0},
		{"points": PackedVector2Array([Vector2(-800, 500), Vector2(20000, 500)]), "width": 120.0},
	]

func _initialize() -> void: run.call_deferred()

func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ") + label)
	if not value: failures += 1

func run() -> void:
	var world := Node2D.new()
	world.position = Vector2(70, 30)
	root.add_child(world)
	current_scene = world
	var weather := Weather.new()
	world.add_child(weather)
	weather.add_to_group("day_night_manager")
	var roads := Roads.new()
	roads.name = "RoadNetwork"
	roads.position = Vector2(13, 20)
	world.add_child(roads)
	var rain := RAIN.new()
	world.add_child(rain)
	rain.set_process(false)
	rain._rng.seed = 12345
	var camera := Camera2D.new()
	world.add_child(camera)
	camera.position = Vector2(125, 0)
	camera.zoom = Vector2.ONE * 2.6
	camera.make_current()
	await process_frame
	rain._process(30)
	check(rain.get_child_count() == 0, "Clear weather creates no puddles")
	weather.intensity = 0.8
	for i in 4: rain._process(0.25)
	var initially_hidden := true
	for puddle in rain.get_children(): initially_hidden = initially_hidden and not puddle.visible
	check(initially_hidden, "Rain starts without instantly visible puddles")
	for i in 36: rain._process(0.25)
	var growing := rain.get_child(0)
	var early_scale: Vector2 = growing.scale
	var early_alpha: float = growing.modulate.a
	for i in 80: rain._process(0.25)
	check(growing.scale.length() > early_scale.length() and growing.modulate.a > early_alpha, "Puddles gradually expand and deepen over sustained rainfall")
	var accumulated: float = rain.wetness
	weather.intensity = 0.2
	rain._process(0.25)
	check(rain.wetness >= accumulated, "Weaker rainfall retains accumulated water")
	weather.intensity = 0.8
	check(rain.get_child_count() > 20 and rain.get_child_count() <= 96, "Rain creates a bounded population")
	var first_layout: Array[Vector2] = []
	var ids: Array[int] = []
	var nearby: Area2D
	var all_on_asphalt := true
	for puddle in rain.get_children():
		first_layout.append(puddle.global_position)
		ids.append(puddle.get_instance_id())
		if puddle.visible: nearby = puddle
		var local: Vector2 = roads.to_local(puddle.global_position)
		var inside := false
		for road in roads._roads:
			if absf(local.y - road.points[0].y) + puddle.scale.y * puddle.puddle_radius.y * 1.13 <= road.width * 0.5:
				inside = true
		all_on_asphalt = all_on_asphalt and inside
	check(all_on_asphalt, "Water footprints stay on asphalt, including narrow roads")
	check(nearby != null and nearby.monitoring, "Nearby rain puddles render and trigger splashes")
	rain._process(2)
	check(first_layout[0] == rain.get_child(0).global_position, "Puddles stay in place during the same storm")
	weather.intensity = 0.0
	var alpha_before: float = nearby.modulate.a
	rain._process(0.25)
	check(nearby.modulate.a <= alpha_before and not nearby.monitoring, "Sun fades the water and stops splash detection")
	for i in 8: rain._process(0.25)
	var dry := true
	for puddle in rain.get_children():
		dry = dry and not puddle.visible and not puddle.monitoring and not puddle.is_processing()
	check(dry and is_zero_approx(rain.wetness), "All puddles disappear within two seconds of clear weather")
	weather.intensity = 1.0
	for i in 60: rain._process(0.25)
	var changed := 0
	var reused := true
	for i in rain.get_child_count():
		if not first_layout[i].is_equal_approx(rain.get_child(i).global_position): changed += 1
		reused = reused and rain.get_child(i).get_instance_id() == ids[i]
	check(changed > rain.get_child_count() / 2, "Next storm has a new random distribution")
	check(reused, "Repeated storms reuse the bounded pool")
	weather.intensity = 0.0
	rain._process(3)
	weather.intensity = 0.05
	for i in 20: rain._process(0.25)
	check(rain.wetness > 0.0, "Light rain can accumulate water")
	weather.intensity = 0.0
	rain._process(3)
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(1280, 720)
		root.content_scale_size = root.size
		RenderingServer.set_default_clear_color(Color("#777e75"))
		for spec in [["CornerDiner", Vector2.ZERO, Vector2(210,160), "corner_shop"], ["Laundry", Vector2(240,0), Vector2(170,150), "commercial_laundromat"]]:
			var building := BUILDING.new()
			building.name = spec[0]
			building.position = spec[1]
			building.footprint = spec[2]
			building.building_kind = spec[3]
			world.add_child(building)
		for mode in ["day", "night", "rain"]:
			weather.is_dark = mode == "night"
			weather.intensity = 1.0 if mode == "rain" else 0.0
			weather.color = Color("#818fa6") if mode == "night" else (Color("#a2afb9") if mode == "rain" else Color.WHITE)
			for node in get_nodes_in_group("procedural_building"): node.queue_redraw()
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/geteco/artifacts/shopfronts-" + mode + ".png")
	world.queue_free()
	await process_frame
	print("SHOPFRONT RAIN CYCLE failures=", failures)
	quit(0 if failures == 0 else 1)
