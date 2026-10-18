extends "res://gameplay/CobraAgent.gd"
## A proteção é consumível; preserva projéteis, animação e morte compartilhados.
var armor := 100.0
static var _vest_mesh: BoxMesh
static var _vest_material: StandardMaterial3D

func _ready() -> void:
	# Escolta de transportadora: cáqui e cinza de serviço, não o verde-oliva da gangue.
	uniform_tones = [Color(0.55, 0.48, 0.34), Color(0.46, 0.44, 0.38), Color(0.34, 0.36, 0.38)]
	super._ready()
	set_meta("character_name","Segurança da carga")
	set_meta("desert_cargo_guard",true)
	remove_from_group("iron_cobras")
	if _vest_mesh == null:
		_vest_mesh=BoxMesh.new()
		_vest_mesh.size=Vector3(.46,.45,.32)
		_vest_material=StandardMaterial3D.new()
		_vest_material.albedo_color=Color("272c2a")
		_vest_material.roughness=.9
	var vest:=MeshInstance3D.new()
	vest.name="BallisticVest"
	vest.mesh=_vest_mesh
	vest.material_override=_vest_material
	vest.position=Vector3(0,.15,0)
	visual.torso_node.add_child(vest)

func receive_damage(amount: float, source: Node = null) -> void:
	if dead or not is_finite(amount) or amount<=0: return
	var absorbed:=minf(armor,amount*.65)
	armor-=absorbed
	super.receive_damage(amount-absorbed,source)
