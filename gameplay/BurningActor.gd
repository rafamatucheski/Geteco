extends Node3D
## Estado curto de queimadura do combate V2. A vítima mantém as chamas no
## corpo enquanto foge; dano e autoria passam pelo Gameplay normal.
const DURATION := 6.0
const TICK_SECONDS := 0.4
const TICK_DAMAGE := 12.0
const MAX_VISUALS := 16
const RESOURCES := preload("res://gameplay/vehicle_effects/VehicleEffectResources.gd")

var actor: Node3D
var gameplay: Node
var source_ref: WeakRef
var remaining := DURATION
var tick_clock := 0.0
var flames: GPUParticles3D
var smoke: GPUParticles3D

func configure(p_actor: Node3D, p_gameplay: Node, p_source: Node) -> void:
	actor = p_actor
	gameplay = p_gameplay
	source_ref = weakref(p_source) if is_instance_valid(p_source) else null

func _ready() -> void:
	add_to_group("v2_burning_actor")
	var visible_burns := get_tree().get_nodes_in_group("v2_burning_visual").size()
	if visible_burns >= MAX_VISUALS: return
	add_to_group("v2_burning_visual")
	flames = RESOURCES.emitter("ActorFlames", 30, 0.68, Vector2(0.38, 0.72), false)
	var flame_process := RESOURCES.particle_process()
	flame_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	flame_process.emission_box_extents = Vector3(0.23, 0.38, 0.16)
	flame_process.initial_velocity_min = 0.8
	flame_process.initial_velocity_max = 2.0
	flame_process.gravity = Vector3(0.0, 0.8, 0.0)
	flame_process.color = Color(1.0, 0.48, 0.07, 0.96)
	flames.process_material = flame_process
	flames.position = Vector3(0.0, 0.72, 0.0)
	flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flames)
	flames.emitting = true
	smoke = RESOURCES.emitter("ActorBurnSmoke", 12, 1.1, Vector2(0.48, 0.48), true)
	var smoke_process := RESOURCES.particle_process()
	smoke_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	smoke_process.emission_box_extents = Vector3(0.20, 0.18, 0.14)
	smoke_process.initial_velocity_min = 0.25
	smoke_process.initial_velocity_max = 0.8
	smoke_process.gravity = Vector3(0.0, 0.2, 0.0)
	smoke_process.color = Color(0.15, 0.14, 0.13, 0.46)
	smoke.process_material = smoke_process
	smoke.position = Vector3(0.0, 1.20, 0.0)
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(smoke)
	smoke.emitting = true

func ignite(source: Node = null) -> void:
	remaining = DURATION
	if is_instance_valid(source): source_ref = weakref(source)
	if flames != null: flames.emitting = true
	if smoke != null: smoke.emitting = true

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or actor.get("dead") == true or actor.is_queued_for_deletion():
		_stop_visuals()
		queue_free()
		return
	if flames != null: flames.global_position = actor.global_position + Vector3(0.0, 0.72, 0.0)
	if smoke != null: smoke.global_position = actor.global_position + Vector3(0.0, 1.20, 0.0)
	remaining -= delta
	tick_clock += delta
	while tick_clock >= TICK_SECONDS:
		tick_clock -= TICK_SECONDS
		var source: Node = source_ref.get_ref() if source_ref != null else null
		gameplay._damage(actor, TICK_DAMAGE, source, true)
		if actor.get("dead") == true:
			_stop_visuals()
			queue_free()
			return
	if remaining <= 0.0:
		actor.remove_meta("v2_burning")
		_stop_visuals()
		queue_free()

func _stop_visuals() -> void:
	if is_instance_valid(flames): flames.emitting = false
	if is_instance_valid(smoke): smoke.emitting = false

func _exit_tree() -> void:
	if is_instance_valid(actor) and actor.has_meta("v2_burning"):
		actor.remove_meta("v2_burning")
	_stop_visuals()

static func char_body(actor: Node3D) -> void:
	if not is_instance_valid(actor): return
	actor.set_meta("v2_charred", true)
	var visual: Node3D = actor.get("visual")
	if not is_instance_valid(visual): return
	var soot := Color(0.075, 0.07, 0.068, 1.0)
	var ember := Color(0.16, 0.105, 0.075, 1.0)
	for part in visual.find_children("*", "MeshInstance3D", true, false):
		for parameter in ["skin_color", "hair_color", "top_color", "inner_color", "bottom_color", "shoe_color", "accent_color"]:
			part.set_instance_shader_parameter(parameter, ember if parameter == "accent_color" else soot)
		var material: Material = part.material_override
		if material is StandardMaterial3D:
			var charred := material.duplicate() as StandardMaterial3D
			charred.albedo_color = charred.albedo_color.lerp(soot, 0.82)
			charred.roughness = 0.98
			part.material_override = charred
