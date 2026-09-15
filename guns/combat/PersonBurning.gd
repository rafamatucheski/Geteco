extends Node2D
## One renewable burn per person. Damage outlives the jet; visuals inherit
## the person's canvas depth and disappear with the actor/scene.
const DURATION := 6.0
const TICK_SECONDS := 0.5
const TICK_DAMAGE := 6
const MAX_VISIBLE_FIRES := 24
const MATERIAL := preload("res://audio/combat/ImpactMaterial.gd")
var remaining := DURATION
var tick_clock := 0.0
var from_player := false
var attacker: WeakRef
var actor: Node2D
var flames: CPUParticles2D
var smoke: CPUParticles2D
var interior_fire: Node3D
static var flame_texture: GradientTexture2D
static var flame_colors: Gradient
static var smoke_colors: Gradient

static func ignite(target: Node2D, source: Node2D = null) -> Node2D:
	if not target.has_method("take_damage") or MATERIAL.resolve(target) != &"flesh": return null
	if target.is_queued_for_deletion() or not target.is_visible_in_tree(): return null
	var effect := target.get_node_or_null("PersonBurning")
	if effect == null:
		effect = new()
		effect.name = "PersonBurning"
		effect.actor = target
		target.add_child(effect)
	effect.remaining = DURATION
	# Reigniting during the smoke tail must restart visible emission too.
	if effect.flames: effect.flames.emitting = true
	if effect.smoke: effect.smoke.emitting = true
	if is_instance_valid(effect.interior_fire):
		for emitter in effect.interior_fire.get_children(): emitter.emitting = true
	effect.from_player = is_instance_valid(source) and source.is_in_group("player")
	effect.attacker = weakref(source) if is_instance_valid(source) else null
	return effect

func _ready() -> void:
	# The status keeps dealing damage even when the visual budget is full.
	var render_fire := get_tree().get_nodes_in_group("person_fire_visuals").size() < MAX_VISIBLE_FIRES
	add_to_group("burning_people")
	if not render_fire: return
	add_to_group("person_fire_visuals")
	_make_resources()
	flames = _emitter(24, 0.65, flame_colors)
	flames.emission_rect_extents = Vector2(6, 7)
	flames.scale_amount_min = 0.12
	flames.scale_amount_max = 0.27
	flames.scale = Vector2(0.8, 1.4)
	flames.preprocess = 0.3
	smoke = _emitter(8, 1.1, smoke_colors)
	smoke.position.y = -10
	smoke.scale_amount_min = 0.18
	smoke.scale_amount_max = 0.36
	_update_interior_visual()

static func _make_resources() -> void:
	if flame_texture != null: return
	flame_texture = GradientTexture2D.new()
	flame_texture.width = 48
	flame_texture.height = 64
	flame_texture.fill = GradientTexture2D.FILL_RADIAL
	flame_texture.fill_from = Vector2(0.5, 0.5)
	flame_texture.fill_to = Vector2(0.5, 0.0)
	flame_texture.gradient = Gradient.new()
	flame_texture.gradient.colors = PackedColorArray([Color.WHITE, Color(1, 1, 1, 0)])
	flame_colors = Gradient.new()
	flame_colors.offsets = PackedFloat32Array([0, 0.2, 0.6, 1])
	flame_colors.colors = PackedColorArray([Color(1, 0.95, 0.5, 0.9), Color(1, 0.65, 0.05, 1), Color(1, 0.19, 0.015, 0.8), Color(0.4, 0.06, 0.01, 0)])
	smoke_colors = Gradient.new()
	smoke_colors.colors = PackedColorArray([Color(0.18, 0.15, 0.13, 0.35), Color(0.12, 0.12, 0.12, 0)])

func _emitter(count: int, lifetime: float, colors: Gradient) -> CPUParticles2D:
	var emitter := CPUParticles2D.new()
	emitter.amount = count
	emitter.lifetime = lifetime
	emitter.texture = flame_texture
	emitter.color_ramp = colors
	emitter.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	emitter.emission_rect_extents = Vector2(5, 3)
	emitter.direction = Vector2.UP
	emitter.spread = 18
	emitter.gravity = Vector2(0, -24)
	emitter.initial_velocity_min = 9
	emitter.initial_velocity_max = 22
	emitter.local_coords = false
	add_child(emitter)
	return emitter

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion() or not actor.is_visible_in_tree():
		queue_free()
		return
	global_rotation = 0
	_update_interior_visual()
	var burning_delta := minf(delta, maxf(remaining, 0.0))
	remaining -= delta
	tick_clock += burning_delta
	while tick_clock >= TICK_SECONDS:
		tick_clock -= TICK_SECONDS
		if actor.get("is_dead") == true: continue
		if attacker != null: actor.set_meta("combat_attacker", attacker.get_ref())
		actor.take_damage(TICK_DAMAGE, from_player)
		if actor.has_method("panic"): actor.panic()
	if remaining <= 0:
		if flames: flames.emitting = false
		if smoke: smoke.emitting = false
		if is_instance_valid(interior_fire):
			for emitter in interior_fire.get_children(): emitter.emitting = false
		if remaining <= -1.1: queue_free()

func _update_interior_visual() -> void:
	if flames == null: return
	var presentation: Node = actor.get_meta("interior_actor_presentation") if actor.has_meta("interior_actor_presentation") else null
	var indoors := is_instance_valid(presentation)
	flames.visible = not indoors
	smoke.visible = not indoors
	if not indoors:
		if is_instance_valid(interior_fire): interior_fire.queue_free()
		return
	if is_instance_valid(interior_fire): return
	interior_fire = Node3D.new()
	presentation.rig.add_child(interior_fire)
	for i in 2:
		var particles := CPUParticles3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.22, 0.42) if i == 0 else Vector2(0.3, 0.3)
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		material.albedo_texture = flame_texture
		mesh.material = material
		particles.mesh = mesh
		particles.amount = 24 if i == 0 else 8
		particles.lifetime = 0.65 if i == 0 else 1.1
		particles.color_ramp = flame_colors if i == 0 else smoke_colors
		particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		particles.emission_box_extents = Vector3(0.18, 0.32, 0.1)
		particles.position.y = 0.65 if i == 0 else 1.15
		particles.direction = Vector3.UP
		particles.gravity = Vector3(0, 0.6, 0)
		particles.initial_velocity_min = 0.15
		particles.initial_velocity_max = 0.45
		particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		interior_fire.add_child(particles)

func _exit_tree() -> void:
	if is_instance_valid(interior_fire): interior_fire.queue_free()
