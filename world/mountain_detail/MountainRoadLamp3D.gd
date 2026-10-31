extends Node3D

## Small roadside lantern. The weather clock controls its shadowless light.
## Passa pelo LightBudget como RoadsideLamp (runtime/desert/roadside): a serra tem dezenas destes
## postes e todos acendiam à noite sem teto; agora só os que estão a até 25 m do jogador e
## dentro das 8 fontes acendem. A região (NativeRegion.set_night_lights) continua dona do nível
## da noite; aqui ele só vira a energia base do pedido.
## Sem orçamento (GETECO_LIGHT_BUDGET=0) vale o comportamento antigo: a região manda sozinha.
const LIGHT_BUDGET := preload("res://gameplay/lights/LightBudget.gd")
var lamp: OmniLight3D
var _player: Node3D
var _region: Node

func _ready() -> void:
	name = "MountainRoadLamp"
	var pole := _box("Pole",Vector3(0,1.65,0),Vector3(.16,3.3,.16),Color("403e37"))
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box("LanternFrame",Vector3(0,3.45,0),Vector3(.42,.48,.42),Color("323b3d"))
	_box("LanternGlass",Vector3(0,3.45,0),Vector3(.30,.36,.30),Color("d1ab68"))
	_box("LanternCap",Vector3(0,3.75,0),Vector3(.5,.10,.5),Color("323b3d"))
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.24,3.5,.24)
	collider.shape = shape
	collider.position.y = 1.75
	body.add_child(collider)
	add_child(body)
	var light := OmniLight3D.new()
	light.name = "RoadNightLight"
	light.position.y = 3.45
	light.light_color = Color("ffe0ab")
	light.omni_range = 10.0
	light.omni_attenuation = 1.6
	light.shadow_enabled = false
	light.light_energy = 0.0
	light.set_meta("night_energy",1.15)
	light.add_to_group("mountain_night_light")
	add_child(light)
	lamp = light
	preload("res://gameplay/street_physics/FragileProps3D.gd").register_node("lamp",self,get_parent())
	# Referência do orçamento é o jogador, como em RoadsideLamp/VehicleEquipment (a câmera fica longe
	# demais para o raio de 25 m). A região é o ancestral que guarda o nível da noite.
	var node := get_parent()
	while node != null and _region == null:
		if node.get("mountain_night_level") != null: _region = node
		node = node.get_parent()
	node = get_parent()
	while node != null and node.get("session") == null: node = node.get_parent()
	if node != null:
		var world = node.session.get("world")
		if world != null: _player = world.get("player")
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.register(self)

func _exit_tree() -> void:
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.unregister(self)

func _night() -> float:
	return float(_region.get("mountain_night_level")) if is_instance_valid(_region) else 0.0

func _reference() -> Vector3:
	if is_instance_valid(_player): return _player.global_position
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if is_instance_valid(camera) else Vector3.INF

func _budget_request() -> Dictionary:
	var night := _night()
	var wanted: Array[Dictionary] = []
	# Poste derrubado (FragileProps3D._kill_light) fica fora da disputa até LampRecovery3D tirar a marca.
	if night > .05 and is_visible_in_tree() and not lamp.get_meta("street_destroyed",false):
		# O orçamento esmaece pela distância a partir desta energia; a noite da região entra aqui.
		lamp.set_meta("budget_energy",float(lamp.get_meta("night_energy",1.0))*night)
		wanted.append({"light": lamp, "headlight": false})
	var lights: Array[Light3D] = [lamp]
	return {"lights": lights, "wanted": wanted, "player": false, "camera": _reference()}

func _process(_delta: float) -> void:
	if not LIGHT_BUDGET.enabled: return
	# De dia e apagada não custa nada; à noite pede a rodada do quadro (refresh ignora repetidos),
	# porque sem veículo por perto ninguém mais a chamaria (mesmo motivo de RoadsideLamp).
	if lamp.visible or (_night() > .05 and is_visible_in_tree()): LIGHT_BUDGET.refresh()

func _box(label: String,at: Vector3,size: Vector3,color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = label
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .8
	mesh.material_override = material
	add_child(mesh)
	return mesh
