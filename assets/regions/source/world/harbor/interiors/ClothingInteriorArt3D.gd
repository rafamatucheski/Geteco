extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"

var variant := 0
var counter := Vector2.ZERO
var _wood := "654833"
var _cloth := "496575"

func _ready() -> void:
	_wood = ["654833", "59452e", "b5a081", "744f3f"][variant]
	_cloth = ["6b4145", "466774", "66795e", "a06045"][variant]
	box("Foundation", Vector3(13, .18, 9), Vector3(0, -.11, 0), "403a31")
	for i in 26:
		box("Floorboard", Vector3(.49, .045, 9), Vector3(-6.25 + i * .5, 0, 0), _wood if i % 3 else "755941")
	_solid("BackWall", Vector3(13, 3.2, .2), Vector3(0, 1.6, -4.5), "9d9785" if variant != 3 else "875849")
	for side in [-1.0, 1.0]:
		_solid("SideWall%d" % int(side), Vector3(.18, 3.2, 9), Vector3(side * 6.5, 1.6, 0), "6e6251")
		box("Cornice", Vector3(.12, .12, 9), Vector3(side * 6.35, 2.9, 0), "c3aa7a")
		_solid("FrontWall%d" % int(side), Vector3(5.3, .7, .18), Vector3(side * 3.85, .35, 4.5), _wood)
	box("Runner", Vector3(2, .012, 6.8), Vector3(0, .032, .45), _cloth)
	for z in [-2.5, -2.35, 3.0, 3.15]:
		box("RunnerBorder", Vector3(1.9, .008, .05), Vector3(0, .043, z), "cbb785")
	match variant:
		0:
			counter = Vector2(0, -3.35)
			_rack("WestRack", Vector2(-4.7, -1.1), false)
			_rack("EastRack", Vector2(4.7, -1.1), false)
			_mannequin("DisplayWest", Vector2(-3.5, 2.3), "7a4844")
			_mannequin("DisplayEast", Vector2(3.5, 2.3), "475e71")
			_bench("FittingBench", Vector2(-4.8, .9))
		1:
			counter = Vector2(-4.1, -3.3)
			_rack("ExpeditionRack", Vector2(4.6, -2.7), false)
			_island("EquipmentIsland", Vector2(3.5, .2))
			_mannequin("WinterSuit", Vector2(-3.8, -.4), "426777")
			_bench("BootBench", Vector2(-3.8, 2.5))
			_shelves("BootShelves", Vector2(5.5, 2.9))
		2:
			counter = Vector2(4.1, -3.3)
			_island("BoutiqueIsland", Vector2(-2.9, -.6))
			_mannequin("TailoredCoat", Vector2(-4.8, -2.8), "889481")
			_mannequin("AlpineCoat", Vector2(3.4, .5), "c1aa88")
			_bench("VelvetSeat", Vector2(-3.4, 2.4))
			_rack("BackCollection", Vector2(-.4, -3.3), false)
		3:
			counter = Vector2(0, -3.35)
			_rack("VillageLeftRack", Vector2(-4.7, -.9), true)
			_rack("VillageRightRack", Vector2(4.7, 1), true)
			_mannequin("VillageParka", Vector2(-3.8, 2.7), "995344")
			_shelves("DeliveryShelves", Vector2(4.7, -3.1))
			_bench("FamilySeat", Vector2(-4.0, -3.3))
	_checkout(counter)
	# A full-height framed mirror and practical lamps, without decorative copy.
	box("Mirror", Vector3(1.2, 2.15, .06), Vector3(-6.35, 1.25, 2.1), "859b9e").rotation.y = PI / 2
	for x in [-4.5, 4.5]:
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, 2.8, -.3)
		lamp.light_color = Color("ffd6a1")
		lamp.light_energy = 1.1
		lamp.omni_range = 6
		add_child(lamp)
		box("LampShade", Vector3(.8, .14, .45), Vector3(x, 2.85, -.3), "d2b384")

func _solid(id: String, size: Vector3, point: Vector3, color: String) -> MeshInstance3D:
	var mesh := box(id, size, point, color)
	mesh.set_meta("interior_solid_id", StringName(id))
	return mesh

func _checkout(point: Vector2) -> void:
	var p := Vector3(point.x, 0, point.y)
	_solid("Checkout", Vector3(2.7, 1.05, 1.0), p + Vector3(0, .525, 0), _wood)
	_solid("Checkout", Vector3(2.84, .08, 1.1), p + Vector3(0, 1.09, 0), "c3b496")
	_solid("Checkout", Vector3(.44, .27, .35), p + Vector3(.7, 1.24, 0), "293835")
	for x in [-.9, -.65, -.4]:
		_solid("Checkout", Vector3(.2, .05, .27), p + Vector3(x, 1.17, 0), "d0b896")

func _rack(id: String, point: Vector2, along_z: bool) -> void:
	var root_node := Node3D.new()
	root_node.position = Vector3(point.x, 0, point.y)
	root_node.rotation.y = PI / 2 if along_z else 0
	add_child(root_node)
	for x in [-1.15, 1.15]:
		var post := cylinder("RackPost", .035, 2, Vector3(x, 1, 0), "55514a", root_node)
		post.set_meta("interior_solid_id", StringName(id))
	var rail := box("RackRail", Vector3(2.45, .06, .07), Vector3(0, 1.97, 0), "9c895c", root_node)
	rail.set_meta("interior_solid_id", StringName(id))
	for i in 5:
		var coat := box("FoldedCoat", Vector3(.31, 1.02, .42), Vector3(-.85 + i * .42, 1.25, 0), [_cloth, "997253", "69725b"][i % 3], root_node)
		coat.set_meta("interior_solid_id", StringName(id))
		box("Hanger", Vector3(.27, .03, .02), Vector3(-.85 + i * .42, 1.81, 0), "c3ad79", root_node)

func _bench(id: String, point: Vector2) -> void:
	_solid(id, Vector3(1.65, .5, .65), Vector3(point.x, .25, point.y), _wood)
	_solid(id, Vector3(1.7, .12, .7), Vector3(point.x, .56, point.y), _cloth)

func _island(id: String, point: Vector2) -> void:
	_solid(id, Vector3(1.5, .9, 1.8), Vector3(point.x, .45, point.y), _wood)
	_solid(id, Vector3(1.6, .07, 1.9), Vector3(point.x, .94, point.y), "c3aa7c")
	for x in [-.35, .35]:
		for i in 3:
			_solid(id, Vector3(.5, .09, .65), Vector3(point.x + x, 1.02 + i * .09, point.y), _cloth if i % 2 else "c3b59a")

func _shelves(id: String, point: Vector2) -> void:
	for i in 3:
		_solid(id, Vector3(1.25, .07, .65), Vector3(point.x, .35 + i * .52, point.y), _wood)
		for side in [-1.0, 1.0]:
			_solid(id, Vector3(.38, .23, .48), Vector3(point.x + side * .31, .50 + i * .52, point.y), "b1a28c")
	for side in [-1.0, 1.0]:
		_solid(id, Vector3(.07, 1.8, .65), Vector3(point.x + side * .63, .9, point.y), _wood)

func _mannequin(id: String, point: Vector2, coat: String) -> void:
	var p := Vector3(point.x, 0, point.y)
	var base := cylinder(id, .42, .06, p + Vector3(0, .05, 0), "aa9773")
	base.set_meta("interior_solid_id", StringName(id))
	for side in [-1.0, 1.0]:
		_solid(id, Vector3(.15, .13, .29), p + Vector3(side * .12, .13, .035), "292d2b")
		var leg := cylinder(id, .085, .69, p + Vector3(side * .12, .50, 0), "454946")
		leg.set_meta("interior_solid_id", StringName(id))
		var arm := cylinder(id, .075, .58, p + Vector3(side * .31, 1.16, 0), coat)
		arm.rotation.z = side * .13
		arm.set_meta("interior_solid_id", StringName(id))
		var hand := cylinder(id, .058, .13, p + Vector3(side * .35, .82, 0), "bcaf92")
		hand.set_meta("interior_solid_id", StringName(id))
	var torso := cylinder(id, .25, .73, p + Vector3(0, 1.12, 0), coat)
	torso.mesh.top_radius = .23
	torso.mesh.bottom_radius = .27
	torso.scale.z = .68
	torso.set_meta("interior_solid_id", StringName(id))
	_solid(id, Vector3(.022, .64, .02), p + Vector3(0, 1.13, .176), "d2bc86")
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = .125
	sphere.height = .29
	sphere.radial_segments = 16
	sphere.rings = 8
	head.mesh = sphere
	head.position = p + Vector3(0, 1.68, 0)
	head.material_override = material("bcaf92")
	head.set_meta("interior_solid_id", StringName(id))
	add_child(head)
