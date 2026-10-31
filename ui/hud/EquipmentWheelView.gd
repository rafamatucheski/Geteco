extends Control
## Só apresentação. O runtime cuida da entrada, das transações de inventário e da escala de tempo.
const STYLE := preload("res://ui/GameStyle.gd")
const MAX_SECTORS := 8
var _entries: Array[Dictionary] = []
var _selected := -1
var _page := 0
var _hints: Dictionary = {}
var _locale := ""
var _hint_style: StyleBoxFlat
var _center := Vector2.ZERO
var _radius := 210.0
var _inner := 98.0
var _scale := 1.0
var _slots := 8
var _sectors: Array[ArrayMesh] = []
var _accents: Array[ArrayMesh] = []
var _anchors: Array[Vector2] = []

func _ready() -> void:
	name = "EquipmentWheelView"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_hint_style = STYLE.compact(false, 4, Vector2.ZERO)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_rebuild_geometry)
	_rebuild_geometry()

func configure_view(entries: Array[Dictionary], selected: int, page: int, hints: Dictionary = {}) -> void:
	var next_entries: Array[Dictionary] = []
	for entry in entries.slice(0, MAX_SECTORS): next_entries.append(entry)
	var next_selected := selected if selected >= 0 and selected < next_entries.size() else -1
	var locale := TranslationServer.get_locale()
	if _entries == next_entries and _selected == next_selected and _page == page and _hints == hints and _locale == locale: return
	_entries = next_entries
	_selected = next_selected
	_page = page
	_hints = hints.duplicate()
	_locale = locale
	var next_slots := maxi(4, _entries.size()) if not _entries.is_empty() else 8
	if _sectors.is_empty() or _slots != next_slots: _rebuild_geometry()
	else: queue_redraw()

func select(index: int) -> void:
	var next := index if index >= 0 and index < _entries.size() else -1
	if next == _selected: return
	_selected = next
	queue_redraw()

func selection_at(point: Vector2) -> int:
	var offset := point - _center
	if offset.length() < _inner * .83 or _entries.is_empty(): return -1
	var angle := fposmod(offset.angle() + PI * .5 + PI / float(_slots), TAU)
	var index := int(floor(angle / TAU * float(_slots)))
	return index if index < _entries.size() else -1

func _rebuild_geometry() -> void:
	_scale = clampf(minf(size.y / 720.0, size.x / 1000.0), .65, 1.3)
	_center = size * .5
	_radius = 210.0 * _scale
	_inner = 98.0 * _scale
	_slots = maxi(4, _entries.size()) if not _entries.is_empty() else 8
	_sectors.clear()
	_accents.clear()
	_anchors.clear()
	var step := TAU / float(_slots)
	# Um pixel físico de cobertura na borda, incluindo janelas escaladas.
	var screen_scale := get_viewport().get_screen_transform().get_scale().abs()
	var fringe := 1.0 / maxf(minf(screen_scale.x, screen_scale.y), .5)
	for index in _slots:
		var angle := -PI * .5 + float(index) * step
		var start := angle - step * .5 + .012
		var finish := angle + step * .5 - .012
		_sectors.append(_smooth_polygon(_annulus(start, finish, _inner, _radius), fringe))
		_accents.append(_smooth_polygon(_annulus(start, finish, _radius - 4.0 * _scale, _radius), fringe))
		_anchors.append(_center + Vector2.from_angle(angle) * (_inner + _radius) * .5)
	queue_redraw()

func _annulus(start: float, finish: float, inside: float, outside: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var steps := maxi(24, ceili((finish - start) * outside / 5.0))
	for index in steps + 1:
		points.append(_center + Vector2.from_angle(lerpf(start, finish, float(index) / steps)) * outside)
	for index in range(steps, -1, -1):
		points.append(_center + Vector2.from_angle(lerpf(start, finish, float(index) / steps)) * inside)
	return points

func _smooth_polygon(points: PackedVector2Array, fringe: float) -> ArrayMesh:
	# Cache fill and alpha coverage together: one draw per shape, no viewport,
	# global MSAA, per-frame triangulation or overlapping translucent outlines.
	var count := points.size()
	var vertices := points.duplicate()
	var colors := PackedColorArray()
	colors.resize(count * 2)
	var indices := Geometry2D.triangulate_polygon(points)
	for index in count:
		var previous := (points[index] - points[posmod(index - 1, count)]).normalized()
		var next := (points[(index + 1) % count] - points[index]).normalized()
		var normal_before := Vector2(previous.y, -previous.x)
		var normal_after := Vector2(next.y, -next.x)
		var miter := (normal_before + normal_after).normalized()
		var reach := fringe / maxf(miter.dot(normal_after), .25)
		vertices.append(points[index] + miter * reach)
		colors[index] = Color.WHITE
		colors[count + index] = Color(1, 1, 1, 0)
		var following := (index + 1) % count
		indices.append_array(PackedInt32Array([index, following, count + following, index, count + following, count + index]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _draw() -> void:
	if size.x <= 0 or size.y <= 0: return
	draw_rect(Rect2(Vector2.ZERO, size), Color(.018, .023, .030, .32))
	draw_circle(_center, _inner - 3.0 * _scale, Color(.055, .066, .080, .94), true, -1.0, true)
	draw_arc(_center, _inner - 3.0 * _scale, 0, TAU, 96, Color(STYLE.LINE, .65), 1.0, true)
	for index in _slots:
		var present := index < _entries.size()
		var enabled := present and bool(_entries[index].get("enabled", true))
		var active := index == _selected and present
		var shade := Color(.075, .085, .10, .92) if present else Color(.075, .085, .10, .58)
		if active: shade = Color(.33, .27, .17, .95) if enabled else Color(.18, .19, .21, .95)
		draw_mesh(_sectors[index], null, Transform2D.IDENTITY, shade)
		draw_mesh(_accents[index], null, Transform2D.IDENTITY, STYLE.ACCENT if active and enabled else Color(STYLE.LINE, .65))
		if present: _draw_entry(index, enabled, active)
		else: draw_circle(_anchors[index], 2.0 * _scale, Color(STYLE.MUTED, .32), true, -1.0, true)
	_draw_heading()
	_draw_center()
	_draw_footer()

func _draw_entry(index: int, enabled: bool, active: bool) -> void:
	var entry := _entries[index]
	var anchor := _anchors[index]
	var tint := Color.WHITE if enabled else Color(1, 1, 1, .28)
	var icon: Texture2D = entry.get("icon")
	if icon != null:
		var available := Vector2(80, 45) * _scale
		var texture_size := icon.get_size()
		var fitted := texture_size * minf(available.x / maxf(texture_size.x, 1), available.y / maxf(texture_size.y, 1))
		draw_texture_rect(icon, Rect2(anchor - Vector2(fitted.x * .5, fitted.y * .5 + 7.0 * _scale), fitted), false, tint)
	var label := _display_name(str(entry.get("slot_label", entry.get("label", ""))))
	var color := STYLE.TEXT if enabled else STYLE.DISABLED
	if active and enabled: color = Color("f8e1b7")
	_name_text(label, anchor + Vector2(0, 30) * _scale, 104.0 * _scale, 14, color)
	var count := str(entry.get("count_label", ""))
	if not count.is_empty(): _text(count, anchor + Vector2(0, -35) * _scale, 85.0 * _scale, 12, STYLE.ACCENT if enabled else STYLE.DISABLED)

func _draw_heading() -> void:
	var baseline := _center.y - _radius - 29.0 * _scale
	var tab_width := 154.0 * _scale
	for index in 2:
		var anchor := Vector2(_center.x + (-.5 if index == 0 else .5) * tab_width, baseline)
		var selected := _page == index
		_text(_tr("Armas", "Weapons") if index == 0 else _tr("Consumíveis", "Consumables"), anchor, tab_width, 19, STYLE.TEXT if selected else STYLE.MUTED)
		if selected: draw_line(anchor + Vector2(-tab_width * .38, 10.0 * _scale), anchor + Vector2(tab_width * .38, 10.0 * _scale), STYLE.ACCENT, 3.0 * _scale, true)
	_text("01" if _page == 0 else "02", Vector2(_center.x, baseline - 29.0 * _scale), 80.0 * _scale, 12, STYLE.ACCENT)

func _draw_center() -> void:
	var width := _inner * 1.7
	if _entries.is_empty():
		_text(_tr("Vazio", "Empty"), _center + Vector2(0, -7) * _scale, width, 21, STYLE.TEXT)
		_text(_tr("Sem consumíveis", "No consumables") if _page == 1 else _tr("Sem armas", "No weapons"), _center + Vector2(0, 20) * _scale, width, 14, STYLE.MUTED)
		return
	if _selected < 0 or _selected >= _entries.size():
		_text(_tr("Selecionar", "Select"), _center + Vector2(0, 6) * _scale, width, 18, STYLE.MUTED)
		return
	var entry := _entries[_selected]
	var enabled := bool(entry.get("enabled", true))
	var label := _display_name(str(entry.get("label", "")))
	var stats: Array = entry.get("stats", [])
	if _page == 0 and not stats.is_empty():
		_name_text(label, _center + Vector2(0, -44) * _scale, width, 15, STYLE.TEXT)
		_text(str(entry.get("role", "")), _center + Vector2(0, -7) * _scale, width, 12, STYLE.ACCENT)
		_text(str(entry.get("detail", "")), _center + Vector2(0, 16) * _scale, width, 16, STYLE.TEXT)
		for index in mini(stats.size(), 2):
			_text(str(stats[index]), _center + Vector2(0, 37 + 17 * index) * _scale, width, 12, STYLE.MUTED)
		var count := int(entry.get("variant_count", 1))
		if count > 1:
			for index in count:
				var point := _center + Vector2((float(index) - float(count - 1) * .5) * 12, 70) * _scale
				draw_circle(point, 2.5 * _scale, STYLE.ACCENT if index == int(entry.get("variant_index", 0)) else STYLE.LINE, true, -1.0, true)
		return
	_name_text(label, _center + Vector2(0, -30) * _scale, width, 18, STYLE.TEXT)
	draw_line(_center + Vector2(-22, 2) * _scale, _center + Vector2(22, 2) * _scale, STYLE.ACCENT if enabled else STYLE.LINE, 2.0 * _scale, true)
	var details := str(entry.get("detail", "")).split("\n")
	for index in mini(details.size(), 3):
		_text(details[index], _center + Vector2(0, 23 + 19 * index) * _scale, width, 14, STYLE.MUTED)

func _name_lines(value: String, width: float, font_size: int) -> Array[String]:
	var lines: Array[String] = [""]
	for word in value.split(" "):
		var candidate := (lines[-1] + " " + word).strip_edges()
		if not lines[-1].is_empty() and STYLE.STRONG.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			lines.append(word)
		else: lines[-1] = candidate
	return lines

func _name_text(value: String, baseline: Vector2, width: float, base_size: int, color: Color) -> void:
	var font_size := maxi(11, roundi(base_size * _scale))
	var lines := _name_lines(value, width, font_size)
	while font_size > 10:
		var fits := lines.size() <= 2
		for line in lines:
			fits = fits and STYLE.STRONG.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width
		if fits: break
		font_size -= 1
		lines = _name_lines(value, width, font_size)
	var line_height := float(font_size) + 3.0 * _scale
	for index in lines.size():
		draw_string(STYLE.STRONG, baseline + Vector2(-width * .5, index * line_height), lines[index], HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)

func _display_name(value: String) -> String:
	# Catalog/localization identifiers stay unchanged; only display casing changes.
	if value.is_empty() or value != value.to_upper(): return value
	var words := value.to_lower().split(" ")
	for index in words.size():
		if words[index].to_upper() in ["AK-47", "M4A1", "MP5", "RPG", "RPG-7", "SMG"]:
			words[index] = words[index].to_upper()
	var result := " ".join(words)
	return result.left(1).to_upper() + result.substr(1)

func _draw_footer() -> void:
	var y := _center.y + _radius + 34.0 * _scale
	var row := [
		[str(_hints.get("hold", "Q")), _tr("Soltar para usar", "Release to use") if _page == 1 else _tr("Soltar para equipar", "Release to equip")],
		[str(_hints.get("switch", "E")), _tr("Trocar roda", "Switch wheel")],
		[str(_hints.get("cancel", "Esc")), _tr("Cancelar", "Cancel")],
	]
	var total := 0.0
	var widths: Array[float] = []
	var font_size := maxi(11, roundi(15 * _scale))
	for hint in row:
		var width := STYLE.STRONG.get_string_size(str(hint[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + STYLE.FONT.get_string_size(str(hint[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 38.0 * _scale
		widths.append(width)
		total += width
	var x := _center.x - total * .5
	for index in row.size():
		var key := str(row[index][0])
		var key_width := maxf(23.0 * _scale, STYLE.STRONG.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 12.0 * _scale)
		var box := Rect2(x, y - 16.0 * _scale, key_width, 23.0 * _scale)
		if _hint_style != null: draw_style_box(_hint_style, box)
		_text(key, Vector2(x + key_width * .5, y + 1.0 * _scale), key_width, 14, STYLE.TEXT)
		draw_string(STYLE.FONT, Vector2(x + key_width + 8.0 * _scale, y), str(row[index][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, STYLE.TEXT)
		x += widths[index]
	var subcycle := str(_hints.get("subcycle", ""))
	if not subcycle.is_empty(): _text(subcycle, Vector2(_center.x, y + 29.0 * _scale), size.x - 48.0 * _scale, 13, STYLE.MUTED)

func _text(value: String, baseline: Vector2, width: float, base_size: int, color: Color) -> void:
	var font_size := maxi(10, roundi(base_size * _scale))
	while font_size > 10 and STYLE.STRONG.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		font_size -= 1
	var text := value
	while text.length() > 2 and STYLE.STRONG.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		text = text.left(text.length() - 2) + "…"
	draw_string(STYLE.STRONG, baseline - Vector2(width * .5, 0), text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, color)

func _tr(pt: String, en: String) -> String:
	return en if TranslationServer.get_locale().begins_with("en") else pt
