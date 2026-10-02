extends SceneTree
## Two finite 30 s samples in one warmed production world. Geometry-only diagnostic.
const CATALOG := preload("res://world/places/PlaceCatalog.gd")
var world
var yard: Node3D
var duplicate: Node3D
var final_bodies: Array[StaticBody3D] = []
var old_bodies: Array[StaticBody3D] = []
var ground_materials: Array[ShaderMaterial] = []
var final_shader: Shader
var reports: Array[Dictionary] = []
var frozen_count := 0
var folder := "D:/geteco/artifacts/mountain-review-1001/sawmill-controlled-depth"
func _initialize() -> void: run.call_deferred()
func frames(count: int) -> void:
	for i in count: await process_frame
func freeze_tree(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	frozen_count += 1
	for child in node.get_children(): freeze_tree(child)
func legacy_ground() -> void:
	duplicate = Node3D.new()
	duplicate.name = "DiagnosticLegacyOpaqueCopies"
	yard.get_parent().add_child(duplicate)
	duplicate.transform = yard.transform
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("382e22")
	material.roughness = .86
	for polygon in [PackedVector2Array([Vector2(-180,-110),Vector2(180,-110),Vector2(200,130),Vector2(-170,140)]),PackedVector2Array([Vector2(-35,-165),Vector2(35,-165),Vector2(55,-100),Vector2(-55,-100)])]:
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in Geometry2D.triangulate_polygon(polygon):
			var point: Vector2 = polygon[index]/16.0
			surface.add_vertex(Vector3(point.x,.024,point.y))
		surface.generate_normals()
		var mesh := MeshInstance3D.new()
		mesh.mesh = surface.commit()
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		duplicate.add_child(mesh)
		mesh.create_trimesh_collision()
		for body in mesh.get_children():
			if body is StaticBody3D:
				body.collision_mask = 0
				old_bodies.append(body)
func set_variant(before: bool) -> void:
	duplicate.visible = before
	for body in old_bodies: body.collision_layer = 1 if before else 0
	for body in final_bodies: body.collision_layer = 0 if before else 1
	for material in ground_materials:
		material.shader = preload("res://world/regions/natural_ground.gdshader") if before else final_shader
func sample(variant: String) -> void:
	# Warm every shader/material combination after the toggle, outside the sample.
	var warm := Time.get_ticks_usec()
	while Time.get_ticks_usec()-warm<5000000: await process_frame
	# Capture outside the timing window; a process_frame has already drawn.
	root.get_texture().get_image().save_png(folder.path_join(variant+".png"))
	await frames(5)
	var values: Array[float] = []
	var began := Time.get_ticks_usec()
	var previous := began
	while Time.get_ticks_usec()-began<30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		values.append(float(now-previous)/1000.0)
		previous = now
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	var over33 := 0
	var over66 := 0
	for value in values:
		total += value
		if value>33.3: over33 += 1
		if value>66.7: over66 += 1
	var report := {"variant":variant,"frames":values.size(),"duration_ms":total,"fps":values.size()*1000.0/total,"p50_ms":sorted[int((sorted.size()-1)*.5)],"p95_ms":sorted[int((sorted.size()-1)*.95)],"p99_ms":sorted[int((sorted.size()-1)*.99)],"max_ms":sorted[-1],"over33":over33,"over66":over66,"samples_ms":values}
	var file := FileAccess.open(folder.path_join(variant+".json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report))
	file.close()
	report.erase("samples_ms")
	reports.append(report)
	print("SAWMILL_CONTROLLED ",JSON.stringify(report))
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(folder)
	root.size = Vector2i(1280,720)
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival",true)
	root.add_child(world)
	for i in 1800:
		await process_frame
		if world.session!=null and world.session.ready_for_play: break
	if world.session==null or not world.session.ready_for_play: push_error("Sawmill diagnostic did not boot"); quit(1); return
	world.production.set_process(false)
	world.player.set_physics_process(false)
	world.camera.set_process(false)
	world.camera.set_process_unhandled_input(false)
	var point: Vector3 = CATALOG._at(Vector2(6350,560),"mountain")
	world.production._update_physical_residency(point)
	world.production._update_logical_region(point)
	world.production.region.set_focus(point)
	world.player.teleport(point+Vector3(4.4,.05,-4))
	world.camera.locked = true
	world.camera.size = 36
	world.camera.global_position = point+Vector3(0,34,24)
	world.camera.look_at(point)
	world.camera.make_current()
	world.hud.hide()
	world.session.weather.time_of_day = .5
	world.session.weather.weather_state = 0
	world.session.weather._update()
	world.session.weather.set_process(false)
	var started := Time.get_ticks_usec()
	while not world.production.region.is_streaming_idle() or not world.production.region._retiring.is_empty():
		await process_frame
		if Time.get_ticks_usec()-started>60000000: push_error("Sawmill diagnostic streaming did not settle"); quit(1); return
	await frames(10)
	yard = world.production.region.find_child("SawmillYard3D",true,false)
	if yard==null: push_error("Sawmill diagnostic missing live yard"); quit(1); return
	for name in ["OriginalSawmillYard","OriginalSawmillDriveway"]:
		var mesh: MeshInstance3D = yard.get_node(name)
		var ground: ShaderMaterial = mesh.material_override
		if not ground in ground_materials: ground_materials.append(ground)
		final_shader = ground.shader
		for body in mesh.get_children():
			if body is StaticBody3D: final_bodies.append(body)
	if final_bodies.size()!=2: push_error("Sawmill diagnostic requires two authoritative ground bodies"); quit(1); return
	legacy_ground()
	freeze_tree(world)
	print("SAWMILL_CONTROLLED_SETUP frozen_nodes=",frozen_count," streaming_idle=",world.production.region.is_streaming_idle()," camera=",world.camera.global_transform)
	set_variant(true)
	await sample("before")
	set_variant(false)
	await sample("after")
	var result := {"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"resolution":[root.size.x,root.size.y],"vsync":DisplayServer.window_get_vsync_mode(),"max_fps":Engine.max_fps,"frozen_nodes":frozen_count,"comparison":"Same final production world, fixed camera/weather/population/poses; all scene scripts and animators frozen after streaming and retirement became idle. Before restores the original two opaque coplanar copies and original transparent shader. After uses the single authoritative shader ground with its local cached depth_prepass_alpha variant. Floor collision ownership switches accordingly. Two 30 s samples with 5 s warm-up each. Geometry/material-only diagnostic; not a normal live-NPC gameplay performance certificate.","scenarios":reports}
	var file := FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	world.free()
	await frames(5)
	quit()
