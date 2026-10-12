extends StaticBody3D
var health := 100.0
var dead := false
var visual: Node3D
func _ready() -> void:
	add_to_group("v2_damageable")
	add_to_group("police_witness")
func receive_damage(amount: float, source: Node = null) -> void:
	preload("res://runtime/desert/drag_meet/TrackParticipantDamage.gd").receive(self,visual,amount,source)
