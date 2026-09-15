extends RefCounted
## Shared ground contact and live silhouette projection; no extra viewports.
static var _texture: GradientTexture2D
static var _canvas_material: ShaderMaterial
static var _box_texture: ImageTexture
static var _box_material: ShaderMaterial
static var _vehicle_texture: ImageTexture
static var _vehicle_material: ShaderMaterial
static var _motorcycle_texture: ImageTexture
static var _motorcycle_material: ShaderMaterial

static func texture() -> GradientTexture2D:
	if _texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.38, 0.72, 1.0])
		gradient.colors = PackedColorArray([Color.WHITE, Color(1,1,1,0.85), Color(1,1,1,0.32), Color(1,1,1,0)])
		_texture = GradientTexture2D.new()
		_texture.width = 64
		_texture.height = 64
		_texture.gradient = gradient
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5,0.5)
		_texture.fill_to = Vector2(1.0,0.5)
	return _texture

static func add_2d(parent: Node2D, footprint: Vector2, opacity := 0.40) -> Sprite2D:
	var shadow := parent.get_node_or_null("ContactShadow") as Sprite2D
	if shadow == null:
		shadow = Sprite2D.new()
		shadow.name = "ContactShadow"
		shadow.show_behind_parent = true
		parent.add_child(shadow)
		parent.move_child(shadow, 0)
	if _canvas_material == null:
		var shader := Shader.new()
		# The footprint turns with the vehicle; the small offset stays fixed in
		# world space, including when the vehicle turns or the camera zooms.
		shader.code = "shader_type canvas_item;\nrender_mode unshaded, world_vertex_coords;\nuniform vec2 ground_offset = vec2(2.0, 3.0);\nvoid vertex() { VERTEX += ground_offset; }\n"
		_canvas_material = ShaderMaterial.new()
		_canvas_material.shader = shader
	shadow.texture = texture()
	shadow.material = _canvas_material
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shadow.modulate = Color(0.025,0.03,0.045,opacity)
	shadow.scale = footprint / Vector2(64,64)
	return shadow

static func add_box(parent: Node2D, footprint: Vector2, opacity := 0.45) -> Sprite2D:
	var shadow := add_2d(parent, footprint * 1.04, opacity)
	if _box_texture == null:
		var pixels := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var uv := Vector2((x + 0.5) / 64.0, (y + 0.5) / 64.0)
				var q := (uv - Vector2(0.5, 0.5)).abs() - Vector2(0.36, 0.36)
				var d := Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0) - 0.07
				var alpha := 1.0 - smoothstep(-0.06, 0.06, d)
				pixels.set_pixel(x, y, Color(1, 1, 1, alpha))
		_box_texture = ImageTexture.create_from_image(pixels)
		_box_material = _canvas_material.duplicate() as ShaderMaterial
		_box_material.set_shader_parameter("ground_offset", Vector2(1.5, 2.5))
	shadow.texture = _box_texture
	shadow.material = _box_material
	shadow.scale = footprint * 1.04 / Vector2(64, 64)
	return shadow

static func add_vehicle(parent: Node2D, footprint: Vector2) -> Sprite2D:
	if parent.get_meta("vehicle_kind", "car") == "motorcycle":
		return _add_motorcycle(parent, footprint)
	var shadow := add_2d(parent, footprint * Vector2(1.02, 0.95), 0.60)
	if _vehicle_texture == null:
		# 4 tire contact patches + underbody chassis ambient occlusion.
		# Front is +X in the vehicle's 2D space.
		var width := 128
		var height := 64
		var pixels := Image.create(width, height, false, Image.FORMAT_RGBA8)
		var front_x := 0.76
		var rear_x := 0.24
		var left_y := 0.25
		var right_y := 0.75
		var wheels = [
			Vector2(front_x, left_y),
			Vector2(front_x, right_y),
			Vector2(rear_x, left_y),
			Vector2(rear_x, right_y)
		]
		var tire_rx := 0.09
		var tire_ry := 0.075

		for y in height:
			for x in width:
				var uv := Vector2((x + 0.5) / float(width), (y + 0.5) / float(height))
				var alpha := 0.0

				# 1. Four wheel contact patches (darkest occlusion at tire ground contact)
				for w in wheels:
					var d_wheel := Vector2((uv.x - w.x) / tire_rx, (uv.y - w.y) / tire_ry).length()
					var wheel_alpha := 1.0 - smoothstep(0.4, 1.1, d_wheel)
					alpha = maxf(alpha, wheel_alpha * 0.95)

				# 2. Chassis underbody ambient occlusion (tapered capsule tucked inside wheels)
				var center_rel := uv - Vector2(0.5, 0.5)
				var q := center_rel.abs() - Vector2(0.38, 0.20)
				var d_body := Vector2(maxf(q.x, 0), maxf(q.y, 0)).length() + minf(maxf(q.x, q.y), 0) - 0.08
				var body_alpha := 1.0 - smoothstep(-0.08, 0.09, d_body)

				# Taper front and rear overhangs
				var x_edge := absf(center_rel.x) - 0.28
				if x_edge > 0.0:
					var taper := 1.0 - (x_edge / 0.18) * 0.45
					body_alpha *= clampf(taper, 0.0, 1.0)

				alpha = maxf(alpha, body_alpha * 0.75)
				pixels.set_pixel(x, y, Color(1, 1, 1, alpha))

		_vehicle_texture = ImageTexture.create_from_image(pixels)
		_vehicle_material = _canvas_material.duplicate() as ShaderMaterial
		_vehicle_material.set_shader_parameter("ground_offset", Vector2(1.5, 2.0))
	shadow.texture = _vehicle_texture
	shadow.material = _vehicle_material
	shadow.scale = footprint * Vector2(1.02, 0.95) / Vector2(128, 64)

	# Automatically hook up live silhouette projection if vehicle has 3D display
	var display := parent.get_node_or_null("Sprite2D") as Sprite2D
	if display == null: display = parent.get("sprite") as Sprite2D
	if display == null: display = parent.get("visual") as Sprite2D
	var vp := parent.get_node_or_null("CoupeRender") as SubViewport
	if vp == null: vp = parent.get("body_viewport") as SubViewport
	if vp == null: vp = parent.get("viewport_3d") as SubViewport
	if is_instance_valid(display) and is_instance_valid(vp) and vp.transparent_bg:
		add_silhouette(display, vp)

	return shadow

static func _add_motorcycle(parent: Node2D, footprint: Vector2) -> Sprite2D:
	var shadow := add_2d(parent, footprint, 0.36)
	if _motorcycle_texture == null:
		# One shared soft silhouette: narrow tire contacts, tapered engine/tank
		# and a small handlebar spread. Front is +X in the vehicle's 2D space.
		var pixels := Image.create(96,64,false,Image.FORMAT_RGBA8)
		var centers: Array[Vector2] = [Vector2(.49,.5), Vector2(.15,.5), Vector2(.86,.5), Vector2(.70,.5)]
		var radii: Array[Vector2] = [Vector2(.32,.25), Vector2(.12,.13), Vector2(.12,.13), Vector2(.09,.35)]
		for y in 64:
			for x in 96:
				var uv := Vector2((x+.5)/96.0,(y+.5)/64.0)
				var alpha := 0.0
				for i in centers.size():
					var distance := ((uv-centers[i])/radii[i]).length()
					alpha = maxf(alpha,1.0-smoothstep(.35,1.0,distance))
				pixels.set_pixel(x,y,Color(1,1,1,alpha))
		_motorcycle_texture = ImageTexture.create_from_image(pixels)
		_motorcycle_material = _canvas_material.duplicate() as ShaderMaterial
		_motorcycle_material.set_shader_parameter("ground_offset",Vector2(1,1.5))
	shadow.texture = _motorcycle_texture
	shadow.material = _motorcycle_material
	shadow.scale = footprint * Vector2(1.06,1.10) / Vector2(96,64)
	return shadow

static func soften(shadow: MeshInstance3D, size := Vector2(0.86,0.72)) -> void:
	var plane := PlaneMesh.new()
	plane.size = size
	shadow.mesh = plane
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.025,0.03,0.045,0.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	shadow.material_override = material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Keep the floor patch out of the animated rig's yaw and body lean.
	if shadow.get_parent() is Node3D:
		shadow.top_level = true
	shadow.position = Vector3(0,0.008,0)
	shadow.visible = false # Preserve the rig/fall slot; the live display casts its silhouette.

static func add_person(viewport: SubViewport) -> MeshInstance3D:
	var shadow := viewport.get_node_or_null("GroundShadow") as MeshInstance3D
	if shadow == null:
		shadow = MeshInstance3D.new()
		shadow.name = "GroundShadow"
		viewport.add_child(shadow)
		soften(shadow)
	return shadow

## Reuse the live model texture: pose/equipment and cached updates stay in sync.
## Child visibility/transform inherit from the display, including interior hiding.
static func add_silhouette(display: Sprite2D, viewport: SubViewport) -> void:
	if display.has_node("PoseShadow"): return
	var camera := viewport.get_camera_3d()
	if camera == null: return
	var shadow := preload("res://systems/LivePoseShadow.gd").new()
	shadow.source_display = display
	shadow.source_viewport = viewport
	shadow.name = "PoseShadow"
	shadow.texture = display.texture
	shadow.centered = display.centered
	shadow.offset = display.offset
	shadow.show_behind_parent = true
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://systems/ProjectedSilhouette.gdshader")
	var foot := camera.unproject_position(Vector3.ZERO)
	if display.centered: foot -= Vector2(viewport.size)*.5
	mat.set_shader_parameter("foot",foot+display.offset)
	shadow.material = mat
	shadow.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	display.add_child(shadow)
