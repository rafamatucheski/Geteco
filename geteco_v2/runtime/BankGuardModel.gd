extends "res://gameplay/PoliceModel.gd"
# Original BankGuard uniform applied to the same articulated native rig.
const PART = preload("res://assets/regions/source/characters/pedestrians/CitizenDetails.gd")
var uses_shotgun := false
var eyes: Array[MeshInstance3D] = []
func _ready() -> void:
	super._ready()
	_rebuild_uniform()
	scale = Vector3(.88,.94,.90)*1.28
## Farda marrom original do segurança, sobre o corpo articulado.
func _body_look() -> Dictionary:
	var look := super._body_look()
	look.merge({"top": 6, "hat": 4, "shoe": 1, "top_color": Color("635544"), "bottom_color": Color("3a332b"),
		"accent": Color("2b2620"), "skin": Color("b98062") if uses_shotgun else Color("d6a582")}, true)
	return look

## O assalto (`RobberyActor`) pendura a arma direto no antebraço antigo e mira
## girando `right_upper_arm`. O antebraço antigo fica invisível; a arma volta a
## aparecer e a mão direita do corpo novo segue o cabo.
func _install_body() -> void:
	super._install_body()
	if not is_instance_valid(body): return
	for child in right_lower_arm.get_children():
		if child is Node3D and not child is GeometryInstance3D and child != muzzle_flash_3d:
			for geometry in child.find_children("*", "GeometryInstance3D", true, false): geometry.visible = true
	body.hand_provider = func() -> Array:
		for child in right_lower_arm.get_children():
			if child is Node3D and not child is GeometryInstance3D and child != muzzle_flash_3d and child.is_visible_in_tree():
				return [child.global_position, null]
		return body.hand_targets

func _clear_parts(parent: Node3D) -> void:
	for child in parent.get_children():
		if child is MeshInstance3D:
			child.hide()
func _rebuild_uniform() -> void:
	var cloth=Color("635544")
	var skin=Color("b98062") if uses_shotgun else Color("d6a582")
	_clear_parts(torso_node)
	_clear_parts(head_node)
	PART.piece(torso_node,Vector3(.37,.40,.25),Vector3.ZERO,cloth)
	PART.piece(torso_node,Vector3(.39,.055,.28),Vector3(0,-.19,0),Color("24282c"))
	for side in [-1,1]:
		PART.piece(torso_node,Vector3(.115,.10,.03),Vector3(side*.105,.07,-.14),cloth.darkened(.18))
		PART.piece(torso_node,Vector3(.09,.04,.15),Vector3(side*.17,.22,0),Color("33363a"))
	PART.piece(torso_node,Vector3(.055,.07,.025),Vector3(-.10,.15,-.16),Color("dabd72"))
	PART.piece(torso_node,Vector3(.06,.11,.055),Vector3(.19,-.15,0),Color("20252c"))
	PART.piece(head_node,Vector3(.26,.28,.245),Vector3(0,-.025,0),skin,true)
	PART.piece(head_node,Vector3(.055,.07,.06),Vector3(0,-.03,-.14),skin)
	for side in [-1,1]:
		eyes.append(PART.piece(head_node,Vector3(.035,.018,.02),Vector3(side*.065,.005,-.13),Color("22252b")))
		PART.piece(head_node,Vector3(.045,.07,.05),Vector3(side*.145,-.025,0),skin,true)
	# Solid crown covers the scalp; the brim is entirely above the face.
	var crown := PART.piece(head_node,Vector3.ONE,Vector3(0,.145,0),cloth)
	var cap := CylinderMesh.new()
	cap.top_radius=.17
	cap.bottom_radius=.155
	cap.height=.11
	cap.radial_segments=12
	crown.mesh=cap
	PART.piece(head_node,Vector3(.34,.035,.20),Vector3(0,.105,-.16),cloth.darkened(.2))
	PART.piece(head_node,Vector3(.06,.05,.018),Vector3(0,.15,-.157),Color("dabd72"))
	for limb in [left_upper_leg,right_upper_leg,left_lower_leg,right_lower_leg]:
		for child in limb.get_children():
			if child is MeshInstance3D and child.mesh is CylinderMesh:
				var shape=BoxMesh.new()
				shape.size=Vector3(.135,child.mesh.height,.15)
				child.mesh=shape
	# Keep the shared articulated arms, mesh arsenal and Dante combat poses.
	for limb in [left_upper_arm, right_upper_arm]:
		for part in limb.get_children():
			if part is MeshInstance3D:
				part.material_override = _make_mat(cloth, .8)
	# Antebraços contínuos até as mãos; pele igual à do rosto em ambos os lados.
	for limb in [left_lower_arm,right_lower_arm]:
		for part in limb.get_children():
			if part is MeshInstance3D and part!=muzzle_flash_3d:
				part.material_override=_make_mat(skin,.8)
				if part.mesh is CylinderMesh:
					part.mesh=part.mesh.duplicate()
					part.mesh.height=.20
					part.mesh.top_radius=.052
					part.mesh.bottom_radius=.045
					part.position.y=-.10
	model_root.rotation.y = PI
