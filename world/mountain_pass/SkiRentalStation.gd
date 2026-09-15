class_name SkiRentalStation
extends Node2D

const RENTAL_PRICE := 250
var station_kind := "rental"
var prompt: Label
var _near := false

func _ready() -> void:
	z_index = 20
	prompt = Label.new()
	prompt.position = Vector2(-125, -48)
	prompt.size = Vector2(250, 48)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt.add_theme_font_size_override("font_size", 13)
	prompt.add_theme_color_override("font_color", Color("f2e5c8"))
	prompt.add_theme_color_override("font_outline_color", Color("10171c"))
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.hide()
	add_child(prompt)

func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	_near = is_instance_valid(player) and player.has_meta("mountain_interior_id") and player.get_meta("mountain_interior_id") == &"ski_lodge" and global_position.distance_to(player.global_position) < 54.0
	prompt.visible = _near
	if not _near: return

	var schedule_script := preload("res://world/mountain_pass/MountainSkiSchedule.gd")
	var is_open := schedule_script.is_open(self)
	var key: String = get_node("/root/GameInput").hint("interact")

	if station_kind == "rental":
		if player.get("ski_rental_active") == true:
			prompt.text = "[%s] DEVOLVER EQUIPAMENTO E TROCAR DE ROUPA" % key
		elif not is_open:
			prompt.text = schedule_script.get_closed_notice(self, "LOCAÇÃO")
		else:
			prompt.text = "[%s] ALUGAR ROUPA DE SKI · $%d" % [key, RENTAL_PRICE]
	else:
		if player.get("ski_equipment_ready") == true:
			prompt.text = "[%s] SKIS RETIRADOS" % key
		elif not is_open and player.get("ski_rental_active") != true:
			prompt.text = schedule_script.get_closed_notice(self, "RACK DE SKIS")
		else:
			prompt.text = "[%s] RETIRAR SKIS E BASTÕES" % key

	if Input.is_action_just_pressed("interact"):
		_activate(player, is_open)

func _activate(player: Node, is_open: bool) -> void:
	if station_kind == "rental":
		if player.get("ski_rental_active") == true:
			player.return_ski_rental()
			player._show_weapon_notice("EQUIPAMENTO DEVOLVIDO · ROUPA ANTERIOR VESTIDA")
		elif not is_open:
			player._show_weapon_notice("LOCAÇÃO ENCERRADA · FUNCIONAMENTO: 08:00 ÀS 18:00")
		elif not player.begin_ski_rental(RENTAL_PRICE):
			player._show_weapon_notice("DINHEIRO INSUFICIENTE PARA O ALUGUEL")
		else:
			player._show_weapon_notice("ROUPA DE SKI VESTIDA · SIGA ATÉ O RACK")
	else:
		if player.get("ski_rental_active") != true:
			if not is_open:
				player._show_weapon_notice("ESTAÇÃO FECHADA · FUNCIONAMENTO: 08:00 ÀS 18:00")
			else:
				player._show_weapon_notice("ALUGUE A ROUPA ANTES DE RETIRAR OS SKIS")
		elif player.get("ski_equipment_ready") == true:
			player._show_weapon_notice("SKIS E BASTÕES JÁ RETIRADOS")
		else:
			player.take_ski_equipment()
			player._show_weapon_notice("EQUIPAMENTO RETIRADO · SAIA PELA PORTA DAS PISTAS")
