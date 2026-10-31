extends "res://assets/CivilianModel.gd"
## Rig humano com ciclo de goles defasado. O copo segue o mesmo alvo da mão.
## As variantes 0-3 são os frequentadores do Lastro e 4-7 os do Sede; o slot 3 de cada bar trabalha no balcão.
const BODY_INDEX := [0,3,2,5, 1,4,2,5]
# Os frequentadores do deserto usam boné e um tom mais quente para os corpos compartilhados nunca parecerem as mesmas pessoas.
const DESERT_CAPS := [Color("8a3b2c"),Color("c9a25a"),Color("39505a"),Color("5b4a35")]
var patron_variant := 0
var character_name := ""
var cup: MeshInstance3D
var _standing_at := Vector3.ZERO
var _station_ready := false

func _is_bartender() -> bool:
	return patron_variant%4 == 3

func _is_female() -> bool:
	return BODY_INDEX[patron_variant%8] >= 3

func _ready() -> void:
	appearance_locked = true
	appearance_variant = 11140+patron_variant
	lod_enabled = false
	rotation.y = PI
	var desert := patron_variant >= 4
	coat_color = [Color("896746"),Color("596e6c"),Color("9a5650"),Color("737b47"),Color("b07a45"),Color("6d5a7a"),Color("8c8f5a"),Color("a4553f")][patron_variant%8]
	pants_color = Color("5a4b3c") if desert else Color("343d43")
	wardrobe_overrides = {"female":_is_female(),"height":.96+(patron_variant%4)*.02,"build":0,
		"top":1,"bottom":0,"shoe":0,"hair":4 if _is_female() else 1,
		"hair_color":[Color("40302a"),Color("1e1a17"),Color("6a4a32"),Color("2c2420")][patron_variant%4],
		"skin":[Color("c79470"),Color("8d5a3c"),Color("e0b08c"),Color("a8714c"),Color("6e452e"),Color("d29e78"),Color("b07c56"),Color("f0c49e")][patron_variant%8],
		"beard":1 if patron_variant in [2,4] else 0,"hat":0,
		"backpack":false,"bag":0,"glasses":patron_variant == 6,"inner":Color("d4c7ac"),"accent":Color("b9a274")}
	hand_provider = _working_hands if _is_bartender() else _drinking_hands
	if _is_bartender(): activity = ""
	elif patron_variant%4 < 2: activity = "talk"
	var picked: Dictionary = preload("res://assets/civilians/RoleBodyCatalog.gd").pick("pedestrian",patron_variant,false,false,BODY_INDEX[patron_variant%8])
	if not picked.is_empty():
		body_source = String(picked.path)
		body_tint = {"tone":Color(1.04,.95,.84)} if desert else picked.tint
		body_accessories = [{"kind":"cap","color":DESERT_CAPS[patron_variant%4],"band":Color("1c1d1e")}] if desert and patron_variant != 5 else picked.accessories
	super._ready()
	cup = MeshInstance3D.new()
	cup.name = "BarRag" if _is_bartender() else "DrinkGlass"
	var material := StandardMaterial3D.new()
	if _is_bartender():
		var rag := BoxMesh.new()
		rag.size = Vector3(.16,.02,.12)
		cup.mesh = rag
		material.albedo_color = Color("d8d2c0")
		material.roughness = .9
	else:
		var mesh := CylinderMesh.new()
		mesh.top_radius = .038
		mesh.bottom_radius = .031
		mesh.height = .115
		mesh.radial_segments = 10
		cup.mesh = mesh
		material.albedo_color = Color("bb8a39")
		material.roughness = .24
	cup.material_override = material
	add_child(cup)
	_standing_at = global_position
	_station_ready = true
	set_meta("work_activity","bar_service" if _is_bartender() else "bar_drinking")

func _can_drink() -> bool:
	return _station_ready and global_position.distance_to(_standing_at) < .12 and (not is_instance_valid(_owner_actor) or (_owner_actor.get("dead") != true and not _owner_actor.get_meta("workplace_threatened",false)))

func _sip() -> float:
	return smoothstep(.25,.8,sin(clock*.55+patron_variant*1.9))

func _drinking_hands() -> Array:
	if not _can_drink(): return [null,null]
	var drink := to_global(Vector3(.18,lerpf(1.02,1.51,_sip()),lerpf(.27,.12,_sip())))
	# O gesto de fala do rig fica na mão do copo, então quem fala é a mão livre.
	if activity != "talk": return [null,drink]
	var phase := clock*2.1+patron_variant*1.3
	var gesture := Vector3(-.2+sin(phase*.7)*.05,1.08+sin(phase)*.09,.28+sin(phase*1.6)*.04)
	# Mistura em direção a uma mão apoiada no quadril enquanto bebe, nunca saltando entre alvos.
	return [to_global(Vector3(-.22,.86,.06).lerp(gesture,1.0-smoothstep(0.0,.3,_sip()))),drink]

# Limpa o balcão em surtos, descansando entre eles, para o bar ter alguém trabalhando.
func _wipe() -> Vector3:
	var working := smoothstep(-.2,.2,sin(clock*.38+patron_variant))
	return Vector3(.18+sin(clock*2.2)*.2*working,lerpf(1.0,1.17,working),lerpf(.22,.46,working))

func _working_hands() -> Array:
	if not _can_drink(): return [null,null]
	return [null,to_global(_wipe())]

func _pose(delta: float) -> void:
	super._pose(delta)
	if not is_instance_valid(cup): return
	cup.visible = _can_drink()
	if not cup.visible: return
	if _is_bartender():
		cup.position = _wipe()-Vector3(0,.03,0)
		return
	cup.position = Vector3(.18,lerpf(1.02,1.51,_sip())+.035,lerpf(.27,.12,_sip())+.01)
	cup.rotation.x = -.65*_sip()
