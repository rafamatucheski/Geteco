class_name ResortPromenade
extends Node2D

## Passeio de Pedestres e Boulevard do Resort (Resort Promenade):
## Conecta fisicamente o Concourse de chegada de veículos, o Chalé Cume Branco,
## a Boutique Alpina e o Teleférico da Montanha através de deck aquecido de madeira tratada,
## piso de pedras térmicas, postes de iluminação alpina, racks de esquis ao ar livre,
## e um braseiro central aquecido (heat source) com bancos para descanso dos visitantes.

const BOARDWALK_COLOR := Color("#433224")
const PLANK_LINE_COLOR := Color("#2e2117")
const FLAGSTONE_COLOR := Color("#58636e")
const SNOW_BANK_COLOR := Color("#d6e0e6")

func _ready() -> void:
	z_index = 2
	_build_boardwalk()
	_build_lantern_posts()
	_build_ski_racks()
	_build_fire_brazier()
	_build_amenities()
	_build_promenade_instructor()

func _build_boardwalk() -> void:
	# 1. Calçadão principal leste-oeste ligando Concourse / Estacionamento -> Chalé -> Boutique
	var main_deck := Polygon2D.new()
	main_deck.name = "MainPlazaDeck"
	main_deck.color = BOARDWALK_COLOR
	main_deck.polygon = PackedVector2Array([
		Vector2(6940, -2665), Vector2(7480, -2665),
		Vector2(7480, -2725), Vector2(7220, -2725),
		Vector2(7220, -2760), Vector2(7060, -2760),
		Vector2(7060, -2725), Vector2(6940, -2725)
	])
	add_child(main_deck)


	# Frisos de pranchas de madeira horizontais
	for y in range(-2720, -2665, 8):
		var seam := Line2D.new()
		seam.width = 1.4
		seam.default_color = PLANK_LINE_COLOR
		seam.points = PackedVector2Array([Vector2(6940, y), Vector2(7480, y)])
		add_child(seam)

	# 2. Alameda Norte conectando o Chalé e a Boutique ao Teleférico e Largada das Pistas
	var lift_path := Polygon2D.new()
	lift_path.name = "LiftPromenadeDeck"
	lift_path.color = FLAGSTONE_COLOR
	lift_path.polygon = PackedVector2Array([
		Vector2(7050, -2730), Vector2(7130, -2730),
		Vector2(7050, -2980), Vector2(6950, -2980),
		Vector2(6950, -2940), Vector2(7020, -2850),
		Vector2(7050, -2800)
	])
	add_child(lift_path)


	# 3. Cordões de pedra e neve limpa nas bordas do calçadão
	var borders := Line2D.new()
	borders.width = 3.2
	borders.default_color = SNOW_BANK_COLOR
	borders.points = PackedVector2Array([
		Vector2(6940, -2725), Vector2(7060, -2725), Vector2(7060, -2760),
		Vector2(7220, -2760), Vector2(7220, -2725), Vector2(7480, -2725)
	])
	add_child(borders)

	var s_borders := Line2D.new()
	s_borders.width = 3.2
	s_borders.default_color = SNOW_BANK_COLOR
	s_borders.points = PackedVector2Array([
		Vector2(6940, -2665), Vector2(7480, -2665)
	])
	add_child(s_borders)

func _prop(kind: String, point: Vector2, label: String) -> void:
	var prop := preload("res://world/mountain_pass/ResortPromenadeProp.gd").new()
	prop.kind = kind
	prop.position = point
	prop.name = label
	add_child(prop)

func _build_lantern_posts() -> void:
	var positions := [Vector2(6960,-2675),Vector2(7280,-2675),Vector2(7030,-2820),Vector2(7040,-2940)]
	for i in positions.size(): _prop("lamp",positions[i],"AlpineLantern%d"%i)

func _build_ski_racks() -> void:
	_prop("rack",Vector2(7075,-2700),"SkiRackWest")
	_prop("rack",Vector2(7445,-2680),"SkiRackEast")

func _build_fire_brazier() -> void:
	_prop("brazier",Vector2(7310,-2700),"ResortCentralBrazier")

func _build_amenities() -> void: pass

func _build_promenade_instructor() -> void:
	# Instrutora do Resort no início do calçadão das pistas
	var instructor := preload("res://world/mountain_pass/WinterResident.gd").new()
	instructor.name = "ResortSkiInstructor"
	instructor.position = Vector2(7310, -2668)
	instructor.resident_name = "CAMILA"
	instructor.role = "ranger"
	instructor.coat_color = Color("#c0392b")
	instructor.is_stationary = true
	instructor.lines = [
		"Mantenha os joelhos flexionados na saída do teleférico.",
		"A Pista Verde é perfeita para aquecer; Pista da Sombra exige trajes térmicos reforçados.",
		"O braseiro na praça recupera a temperatura caso sinta frio na descida."
	]
	instructor.home = instructor.position
	instructor.destination = instructor.position
	add_child(instructor)
