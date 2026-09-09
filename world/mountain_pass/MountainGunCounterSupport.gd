extends "res://world/harbor/interiors/HarborInteriorBase.gd"
## Compatibility for the mountain's independently authored room and counter UI.
var gunsmith_npc: CharacterBody2D
var counter_area: Area2D
var counter_badge: Label
var counter_dialog: PanelContainer
var counter_text: Label
var is_near_counter := false
var weapon_buttons := {}
func _build_gunsmith() -> void:
	gunsmith_npc=preload("res://world/harbor/interiors/HarborConversationalNPC.gd").new()
	gunsmith_npc.character_name="Armeiro Vance"
	gunsmith_npc.shirt_color=Color("7f1d1d")
	gunsmith_npc.dialogues=["Bem-vindo à Ammu-Nation. Escolha sua arma ou reponha a munição."]
	add_child(gunsmith_npc)
func _build_interaction_counter() -> void:
	counter_area=Area2D.new()
	counter_area.collision_layer=0
	counter_area.collision_mask=4
	var col=CollisionShape2D.new()
	col.shape=RectangleShape2D.new()
	col.shape.size=Vector2(240,70)
	counter_area.add_child(col)
	add_child(counter_area)
	counter_badge=Label.new()
	add_child(counter_badge)
	counter_badge.hide()
	var layer=CanvasLayer.new()
	layer.layer=80
	add_child(layer)
	counter_dialog=PanelContainer.new()
	layer.add_child(counter_dialog)
	counter_dialog.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	counter_dialog.offset_left=-300
	counter_dialog.offset_right=300
	var box=VBoxContainer.new()
	counter_dialog.add_child(box)
	box.add_child(Label.new())
	counter_text=Label.new()
	counter_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	box.add_child(counter_text)
	counter_dialog.hide()
	counter_area.body_entered.connect(func(body):
		if body.is_in_group("player"):
			is_near_counter=true
			counter_badge.show())
	counter_area.body_exited.connect(func(body):
		if body.is_in_group("player"):
			is_near_counter=false
			counter_badge.hide()
			if counter_dialog.visible:
				counter_dialog.hide()
				modal_closed.emit())
func _build_purchase_buttons() -> void:
	for id in ["pistol","shotgun","smg","hunting_rifle"]:
		var button=Button.new()
		counter_text.get_parent().add_child(button)
		weapon_buttons[id]=button
		button.pressed.connect(func():
			if is_near_counter:
				counter_text.text=get_tree().get_first_node_in_group("player").buy_weapon(id)
				_refresh_weapon_buttons())
	var ammo=Button.new()
	ammo.text="MUNIÇÃO DA ARMA EQUIPADA · $120"
	counter_text.get_parent().add_child(ammo)
	ammo.pressed.connect(func():
		if is_near_counter: counter_text.text=get_tree().get_first_node_in_group("player").buy_ammo(120))
func _refresh_weapon_buttons() -> void:
	var player=get_tree().get_first_node_in_group("player")
	if not player: return
	for id in weapon_buttons:
		var data=WeaponCatalog.get_weapon(id)
		var owned=player.weapon_inventory.get(id,false)==true
		var unlocked=player.is_weapon_shop_unlocked(id)
		weapon_buttons[id].disabled=owned or not unlocked
		weapon_buttons[id].text="%s · %s"%[data.get("label",id),"JÁ POSSUI" if owned else ("$%d"%data.get("price",0) if unlocked else "BLOQUEADA")]
func _resupply_ammo() -> void:
	_refresh_weapon_buttons()
	counter_dialog.show()
	modal_opened.emit()
func _unhandled_input(event: InputEvent) -> void:
	if not is_near_counter: return
	if event.is_action_pressed("interact"):
		if counter_dialog.visible:
			counter_dialog.hide()
			modal_closed.emit()
		else: _resupply_ammo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and counter_dialog.visible:
		counter_dialog.hide()
		modal_closed.emit()
		get_viewport().set_input_as_handled()
