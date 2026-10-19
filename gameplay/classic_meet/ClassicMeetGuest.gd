extends "res://scripts/Actor.gd"
## Normal damageable civilians, sharing walking, gestures and threat recovery.
signal died(actor: CharacterBody3D)
var meetup_activity := "talk"
var initial_yaw := 0.0
var owner_gameplay: Node
var person: Node3D

func _ready() -> void:
	super._ready()
	# Papel próprio (CrimeVictims.PERSON_ROLES): matar um convidado conta homicídio, como civil.
	set_meta("gameplay_role","meet_guest")
	add_to_group("v2_damageable")
	person = visual.get_child(0)
	visual.rotation.y = initial_yaw
	person.activity = "talk" if meetup_activity == "talk" else ""
	if meetup_activity == "inspect": person.hand_provider = _engine_gesture
	if is_instance_valid(owner_gameplay):
		var reaction = preload("res://gameplay/civilian_reactions/WorkplaceThreatReaction.gd").install(self,person,owner_gameplay)
		if reaction != null: reaction.react_to_aim = true

func _physics_process(delta: float) -> void:
	# The threat adapter temporarily rotates the CivilianModel directly. Restore
	# Actor's +Z model / -Z visual convention before ordinary walking resumes.
	if is_instance_valid(person): person.rotation.y = PI
	if route.is_empty(): visual.rotation.y = initial_yaw
	super._physics_process(delta)

func _facing_yaw(direction: Vector3) -> float:
	return atan2(direction.x,direction.z)-visual.global_rotation.y

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount <= 0.0: return
	super.receive_damage(amount,source)
	if dead: died.emit(self)

func _engine_gesture() -> Array:
	if dead or get_meta("workplace_threatened",false): return [null,null]
	var reach := .43+.045*sin(person.clock*1.1+identity)
	return [null,person.to_global(Vector3(.19,1.11,reach))]
