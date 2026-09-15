extends Node

const SECURITY = preload("res://world/harbor/HarborPortSecurity.gd")
var authorized := false
var alerted := false
var was_inside := false
var initialized := false
var dismissed := false
var guards: Array[Node2D] = []
var panel: PanelContainer
var speech: Label
var pay: Button
var escape_time := 0.0
var approach_time := 0.0
var reply_time := 0.0
var refuse: Button
var _dialogue_lock_player: Node2D
var _dialogue_was_active := false
var _controls_were_disabled := false
const GREETING := "GUARDA: Por que você quer entrar no porto?\nSem autorização, eu chamo a segurança privada."

func player() -> Node2D:
	return get_parent().get_parent().get_node_or_null("Player")

func actor() -> Node2D:
	var travel := get_node_or_null("/root/RegionTravel")
	if travel:
		var car: Node2D = travel.controlled_car()
		if car: return car
	return player()

func _ready() -> void:
	for point in [Vector2(3390,3340), Vector2(3430,3530), Vector2(3510,3540)]:
		var guard := SECURITY.new()
		guard.checkpoint = self
		guard.position = point
		get_parent().add_child.call_deferred(guard)
		guards.append(guard)
	var hud := CanvasLayer.new()
	hud.layer = 24
	add_child(hud)
	panel = PanelContainer.new()
	panel.position = Vector2(24,160)
	hud.add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	speech = Label.new()
	speech.text = GREETING
	box.add_child(speech)
	pay = Button.new()
	pay.text = "Vim tratar de um negócio. Pagar propina — R$ 100"
	pay.pressed.connect(pay_bribe)
	box.add_child(pay)
	refuse = Button.new()
	refuse.text = "Não vou pagar."
	refuse.pressed.connect(refuse_bribe)
	box.add_child(refuse)
	panel.hide()

func _exit_tree() -> void:
	_set_dialogue_lock(false)

func _set_dialogue_lock(active: bool) -> void:
	if active:
		var p := player()
		if p == null or p == _dialogue_lock_player: return
		_set_dialogue_lock(false)
		_dialogue_lock_player = p
		_dialogue_was_active = p.get("is_in_dialogue") == true
		_controls_were_disabled = p.get("is_control_disabled") == true
		p.set("is_in_dialogue", true)
		p.set("is_control_disabled", true)
		if p is CharacterBody2D: p.velocity = Vector2.ZERO
	elif is_instance_valid(_dialogue_lock_player):
		_dialogue_lock_player.set("is_in_dialogue", _dialogue_was_active)
		_dialogue_lock_player.set("is_control_disabled", _controls_were_disabled)
		_dialogue_lock_player = null

func refuse_bribe() -> void:
	if not panel.visible or dismissed: return
	dismissed = true
	reply_time = 5.0
	speech.text = "GUARDA: Então dê meia-volta. A cancela fica fechada.\nSe entrar sem autorização, vou chamar a segurança."
	pay.hide()
	refuse.hide()
	panel.reset_size()

func _position_dialogue() -> void:
	var anchor := guards[0].get_global_transform_with_canvas().origin
	var bounds := get_viewport().get_visible_rect().grow(-12.0)
	var extent := panel.get_combined_minimum_size()
	panel.position = anchor - Vector2(extent.x * 0.5, extent.y + 42.0)
	panel.position.x = clampf(panel.position.x, bounds.position.x, maxf(bounds.position.x, bounds.end.x - extent.x))
	panel.position.y = clampf(panel.position.y, bounds.position.y, maxf(bounds.position.y, bounds.end.y - extent.y))

func pay_bribe() -> void:
	var p := player()
	if p == null or alerted or authorized or actor().global_position.distance_to(Vector2(3340,3330)) > 190: return
	if p.money < 100:
		speech.text = "GUARDA: São R$ 100. Você não tem dinheiro suficiente."
		return
	p.money -= 100
	p._refresh_weapon_ui()
	authorized = true
	panel.hide()
	_set_dialogue_lock(false)
	p._show_weapon_notice("GUARDA: Pode entrar. A passagem está liberada.")

func raise_alarm() -> void:
	if alerted: return
	alerted = true
	authorized = false
	panel.hide()
	_set_dialogue_lock(false)
	var p := player()
	if p: p._show_weapon_notice("GUARDA: Invasor no porto! Segurança privada, peguem ele!")

func _process(delta: float) -> void:
	var p := player()
	var controlled := actor()
	if p == null or controlled == null: return
	var point: Vector2 = controlled.global_position
	var inside := (point.x >= 3200 and point.x <= 6100 and point.y > 3400 and point.y < 6000) or (point.x > 3620 and point.x < 6100 and point.y >= 3200 and point.y <= 3400)
	if initialized and inside and not was_inside and not authorized: raise_alarm()
	initialized = true
	if was_inside and not inside and not alerted: authorized = false
	was_inside = inside
	var guard_ready: bool = not guards.is_empty() and is_instance_valid(guards[0]) and not guards[0].is_dead
	var near: bool = guard_ready and point.distance_to(guards[0].global_position) < 125 and point.y < 3400
	var slow: bool = controlled is CharacterBody2D and controlled.velocity.length() < 35.0
	approach_time = approach_time + delta if near and slow else 0.0
	reply_time = maxf(0.0, reply_time - delta)
	if not near:
		dismissed = false
		reply_time = 0.0
		speech.text = GREETING
		pay.show()
		refuse.show()
	var dialogue_visible := near and not authorized and not alerted and ((not dismissed and approach_time >= 1.2) or reply_time > 0.0)
	if panel.visible != dialogue_visible:
		panel.visible = dialogue_visible
		_set_dialogue_lock(dialogue_visible)
	if panel.visible: _position_dialogue()
	if alerted:
		var escaped := not inside
		for guard in guards:
			if is_instance_valid(guard) and not guard.is_dead and guard.global_position.distance_to(point) < 650: escaped = false
		escape_time = escape_time+delta if escaped else 0.0
		if escape_time > 10 or p.health <= 0:
			alerted = false
			escape_time = 0.0
			dismissed = false
