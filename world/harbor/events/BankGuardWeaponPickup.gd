extends "res://legacy/city_demo/scenes/pickups/WeaponPickup.gd"
## O jogador escolhe recolher a arma solta, sem coleta automática ao pisar nela.
var drop_origin := Vector2.ZERO
var landed := false
var room: Node2D
var visual: Node3D

func _ready() -> void:
	persistent_loot=true
	super._ready()
	add_to_group("bank_guard_weapon")
	_prompt_label.text="E · "+_get_weapon_short_name()
	_prompt_label.position=Vector2(-44,-43)
	_prompt_label.size=Vector2(88,15)
	_prompt_label.z_as_relative=false
	_prompt_label.z_index=20
	_art_root.hide()
	_glow_circle.hide()
	visual=Node3D.new()
	visual.name="DroppedWeapon"
	preload("res://scripts/player/ArsenalWeapon3D.gd").build(visual,String(weapon_id))
	visual.rotation=Vector3(0,-.35 if weapon_id==&"shotgun" else .4,PI*.5)
	visual.scale=Vector3.ONE*1.24
	preload("res://world/harbor/events/BankFloorItem.gd").place(room,visual,global_position)
	var resting:Vector3=visual.position
	visual.position=preload("res://world/harbor/events/BankFloorItem.gd").floor_position(room,drop_origin)+Vector3.UP*.35
	var tween := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual,"position",resting,.42)
	tween.tween_callback(func(): landed=true)

func _process(_delta: float) -> void:
	if _consumed: return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var nearby: bool = landed and is_instance_valid(player) and player.visible and not player.is_dead and not player.is_in_dialogue and player.global_position.distance_to(global_position)<interaction_radius
	_prompt_label.visible=nearby
	_nearby_player=player if nearby else null

func _unhandled_input(event: InputEvent) -> void:
	if _consumed or not landed or not event.is_action_pressed("interact") or event.is_echo(): return
	if not is_instance_valid(_nearby_player) or _nearby_player.is_in_dialogue or _nearby_player.is_dead: return
	if _nearby_player.global_position.distance_to(global_position)>=interaction_radius: return
	_take(_nearby_player)
	get_viewport().set_input_as_handled()

func _on_body_entered(_body: Node2D) -> void:
	pass

func _take(player: Node) -> void:
	if _consumed: return
	visual.hide()
	super._take(player)

func _exit_tree() -> void:
	if is_instance_valid(visual): visual.queue_free()
