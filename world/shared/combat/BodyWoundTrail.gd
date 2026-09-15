extends Node2D
## One bounded bleeding timer per actor; visible blood belongs to the world.
const DURATION := 6.0
const INTERVAL := 1.15
var remaining := DURATION
var drip_clock := INTERVAL
var last_drip := Vector2.INF
var severity := 0

static func attach(actor: Node2D, direction: Vector2) -> void:
	var wound := actor.get_node_or_null("BodyWound")
	if wound == null:
		wound = load("res://world/shared/combat/BodyWoundTrail.gd").new()
		wound.name = "BodyWound"
		actor.add_child(wound)
		wound.last_drip = actor.global_position
	wound.remaining = DURATION
	wound.severity = mini(4, wound.severity + 1)
	var effects := actor.get_tree().get_first_node_in_group("weapon_effects")
	if effects == null:
		effects = preload("res://world/shared/combat/WeaponEffects.gd").new()
		actor.get_parent().add_child(effects)
	effects.spawn_blood(actor.global_position + Vector2(0,-12), direction, 18)

func _process(delta: float) -> void:
	var actor := get_parent() as Node2D
	if actor == null or actor.get("is_recovering") == true or actor.get("is_dead") == true:
		queue_free()
		return
	var active_delta := minf(delta, maxf(remaining, 0.0))
	remaining -= delta
	drip_clock -= active_delta
	if drip_clock <= 0.000001:
		# Preserve fractional time, but never replay a backlog after a stall.
		drip_clock = INTERVAL - fposmod(-drip_clock, INTERVAL)
		if actor.is_visible_in_tree() and actor.get("is_flying") != true and (last_drip == Vector2.INF or actor.global_position.distance_to(last_drip) >= 28.0):
			preload("res://world/shared/combat/GroundBlood.gd").spawn_drip(actor, clampf(remaining / DURATION, 0.0, 1.0))
			last_drip = actor.global_position
	if remaining <= 0.0: queue_free()

