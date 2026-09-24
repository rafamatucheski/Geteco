extends Node3D

## Human-scale hold beneath Santa Mare's working deck. NativePlace owns the
## matching physical solids, while this model supplies the visible interior.
var solid_rects := {
	"PortBulkhead": Rect2(-9.0, -6.0, .28, 12.0),
	"StarboardBulkhead": Rect2(8.72, -6.0, .28, 12.0),
	"BowBulkhead": Rect2(-9.0, -6.0, 18.0, .28),
	"SternBulkhead": Rect2(-9.0, 5.72, 18.0, .28),
	"PortCargoRacks": Rect2(-8.0, -2.25, 3.15, 4.7),
	"StarboardCargoRacks": Rect2(4.85, -1.35, 3.15, 3.8),
	"ForwardMachinery": Rect2(-3.5, -5.4, 2.0, 1.5),
	"SecretChest": Rect2(6.15, -5.05, 1.1, .9),
}
var materials: Dictionary = {}

func _ready() -> void:
	name = "SantaMareCargoHold3D"
	_box("RibbedSteelFloor",Vector3(0,-.075,0),Vector3(18,.15,12),"384a50")
	for x in [-8.85,8.85]:
		_box("HullBulkhead",Vector3(x,1.6,0),Vector3(.3,3.2,12),"52666b")
	for z in [-5.85,5.85]:
		_box("EndBulkhead",Vector3(0,1.6,z),Vector3(18,3.2,.3),"52666b")
	for x in [-8.35,-4.35,0.0,4.35,8.35]:
		_box("HullFrame",Vector3(x,1.62,-5.65),Vector3(.15,3.24,.25),"a6aa9b")
		_box("HullFrame",Vector3(x,1.62,5.65),Vector3(.15,3.24,.25),"a6aa9b")
	for z in [-4.7,-2.35,0.0,2.35,4.7]:
		for x in [-8.55,8.55]:
			_box("HullRib",Vector3(x,1.55,z),Vector3(.17,3.1,.23),"a0a89e")
		for side in [-7.3,7.3]:
			_box("CeilingRib",Vector3(side,3.1,z),Vector3(2.4,.17,.2),"879795")
	for x in [-6.4,6.4]:
		for z in [-1.6,.15,1.9]:
			_box("Pallet",Vector3(x,.1,z),Vector3(2.6,.2,1.28),"86684c")
			for side in [-.85,.85]:
				_box("StackedFreight",Vector3(x+side,.75,z),Vector3(.82,1.1,1.02),"997654" if x < 0 else "738583")
				_box("CrateBand",Vector3(x+side,1.0,z),Vector3(.85,.06,1.05),"c2ad7c")
	_box("MachineryPedestal",Vector3(-2.5,.75,-4.65),Vector3(2.0,1.5,1.5),"3b5158")
	_box("MachineryWheel",Vector3(-2.5,1.4,-3.86),Vector3(1.1,.12,.12),"b9a269")
	for x in [-7.7,7.7]:
		_box("PipeRun",Vector3(x,2.7,0),Vector3(.09,.09,10.7),"b89864")
	for z in [-3.0,0.0,3.0]:
		_box("CeilingLamp",Vector3(0,2.94,z),Vector3(1.6,.12,.55),"dbd8b8")
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(0,2.72,z)
		lamp.light_color = Color("ffe4b3")
		lamp.light_energy = .65
		lamp.omni_range = 6.8
		lamp.shadow_enabled = false
		add_child(lamp)
	_box("HatchLadder",Vector3(-.95,1.2,5.42),Vector3(.12,2.4,.12),"c9af64")
	_box("HatchLadder",Vector3(-.15,1.2,5.42),Vector3(.12,2.4,.12),"c9af64")
	for y in 6:
		_box("LadderRung",Vector3(-.55,.32+float(y)*.36,5.42),Vector3(.86,.07,.12),"d1ba75")
	# A narrow gap around the forward racks reveals the hidden sea chest.
	_box("TreasureChest",Vector3(6.7,.36,-4.6),Vector3(1.1,.72,.9),"7b5638")
	_box("TreasureLid",Vector3(6.7,.77,-4.6),Vector3(1.15,.13,.95),"ae8851")
	for x in [6.27,7.13]:
		_box("ChestBand",Vector3(x,.46,-4.6),Vector3(.08,.86,.97),"d4b75e")
	_box("ChestLatch",Vector3(6.7,.48,-4.1),Vector3(.24,.25,.07),"e1c970")
	for x in [-2.4,2.4]:
		_box("WalkingLaneEdge",Vector3(x,.012,0),Vector3(.055,.01,9.7),"bca966")

func _mat(color: String) -> StandardMaterial3D:
	if materials.has(color): return materials[color]
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.metallic = .14
	result.roughness = .78
	materials[color] = result
	return result

func _box(label: String, point: Vector3, size: Vector3, color: String) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	mesh.material_override = _mat(color)
	add_child(mesh)
