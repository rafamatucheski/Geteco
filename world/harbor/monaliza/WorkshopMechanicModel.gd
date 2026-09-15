extends "res://world/mountain_pass/WinterResidentModel.gd"
## Workshop coveralls, chest pockets, reinforced knees and dark work boots.
func _ready() -> void:
	var uniform := Color("345b70")
	var skin := Color("bd8968")
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * 0.12, 0.82, 0)
		add_child(leg)
		limbs.append(leg)
		part(leg, Vector3(0,-0.32,0), Vector3(0.19,0.64,0.22), uniform)
		part(leg, Vector3(0,-0.39,0.10), Vector3(0.15,0.18,0.035), uniform.darkened(0.22))
		part(leg, Vector3(0,-0.73,0.06), Vector3(0.21,0.18,0.33), Color("292b2d"))
		var arm := Node3D.new()
		arm.position = Vector3(side * 0.26,1.35,0)
		add_child(arm)
		limbs.append(arm)
		part(arm, Vector3(0,-0.23,0), Vector3(0.18,0.47,0.21), uniform)
		part(arm, Vector3(0,-0.49,0.02), Vector3(0.14,0.15,0.15), skin)
	part(self, Vector3(0,1.12,0), Vector3(0.49,0.64,0.33), uniform)
	part(self, Vector3(0,0.83,0), Vector3(0.44,0.09,0.32), uniform.darkened(0.18))
	part(self, Vector3(0,1.12,0.17), Vector3(0.025,0.53,0.025), Color("a3adb0"))
	for side in [-1.0,1.0]:
		part(self, Vector3(side*0.13,1.26,0.17), Vector3(0.16,0.15,0.045), uniform.lightened(0.13))
	part(self, Vector3(0,1.47,0), Vector3(0.16,0.17,0.18), skin)
	part(self, Vector3(0,1.63,0), Vector3(0.32,0.32,0.29), skin)
	part(self, Vector3(0,1.76,-0.015), Vector3(0.34,0.11,0.29), Color("35302b"))
	for side in [-1.0,1.0]:
		part(self, Vector3(side*0.065,1.65,0.14), Vector3(0.035,0.026,0.02), Color("25272a"))
	part(self, Vector3(0,1.59,0.16), Vector3(0.06,0.07,0.07), skin)

func _process(delta: float) -> void:
	clock += delta
	for i in limbs.size():
		limbs[i].rotation.x = sin(clock*7.0+(PI if i in [0,3] else 0.0)) * (0.35 if walking else 0.012)
