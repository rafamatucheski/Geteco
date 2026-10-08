extends "res://assets/CivilianModel.gd"
## Nelson, 60+: the shared native rig with an exposed crown and white temples.
var character_name := "Nelson"

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 10601
	lod_enabled = false
	coat_color = Color("6a283a")
	pants_color = Color("4a4034")
	wardrobe_overrides = {"female":false,"height":1.0,"build":1,"top":5,"bottom":0,"shoe":2,
		"hair":7,"hair_color":Color("e0dfd5"),"skin":Color("d4a585"),"beard":0,"hat":0,
		"glasses":true,"backpack":false,"bag":0,"inner":Color("e8ddc5"),"accent":Color("a99161")}
	activity = "talk"
	super._ready()
	set_meta("character_age_group","60_plus")
	set_meta("hair_style","bald_crown_white_sides")
	# Explicit temples ensure white side hair remains readable from the fixed
	# top-down camera, without covering the bald crown or enlarging the head.
	var kit = preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
	for side in [-1,1]:
		kit.piece(head_node,Vector3(.026,.103,.104),Vector3(side*.104,.172,-.019),Color("e0dfd5"),true)
		kit.piece(head_node,Vector3(.022,.035,.035),Vector3(side*.104,.130,.025),Color("d1d1ca"),true)
	# A tailored sommelier apron follows the torso, keeping normal shoulders,
	# hands and human stature shared with Dante.
	kit.piece(spine,Vector3(.30,.34,.025),Vector3(0,.035,.167),Color("442732"))
	kit.piece(spine,Vector3(.12,.095,.012),Vector3(.057,.035,.186),Color("573240"))
	kit.piece(spine,Vector3(.009,.064,.014),Vector3(.046,.071,.195),Color("ccb683"))
