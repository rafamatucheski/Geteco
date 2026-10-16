extends SceneTree
## Corrida da fusão por trecho (world/chunk_bake/ChunkCellMerge.gd) com teleporte rápido: dois trechos fundindo
## em fatias ao mesmo tempo, um deles liberado no meio e uma fonte do outro liberada/levada para fora no meio.
## Antes, o estado da fatia era estático e compartilhado: o trecho liberado seguia porque olhava o trecho vivo
## do outro, e dava SCRIPT ERROR em _merge_scope (instância liberada), _sum ('batches') e get_children
## (auditoria de 15/10). Aqui as duas fusões precisam terminar sem erro e o lote não leva fonte que saiu.
const MERGE := preload("res://world/chunk_bake/ChunkCellMerge.gd")
var failures: Array[String] = []
var checks := 0
var finished := {}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

## Trecho sintético: muitas caixas em células diferentes (um grupo por célula), para a fatia ceder entre grupos.
func _chunk(region: Node3D, name: String, offset: float) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = name
	chunk.set_meta("vegetation_ready_frame", 0)
	region.add_child(chunk)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.4, 0.5, 0.6)
	var box := BoxMesh.new()
	for index in 40:
		var mesh := MeshInstance3D.new()
		mesh.name = "Piece%d" % index
		mesh.mesh = box
		mesh.material_override = material
		chunk.add_child(mesh)
		mesh.position = Vector3(offset + index * 40.0, 2.0, 0.0)
	return chunk

func _merge(name: String, chunk: Node3D) -> void:
	finished[name] = await MERGE._run(chunk, 1)

func run() -> void:
	# Orçamento de 1 µs: cede o quadro a cada grupo, como em jogo, só que sempre.
	var region := Node3D.new()
	region.set("name", "RaceRegion")
	root.add_child(region)
	var a := _chunk(region, "ChunkA", 0.0)
	var b := _chunk(region, "ChunkB", 5000.0)
	var leaving: MeshInstance3D = b.get_node("Piece39")
	var freed_source: MeshInstance3D = b.get_node("Piece38")
	_merge("a", a)
	_merge("b", b)
	for frame in 3: await process_frame
	# Teleporte: o trecho A sai da árvore no meio da fusão; no B uma fonte é liberada e outra sai do trecho.
	a.queue_free()
	freed_source.queue_free()
	b.remove_child(leaving)
	region.add_child(leaving)
	# Cada lote cede o quadro várias vezes com 1 µs (coleta, divisão por vértices, montagem, envio).
	for frame in 1000:
		await process_frame
		if finished.has("a") and finished.has("b"): break
	check(finished.has("a"), "Fusão do trecho liberado termina (não fica presa nem segue no trecho alheio)")
	check(finished.has("b"), "Fusão do trecho vivo termina")
	if finished.has("b"):
		var report: Dictionary = finished["b"]
		print("CELL_MERGE_RACE b=%s a=%s" % [JSON.stringify(report), JSON.stringify(finished.get("a", {}))])
		check(report.batches > 0, "Trecho vivo ganha lotes")
		check(report.sources == 38, "Só as 38 fontes que ficaram no trecho entram nos lotes (%d)" % report.sources)
	check(leaving.visible and not leaving.has_meta(MERGE.MERGED_SOURCE), "Fonte que saiu do trecho no meio continua visível")
	print("CELL_MERGE_RACE checks=%d falhas=%s" % [checks, failures])
	region.free()
	quit(0 if failures.is_empty() else 1)
