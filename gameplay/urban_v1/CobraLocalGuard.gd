extends "res://gameplay/CobraAgent.gd"
## Guarda ambiental: estar perto não autoriza disparar contra o jogador.
var territory: Node
var home := Vector3.ZERO
func _ready() -> void:
	super._ready()
	home = global_position
	engaged = false
	add_to_group("cobra_local")
	_rest_arms()

func _rest_arms() -> void:
	preload("res://gameplay/urban_v1/CobraAppearance.gd").arms(visual,false)

func _physics_process(delta: float) -> void:
	if dead: return
	if engaged:
		super._physics_process(delta)
		return
	# Mantém contato físico com o chão também quando está de guarda.
	velocity = Vector3(0, -1.0 if is_on_floor() else velocity.y - 20.0 * delta, 0)
	move_and_slide()
	visual.update_pose(delta, false, false, 0.0, 0.0)

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or amount<=0: return
	if is_instance_valid(territory): territory.provoke(source)
	super.receive_damage(amount,source)

func set_engaged(value: bool) -> void:
	engaged = value
	if not value:
		alerted = false
		sees_target = false
		path.clear()
		_rest_arms()
