extends Node3D
## Small visual cargo cycle under each streamed Northstar jib. The load stays
## above the walkable deck and the authored crane remains the physical object.
const PAINT := preload("res://world/regions/PortShipMaterials3D.gd")
var anchor := Vector2.ZERO
var phase_offset := 0.0
var clock := 0.0
var trolley: MeshInstance3D
var cable: MeshInstance3D
var spreader: MeshInstance3D
var load_mesh: MeshInstance3D

func configure(point: Vector2, offset: float) -> void:
	anchor = point
	phase_offset = offset

func _ready() -> void:
	name = "NorthstarCargoHoist3D"
	trolley = _part("Trolley",Vector3(.82,.32,.8),PAINT.material("crane"))
	cable = _part("HoistCable",Vector3(.045,1,.045),_color("384448"))
	spreader = _part("Spreader",Vector3(2.7,.16,.34),PAINT.material("crane"))
	load_mesh = _part("SuspendedCargo",Vector3(2.55,1.0,1.4),_color("a65f4c"))
	_update_pose()

func _part(label: String, size: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var shape := BoxMesh.new()
	shape.size = size
	instance.mesh = shape
	instance.material_override = material
	add_child(instance)
	return instance

func _color(hex: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(hex)
	material.roughness = .8
	return material

func _process(delta: float) -> void:
	clock += delta
	_update_pose()

func _update_pose() -> void:
	var cycle := fposmod(clock/30.0+phase_offset,1.0)
	var x := anchor.x+17.0
	var lift := 3.05
	if cycle < .20:
		lift = lerpf(3.05,3.9,smoothstep(0.0,.20,cycle))
	elif cycle < .50:
		x = lerpf(anchor.x+17.0,anchor.x+6.0,smoothstep(.20,.50,cycle))
		lift = 3.9
	elif cycle < .70:
		x = anchor.x+6.0
		lift = lerpf(3.9,3.05,smoothstep(.50,.70,cycle))
	elif cycle < .85:
		x = anchor.x+6.0
		lift = lerpf(3.05,3.9,smoothstep(.70,.85,cycle))
	else:
		x = lerpf(anchor.x+6.0,anchor.x+17.0,smoothstep(.85,1.0,cycle))
		lift = 3.9
	var boom_y := 5.15
	var cargo_top := lift+.5
	var cable_length := boom_y-cargo_top-.16
	trolley.position = Vector3(x,boom_y,anchor.y)
	load_mesh.position = Vector3(x,lift,anchor.y)
	spreader.position = Vector3(x,cargo_top+.12,anchor.y)
	cable.position = Vector3(x,cargo_top+.16+cable_length*.5,anchor.y)
	cable.scale.y = cable_length
