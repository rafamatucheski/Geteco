extends "res://tests/test_combat_flow.gd"
## Same assertions and production flow; capture collisions around the two
## locomotion failures without changing Actor or relaxing expectations.
var recent_motion: Array[Dictionary] = []
func _initialize() -> void:
	physics_frame.connect(_sample_motion)
	super._initialize()
func _sample_motion() -> void:
	if not is_instance_valid(player): return
	var contacts: Array[String] = []
	for index in player.get_slide_collision_count():
		var collision = player.get_slide_collision(index)
		contacts.append(str(collision.get_collider()))
	recent_motion.append({"position": player.global_position, "velocity": player.velocity, "phase": player.phase, "contacts": contacts})
	if recent_motion.size() > 30: recent_motion.pop_front()
func check(ok: bool, label: String, detail: String = "") -> void:
	if label.begins_with("recuando mirando:") or label.begins_with("fase da caminhada"):
		print("POLICE_FLOW_MOTION ", JSON.stringify(recent_motion))
	super.check(ok, label, detail)
