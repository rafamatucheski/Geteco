extends SceneTree
## Lista quem projeta sombra perto do conector Harbor–Mountain (manchas quadradas no asfalto) e
## refaz a captura sem cada suspeito. Rodar com --no-save.
const OUTPUT := "res://evidence/bridge-water-0924/"
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")
var world
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func shot(label: String) -> void:
	await frames(2)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + label + ".png"))
func run() -> void:
	if not "--no-save" in OS.get_cmdline_user_args(): quit(2); return
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	current_scene = world
	for i in 1200:
		await process_frame
		if world.session != null and world.session.ready_for_play: break
	var weather = world.session.weather
	weather.weather_state = 0
	weather.weather_timer = 99999.0
	var point := Vector3(CONNECTION.HARBOR_CONNECTOR_X + 20.0, .2, CONNECTION.CENTER_Z)
	world.player.teleport(point)
	world.session.controller.region.set_focus(point)
	weather.time_of_day = .45
	await frames(300)
	var sun: DirectionalLight3D
	var omni_count := 0
	for node in world.find_children("*", "Light3D", true, false):
		if node is DirectionalLight3D: sun = node
		else: omni_count += 1
	print("LIGHTS sun=", sun != null, " others=", omni_count)
	if sun != null:
		sun.shadow_enabled = false
		await frames(10)
		await shot("sombra_sol_sem_sombra")
		sun.shadow_enabled = true
	for node in world.find_children("*", "Light3D", true, false):
		if node != sun: node.visible = false
	await frames(10)
	await shot("sombra_sem_outras_luzes")
	var camera := root.get_viewport().get_camera_3d()
	for screen in [Vector2(850, 250), Vector2(480, 20), Vector2(1400, 610), Vector2(700, 330)]:
		var origin := camera.project_ray_origin(screen)
		var direction := camera.project_ray_normal(screen)
		var hit: Variant = Plane(Vector3.UP, 0.03).intersects_ray(origin, direction)
		print("ALVO ", screen, " -> ", hit)
		if hit == null: continue
		for node in world.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree(): continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			if Vector2(hit.x, hit.z).distance_to(Vector2(box.get_center().x, box.get_center().z)) > 80.0: continue
			if box.grow(0.1).has_point(Vector3(hit.x, box.position.y + box.size.y * 0.5, hit.z)) and box.position.y < 1.0 and box.end.y > -0.3:
				var mat := mi.material_override if mi.material_override != null else mi.get_active_material(0)
				print("  MESH ", mi.get_path(), " y=[%.3f,%.3f] size=%s mat=%s" % [box.position.y, box.end.y, str(box.size), mat.resource_name if mat != null else "-"])
	print("DONE2")
	quit(0)
	var casters: Array[GeometryInstance3D] = []
	var stack: Array[Node] = [world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children(): stack.append(child)
		if node is GeometryInstance3D and node.visible and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and node.is_inside_tree():
			var center: Vector3 = node.global_transform * node.get_aabb().get_center()
			if Vector2(center.x - point.x, center.z - point.z).length() < 45.0 and center.y > 1.0 and not node is Light3D:
				casters.append(node)
				print("CASTER ", node.get_path(), " y=%.1f size=%s" % [center.y, str(node.get_aabb().size)])
	for index in casters.size():
		casters[index].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await frames(10)
	await shot("sombra_sem_todos")
	print("DONE ", casters.size())
	quit(0)
