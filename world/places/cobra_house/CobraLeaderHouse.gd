extends Node3D
## Takeshi's ground-floor living room and race office, in human-scale metres.
var solids: Array[Rect2] = [Rect2(-6,-4.5,12,.25),Rect2(-6,-4.5,.25,9),Rect2(5.75,-4.5,.25,9),Rect2(-6,4.25,4.8,.25),Rect2(1.2,4.25,4.8,.25),Rect2(1.15,-2.4,2.5,1.3),Rect2(-5.45,-2.8,1.15,3.9),Rect2(-1.3,-4.15,4.8,.65)]
# East service wall leaves the living room, desk and entrance axis unobstructed.
var roof_access_point := Vector3(4.86,0,2.0)
var roof_access_yaw := PI*.5

static func definition_data() -> Dictionary:
	var exterior := Vector3(8352.5,0,1975.0)/16.0
	var exterior_depth := 170.0/16.0
	var yaw := 0.0
	var edit: Dictionary = preload("res://world/editing/WorldServiceBuildings.gd").changes().get("building/CourtyardHouse",{})
	if not edit.is_empty():
		exterior = Vector3(float(edit.position[0]),0,float(edit.position[1]))
		exterior_depth = float(edit.size[1])
		yaw = deg_to_rad(float(edit.rotation))
	var outward := Vector3.BACK.rotated(Vector3.UP,yaw)
	var doorway := exterior + outward*(exterior_depth*.5-1.8+.04)
	var reward := {"id":"cobra_leader_house_cash_01","kind":"cash","amount":1200,"local_position":Vector3(-2.5,0,-3.3)}
	return {"id":"cobra_leader_house","name":"Takeshi","original_name":"Takeshi","region":"harbor","model":"res://world/places/cobra_house/CobraLeaderHouse.gd","variant":0,"size":Vector2(12,9),"service":"story_records","exterior_position":exterior,"editor_rotation":yaw,"walkup_door_position":doorway,"entry_position":doorway+outward*3.1,"return_position":doorway+outward*3.5,"spawn":Vector3(0,.08,3.5),"exit":Vector3(0,.08,4),"camera_target":Vector3(0,.55,-.15),"camera_offset":Vector3(0,18,15),"camera_size":14.0,"npc_model":"","npc_point":Vector3.ZERO,"hidden_access":true,"reward":reward,"rewards":[reward]}

func _ready() -> void:
	_box("Floor",Vector3(0,-.03,0),Vector3(12,.1,9),Color("635144"))
	_box("BackWall",Vector3(0,1.55,-4.4),Vector3(12,3.1,.2),Color("b4a18a"))
	for side in [-1.0,1.0]:
		_box("SideWall",Vector3(side*5.9,1.55,0),Vector3(.2,3.1,9),Color("b4a18a"))
		_box("EntranceWall",Vector3(side*3.55,.25,4.4),Vector3(4.7,.5,.2),Color("b4a18a"))
	_box("Rug",Vector3(-1,.035,.6),Vector3(5.2,.015,3.8),Color("493e36"))
	_box("Sofa",Vector3(-4.87,.37,-.85),Vector3(1.05,.72,3.7),Color("33463e"))
	_box("SofaBack",Vector3(-5.36,.68,-.85),Vector3(.2,.7,3.7),Color("33463e"))
	for z in [-2.0,-.85,.3]: _box("Cushion",Vector3(-4.7,.77,z),Vector3(.8,.18,1.05),Color("516253"))
	_box("DeskTop",Vector3(2.4,.84,-1.75),Vector3(2.5,.12,1.3),Color("7d5336"))
	for x in [1.25,3.55]:
		for z in [-2.3,-1.2]: _box("DeskLeg",Vector3(x,.4,z),Vector3(.12,.8,.12),Color("40342a"))
	_box("RaceList",Vector3(2.1,.917,-1.7),Vector3(.48,.015,.65),Color("ebe6d1"))
	for z in [-1.92,-1.8,-1.68,-1.56]: _box("Ink",Vector3(2.1,.929,z),Vector3(.34,.005,.015),Color("454238"))
	_box("Telephone",Vector3(3.15,.96,-1.75),Vector3(.3,.12,.25),Color("23282b"))
	_box("Cabinet",Vector3(1.1,.6,-3.83),Vector3(4.8,1.2,.6),Color("65442e"))
	for x in [-.9,.45,1.8,3.15]:
		_box("CabinetDoor",Vector3(x,.6,-3.51),Vector3(1.15,1.1,.04),Color("785439"))
		_box("Handle",Vector3(x+.4,.7,-3.47),Vector3(.03,.16,.03),Color("b7b7ac"))
	_box("RacePhotoFrame",Vector3(-2.8,1.9,-4.24),Vector3(1.2,.85,.05),Color("352b26"))
	_box("RacePhoto",Vector3(-2.8,1.9,-4.2),Vector3(1.05,.7,.02),Color("384f59"))
	_box("CarInPhoto",Vector3(-2.8,1.85,-4.18),Vector3(.65,.2,.02),Color("bf3a32"))
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0,2.65,-1)
	lamp.light_color = Color("ffe0b4")
	lamp.light_energy = .55
	lamp.omni_range = 8.0
	lamp.shadow_enabled = false
	add_child(lamp)
	_box("LampShade",Vector3(0,2.75,-1),Vector3(.65,.12,.65),Color("d1bd98"))

func _box(label: String, point: Vector3, size_value: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.name = label
	var mesh := BoxMesh.new()
	mesh.size = size_value
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .82
	# Caixas de cor lisa liam como plano chapado: relevo por tipo de peça, mesmo tom.
	var kind := "wood" if label == "Floor" else ("fabric" if label in ["Rug", "Sofa", "SofaBack", "Cushion"] else "plaster")
	preload("res://assets/urban_detail/UrbanSurfaces.gd").detail(material, kind, 1.5, .7)
	material.albedo_color = Color(minf(color.r * material.albedo_color.r, 1.0), minf(color.g * material.albedo_color.g, 1.0), minf(color.b * material.albedo_color.b, 1.0))
	material.roughness = 1.0
	node.material_override = material
	add_child(node)
	node.position = point
