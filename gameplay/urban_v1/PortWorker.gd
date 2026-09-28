extends "res://gameplay/routines_v1/V1RoutineActor.gd"
## Damage is opt-in for port staff. Protected garage residents never use this actor.
signal died(actor: CharacterBody3D)
var health := 100.0
var dead := false
var gameplay: Node
var visual: Node3D:
	get: return model

func _ready() -> void:
	super._ready()
	add_to_group("v2_damageable")
	if get_parent().get("gameplay") != null: gameplay = get_parent().gameplay
	if is_instance_valid(carried_crate):
		carried_crate.reparent(model, false)
		carried_crate.position = Vector3(0,1.0,.38)
		model.hand_provider = _cargo_hands
	var reaction := get_node_or_null("WorkplaceThreatReaction")
	if reaction != null: reaction.react_to_aim = true

func _facing_yaw(direction: Vector3) -> float:
	return atan2(direction.x, direction.z)

func _cargo_hands() -> Array:
	if not carrying or dead: return [null,null]
	return [model.to_global(Vector3(-.24,1.0,.38)),model.to_global(Vector3(.24,1.0,.38))]

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0: return
	health = maxf(0,health-amount)
	if health <= 0:
		dead = true
		activity = "dead"
		velocity = Vector3.ZERO
		collision_layer = 0
		collision_mask = 0
		set_physics_process(false)
		set_process(false)
		if is_instance_valid(carried_crate): carried_crate.hide()
		model.hand_provider = Callable()
		if has_meta("v2_burning"): preload("res://gameplay/BurningActor.gd").char_body(self)
		var impact: Vector3 = global_position-source.global_position if source is Node3D else Vector3.ZERO
		preload("res://gameplay/CharacterFallPresentation3D.gd").apply_fall(self,model,impact)
		died.emit(self)
	else:
		var reaction := get_node_or_null("WorkplaceThreatReaction")
		if reaction != null: reaction._notice(global_position,1.0)
	if is_instance_valid(gameplay):
		if is_instance_valid(source) and source.has_method("is_player_damage_source") and source.is_player_damage_source(): gameplay.report_vehicle_assault(self,source)
		if is_instance_valid(gameplay.emergency): gameplay.emergency.report_injury(self,dead)

func recover_from_injury() -> void:
	if not dead: health = 100.0

static func safe_to_return(world: Node3D, point: Vector3) -> bool:
	var camera := world.get_viewport().get_camera_3d()
	if camera != null and not camera.is_position_behind(point+Vector3.UP):
		if world.get_viewport().get_visible_rect().grow(80).has_point(camera.unproject_position(point+Vector3.UP)): return false
	if world.get("gameplay") != null and world.gameplay.aim_active: return false
	return true
