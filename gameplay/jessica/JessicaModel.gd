extends "res://assets/CivilianModel.gd"
## Existing articulated rig, with a fixed slender, blonde identity.
func _init() -> void:
	appearance_locked = true
	appearance_variant = 9301
	coat_color = Color("d8d0c6")
	pants_color = Color("27323b")
	wardrobe_overrides = {"female":true,"build":0,"height":1.0,"top":1,"bottom":0,
		"shoe":0,"hat":0,"bag":0,"backpack":false,"glasses":false,"beard":0,
		"hair":3,"hair_color":Color("d7b969"),"skin":Color("efc5a5"),
		"inner":Color("ede8df"),"shoe_color":Color("f0eee9")}
	set_meta("character_identity","jessica")
	set_meta("voice_direction","delicate")
	set_meta("standing_rig_height",1.76)

func set_talking(value: bool) -> void:
	activity = "talk" if value else ""
