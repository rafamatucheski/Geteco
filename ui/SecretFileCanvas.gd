extends Control
## Desenho procedural da pasta de Vicente. O canvas nao processa quadros: seu
## proprietario chama queue_redraw() apenas quando estado, aba ou selecao mudam.

const INK := Color("171713")
const PAPER := Color("d8c7a0")
const PAPER_DARK := Color("b49b72")
const GRAPHITE := Color("4b4438")
const RED := Color("9e3c35")
const GREEN := Color("688b68")
const AMBER := Color("d0a45f")
const MUTED := Color("817762")

const FRAGMENT_IDS := [
	"map_village_fold",
	"map_drainage_grid",
	"map_service_tunnel",
	"map_pump_station",
	"map_power_branch",
	"map_sealed_annex",
]
const ROUTE_IDS := [
	"route_village_house",
	"route_harbor_sewer",
	"route_south_port_drain",
	"route_mountain_outfall",
]

var tab := 0
var snapshot: Dictionary = {}
var summary: Dictionary = {}
var selected_id := ""
var map_zoom := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_context(next_tab: int, next_snapshot: Dictionary, next_summary: Dictionary, next_selected: String, next_zoom: float) -> void:
	tab = clampi(next_tab, 0, 2)
	snapshot = next_snapshot.duplicate(true)
	summary = next_summary.duplicate(true)
	selected_id = next_selected
	map_zoom = clampf(next_zoom, 0.8, 1.45)
	queue_redraw()


func folder_rect() -> Rect2:
	var available := size - Vector2(48.0, 38.0)
	var extent := Vector2(minf(1120.0, available.x), minf(680.0, available.y))
	extent.x = maxf(extent.x, 720.0)
	extent.y = maxf(extent.y, 480.0)
	return Rect2(((size - extent) * 0.5).round(), extent.round())


func content_rect() -> Rect2:
	var folder := folder_rect()
	return Rect2(folder.position + Vector2(28, 82), folder.size - Vector2(56, 136))


func left_page_rect() -> Rect2:
	var content := content_rect()
	return Rect2(content.position, Vector2(content.size.x * 0.5 - 18, content.size.y))


func right_page_rect() -> Rect2:
	var content := content_rect()
	return Rect2(content.position + Vector2(content.size.x * 0.5 + 18, 0), Vector2(content.size.x * 0.5 - 18, content.size.y))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.008, 0.012, 0.014, 0.86))
	var folder := folder_rect()
	_box(folder.grow(10), Color(0, 0, 0, 0.38), Color.TRANSPARENT, 18)
	_box(folder, Color("6d5637"), Color("9a7b50"), 13)
	var content := content_rect()
	var left := left_page_rect()
	var right := right_page_rect()
	_box(left.grow(10), PAPER_DARK, Color("7d6848"), 7)
	_box(right.grow(10), PAPER_DARK, Color("7d6848"), 7)
	_box(left, PAPER, Color("aa9167"), 4)
	_box(right, Color("d1bd94"), Color("aa9167"), 4)
	draw_rect(Rect2(Vector2(content.get_center().x - 5, content.position.y - 10), Vector2(10, content.size.y + 20)), Color("473724"))
	draw_line(Vector2(content.get_center().x, content.position.y), Vector2(content.get_center().x, content.end.y), Color("97794e"), 1.0)
	_draw_paper_noise(left)
	_draw_paper_noise(right)
	match tab:
		0: _draw_map(left, right)
		1: _draw_evidence(left, right)
		2: _draw_network(left, right)
	_draw_footer(folder)


func _draw_paper_noise(rect: Rect2) -> void:
	# Linhas fixas e baratas sugerem fibra sem textura, shader ou animacao.
	for index in 18:
		var y := rect.position.y + 18.0 + float(index) * (rect.size.y - 36.0) / 18.0
		var offset := float((index * 37) % 29)
		draw_line(Vector2(rect.position.x + 12 + offset, y), Vector2(rect.end.x - 16, y + float((index % 3) - 1)), Color(0.22, 0.18, 0.12, 0.055), 1.0)


func _draw_map(left: Rect2, right: Rect2) -> void:
	_heading(left, _text("MAPA RASGADO", "TORN MAP"))
	var board := Rect2(left.position + Vector2(22, 54), left.size - Vector2(44, 90))
	var center := board.get_center()
	var scaled := Vector2(board.size.x / map_zoom, board.size.y / map_zoom)
	var visible_board := Rect2(center - scaled * 0.5, scaled)
	var placements := [
		Rect2(0.04, 0.06, 0.44, 0.38), Rect2(0.48, 0.02, 0.47, 0.42),
		Rect2(0.00, 0.42, 0.38, 0.51), Rect2(0.36, 0.39, 0.34, 0.55),
		Rect2(0.68, 0.40, 0.31, 0.37), Rect2(0.66, 0.75, 0.30, 0.23),
	]
	var found: Array = snapshot.get("fragments", [])
	for index in FRAGMENT_IDS.size():
		var unit: Rect2 = placements[index]
		var piece := Rect2(
			visible_board.position + Vector2(unit.position.x * visible_board.size.x, unit.position.y * visible_board.size.y),
			Vector2(unit.size.x * visible_board.size.x, unit.size.y * visible_board.size.y)
		)
		if found.has(FRAGMENT_IDS[index]):
			_draw_fragment(piece, index)
		else:
			_draw_missing_fragment(piece)
	var found_count := int(summary.get("fragments_found", found.size()))
	var total_count := int(summary.get("fragments_total", FRAGMENT_IDS.size()))
	_caption(left, "%d / %d" % [found_count, total_count], true)

	_heading(right, _text("ANOTAÇÕES", "NOTES"))
	var note := right.grow(-28)
	note.position.y += 52
	note.size.y -= 68
	_draw_map_notes(note)


func _draw_fragment(rect: Rect2, index: int) -> void:
	var skew := 5.0 + float(index % 3) * 2.0
	var polygon := PackedVector2Array([
		rect.position + Vector2(skew, 0), rect.position + Vector2(rect.size.x, 4 + index),
		rect.end - Vector2(4, skew), rect.position + Vector2(0, rect.size.y - 3 - index),
	])
	draw_colored_polygon(polygon, Color("eadbb8" if index % 2 == 0 else "e1cfaa"))
	draw_polyline(PackedVector2Array([polygon[0], polygon[1], polygon[2], polygon[3], polygon[0]]), Color("8d7958"), 1.4, true)
	var a := rect.position + Vector2(12, rect.size.y * (0.28 + 0.08 * float(index % 3)))
	var b := rect.end - Vector2(12, rect.size.y * (0.24 + 0.06 * float((index + 1) % 3)))
	draw_line(a, b, Color("78847a"), 3.0, true)
	draw_line(a + Vector2(0, 16), b + Vector2(-18, 22), Color("9a7654"), 1.4, true)
	if index in [1, 3, 5]:
		draw_circle(rect.get_center() + Vector2(index * 2 - 8, 0), 8.0, Color(0, 0, 0, 0), false, 2.0, true)
		draw_circle(rect.get_center() + Vector2(index * 2 - 8, 0), 3.0, RED)


func _draw_missing_fragment(rect: Rect2) -> void:
	var color := Color(0.25, 0.21, 0.15, 0.26)
	draw_dashed_line(rect.position, Vector2(rect.end.x, rect.position.y), color, 1.0, 5.0)
	draw_dashed_line(Vector2(rect.end.x, rect.position.y), rect.end, color, 1.0, 5.0)
	draw_dashed_line(rect.end, Vector2(rect.position.x, rect.end.y), color, 1.0, 5.0)
	draw_dashed_line(Vector2(rect.position.x, rect.end.y), rect.position, color, 1.0, 5.0)


func _draw_map_notes(rect: Rect2) -> void:
	var clue_count := int(summary.get("keypad_clues_found", snapshot.get("keypad_clues", []).size()))
	var clue_total := int(summary.get("keypad_clues_total", 4))
	_draw_stamp(Rect2(rect.position, Vector2(rect.size.x, 74)), _text("CÓDIGO", "CODE"), "%d / %d" % [clue_count, clue_total], clue_count == clue_total)
	var y := rect.position.y + 102
	var facts := [
		[bool(summary.get("house_discovered", false)), _text("CASA", "HOUSE")],
		[bool(summary.get("keypad_unlocked", false)), _text("PASSAGEM", "PASSAGE")],
		[bool(summary.get("headquarters_discovered", false)), _text("QG", "HQ")],
	]
	for fact in facts:
		var active: bool = fact[0]
		draw_circle(Vector2(rect.position.x + 13, y + 9), 6, GREEN if active else Color("887d68"), active, 2.0)
		_text_at(Vector2(rect.position.x + 30, y + 15), str(fact[1]), 15, GRAPHITE if active else MUTED)
		y += 42
	if bool(summary.get("sealed_sector_discovered", false)):
		var mark := Rect2(rect.position + Vector2(0, rect.size.y - 96), Vector2(rect.size.x, 70))
		_draw_alert_mark(mark)


func _draw_evidence(left: Rect2, right: Rect2) -> void:
	_heading(left, _text("EVIDÊNCIAS", "EVIDENCE"))
	_heading(right, _text("REGISTRO", "RECORD"))
	var art := right.grow(-32)
	art.position.y += 54
	art.size.y -= 74
	if selected_id.is_empty():
		_text_center(art, _text("SEM REGISTRO SELECIONADO", "NO RECORD SELECTED"), 15, MUTED)
		return
	_draw_evidence_art(art, selected_id)
	var evidence_count: int = int(snapshot.get("keypad_clues", []).size()) + int(snapshot.get("audio_logs", []).size()) + int(snapshot.get("lab_clues", []).size())
	_caption(left, _text("%d REGISTROS" % evidence_count, "%d RECORDS" % evidence_count), false)


func _draw_evidence_art(rect: Rect2, id: String) -> void:
	if id.begins_with("audio_"):
		_draw_audio_record(rect, id)
	elif id == "lab_incident_photo":
		_draw_incident_photo(rect)
	elif id == "lab_access_badge":
		_draw_badge(rect)
	elif id == "lab_power_report":
		_draw_power_report(rect)
	elif id == "keypad_house_plaque":
		_draw_plaque(rect)
	elif id == "keypad_radio_frequency":
		_draw_radio_note(rect)
	elif id == "keypad_service_stamp":
		_draw_service_stamp(rect)
	else:
		_draw_invoice(rect)


func _draw_audio_record(rect: Rect2, id: String) -> void:
	var tape := Rect2(rect.position + Vector2(24, 34), Vector2(rect.size.x - 48, 126))
	_box(tape, Color("302d27"), Color("736955"), 8)
	draw_circle(tape.position + Vector2(74, 63), 31, Color("161614"))
	draw_circle(tape.position + Vector2(74, 63), 10, Color("9d8d70"))
	draw_circle(tape.end - Vector2(74, 63), 31, Color("161614"))
	draw_circle(tape.end - Vector2(74, 63), 10, Color("9d8d70"))
	var wave := Rect2(rect.position + Vector2(12, 196), Vector2(rect.size.x - 24, 116))
	_box(wave, Color("292c27"), Color("5d665a"), 4)
	var points := PackedVector2Array()
	for index in 72:
		var x := wave.position.x + 8 + float(index) * (wave.size.x - 16) / 71.0
		var seed_value := float((index * 19 + id.length() * 7) % 23) / 22.0
		var height := (seed_value - 0.5) * wave.size.y * (0.28 if index < 47 else 0.72)
		points.append(Vector2(x, wave.get_center().y + height))
	draw_polyline(points, AMBER, 1.6, true)
	_text_at(rect.position + Vector2(14, rect.size.y - 34), _text("SINAL INTERROMPIDO", "SIGNAL LOST"), 13, RED)


func _draw_incident_photo(rect: Rect2) -> void:
	var photo := Rect2(rect.position + Vector2(38, 14), rect.size - Vector2(76, 66))
	_box(photo, Color("e0d6bd"), Color("8d8068"), 2)
	var image := Rect2(photo.position + Vector2(14, 14), photo.size - Vector2(28, 66))
	draw_rect(image, Color("242827"))
	for index in 11:
		var y := image.position.y + float(index) * image.size.y / 10.0
		draw_line(Vector2(image.position.x, y), Vector2(image.end.x, y + float(index % 2)), Color(0.68, 0.76, 0.69, 0.045), 1.0)
	var silhouette := PackedVector2Array([
		image.get_center() + Vector2(-18, 72), image.get_center() + Vector2(-24, -18),
		image.get_center() + Vector2(-10, -62), image.get_center() + Vector2(8, -68),
		image.get_center() + Vector2(22, -22), image.get_center() + Vector2(28, 74),
	])
	draw_colored_polygon(silhouette, Color(0.02, 0.025, 0.02, 0.68))
	draw_line(image.position + Vector2(0, image.size.y * .66), image.end - Vector2(0, image.size.y * .33), Color(0.85, 0.88, 0.74, 0.13), 5)
	_text_at(photo.position + Vector2(18, photo.size.y - 18), "C-03", 15, GRAPHITE)


func _draw_badge(rect: Rect2) -> void:
	var badge := Rect2(rect.get_center() - Vector2(104, 150), Vector2(208, 300))
	_box(badge, Color("c7c3b3"), Color("706b5c"), 12)
	draw_rect(Rect2(badge.position + Vector2(22, 28), Vector2(badge.size.x - 44, 82)), Color("343b3a"))
	draw_circle(badge.position + Vector2(58, 69), 27, Color("1c211f"))
	draw_line(badge.position + Vector2(34, 145), badge.position + Vector2(174, 145), GRAPHITE, 4)
	draw_line(badge.position + Vector2(34, 177), badge.position + Vector2(138, 177), MUTED, 3)
	_draw_alert_mark(Rect2(badge.position + Vector2(30, 214), Vector2(badge.size.x - 60, 52)))


func _draw_power_report(rect: Rect2) -> void:
	var page := rect.grow(-18)
	for index in 8:
		var y := page.position.y + 42 + index * 36
		draw_line(Vector2(page.position.x + 12, y), Vector2(page.end.x - 12, y), Color(0.22, 0.20, 0.16, 0.34), 1.0)
	for index in 5:
		var p := page.position + Vector2(46 + index * 64, 78 + (index % 2) * 82)
		draw_circle(p, 10, GREEN if index < 3 else RED, index < 3, 2.0)
		if index > 0: draw_line(p - Vector2(64, (index % 2 - (index - 1) % 2) * 82), p, GRAPHITE, 2.0)


func _draw_plaque(rect: Rect2) -> void:
	var plaque := Rect2(rect.get_center() - Vector2(168, 88), Vector2(336, 176))
	_box(plaque, Color("56534b"), Color("8e8879"), 5)
	for corner in [Vector2(18, 18), Vector2(plaque.size.x - 18, 18), Vector2(18, plaque.size.y - 18), plaque.size - Vector2(18, 18)]:
		draw_circle(plaque.position + corner, 6, Color("252521"))
	_text_center(plaque, "19  •  7", 38, Color("d3c7a9"))


func _draw_radio_note(rect: Rect2) -> void:
	var dial := Rect2(rect.position + Vector2(20, 42), Vector2(rect.size.x - 40, 142))
	_box(dial, Color("373832"), Color("787662"), 6)
	for index in 19:
		var x := dial.position.x + 22 + index * (dial.size.x - 44) / 18.0
		draw_line(Vector2(x, dial.position.y + 74), Vector2(x, dial.position.y + 91 + (8 if index % 5 == 0 else 0)), Color("c9bea2"), 1.0)
	draw_line(Vector2(dial.get_center().x + 34, dial.position.y + 48), Vector2(dial.get_center().x + 34, dial.end.y - 30), RED, 3.0)
	_text_at(rect.position + Vector2(40, 238), "•••  — —  ••", 28, GRAPHITE)


func _draw_service_stamp(rect: Rect2) -> void:
	var stamp := Rect2(rect.get_center() - Vector2(150, 95), Vector2(300, 190))
	draw_arc(stamp.get_center(), 86, 0, TAU, 48, RED, 5, true)
	draw_arc(stamp.get_center(), 66, 0, TAU, 48, RED, 2, true)
	_text_center(stamp, "V.F.  /  04", 28, RED)


func _draw_invoice(rect: Rect2) -> void:
	var page := Rect2(rect.position + Vector2(34, 12), rect.size - Vector2(68, 34))
	_box(page, Color("ece0bf"), Color("9e8c68"), 2)
	for index in 8:
		var y := page.position.y + 58 + index * 35
		draw_line(Vector2(page.position.x + 18, y), Vector2(page.end.x - 18, y), Color("6f6655"), 1.0)
	_text_at(page.position + Vector2(18, 34), "V. FERRAZ", 20, GRAPHITE)
	_text_at(page.end - Vector2(122, 24), "7  •  1  •  9", 18, RED)


func _draw_network(left: Rect2, right: Rect2) -> void:
	_heading(left, _text("REDE", "NETWORK"))
	_heading(right, _text("CONEXÕES", "CONNECTIONS"))
	var board := Rect2(left.position + Vector2(left.size.x * .36, 68), Vector2(left.size.x * 1.33, left.size.y - 118))
	var active: Array = snapshot.get("routes", [])
	var nodes := {
		"route_village_house":Vector2(0.08, 0.22),
		"route_harbor_sewer":Vector2(0.40, 0.48),
		"route_south_port_drain":Vector2(0.73, 0.78),
		"route_mountain_outfall":Vector2(0.90, 0.18),
	}
	var links := [
		["route_village_house", "route_harbor_sewer"],
		["route_harbor_sewer", "route_south_port_drain"],
		["route_harbor_sewer", "route_mountain_outfall"],
	]
	for link in links:
		var a: Vector2 = board.position + nodes[link[0]] * board.size
		var b: Vector2 = board.position + nodes[link[1]] * board.size
		var on := active.has(link[0]) and active.has(link[1])
		draw_dashed_line(a, b, GREEN if on else Color("7f7562"), 3.0 if on else 1.4, 9.0)
	for id in ROUTE_IDS:
		var point: Vector2 = board.position + nodes[id] * board.size
		var on := active.has(id)
		draw_circle(point, 17, Color("e6d6ae"))
		if on:
			draw_circle(point, 12, GREEN)
		else:
			draw_circle(point, 12, Color("6f685a"), false, 3.0, true)
		if id == selected_id: draw_arc(point, 23, 0, TAU, 36, RED, 2.0, true)
	_caption(right, "%d / %d" % [int(summary.get("routes_active", active.size())), int(summary.get("routes_total", ROUTE_IDS.size()))], true)
	if bool(summary.get("sealed_sector_discovered", false)):
		_draw_alert_mark(Rect2(right.end - Vector2(184, 96), Vector2(158, 60)))


func _draw_alert_mark(rect: Rect2) -> void:
	_box(rect, Color(0.34, 0.12, 0.10, 0.10), RED, 3)
	for index in 5:
		var x := rect.position.x + index * rect.size.x / 5.0
		draw_line(Vector2(x, rect.end.y), Vector2(x + rect.size.x / 5.0, rect.position.y), Color(0.48, 0.17, 0.13, 0.32), 5)
	_text_center(rect, _text("SINAL INTERROMPIDO", "SIGNAL LOST"), 12, RED)


func _draw_stamp(rect: Rect2, title: String, value: String, active: bool) -> void:
	_box(rect, Color(0, 0, 0, 0.025), GREEN if active else MUTED, 4)
	_text_at(rect.position + Vector2(14, 24), title, 13, GRAPHITE)
	_text_at(rect.position + Vector2(14, 55), value, 24, GREEN if active else MUTED)


func _heading(rect: Rect2, text: String) -> void:
	_text_at(rect.position + Vector2(18, 30), text, 18, GRAPHITE)
	draw_line(rect.position + Vector2(18, 40), Vector2(rect.end.x - 18, rect.position.y + 40), Color(0.28, 0.24, 0.18, 0.42), 1.0)


func _caption(rect: Rect2, text: String, right_aligned: bool) -> void:
	var local_position := rect.end - Vector2(22, 16)
	if not right_aligned: local_position.x = rect.position.x + 22
	draw_string(ThemeDB.fallback_font, local_position, text, HORIZONTAL_ALIGNMENT_RIGHT if right_aligned else HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)


func _draw_footer(folder: Rect2) -> void:
	var text := _text("J / ESC  FECHAR", "J / ESC  CLOSE")
	draw_string(ThemeDB.fallback_font, folder.end - Vector2(182, 18), text, HORIZONTAL_ALIGNMENT_RIGHT, 160, 12, Color("d6c49f"))


func _box(rect: Rect2, color: Color, border: Color, radius: int) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)


func _text_at(p_position: Vector2, text: String, font_size: int, color: Color) -> void:
	draw_string(ThemeDB.fallback_font, p_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _text_center(rect: Rect2, text: String, font_size: int, color: Color) -> void:
	var y := rect.get_center().y + float(font_size) * 0.35
	draw_string(ThemeDB.fallback_font, Vector2(rect.position.x, y), text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, color)


func _text(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
