extends Node3D
## A única luz de um lugar da beira de estrada (cobertura do posto, porta da casinha da torre,
## portal do ferro-velho, toldo do lanche). Passa pelo LightBudget como os faróis: só acende à
## noite, a até 25 m do jogador e dentro do teto de 8 fontes; de dia nem entra na disputa.
## O orçamento só roda quando algum veículo pede (VehicleEquipment); a pé e sem trânsito por
## perto a luz nunca acendia (captura de 19/10), então à noite ela mesma pede a rodada do quadro
## (refresh ignora o segundo pedido no mesmo quadro).
## Sem orçamento (GETECO_LIGHT_BUDGET=0) ela mesma confere noite e distância, devagar.
## O resto da noite do lugar é emissão do atlas (letreiro, visor, janela), sem custo de luz.
const LIGHT_BUDGET := preload("res://gameplay/lights/LightBudget.gd")
const CHECK_SECONDS := .5
var lamp: OmniLight3D
var energy := 1.6
var _player: Node3D
var _clock := 0.0

func setup(color: Color, reach: float, power: float) -> void:
	energy = power
	lamp = OmniLight3D.new()
	lamp.name = "RoadsideLight"
	lamp.light_color = color
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	lamp.light_energy = 0.0
	lamp.visible = false
	add_child(lamp)

func _ready() -> void:
	# O jogador é o ponto de referência do orçamento, como em VehicleEquipment (a câmera fica a
	# ~36 m dele e nunca entraria no raio de 25 m).
	var node := get_parent()
	while node != null and node.get("session") == null: node = node.get_parent()
	if node != null:
		var world = node.session.get("world")
		if world != null: _player = world.get("player")
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.register(self)

func _exit_tree() -> void:
	if LIGHT_BUDGET.enabled: LIGHT_BUDGET.unregister(self)

func _night() -> float:
	return PaintedWindow._night

func _reference() -> Vector3:
	if is_instance_valid(_player): return _player.global_position
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	return camera.global_position if is_instance_valid(camera) else Vector3.INF

func _budget_request() -> Dictionary:
	var night := _night()
	var wanted: Array[Dictionary] = []
	if night > .05 and is_visible_in_tree():
		# O orçamento esmaece pela distância a partir desta energia; a noite entra aqui.
		lamp.set_meta("budget_energy", energy * night)
		wanted.append({"light": lamp, "headlight": false})
	var lights: Array[Light3D] = [lamp]
	return {"lights": lights, "wanted": wanted, "player": false, "camera": _reference()}

func _process(delta: float) -> void:
	if LIGHT_BUDGET.enabled:
		# De dia e apagada não custa nada; acesa, a mesma rodada também a apaga ao amanhecer.
		if lamp.visible or (_night() > .05 and is_visible_in_tree()): LIGHT_BUDGET.refresh()
		return
	_clock += delta
	if _clock < CHECK_SECONDS: return
	_clock = 0.0
	var on := _night() > .05 and is_visible_in_tree() and lamp.global_position.distance_to(_reference()) <= LIGHT_BUDGET.LIGHT_RADIUS
	if lamp.visible != on: lamp.visible = on
	var target := energy * _night() if on else 0.0
	if not is_equal_approx(lamp.light_energy, target): lamp.light_energy = target
