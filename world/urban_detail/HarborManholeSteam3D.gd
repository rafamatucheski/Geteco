extends CPUParticles3D
## Vapor subindo pelas frestas da tampa do esgoto. Só visual e barato
## (poucas partículas, sem sombra): denuncia de longe que ali há uma entrada.

func _ready() -> void:
	name = "ManholeSteam"
	position.y = 0.12
	amount = 9
	lifetime = 4.2
	preprocess = 4.2
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = 0.4
	direction = Vector3.UP
	spread = 14
	gravity = Vector3(0.05, 0.12, 0.0)
	initial_velocity_min = 0.2
	initial_velocity_max = 0.38
	damping_min = 0.04
	damping_max = 0.08
	angle_min = -180
	angle_max = 180
	scale_amount_min = 0.7
	scale_amount_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.35))
	grow.add_point(Vector2(1, 1.6))
	scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.65, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0)])
	color_ramp = ramp
	var puff := QuadMesh.new()
	puff.size = Vector2(0.9, 0.9)
	mesh = puff
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var soft := GradientTexture2D.new()
	soft.gradient = gradient
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	soft.width = 64
	soft.height = 64
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.86, 0.89, 0.88, 0.2)
	material.albedo_texture = soft
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
