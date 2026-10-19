extends Node
## Um anel mundial evita multiplicar malhas, timers e 320 segmentos por carro.
static var enabled := OS.get_environment("GETECO_SKID_BUDGET") != "0"
const MAX_SEGMENTS := 256
const REDRAW_INTERVAL := .10
static var _instance: Node

var _slots: Array[Dictionary] = []
var _head := 0
var segment_count := 0
var geometry := ArrayMesh.new()
var mark_mesh: MeshInstance3D
var _timer: Timer
var _dirty := false
var _last_colors := PackedInt64Array()
var redraw_count := 0

static func append(source: Node, mark: Dictionary, material: StandardMaterial3D) -> void:
	if not is_instance_valid(_instance):
		_instance = load("res://gameplay/vehicle_effects/SkidmarkBudget.gd").new()
		_instance.name = "WorldSkidmarkBudget"
		source.get_tree().root.add_child(_instance)
		_instance._setup(material)
	_instance._append(source, mark)

static func release(source: Node) -> void:
	if is_instance_valid(_instance):
		_instance._remove(source, Time.get_ticks_msec())
		_instance._redraw()

static func expire() -> void:
	if is_instance_valid(_instance): _instance._remove(null, Time.get_ticks_msec())

static func redraw() -> void:
	if is_instance_valid(_instance): _instance._redraw()

func _setup(material: StandardMaterial3D) -> void:
	_slots.resize(MAX_SEGMENTS)
	mark_mesh = MeshInstance3D.new()
	mark_mesh.name = "SurfaceAlignedWorldTireMarks"
	mark_mesh.mesh = geometry
	mark_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mark_mesh.material_override = material
	add_child(mark_mesh)
	mark_mesh.top_level = true
	mark_mesh.global_transform = Transform3D.IDENTITY
	_timer = Timer.new()
	_timer.process_mode = Node.PROCESS_MODE_PAUSABLE
	_timer.wait_time = REDRAW_INTERVAL
	add_child(_timer)
	_timer.timeout.connect(_tick)

func _append(source: Node, mark: Dictionary) -> void:
	if segment_count == MAX_SEGMENTS:
		_forget(_slots[_head])
		_slots[_head] = {"source": weakref(source), "mark": mark}
		_head = (_head + 1) % MAX_SEGMENTS
	else:
		_slots[(_head + segment_count) % MAX_SEGMENTS] = {"source": weakref(source), "mark": mark}
		segment_count += 1
	_dirty = true
	if _timer.is_stopped(): _timer.start()

func _forget(entry: Dictionary) -> void:
	var source: Node = entry.source.get_ref()
	if is_instance_valid(source): source.marks.erase(entry.mark)

func _remove(source: Node, now: int) -> void:
	var kept: Array[Dictionary] = []
	for offset in segment_count:
		var entry := _slots[(_head + offset) % MAX_SEGMENTS]
		var owner: Node = entry.source.get_ref()
		if not is_instance_valid(owner) or owner == source or now-int(entry.mark.born) >= int(entry.mark.life):
			_forget(entry)
			_dirty = true
		else:
			kept.append(entry)
	if not _dirty: return
	_slots.clear()
	_slots.resize(MAX_SEGMENTS)
	_head = 0
	segment_count = kept.size()
	for offset in segment_count: _slots[offset] = kept[offset]
	if segment_count == 0:
		_timer.stop()
		_redraw()

func _tick() -> void:
	_remove(null, Time.get_ticks_msec())
	_redraw()

func _redraw() -> void:
	var entries: Array[Dictionary] = []
	var colors := PackedInt64Array()
	var now := Time.get_ticks_msec()
	for offset in segment_count:
		var mark: Dictionary = _slots[(_head + offset) % MAX_SEGMENTS].mark
		entries.append(mark)
		colors.append(mark_color(mark, now).to_rgba32())
	# O fade também muda a aparência; sem mudança de RGBA8 não há upload.
	if not _dirty and colors == _last_colors: return
	_dirty = false
	_last_colors = colors
	geometry.clear_surfaces()
	mark_mesh.visible = not entries.is_empty()
	if entries.is_empty(): return
	build_geometry(entries, geometry, now)
	redraw_count += 1

func _exit_tree() -> void:
	for offset in segment_count: _forget(_slots[(_head + offset) % MAX_SEGMENTS])
	_slots.clear()
	geometry.clear_surfaces()
	if _instance == self: _instance = null

static func mark_color(mark: Dictionary, now: int) -> Color:
	var age := float(now-int(mark.born))/float(mark.life)
	var depth: float = mark.depth
	var tint := Color(.035,.035,.03,(1.0-age)*(.48 if mark.kind=="hard" else .30))
	if mark.kind == "snow": tint = Color(.38,.43,.44,(1.0-age)*.38)
	elif mark.kind == "dirt": tint = Color(.15,.10,.07,minf(1.0,(1.0-age)*.36*depth))
	elif mark.kind == "sand": tint = Color(.42,.33,.22,minf(1.0,(1.0-age)*.30*depth))
	elif mark.kind == "grass": tint = Color(.13,.15,.06,minf(1.0,(1.0-age)*.42*depth))
	return tint

static func _cache_mark_corners(mark: Dictionary) -> void:
	# A marca depositada não se move; só a cor muda durante o fade.
	# Cachear cantos evita recalcular normais por até 30 segundos.
	var a: Vector3 = mark.a
	var b: Vector3 = mark.b
	var na: Vector3 = mark.na
	var nb: Vector3 = mark.nb
	var tangent := (b-a).normalized()
	var half_width: float = mark.w
	var sa := tangent.cross(na).normalized()*half_width
	var sb := tangent.cross(nb).normalized()*half_width
	mark["corner_a_left"] = a-sa+na*.012
	mark["corner_b_left"] = b-sa+nb*.012
	mark["corner_b_right"] = b+sb+nb*.012
	mark["corner_a_right"] = a+sa+na*.012

static func build_geometry(source_marks: Array[Dictionary], geometry: ArrayMesh, now: int) -> void:
	# Um único envio de arrays evita chamadas individuais por vértice.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var vertex_count := source_marks.size()*6
	vertices.resize(vertex_count)
	normals.resize(vertex_count)
	colors.resize(vertex_count)
	var cursor := 0
	for mark in source_marks:
		if not mark.has("corner_a_left"): _cache_mark_corners(mark)
		var na: Vector3 = mark.na
		var nb: Vector3 = mark.nb
		var tint := mark_color(mark, now)
		vertices[cursor] = mark.corner_a_left
		vertices[cursor+1] = mark.corner_b_left
		vertices[cursor+2] = mark.corner_b_right
		vertices[cursor+3] = vertices[cursor]
		vertices[cursor+4] = vertices[cursor+2]
		vertices[cursor+5] = mark.corner_a_right
		normals[cursor] = na
		normals[cursor+1] = nb
		normals[cursor+2] = nb
		normals[cursor+3] = na
		normals[cursor+4] = nb
		normals[cursor+5] = na
		for offset in 6: colors[cursor+offset] = tint
		cursor += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	geometry.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
