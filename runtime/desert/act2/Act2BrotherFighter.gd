extends "res://runtime/desert/DesertCharacter.gd"
## Vicente na briga do motel (A2-12): apanha, cambaleia e cai sentado antes de morrer; nunca morre.
## Anda na direção de Dante para trocar socos (a mesma física de chão do DesertCharacter).
## Era a classe interna VicenteReunion.BrotherFighter até 01/11; a VicenteReunion reexporta com o mesmo nome
## (o teste do A2-12 confere `actor is REUNION.BrotherFighter`).

const DOWN_AT := 35.0
const SPEED := 2.4
var down := false
var _push := Vector3.ZERO

func chase(offset: Vector3) -> void:
	if down: return
	_push = offset.normalized() * SPEED if offset.length() > 1.2 else Vector3.ZERO
	if is_instance_valid(visual) and offset.length() > .1: visual.rotation.y = atan2(offset.x, offset.z)

func _physics_process(delta: float) -> void:
	velocity = Vector3(_push.x, maxf(-20.0, velocity.y - 18.0 * delta), _push.z)
	move_and_slide()

func receive_damage(amount: float, _source: Node = null) -> void:
	if down or not is_finite(amount) or amount <= 0: return
	health = maxf(DOWN_AT, health - amount)
	if is_instance_valid(visual) and visual.has_method("take_hit"): visual.take_hit(Vector3.ZERO, clampf(amount / 35.0, .3, 1.0))
	if health <= DOWN_AT:
		down = true
		_push = Vector3.ZERO
		set_talking(false)
