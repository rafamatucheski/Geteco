extends Node
## One atlas per casualty, never one viewport per limb. Render only while
## tumbling; settled fragments retain the last texture without render work.
const MESHES := preload("res://guns/combat/BodyFragmentMesh.gd")
const CELL := 128
const CELL_UNITS := 1.7
var viewport: SubViewport
var camera: Camera3D
var models := {}
var clock := 0.0
var finalized := false

func configure(actor: Node2D, remains: Node2D) -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(CELL*3, CELL*2)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CELL_UNITS * 2
	camera.position = Vector3(0, 6, 3)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	light.light_energy = 1.35
	viewport.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CANVAS
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c3cbd8")
	environment.environment.ambient_light_energy = .65
	viewport.add_child(environment)
	var pixels_per_unit := _actor_scale(actor)
	for i in remains.pieces.size():
		var piece: Node2D = remains.pieces[i]
		var model: Node3D = piece.fragment_model
		viewport.add_child(model)
		var center := camera.basis.x * (float(i%3)-1.0) * CELL_UNITS + camera.basis.y * (.5-float(i/3)) * CELL_UNITS
		model.position = center
		model.set_meta("atlas_center", center)
		models[piece] = model
		var texture := AtlasTexture.new()
		texture.atlas = viewport.get_texture()
		texture.region = Rect2((i%3)*CELL, (i/3)*CELL, CELL, CELL)
		texture.filter_clip = true
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * pixels_per_unit * CELL_UNITS / CELL
		piece.add_child(sprite)
		piece.fragment_sprite = sprite
	_update_models()

func _actor_scale(actor: Node2D) -> float:
	var actor_view: SubViewport = actor.get("viewport")
	if actor_view == null: actor_view = actor.get("viewport_3d")
	if actor_view == null: actor_view = actor.get("driver_viewport")
	var display: Sprite2D = actor.get("sprite_3d_display")
	if display == null: display = actor.get("presentation_sprite")
	if display == null and actor_view != null:
		for candidate in actor.find_children("*", "Sprite2D", true, false):
			if candidate.texture == actor_view.get_texture():
				display = candidate
				break
	if actor_view != null and display != null and actor_view.get_camera_3d() != null:
		var cam := actor_view.get_camera_3d()
		return cam.unproject_position(Vector3.ZERO).distance_to(cam.unproject_position(Vector3.RIGHT)) * display.scale.x
	return 22.0

func _process(delta: float) -> void:
	if finalized: return
	clock += delta
	if clock < 1.0/30.0: return
	clock = 0
	_update_models()
	var moving := false
	var on_screen := false
	var screen := get_viewport().get_visible_rect().grow(256)
	for piece in models:
		if not is_instance_valid(piece): continue
		if piece.is_physics_processing(): moving = true
		if screen.has_point(piece.get_global_transform_with_canvas().origin): on_screen = true
	if on_screen or not moving: viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not moving:
		finalized = true
		set_process(false)

func _update_models() -> void:
	for piece in models.keys():
		var model: Node3D = models[piece]
		if not is_instance_valid(piece):
			if is_instance_valid(model): model.queue_free()
			models.erase(piece)
			continue
		model.rotation = piece.tumble
		# Centre the visible geometry in its atlas cell; ground lift is drawn
		# by the sprite, separately from the physical footprint and shadow.
		var bounds: AABB = model.get_meta("fragment_bounds")
		model.position = model.get_meta("atlas_center") - model.basis * bounds.get_center()
		piece.visual_ground_offset = -MESHES.floor_offset(model) * camera.basis.y.y * _actor_pixels(piece)
		piece.fragment_sprite.position = Vector2(0, -piece.height + piece.visual_ground_offset)

func _actor_pixels(piece: Node2D) -> float:
	return piece.fragment_sprite.scale.y * CELL / CELL_UNITS
