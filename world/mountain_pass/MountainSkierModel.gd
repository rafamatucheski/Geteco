extends "res://world/mountain_pass/WinterResidentModel.gd"

var carve := 0.0
var fallen := false
var speed_factor := 0.5
var _fall_blend := 0.0
var ski_root: Node3D

func _ready() -> void:
	super._ready()
	walking = false
	activity = "idle"
	_build_gear()

func _build_gear() -> void:
	ski_root = Node3D.new()
	ski_root.name = "SkiGear"
	add_child(ski_root)
	var red := StandardMaterial3D.new()
	red.albedo_color = coat_color.lightened(.12)
	red.roughness = .62
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("171d22")
	dark.roughness = .82
	for i in 2:
		var ski := Node3D.new()
		ski.name = "SkiBinding%d" % i
		ski_root.add_child(ski)
		ski.add_child(_box(Vector3(0,0,0),Vector3(.12,.035,1.55),red))
		var tip := _box(Vector3(0,.035,.84),Vector3(.115,.03,.20),red)
		tip.rotation.x = -.28
		ski.add_child(tip)
		ski.add_child(_box(Vector3(0,.035,.02),Vector3(.13,.055,.28),dark))
		var pole := Node3D.new()
		pole.name = "SkiPole"
		elbows[i].add_child(pole)
		pole.position = Vector3(0,-.255,.015)
		pole.add_child(_cylinder(Vector3(0,-.49,0),.011,.98,dark))
		pole.add_child(_box(Vector3(0,-.91,0),Vector3(.075,.015,.075),dark))
	var head := pose_root.get_node("Head")
	# Replace headwear, rather than stacking an oversized helmet on a hood.
	for child in head.get_children(): child.free()
	part(head,Vector3(0,-.015,0),Vector3(.29,.32,.28),Color("be906d"))
	part(head,Vector3(0,.10,.01),Vector3(.35,.28,.34),coat_color.darkened(.48)).name = "SkiHelmet"
	part(head,Vector3(0,.025,-.152),Vector3(.27,.085,.05),Color("438d9d")).name = "Goggles"
	part(head,Vector3(0,-.072,-.135),Vector3(.13,.10,.045),Color("26313b"))

func _process(delta: float) -> void:
	super._process(delta)
	if not pose_root: return
	var blend := 1.0 - exp(-delta * 9.0)
	_fall_blend = lerpf(_fall_blend, 1.0 if fallen else 0.0, blend)
	var bend := .32 + speed_factor * .48
	pose_root.rotation = Vector3.ZERO
	pose_root.position = Vector3.ZERO
	for i in 2:
		limbs[i * 2].rotation = Vector3(-bend,0,0)
		knees[i].rotation.x = bend * 1.65
		limbs[i * 2 + 1].rotation = Vector3(-.20,0,.12 if i == 0 else -.12)
		elbows[i].rotation.x = -.90
	# Anchor soles at the bindings after solving knee flexion. No knee-locked
	# forward tilt around the floor, which swung the feet out from under the body.
	var sole: Vector3 = limbs[0].transform * knees[0].transform * Vector3(0,-.429,.04)
	pose_root.position = Vector3(0,.065-sole.y,-sole.z)
	var coat := pose_root.get_node("Coat") as Node3D
	coat.rotation.x = .10 + speed_factor * .16
	pose_root.get_node("Head").position.z = .10 + speed_factor * .08
	for i in 2:
		var foot: Vector3 = pose_root.transform * limbs[i*2].transform * knees[i].transform * Vector3(0,-.429,.04)
		var ski: Node3D = ski_root.get_child(i)
		ski.position = Vector3(foot.x,.035,0)
		ski.rotation = Vector3(0,carve*.10,-carve*.12)
		var pole: Node3D = elbows[i].get_node("SkiPole")
		pole.rotation.x = 1.4
	# A fall bends the body and equipment together, then blends through recovery.
	pose_root.rotation.z = _fall_blend * 1.25
	pose_root.rotation.x = _fall_blend * .35
	pose_root.position.y -= _fall_blend * .20
	ski_root.rotation.z = _fall_blend * .55


func _box(point: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = material
	node.position = point
	return node

func _cylinder(point: Vector3, radius: float, height: float, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	node.mesh = mesh
	node.material_override = material
	node.position = point
	return node

