extends "res://world/places/WalkupFacadeDoor.gd"
## Streamed with its facade; the shared access controller owns push and timing.
func _ready() -> void:
	add_to_group("v2_walkin_facade")
	hinge = Node3D.new()
	hinge.position = Vector3(-.58, 0, 4.24)
	add_child(hinge)
	var geometry := preload("res://world/desert/DesertGeometry.gd")
	geometry.box(hinge,"Door",Vector3(.58,1.19,0),Vector3(1.16,2.26,.08),Color("796047"),true)
	geometry.box(hinge,"Panel",Vector3(.58,.78,.05),Vector3(.86,.78,.025),Color("896d50"))
	geometry.box(hinge,"Handle",Vector3(.97,1.13,.07),Vector3(.065,.16,.07),Color("737778"))
	set_open_amount(0.0)
