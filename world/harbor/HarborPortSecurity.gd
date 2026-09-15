extends "res://police/PoliceOfficer.gd"

var checkpoint: Node

func _ready() -> void:
	local_security = true
	set_meta("quiet_patrol", true)
	super._ready()
	remove_from_group("police_officer")
	add_to_group("port_private_security")
	mat_uniform.albedo_color = Color("454b42")

func _physics_process(delta: float) -> void:
	if is_instance_valid(checkpoint):
		security_alert = 3 if checkpoint.alerted else 0
		if checkpoint.alerted:
			target = checkpoint.actor()
			response_aggression = 12.0
	super._physics_process(delta)

func take_damage(amount: int, is_player_attacker: bool = false) -> void:
	if amount > 0 and is_player_attacker and is_instance_valid(checkpoint):
		checkpoint.raise_alarm()
	super.take_damage(amount, is_player_attacker)
