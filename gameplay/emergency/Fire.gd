extends Node3D
## Foco de incêndio no chão (explosão, lança-chamas, carro queimando).
##
## Visual: antes eram sete cilindros opacos laranja/amarelos girando, que liam
## como cones de plástico sobre a marca preta de queimado (relato do jogador em
## 2026-09-24). Agora: línguas de fogo em partícula (flame_sprite.gdshader),
## brasas subindo, fumaça escura, brilho alaranjado no chão e uma luz que
## tremula. Tudo escala com `intensity`. Dano e duração não mudaram.
const MAX_LIT_FIRES := 6
const RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")
static var _visual_template: PackedScene

var manager: Node3D
var source: Node
var intensity := 1.0
var age := 0.0
var tick := 0.0
var flames: GPUParticles3D
var embers: GPUParticles3D
var smoke: GPUParticles3D
var glow: MeshInstance3D
var light: OmniLight3D
var _shown_intensity := -1.0
var _fade_from := -1.0
const BURN_SECONDS := 15.0
const FADE_SECONDS := 5.0

func _ready() -> void:
	_ensure_visuals()
	# Only live incidents join the light budget; the cached template never runs.
	add_to_group("ground_fire")
	light.visible = get_tree().get_nodes_in_group("ground_fire").size() <= MAX_LIT_FIRES
	_apply_intensity()

static func prewarm_visuals() -> void:
	if _visual_template != null: return
	var prototype = load("res://gameplay/emergency/Fire.gd").new()
	prototype._ensure_visuals()
	prototype.free()

func _ensure_visuals() -> void:
	if _visual_template == null:
		_build_visuals()
		var template := Node3D.new()
		for child in get_children():
			var copy := child.duplicate(0)
			template.add_child(copy)
			copy.owner = template
		_visual_template = PackedScene.new()
		_visual_template.pack(template)
		template.free()
	else:
		var instance := _visual_template.instantiate()
		for child in instance.get_children():
			child.owner = null
			instance.remove_child(child)
			add_child(child)
		instance.free()
		flames = get_node("GroundFlames")
		embers = get_node("GroundEmbers")
		smoke = get_node("GroundFireSmoke")
		glow = get_node("GroundFireGlow")
		light = get_node("GroundFireLight")

func _build_visuals() -> void:
	flames = RESOURCES.emitter("GroundFlames", 40, 0.75, Vector2(0.55, 0.85), false)
	var flame_process := RESOURCES.particle_process()
	flame_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	flame_process.emission_sphere_radius = 0.55
	flame_process.direction = Vector3.UP
	flame_process.spread = 12.0
	flame_process.initial_velocity_min = 0.6
	flame_process.initial_velocity_max = 1.5
	flame_process.gravity = Vector3(0.0, 1.2, 0.0)
	flame_process.scale_min = 0.7
	flame_process.scale_max = 1.3
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 0.6))
	shrink.add_point(Vector2(0.25, 1.0))
	shrink.add_point(Vector2(1.0, 0.25))
	var shrink_texture := CurveTexture.new()
	shrink_texture.curve = shrink
	flame_process.scale_curve = shrink_texture
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.15, 0.7, 1.0])
	ramp.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 0.8, 0.7, 0.8), Color(0.6, 0.3, 0.2, 0)])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	flame_process.color_ramp = ramp_texture
	flames.process_material = flame_process
	flames.position = Vector3(0, 0.25, 0)
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)
	flames.emitting = true

	embers = RESOURCES.emitter("GroundEmbers", 16, 1.6, Vector2(0.05, 0.05), false)
	var ember_process := RESOURCES.particle_process()
	ember_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ember_process.emission_sphere_radius = 0.5
	ember_process.spread = 25.0
	ember_process.initial_velocity_min = 1.2
	ember_process.initial_velocity_max = 2.8
	ember_process.gravity = Vector3(0.3, 0.4, 0.1)
	ember_process.turbulence_enabled = true
	ember_process.turbulence_noise_strength = 1.4
	ember_process.color = Color(1.0, 0.6, 0.2, 1.0)
	embers.process_material = ember_process
	embers.position = Vector3(0, 0.4, 0)
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(embers)
	embers.emitting = true

	smoke = RESOURCES.emitter("GroundFireSmoke", 18, 3.2, Vector2(1.4, 1.4), true)
	var smoke_process := RESOURCES.particle_process()
	smoke_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	smoke_process.emission_sphere_radius = 0.45
	smoke_process.spread = 18.0
	smoke_process.initial_velocity_min = 0.8
	smoke_process.initial_velocity_max = 1.6
	smoke_process.gravity = Vector3(0.25, 0.35, 0.1)
	smoke_process.scale_min = 0.8
	smoke_process.scale_max = 1.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.5))
	grow.add_point(Vector2(1.0, 2.2))
	grow.max_value = 2.2
	var grow_texture := CurveTexture.new()
	grow_texture.curve = grow
	smoke_process.scale_curve = grow_texture
	var smoke_ramp := Gradient.new()
	smoke_ramp.offsets = PackedFloat32Array([0.0, 0.2, 1.0])
	smoke_ramp.colors = PackedColorArray([Color(0.2, 0.17, 0.15, 0), Color(0.13, 0.12, 0.11, 0.55), Color(0.3, 0.3, 0.3, 0)])
	var smoke_ramp_texture := GradientTexture1D.new()
	smoke_ramp_texture.gradient = smoke_ramp
	smoke_process.color_ramp = smoke_ramp_texture
	smoke.process_material = smoke_process
	smoke.position = Vector3(0, 1.2, 0)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	smoke.emitting = true

	# Brilho no chão: o fogo ilumina a própria marca de queimado.
	glow = MeshInstance3D.new()
	glow.name = "GroundFireGlow"
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	quad.orientation = PlaneMesh.FACE_Y
	glow.mesh = quad
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_material.albedo_texture = RESOURCES.soft_texture()
	glow_material.albedo_color = Color(1.0, 0.42, 0.1, 0.55)
	glow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	glow.material_override = glow_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.position.y = 0.02
	add_child(glow)

	light = OmniLight3D.new()
	light.name = "GroundFireLight"
	light.light_color = Color(1.0, 0.55, 0.2)
	light.omni_range = 5.5
	light.shadow_enabled = false
	light.position.y = 0.9
	add_child(light)

func _apply_intensity() -> void:
	var strength := clampf(intensity, 0.0, 1.5)
	if absf(strength - _shown_intensity) < 0.02: return
	_shown_intensity = strength
	var size := lerpf(0.55, 1.2, clampf(strength, 0.0, 1.0))
	flames.scale = Vector3.ONE * size
	flames.amount_ratio = clampf(0.3 + strength * 0.7, 0.0, 1.0)
	embers.amount_ratio = clampf(strength, 0.0, 1.0)
	smoke.amount_ratio = clampf(0.4 + strength * 0.6, 0.0, 1.0)
	glow.scale = Vector3.ONE * size

func _physics_process(delta: float) -> void:
	age += delta
	# Fogo solto (arma, explosão) apaga sozinho: a partir de BURN_SECONDS mingua até
	# sumir em FADE_SECONDS (pedido do jogador em 2026-09-24; antes queimava 45 s).
	if age > BURN_SECONDS:
		if _fade_from < 0.0: _fade_from = intensity
		intensity -= delta * _fade_from / FADE_SECONDS
	if intensity <= 0:
		queue_free()
		return
	_apply_intensity()
	light.light_energy = (1.4 + sin(age * 17.0) * 0.25 + sin(age * 7.3) * 0.2) * clampf(intensity, 0.2, 1.3)
	tick -= delta
	if tick > 0: return
	tick = 0.5
	var shape := SphereShape3D.new()
	shape.radius = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = global_position + Vector3.UP * 0.65
	query.collision_mask = 6
	for hit in get_world_3d().direct_space_state.intersect_shape(query, 16):
		var actor: Node3D = hit.collider
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, actor.global_position + Vector3.UP, 1)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		# Tique de fogo a cada 0,5 s: fonte contínua, denuncia a mesma vítima uma vez por janela (Gameplay._crime_due).
		manager.gameplay._damage(actor, 5 * intensity, source if is_instance_valid(source) else null, true)
