extends "res://assets/CivilianModel.gd"
## Existing human rig, with hands reaching the occupied machine's controls.
var character_name := ""
var player_variant := 0
var _machine_position := Vector3.ZERO
var _at_machine := false

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 10820 + player_variant
	lod_enabled = false
	rotation.y = PI
	coat_color = Color("c9785c") if player_variant == 0 else Color("5b8d95")
	pants_color = Color("34334a") if player_variant == 0 else Color("383b42")
	wardrobe_overrides = {"female":player_variant == 0,"height":.98 if player_variant == 0 else 1.02,
		"build":0,"top":1,"bottom":0,"shoe":0,"hair":4 if player_variant == 0 else 1,
		"hair_color":Color("3f2c28"),"skin":Color("c89471") if player_variant == 0 else Color("e1b28b"),
		"beard":0,"hat":0,"backpack":false,"bag":0,"glasses":false,
		"inner":Color("dfd5bd"),"accent":Color("d9bd78")}
	hand_provider = _playing_hands
	super._ready()
	_machine_position = global_position
	_at_machine = true
	set_meta("work_activity", "arcade")

func _playing_hands() -> Array:
	if not _at_machine: return [null, null]
	if is_instance_valid(_owner_actor) and (_owner_actor.get("dead") == true or _owner_actor.get_meta("workplace_threatened", false)):
		return [null, null]
	if global_position.distance_to(_machine_position) > .12: return [null, null]
	# Continuous small motions read as joystick steering and button tapping.
	return [to_global(Vector3(-.19+sin(clock*2.3)*.016,1.03,.56)),
		to_global(Vector3(.17,1.01+maxf(0.0,sin(clock*7.2))*.014,.55))]
