extends Node2D

var monster: MountainMonster
var announced := false

func _ready() -> void:
	monster = preload("res://world/mountain_pass/MountainMonster.gd").new()
	monster.name = "MountainShadow"
	monster.position = Vector2(7490, -4140)
	add_child(monster)
	var player := get_tree().get_first_node_in_group("player")
	if is_instance_valid(player) and player.has_signal("collectible_progress_changed"):
		player.collectible_progress_changed.connect(_on_collectible_progress_changed)
	_refresh_unlock()

func _process(_delta: float) -> void:
	_refresh_unlock()

func _on_collectible_progress_changed(_total: int, _milestone: String) -> void:
	_refresh_unlock()

func _refresh_unlock() -> void:
	if announced or not is_instance_valid(monster):
		return
	var player := get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player):
		return
	var clues := 0
	for id in player.collectibles_found:
		if String(id).begins_with("mountain_expedition_"):
			clues += 1
	if clues < 3:
		return
	announced = true
	monster.reveal()
	if player.has_method("_show_weapon_notice"):
		player._show_weapon_notice("A PISTA PRETA FOI ABERTA · ALGO SE MOVE NA FACE NORTE")
