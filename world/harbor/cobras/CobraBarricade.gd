@tool
extends "res://world/shared/PhysicalCargo.gd"
class_name CobraBarricade
## Pilha de pneus do território hostil. Reaproveita o contrato físico de
## PhysicalCargo por inteiro: empurrão, impacto de veículo, dano, desmonte em
## destroços — só a apresentação 3D e os parâmetros de massa/resistência são
## específicos daqui.

func _ready() -> void:
	cargo_material = "rubber"
	mass_kg = 90.0
	resistance = 55.0
	health = resistance
	extent = Vector2(32, 24)
	super._ready()
	add_to_group("cobra_prop")
	var art := preload("res://world/mountain_pass/MountainStaticModelView.gd").new()
	add_child(art)
	art.build_view(preload("res://world/harbor/cobras/CobraTireStack3D.gd"), 2.6, 22.0, Vector3(0, 0.35, 0))
	view = art
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = extent
	shape.shape = rect
	add_child(shape)
