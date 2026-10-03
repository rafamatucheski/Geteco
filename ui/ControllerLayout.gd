extends Control
## Static diagram: redraw only when bindings, layout or size change.
const FONT: Font = preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const INK := Color("e9e5dc")
const MUTED := Color("a6b0b8")
const ACCENT := Color("ff914d")
const CONTEXT_NAMES := ["A pé", "Combate", "Veículo", "Skate", "Ski", "Motocross", "Câmera 3D", "Menus e mapa"]
var context := 0

func _ready() -> void:
	custom_minimum_size.y = 280
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var controls := get_node_or_null("/root/GameInput")
	if controls == null: return
	var scale_factor := minf(size.x / 1000.0, size.y / 320.0)
	draw_set_transform(Vector2((size.x-1000*scale_factor)*.5,0),0,Vector2.ONE*scale_factor)
	var shell := PackedVector2Array([Vector2(368,66),Vector2(408,48),Vector2(592,48),Vector2(632,66),Vector2(675,232),Vector2(664,263),Vector2(632,267),Vector2(578,209),Vector2(422,209),Vector2(368,267),Vector2(336,263),Vector2(325,232)])
	draw_colored_polygon(shell,Color("d4d8da"))
	draw_polyline(shell+PackedVector2Array([shell[0]]),Color("79858e"),2,true)
	draw_style_box(_box(Color("19232c")),Rect2(420,68,160,69))
	draw_style_box(_box(Color("26323b")),Rect2(395,145,210,61))
	for x in [375.0,592.0]:
		draw_style_box(_box(Color("18232b")),Rect2(x,29,34,29))
		draw_style_box(_box(Color("3c4751")),Rect2(x-8,58,49,17))
	for point in [Vector2(442,178),Vector2(558,178)]:
		draw_circle(point,24,Color("101923"))
		draw_arc(point,20,0,TAU,36,Color("5b6871"),2,true)
	var ps: bool = controls.is_playstation_controller()
	_center("L2" if ps else "LT",Vector2(392,49),INK,15)
	_center("R2" if ps else "RT",Vector2(609,49),INK,15)
	_center("L1" if ps else "LB",Vector2(391,72),INK,13)
	_center("R1" if ps else "RB",Vector2(609,72),INK,13)
	_center("L3",Vector2(442,183),INK,16)
	_center("R3",Vector2(558,183),INK,16)
	_center("Touchpad" if ps else "",Vector2(500,105),MUTED,16)
	_center("Create" if ps else "View",Vector2(397,93),Color("26323b"),12)
	_center("Options" if ps else "Menu",Vector2(604,93),Color("26323b"),12)
	for entry in [[Vector2(393,117),"↑"],[Vector2(393,151),"↓"],[Vector2(376,134),"←"],[Vector2(410,134),"→"]]:
		draw_circle(entry[0],12,Color("28343d"))
		_center(entry[1],entry[0]+Vector2(0,5),INK,15)
	for entry in [[Vector2(610,115),3,Color("76c4aa")],[Vector2(610,155),0,Color("8fb7ef")],[Vector2(590,135),2,Color("ddb1d6")],[Vector2(630,135),1,Color("eea39c")]]:
		draw_circle(entry[0],13,Color("28343d"))
		_center(controls._pad_button_hint(entry[1],ps),entry[0]+Vector2(0,6),entry[2],18)
	var profile := _profile()
	for index in profile.left.size():
		_legend(controls,profile.left[index],Vector2(8,32+index*37),285)
	for index in profile.right.size():
		_legend(controls,profile.right[index],Vector2(700,32+index*37),285)
	_center(profile.move,Vector2(500,286),MUTED,16)
	_center(profile.look,Vector2(500,306),MUTED,16)

func _profile() -> Dictionary:
	var profile := {
		"left": ["sprint", "interact", "vehicle_interact", "inventory", "journal", "world_map"],
		"right": ["aim", "fire", "reload", "unarmed", "weapon_flashlight", "surrender"],
		"move": "Analógico esquerdo · mover",
		"look": "Analógico direito ↔ · câmera; ao mirar / atacar · mira",
	}
	match context:
		1:
			profile.left = ["aim", "weapon_previous", "unarmed", "weapon_flashlight", "surrender", "inventory"]
			profile.right = ["fire", "weapon_next", "reload", "interact", "sprint", "pause_game"]
			profile.look = "Segure mirar ou atacar + analógico direito · apontar a mira"
		2:
			profile.left = ["brake", "radio_previous", "radio_toggle", "headlights", "siren_toggle", "tank_fire"]
			profile.right = ["accelerate", "radio_next", "handbrake", "horn", "exit_vehicle", "world_map"]
			profile.move = "Analógico esquerdo ↔ · dirigir"
			profile.look = "Analógico direito ↔ · câmera; no tanque · mirar canhão"
		3:
			profile.left = [["accelerate", "Impulsionar"], ["brake", "Frear"], "skate_shove", "camera_left", "camera_right"]
			profile.right = ["skate_ollie", "skate_flip", ["interact", "Pegar / descer do skate"], ["exit_vehicle", "Descer do skate"], "pause_game"]
			profile.move = "Analógico esquerdo · guiar; ↑ impulsionar / ↓ frear"
			profile.look = "Analógico direito ↔ · girar câmera"
		4:
			profile.left = [["accelerate", "Impulsionar"], ["brake", "Frear"], ["sprint", "Alternar impulso"], "camera_left", "camera_right"]
			profile.right = [["handbrake", "Frear"], ["interact", "Equipar / retirar; prova"], ["interact", "Teleférico / adiantar"], "world_map", "pause_game"]
			profile.move = "Analógico esquerdo · guiar; ↑ impulsionar / ↓ frear"
			profile.look = "Analógico direito ↔ · girar câmera"
		5:
			profile.left = ["accelerate", "brake", ["handbrake", "Freio traseiro"], "camera_left", "camera_right"]
			profile.right = [["interact", "Montar / descer; prova"], ["exit_vehicle", "Descer / cancelar prova"], "pause_game"]
			profile.move = "Analógico esquerdo · guiar; ↑ / ↓ inclinar e acelerar / ré"
			profile.look = "Analógico direito ↔ · girar câmera"
		6:
			profile.left = ["camera_left", "camera_right", "aim"]
			profile.right = ["fire", "tank_fire", "pause_game"]
			profile.move = "Exploração e esportes · giro horizontal; interiores · câmera do ambiente"
			profile.look = "A pé: mirar / atacar reserva a mira; no tanque, mira sempre ativa"
		7:
			profile.left = [["ui_up", "Navegar para cima"], ["ui_down", "Navegar para baixo"], ["ui_left", "Navegar à esquerda"], ["ui_right", "Navegar à direita"]]
			profile.right = [["ui_accept", "Confirmar / selecionar mapa"], ["ui_cancel", "Voltar"], ["weapon_previous", "Mapa: afastar"], ["weapon_next", "Mapa: aproximar"], "pause_game"]
			profile.move = "Analógico esquerdo · navegar; no mapa · mover"
			profile.look = "L1 / R1 (LB / RB) · abas das configurações e do dossiê"
	return profile

func _legend(controls: Node, entry: Variant, point: Vector2, width: float) -> void:
	var action: String = entry[0] if entry is Array else entry
	var binding: String = controls.gamepad_hint(action)
	var caption: String = entry[1] if entry is Array else controls.label(action)
	var line := binding+"  ·  "+caption
	while FONT.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x > width and caption.length() > 3:
		caption = caption.left(caption.length()-1)
		line = binding+"  ·  "+caption+"…"
	draw_string(FONT,point,line,HORIZONTAL_ALIGNMENT_LEFT,width,17,INK)
	draw_line(point+Vector2(0,8),point+Vector2(width,8),Color(ACCENT,.16),1)

func _center(text: String, point: Vector2, color: Color, font_size: int) -> void:
	var width := FONT.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(FONT,point-Vector2(width*.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(8)
	return style
