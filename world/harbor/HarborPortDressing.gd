extends RefCounted

const CARGO := [Vector2(3890,4010),Vector2(4470,4250),Vector2(5030,4250),Vector2(5380,4250),Vector2(4180,4870),Vector2(4740,4870),Vector2(5290,4870),Vector2(5520,4825),Vector2(4180,5410),Vector2(4650,5420),Vector2(5190,5420),Vector2(5830,4840)]
const MASTS := [Vector2(3650,3400),Vector2(4550,3470),Vector2(5450,3470),Vector2(3860,4270),Vector2(5590,4280),Vector2(3860,4880),Vector2(5570,4930),Vector2(5520,5700)]

static func build(port: Node2D) -> void:
	for i in CARGO.size():
		var rect := Rect2(CARGO[i],Vector2(110,65))
		var model: Node2D = port._model("loose_cargo",rect,i,"LooseCargo%d" % i)
		_breakable(port,rect,"LooseCargoSolid%d" % i,"wood",model)
	for point in [Vector2(3920,4990),Vector2(4810,4990),Vector2(5530,5000)]:
		_breakable(port,Rect2(point,Vector2(18,22)),"PortBin","trash",null)
	for i in MASTS.size():
		var point: Vector2 = MASTS[i]
		var model: Node2D = port._model("floodlight",Rect2(point-Vector2(36,12),Vector2(72,24)),i,"PortFloodlight%d" % i)
		model.z_index = 8
		port._solid(Rect2(point-Vector2(8,8),Vector2(16,16)),"FloodlightBase%d" % i)
		var light := preload("res://world/harbor/HarborPortFloodlight.gd").new()
		light.position = point
		light.direction = Vector2(160 if i%2 == 0 else -160,180)
		port.add_child(light)

static func _breakable(port: Node2D, rect: Rect2, label: String, debris_material: String, model: Node2D) -> void:
	var body := preload("res://world/shared/BreakableProp.gd").new()
	body.name = label
	body.position = rect.get_center()
	body.extent = rect.size
	body.debris_material = debris_material
	body.presentation = model
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	collision.shape = shape
	body.add_child(collision)
	port.add_child(body)
