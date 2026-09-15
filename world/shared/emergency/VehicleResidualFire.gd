extends Node
## Wreck cooling is a separate incident from the explosion. It keeps the
## existing particles alive without restarting detonation or repairing damage.
const LIFETIME := 60.0
const NODE_NAME := &"ResidualFire"
var vehicle: Node2D
var remaining := LIFETIME
var _poll := 0.0
var _flames: CPUParticles2D
var _scale_min := 1.0
var _scale_max := 1.0

static func start(body: Node2D) -> void:
	if not is_instance_valid(body) or body.get("is_exploded") != true: return
	var existing := body.get_node_or_null(NodePath(NODE_NAME))
	if is_instance_valid(existing) and not existing.is_queued_for_deletion(): return
	var cooling := new()
	cooling.name = NODE_NAME
	cooling.vehicle = body
	body.add_child(cooling)
	body.set_meta("fire_residual_burning", true)
	body.set_meta("service_complete", false)
	body.remove_meta("fire_water_progress")
	var emitter: Variant = body.get("flame_particles")
	if emitter is CPUParticles2D:
		cooling._flames = emitter
		cooling._scale_min = emitter.scale_amount_min
		cooling._scale_max = emitter.scale_amount_max
		emitter.emitting = true
	# Reuse the incident director's deduplication and finite pool.
	if body.has_method("_dispatch_fire_truck"):
		body._dispatch_fire_truck()
	else:
		var director := body.get_tree().get_first_node_in_group("emergency_depot_director")
		if director and director.has_method("request_dispatch"):
			director.request_dispatch("fire", body, false)

func _process(delta: float) -> void:
	remaining -= delta
	_poll -= delta
	if _poll > 0.0: return
	_poll = 0.25
	if not is_instance_valid(vehicle):
		queue_free()
		return
	if vehicle.get_meta("service_complete", false) or vehicle.get("is_exploded") != true or remaining <= 0.0:
		finish()

func update_fire_suppression(progress: float) -> void:
	if is_instance_valid(_flames):
		_flames.scale_amount_min = lerpf(_scale_min, _scale_min * 0.20, progress)
		_flames.scale_amount_max = lerpf(_scale_max, _scale_max * 0.20, progress)

func finish() -> void:
	if is_instance_valid(vehicle):
		vehicle.set_meta("fire_residual_burning", false)
		vehicle.set_meta("service_complete", true)
		vehicle.remove_meta("fire_water_progress")
		vehicle.remove_meta("fire_response_assigned")
		if is_instance_valid(_flames):
			_flames.emitting = false
			_flames.scale_amount_min = _scale_min
			_flames.scale_amount_max = _scale_max
		var smoke: Variant = vehicle.get("smoke_emitter")
		if smoke is CPUParticles2D:
			smoke.color = Color(0.62, 0.62, 0.62, 0.30)
			smoke.amount = mini(smoke.amount, 20)
	queue_free()
