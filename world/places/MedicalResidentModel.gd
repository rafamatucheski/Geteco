extends "res://world/places/ServiceResidentModel.gd"
## Original Clara/Miguel medical accessories from HarborHospitalInterior3D._build_npcs.
func _ready() -> void:
	super._ready()
	var detail = preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
	detail.piece(torso_node,Vector3(.075,.11,.025),Vector3(-.09,.035,-.155),Color("f0f5ee"))
	detail.piece(torso_node,Vector3(.05,.025,.03),Vector3(-.09,.055,-.17),Color("438c91"))
	for side in [-1,1]: detail.piece(torso_node,Vector3(.018,.19,.022),Vector3(side*.08,.07,-.17),Color("364a52"))
	detail.piece(torso_node,Vector3(.055,.055,.025),Vector3(.08,-.04,-.18),Color("a7b7bc"),true)
	for part in model_root.find_children("*","MeshInstance3D",true,false):
		if part.material_override: part.material_override.roughness = .85

## Jaleco branco sobre pijama cirúrgico verde-azulado.
func _body_look() -> Dictionary:
	var look := super._body_look()
	look.merge({"top": 9, "top_color": Color("f0f5ee"), "inner": Color("438c91"), "bottom_color": Color("3d6f73"), "hat": 0}, true)
	return look
