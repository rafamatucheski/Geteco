extends SceneTree
## Contrato de preparacao: usa scheduler real com fronteiras caras substituidas.
## Nao mede ms/FPS nem aprova colisao/carga visual dos modelos.
class RegionProbe:
	extends "res://world/regions/NativeRegion.gd"
	var focus_requests: Array[Vector3] = []
	var built_records: Array[String] = []
	func prepare_data() -> void:
		data_prepared = true
	func set_focus(point: Vector3) -> void:
		focus_requests.append(point)
	func _build_surfaces(_chunk: Node3D, _rect: Rect2, _key: Vector2i) -> void:
		pass
	func _build_record(_chunk: Node3D, record: Dictionary) -> void:
		built_records.append(str(record.get("model_kind", record.kind)))

var checks := 0
var failures := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("STARTUP_PREWARM: " + label)
func run() -> void:
	var warm := RegionProbe.new()
	warm.initial_focus = Vector3(128, 0, 192)
	warm.initial_prewarm_only = true
	warm._ready()
	check(warm.data_prepared and warm.prepared, "dados/preparacao continuam obrigatorios")
	check(warm.focus_requests.is_empty(), "warm-up distante nao monta vizinhanca de spawn")
	check(warm.chunks.is_empty() and warm.pending.is_empty(), "warm-up distante nao admite piso como residencia")
	warm.records[Vector2i.ZERO] = [
		{"kind": "south_port_model", "model_kind": "ship_cargo", "position": Vector3.ZERO},
		{"kind": "test_regular_record", "position": Vector3.ZERO},
	]
	warm.prewarm()
	check(warm.built_records == ["ship_cargo", "test_regular_record"], "sincrono conserva prewarm completo antes da primeira visita")
	check(warm.records[Vector2i.ZERO].size() == 2, "warm-up preserva todos os registros autorais")
	check(warm.chunks.is_empty(), "warm-up descarta celula temporaria")
	warm.initial_prewarm_only = false
	warm.set_focus(Vector3(192, 0, 128))
	check(warm.focus_requests == [Vector3(192, 0, 128)], "primeira montagem real solicita seu destino")
	warm.built_records.clear()
	warm._build_chunk(Vector2i.ZERO)
	check(warm.built_records == ["ship_cargo", "test_regular_record"], "construcao viva conserva carga e ordem completas")
	warm.free()
	var normal := RegionProbe.new()
	normal.initial_focus = Vector3(64, 0, 128)
	normal._ready()
	check(not normal.initial_prewarm_only and normal.focus_requests == [Vector3(64, 0, 128)], "inicio normal conserva foco salvo")
	normal.free()
	var fallback := RegionProbe.new()
	fallback._ready()
	check(fallback.focus_requests == [fallback.spawn_position], "inicio sem foco conserva spawn original")
	fallback.free()
	print("PASS " if failures == 0 else "FAIL ", "STARTUP_PREWARM checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
