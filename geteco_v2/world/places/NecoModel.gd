extends "res://world/places/ServiceResidentModel.gd"
func _ready() -> void:
	shirt_color = Color("c78c4c")
	pants_color = Color("334c49")
	hat_color = Color("384e49")
	has_hat = true
	super._ready()
	_tailor_neco()

func _tailor_neco() -> void:
	var detail:=preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
	# Heavy leather apron, shoulder straps, patched pocket and a brass buckle.
	detail.piece(torso_node,Vector3(.32,.44,.06),Vector3(0,-.05,-.18),Color("34534c"))
	for side in [-1,1]:
		detail.piece(torso_node,Vector3(.035,.25,.04),Vector3(side*.10,.13,-.18),Color("bda478"))
	detail.piece(torso_node,Vector3(.19,.12,.035),Vector3(0,-.10,-.225),Color("647367"))
	detail.piece(torso_node,Vector3(.05,.045,.04),Vector3(.13,-.22,-.18),Color("ddb96c"))
	# Grey moustache and safety goggles resting on the cap are unique to Neco.
	for side in [-1,1]:
		detail.piece(head_node,Vector3(.065,.032,.035),Vector3(side*.033,-.052,-.151),Color("a6a292"))
		detail.piece(head_node,Vector3(.09,.06,.04),Vector3(side*.055,.10,-.16),Color("202e2c"))
		detail.piece(head_node,Vector3(.065,.035,.012),Vector3(side*.055,.10,-.187),Color("9ebfb4"))
	for arm in [left_lower_arm,right_lower_arm]:
		detail.piece(arm,Vector3(.09,.11,.10),Vector3(0,-.20,0),Color("b5a06d"))
	var tool:=Node3D.new()
	tool.name="Spanner"
	right_lower_arm.add_child(tool)
	tool.position=Vector3(0,-.22,-.09)
	detail.piece(tool,Vector3(.035,.035,.29),Vector3(0,0,-.1),Color("b9c5bd"))
	for side in [-1,1]:
		detail.piece(tool,Vector3(.035,.035,.08),Vector3(side*.045,0,-.25),Color("d0d8cd"))
		detail.piece(model_root,Vector3(.12,.09,.22),Vector3(side*.09,.055,-.04),Color("332d27"))


## Neco: boné, bigode grisalho e camisa de trabalho.
func _body_look() -> Dictionary:
	var look := super._body_look()
	look.merge({"variant": 7777, "female": false, "top": 1, "hat": 1, "beard": 1, "hair": 0,
		"hair_color": Color("a6a292"), "shoe": 1, "build": 2, "shoe_color": Color("332d27")}, true)
	return look
