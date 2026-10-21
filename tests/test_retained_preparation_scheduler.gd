extends SceneTree
## Contrato de reuso e agendamento; nao mede FPS nem substitui a rota renderizada.
const PREPARATION := preload("res://runtime/RetainedRegionPreparation.gd")

class DeferredDetail:
	extends Node3D
	var deferred_ready := false
	func _ready() -> void:
		_finish.call_deferred()
	func _finish() -> void:
		deferred_ready = true

class RegionProbe:
	extends "res://world/regions/NativeRegion.gd"
	var builds := 0
	var holds := 0
	var detail_was_ready := false
	func prepare_data() -> void:
		data_prepared = true
	func _build_record(chunk: Node3D, record: Dictionary) -> void:
		builds += 1
		chunk.add_child(DeferredDetail.new() if record.kind == "harbor_dressing" else Node3D.new())
	func _hold_file_resources(chunk: Node) -> void:
		holds += 1
		for node in chunk.get_children():
			if node is DeferredDetail: detail_was_ready = node.deferred_ready

class InterruptedRegion:
	extends RegionProbe
	var partial: Node3D
	func _step_record_build(_chunk: Node3D, _record: Dictionary, job: Dictionary, _budget_usec: float) -> bool:
		if not job.has("route_zone"):
			job.route_zone = preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd").begin_zone("rodoviaria")
			partial = job.route_zone.root
			_leave_tree.call_deferred()
		return false
	func _leave_tree() -> void:
		get_parent().remove_child(self)

class InterruptedDressingRegion:
	extends RegionProbe
	func _build_record(chunk: Node3D, record: Dictionary) -> void:
		super._build_record(chunk,record)
		_leave_tree.call_deferred()
	func _leave_tree() -> void:
		get_parent().remove_child(self)

var checks := 0
var failures := 0
func _initialize() -> void:
	run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("RETAINED_SCHEDULER: " + label)
func run() -> void:
	var region := RegionProbe.new()
	region.initial_prewarm_only = true
	region.region_id = "preparation_probe"
	for i in 8:
		region.records[Vector2i(i,0)] = [{"kind":"ship","position":Vector3(i,0,0)}]
	root.add_child(region)
	region.set_process(false)
	await PREPARATION.run(region)
	check(region.builds == 8 and region.holds == 8,"todos os modelos distintos foram preparados")
	var built := region.builds
	var held := region.holds
	await PREPARATION.run(region)
	check(region.builds == built,"preparacao repetida nao reconstroi modelos prontos")
	check(region.holds == held,"cache pronto nao e remontado nem percorrido novamente")
	check(region.get_child_count() == 0,"preparacao deixa somente modelos destacados no cache")
	var first_record: Dictionary = region.records[Vector2i.ZERO][0]
	var first_key: String = region._record_cache_key(first_record)
	var stale: Node3D = region._record_cache[first_key][0]
	stale.free()
	await PREPARATION.run(region)
	check(region.builds == built + 1,"cache invalidado recompõe somente o modelo ausente")
	var dressing_record := {"kind":"harbor_dressing","position":Vector3(100,0,0)}
	region.records[Vector2i(100,0)] = [dressing_record]
	await PREPARATION.run(region)
	check(region.detail_was_ready,"acabamento adiado termina na arvore antes de ser guardado")
	check(region.get_child_count() == 0,"acabamento preservado tambem sai da arvore ativa")
	var warmed := Node3D.new()
	region.add_child(warmed)
	region._build_record_cached(warmed,first_record)
	region._warm_tunnel_chunks[Vector2i.ZERO] = warmed
	var before_warm_check := region.builds
	await PREPARATION.run(region)
	check(region.builds == before_warm_check and warmed.get_child_count() == 1,"trecho de tunel preservado nao duplica modelo ainda parentado")
	region.free()
	var interrupted := InterruptedRegion.new()
	interrupted.initial_prewarm_only = true
	interrupted.region_id = "preparation_probe"
	interrupted.records[Vector2i.ZERO] = [{"kind":"ship","position":Vector3.ZERO}]
	root.add_child(interrupted)
	interrupted.set_process(false)
	await PREPARATION.run(interrupted)
	check(not interrupted.is_inside_tree() and not is_instance_valid(interrupted.partial),"interromper preparacao libera a zona parcial destacada")
	interrupted.free()
	var orphan_job := {"route_zone":preload("res://world/harbor_route_detail/HarborRouteDetailFactory.gd").begin_zone("delegacia")}
	var orphan_root: Node3D = orphan_job.route_zone.root
	PREPARATION._cancel_record_job(null,orphan_job)
	check(not is_instance_valid(orphan_root) and not orphan_job.has("route_zone"),"cancelamento sem regiao viva tambem libera a zona parcial")
	var dressing_interrupted := InterruptedDressingRegion.new()
	dressing_interrupted.initial_prewarm_only = true
	dressing_interrupted.region_id = "preparation_probe"
	dressing_interrupted.records[Vector2i.ZERO] = [dressing_record]
	root.add_child(dressing_interrupted)
	dressing_interrupted.set_process(false)
	await PREPARATION.run(dressing_interrupted)
	check(not dressing_interrupted.is_inside_tree() and dressing_interrupted.get_child_count() == 0,"interromper acabamento nao deixa container temporario na regiao reaproveitada")
	var interrupted_nodes: Array = dressing_interrupted._record_cache.values()[0]
	check(interrupted_nodes.size() == 1 and is_instance_valid(interrupted_nodes[0]) and interrupted_nodes[0].get_parent() == null,"modelo concluido fica reaproveitavel mesmo se carga for interrompida")
	dressing_interrupted.free()
	print("RETAINED_SCHEDULER checks=%d failures=%d"%[checks,failures])
	quit(0 if failures == 0 else 1)
