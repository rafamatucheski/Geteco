extends Node2D

## Opt-in service inside the existing garage, without rewriting its NPCs.
const COLORS := preload("res://prototypes/living_cast/HarborCoupe.gd").PALETTE
const NAMES := ["Vermelho","Azul","Verde","Marfim","Preto","Prata","Amarelo","Vinho"]
var service_rect := Rect2(-75,-100,150,300)
var panel: PanelContainer
var target: Node2D
var busy := false
var clock := 0.0
var spray: CPUParticles2D
var paints_completed := 0

func _ready() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 28
	add_child(canvas)
	panel = PanelContainer.new()
	panel.position = Vector2(24,130)
	canvas.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var title := Label.new()
	title.text = "PAINT & SPRAY / escolha a cor — teste gratuito"
	column.add_child(title)
	var row := HBoxContainer.new()
	column.add_child(row)
	for i in COLORS.size():
		var button := Button.new()
		button.text = NAMES[i]
		button.modulate = COLORS[i].lightened(0.4)
		button.pressed.connect(func(): paint_car(i))
		row.add_child(button)
	panel.hide()
	spray = CPUParticles2D.new()
	spray.emitting = false
	spray.amount = 18
	spray.lifetime = 0.5
	spray.spread = 180
	spray.initial_velocity_min = 12
	spray.initial_velocity_max = 30
	spray.gravity = Vector2.ZERO
	spray.scale_amount_min = 2
	spray.scale_amount_max = 4
	spray.z_index = 12
	add_child(spray)

func eligible(car: Node2D) -> bool:
	return is_instance_valid(car) and car.has_method("repair_and_repaint") and car.is_physics_processing() and car.get("is_driven_by_player") == true and car.velocity.length() < 4 and service_rect.has_point(to_local(car.global_position))

func _process(delta: float) -> void:
	clock -= delta
	if clock > 0 or busy: return
	clock = 0.2
	target = null
	for car in get_tree().get_nodes_in_group("vehicle"):
		if eligible(car):
			target = car
			break
	panel.visible = target != null

func paint_car(index: int) -> void:
	if busy or index < 0 or index >= COLORS.size() or not eligible(target): return
	busy = true
	panel.hide()
	var car := target
	var was_processing := car.is_physics_processing()
	car.set_physics_process(false)
	car.velocity = Vector2.ZERO
	spray.global_position = car.global_position
	spray.color = COLORS[index]
	spray.emitting = true
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(car):
		car.repair_and_repaint(COLORS[index])
		car.set_physics_process(was_processing)
		paints_completed += 1
	spray.emitting = false
	busy = false
