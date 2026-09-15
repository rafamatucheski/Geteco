@tool
extends RefCounted
## Coordenadas canônicas do circuito. A simulação continua mesmo com a serra
## descarregada; não existe uma segunda instância do trem na fronteira.
const MOUNTAIN_OFFSET := Vector2(4300, -4960)
const MOUNTAIN_POINTS := [
	Vector2(5800, 1180), Vector2(6350, 1120), Vector2(6850, 1100),
	Vector2(7700, 1160), Vector2(8750, 950), Vector2(9200, 260),
	Vector2(9250, -750), Vector2(8700, -1450), Vector2(8100, -2050),
	Vector2(7700, -2700), Vector2(7500, -3100),
]
const BAY_START := Vector2(6400, -4920)
const BAY_END := Vector2(9150, -4920)
var curve := Curve2D.new()
var points: Array[Vector2] = []
var sections: Array[Dictionary] = []
var landmarks: Array[Dictionary] = []

func _init() -> void:
	points.assign([
		Vector2(-700, 892), Vector2(0, 892), Vector2(2814, 892),
		Vector2(3114, 1192), Vector2(3114, 2240), Vector2(3114, 3320),
		Vector2(3114, 3850), Vector2(4400, 3000), Vector2(4700, -2600),
		Vector2(5850, -4920), BAY_START, Vector2(7300, -4920),
		Vector2(8680, -4920), BAY_END, Vector2(9630, -4820),
	])
	for point in MOUNTAIN_POINTS: points.append(MOUNTAIN_OFFSET + point)
	points.append_array([
		Vector2(11100, -8700), Vector2(6500, -8500), Vector2(-1500, -4000),
		Vector2(-900, 1100), Vector2(-700, 892),
	])
	curve.bake_interval = 12.0
	var harbor_handles := [Vector2(140,0),Vector2(180,0),Vector2(165,0),Vector2(0,165),Vector2(0,100),Vector2(0,100),Vector2(-180,180)]
	for i in points.size():
		var handle := Vector2(140, 0)
		if i < harbor_handles.size():
			handle = harbor_handles[i]
		elif i < points.size() - 1:
			var before := points[i - 1]
			var after := points[i + 1]
			handle = before.direction_to(after) * minf(before.distance_to(points[i]), after.distance_to(points[i])) * 0.30
		if i in [10, 11, 12, 13]: handle = Vector2(140, 0)
		curve.add_point(points[i], -handle, handle)
	_add_section("harbor", "Viaduto do porto", points[1], points[5])
	_add_section("bay", "Ponte ferroviária da serra", BAY_START, BAY_END)
	_add_section("mountain", "Serraria e encosta nevada", MOUNTAIN_OFFSET + MOUNTAIN_POINTS[0], MOUNTAIN_OFFSET + MOUNTAIN_POINTS[-1])
	for entry in [
		["port", "Porto", Vector2(1600,892)],
		["south_tunnel", "Túnel de ligação", points[5]],
		["bay", "Ponte da serra", Vector2(7900,-4920)],
		["ridge_tunnel", "Túnel da encosta", BAY_END],
		["sawmill", "Serraria", MOUNTAIN_OFFSET + MOUNTAIN_POINTS[1]],
		["forest", "Contorno da floresta", MOUNTAIN_OFFSET + MOUNTAIN_POINTS[5]],
		["snow", "Encosta nevada", MOUNTAIN_OFFSET + MOUNTAIN_POINTS[8]],
		["north_tunnel", "Túnel norte / retorno ao porto", MOUNTAIN_OFFSET + MOUNTAIN_POINTS[-1]],
	]:
		landmarks.append({"id": entry[0], "label": entry[1], "position": entry[2], "offset": curve.get_closest_offset(entry[2])})

func _add_section(id: String, label: String, start: Vector2, end: Vector2) -> void:
	sections.append({"id": id, "label": label, "start": curve.get_closest_offset(start), "end": curve.get_closest_offset(end)})

func section_at(offset: float) -> Dictionary:
	var progress := fposmod(offset, curve.get_baked_length())
	for section in sections:
		if progress >= float(section.start) and progress <= float(section.end): return section
	return {}

func sampled_section(section: Dictionary, spacing := 48.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	var offset: float = section.start
	while offset < float(section.end):
		result.append(curve.sample_baked(offset, true))
		offset += spacing
	result.append(curve.sample_baked(section.end, true))
	return result

func is_mountain_reserved(local_point: Vector2, clearance := 100.0) -> bool:
	var point := local_point + MOUNTAIN_OFFSET
	var offset := curve.get_closest_offset(point)
	var section := section_at(offset)
	return not section.is_empty() and String(section.id) == "mountain" and point.distance_to(curve.sample_baked(offset, true)) < clearance

func get_route_data() -> Dictionary:
	var mapped_sections: Array[Dictionary] = []
	for section in sections:
		var data := section.duplicate()
		data["points"] = sampled_section(section)
		mapped_sections.append(data)
	return {"id": "harbor_mountain_freight", "length": curve.get_baked_length(), "sections": mapped_sections, "landmarks": landmarks.duplicate(true), "closed": true}
