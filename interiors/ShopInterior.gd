class_name ShopInterior
extends Node2D

signal player_entered_door(body: Node2D)
signal player_exited_door(body: Node2D)
signal display_slot_activated(slot_id: String, slot_node: Marker2D)

@export_group("Customização da Loja")
@export var shop_name: String = "STORE"
@export var accent_color: Color = Color("f39c12")
@export var floor_color_primary: Color = Color("2c343f")
@export var floor_color_secondary: Color = Color("252c36")
@export var wall_color: Color = Color("1a1f26")
@export var wall_trim_color: Color = Color("3a4454")
@export var counter_wood_color: Color = Color("795548")
@export var show_grid_tiles: bool = true

@onready var spawn_point: Marker2D = $Doorway/SpawnPoint
@onready var exit_area: Area2D = $Doorway
@onready var display_slots_container: Node2D = $DisplaySlots
@onready var shop_title_label: Label = $Decor/Sign/ShopNameLabel

var slot_nodes: Dictionary = {}

func _ready() -> void:
	add_to_group("shop_interior")
	_index_display_slots()
	_apply_theme()
	if exit_area:
		exit_area.body_entered.connect(_on_door_body_entered)
		exit_area.body_exited.connect(_on_door_body_exited)

func _index_display_slots() -> void:
	slot_nodes.clear()
	if display_slots_container:
		for child in display_slots_container.get_children():
			if child is Marker2D:
				slot_nodes[child.name] = child

func _apply_theme() -> void:
	if shop_title_label:
		shop_title_label.text = shop_name.to_upper()
		shop_title_label.add_theme_color_override("font_color", accent_color)
	queue_redraw()

func get_spawn_position() -> Vector2:
	if spawn_point:
		return spawn_point.global_position
	return global_position + Vector2(0, 160)

func get_display_slot(slot_name: String) -> Marker2D:
	return slot_nodes.get(slot_name, null)

func get_all_display_slots() -> Array[Marker2D]:
	var list: Array[Marker2D] = []
	for slot in slot_nodes.values():
		list.append(slot)
	return list

func set_slot_item(slot_name: String, item_instance: Node2D) -> bool:
	var slot := get_display_slot(slot_name)
	if slot and item_instance:
		for existing in slot.get_children():
			if not existing is CollisionShape2D and not existing is Area2D:
				existing.queue_free()
		slot.add_child(item_instance)
		item_instance.position = Vector2.ZERO
		return true
	return false

func _on_door_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_entered_door.emit(body)

func _on_door_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_exited_door.emit(body)
