extends Node
## Short additive push, resolved against world collision without calling run-over damage.
var impulse := Vector2.ZERO
var age := 0.0

static func apply(body: CharacterBody2D, force: Vector2) -> void:
	var effect := body.get_node_or_null("BlastImpulse")
	if effect == null:
		effect = new()
		effect.name = "BlastImpulse"
		body.add_child(effect)
	effect.impulse = force.limit_length(420.0)
	effect.age = 0.0

func _physics_process(delta: float) -> void:
	age += delta
	var body := get_parent() as CharacterBody2D
	if body == null or not body.is_visible_in_tree() or age > 0.75:
		queue_free()
		return
	var hit := body.move_and_collide(impulse * delta)
	if hit: impulse = impulse.bounce(hit.get_normal()) * 0.18
	impulse = impulse.move_toward(Vector2.ZERO, 650.0 * delta)
