extends RefCounted
## Shared presentation resources. V1 also generated its soft particle texture at runtime.

static var _soft_texture: Texture2D
static var _wisp_texture: Texture2D
static var _quads: Dictionary = {}

static func soft_texture() -> Texture2D:
	if _soft_texture != null: return _soft_texture
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var radius := Vector2(x-15.5,y-15.5).length()/15.5
			image.set_pixel(x,y,Color(1,1,1,pow(maxf(0,1-radius),2)))
	_soft_texture = ImageTexture.create_from_image(image)
	return _soft_texture

static func wisp_texture() -> Texture2D:
	if _wisp_texture != null: return _wisp_texture
	var image := Image.create(32,32,false,Image.FORMAT_RGBA8)
	var centers: Array[Vector3] = [
		Vector3(15.5, 15.5, 12.0),
		Vector3(12.5, 14.0, 9.0),
		Vector3(18.5, 14.5, 8.5),
		Vector3(15.0, 18.0, 9.0),
		Vector3(14.0, 11.5, 7.5),
	]
	for y in 32:
		for x in 32:
			var p := Vector2(x, y)
			var density := 0.0
			for c in centers:
				var dist := p.distance_to(Vector2(c.x, c.y))
				var factor := maxf(0.0, 1.0 - dist / c.z)
				density += pow(factor, 1.8) * 0.42
			density = clampf(density, 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, density))
	_wisp_texture = ImageTexture.create_from_image(image)
	return _wisp_texture

static func quad(size: Vector2, use_wisp := true) -> QuadMesh:
	var key := "%0.3f:%0.3f:%s" % [size.x, size.y, "w" if use_wisp else "s"]
	if _quads.has(key): return _quads[key]
	var mesh := QuadMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_texture = wisp_texture() if use_wisp else soft_texture()
	material.albedo_color = Color.WHITE
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	_quads[key] = mesh
	return mesh

static func emitter(label: String, amount: int, lifetime: float, size: Vector2, use_wisp := true) -> GPUParticles3D:
	var result := GPUParticles3D.new()
	result.name = label
	result.emitting = false
	result.amount = amount
	result.lifetime = lifetime
	result.local_coords = false
	result.fixed_fps = 30
	result.interpolate = true
	result.fract_delta = true
	result.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	result.visibility_aabb = AABB(Vector3(-5,-2,-5),Vector3(10,8,10))
	result.draw_pass_1 = quad(size, use_wisp)
	return result

static func particle_process(rotating := true) -> ParticleProcessMaterial:
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = .04
	process.direction = Vector3.UP
	process.spread = 35.0
	process.gravity = Vector3.ZERO
	process.initial_velocity_min = .5
	process.initial_velocity_max = 1.2
	process.scale_min = .45
	process.scale_max = 1.25
	if rotating:
		process.angle_min = 0.0
		process.angle_max = 360.0
		process.angular_velocity_min = -1.2
		process.angular_velocity_max = 1.2
	return process

