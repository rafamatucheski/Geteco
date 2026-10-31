extends Node
## Um render serial, de uso único, do kit de roda real. Sem viewports persistentes.
signal texture_ready(design: String)
const KIT := preload("res://gameplay/desert_cars/TuningWheelKit.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
var _cache: Dictionary = {}
var _queue: Array[String] = []
var _requested: Dictionary = {}
var _busy := false

func texture_for(design: String) -> Texture2D:
	if _cache.has(design): return _cache[design]
	if DisplayServer.get_name() != "headless" and not _requested.has(design):
		_requested[design] = true
		_queue.append(design)
		if not _busy: _render_next.call_deferred()
	return null

func _render_next() -> void:
	if _busy or _queue.is_empty(): return
	_busy = true
	var design: String = _queue.pop_front()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(116,100)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var wheel: Node3D = _stock_wheel(design.trim_prefix("stock:")) if design.begins_with("stock:") else KIT.build(design,.5,Color("d4dadd"))
	viewport.add_child(wheel)
	var camera := Camera3D.new()
	camera.position = Vector3(2.0,.32,1.0)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.25
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0,0,0,0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .95
	var studio := ProceduralSkyMaterial.new()
	studio.sky_top_color = Color("d9dfe3")
	studio.sky_horizon_color = Color("aebbc4")
	studio.ground_horizon_color = Color("aebbc4")
	studio.ground_bottom_color = Color("79848c")
	var sky := Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.sky_material = studio
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	camera.environment = environment
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.position = Vector3(2.5,2.0,2.0)
	light.light_energy = 2.0
	viewport.add_child(light)
	light.look_at(Vector3.ZERO)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not is_instance_valid(viewport): return
	var rendered := viewport.get_texture().get_image()
	if rendered != null and not rendered.is_empty(): _cache[design] = ImageTexture.create_from_image(rendered)
	viewport.queue_free()
	_busy = false
	texture_ready.emit(design)
	if not _queue.is_empty(): _render_next.call_deferred()

func is_ready() -> bool:
	return not _busy and _queue.is_empty()

func _stock_wheel(archetype: String) -> Node3D:
	var root := Node3D.new()
	var source: Node3D = FLEET.create(archetype)
	if source == null: return root
	var center := Vector3.ZERO
	var found := false
	for part: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		if part.mesh != null and part.has_meta("wheel_center") and part.get_meta("wheel_spins",true):
			var candidate: Vector3 = part.get_meta("wheel_center")
			if not found or candidate.x > center.x:
				center = candidate
				found = true
	var radius := 0.0
	for part: MeshInstance3D in source.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or not part.has_meta("wheel_center") or part.get_meta("wheel_center") != center: continue
		if not part.get_meta("wheel_spins",true): continue
		var copy := part.duplicate(0) as MeshInstance3D
		var transform := part.transform
		var ancestor := part.get_parent() as Node3D
		while ancestor != null and ancestor != source:
			transform = ancestor.transform * transform
			ancestor = ancestor.get_parent() as Node3D
		copy.transform = transform
		copy.position -= center
		root.add_child(copy)
		var bounds: AABB = copy.transform * copy.mesh.get_aabb()
		radius = maxf(radius,maxf(bounds.size.y,bounds.size.z)*.5)
	if radius > .001: root.scale = Vector3.ONE*(.5/radius)
	source.free()
	return root
