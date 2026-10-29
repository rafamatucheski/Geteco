extends SceneTree
## Preparação fatiada do acesso de prédio (29/10): na partida release de 29/10 o corte da
## Torque custou 127 ms num quadro (building.access.prepare). Confere que a versão fatiada
## (begin_prepare_access) monta o mesmo que a síncrona (malhas, lotes, colisões, geometria
## recortada), que nenhuma fatia passa de 4 ms, que a síncrona toma o lugar no meio sem
## duplicar peças e que a porta continua atravessável. Rodar COM janela (sem --headless):
## sem renderizador as arrays de malha e as instâncias de MultiMesh voltam vazias/na origem.
const CATALOG = preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const ACCESS = preload("res://world/places/harbor_buildings/HarborBuildingExteriorAccess.gd")
const FACTORY = preload("res://world/urban_detail/UrbanBuildingFactory.gd")
const SITE = preload("res://world/places/classic_meet/ClassicMeetSite.gd")
const MAX_SLICE_MS := 4.0
var failures: Array[String] = []
var checks := 0
var report := {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message)

func _run() -> void:
	await _case("torque", func() -> Node3D:
		var site: Node3D = SITE.new()
		root.add_child(site)
		return site)
	for source_id in ["NorthFrontage5","FoundryLofts"]:
		var definition := CATALOG.for_source(source_id)
		if definition.is_empty(): continue
		await _case(source_id, func() -> Node3D:
			var holder := Node3D.new()
			root.add_child(holder)
			var data := {"id":definition.source_id,"position":definition.facade_position,"size":definition.size,"kind":definition.building_kind,"height_override":definition.storey_height*definition.floor_count}
			if definition.building_kind == "l_shaped_block": data.size.y /= .55
			var art := FACTORY.populate_chunk(holder,data)
			art.rotation.y = definition.exterior_rotation
			ACCESS.install(art,str(definition.source_id))
			return holder)
	print(JSON.stringify({"test":"harbor_building_access_sliced","checks":checks,"failures":failures,"report":report}))
	quit(0 if failures.is_empty() else 1)

func _access_of(holder: Node3D) -> Node3D:
	var found := holder.find_children("BuildingAccess","",true,false)
	return found[0] if not found.is_empty() else null

## Resumo comparável do que a preparação publicou.
func _signature(access: Node3D) -> Dictionary:
	var vertices := 0
	var surfaces := 0
	var cut := 0
	for item in access._meshes:
		var mesh: Mesh = item.open_mesh
		if mesh == null: continue
		if mesh != item.original: cut += 1
		for surface in mesh.get_surface_count():
			surfaces += 1
			if mesh is ArrayMesh: vertices += mesh.surface_get_array_len(surface)
	var boxes := 0
	for child in access._replacement_body.get_children():
		if child is CollisionShape3D: boxes += 1
	return {"meshes":access._meshes.size(), "multimeshes":access._multimeshes.size(), "shapes":access._original_shapes.size(),
		"solids":boxes, "labels":access._labels.size(), "effects":access._effects.size(), "cut":cut, "surfaces":surfaces,
		"vertices":vertices, "details":access.find_children("ParcelDetail*","",false,false).size()}

func _case(label: String, build: Callable) -> void:
	# 1) Síncrona (como antes): referência.
	var holder_sync: Node3D = build.call()
	await physics_frame
	await process_frame
	var sync_access := _access_of(holder_sync)
	check(sync_access != null, label+": acesso instalado")
	if sync_access == null: return
	var began := Time.get_ticks_usec()
	sync_access._prepare_access()
	var sync_ms := float(Time.get_ticks_usec()-began)/1000.0
	var expected := _signature(sync_access)
	holder_sync.queue_free()
	await process_frame
	# 2) Fatiada até o fim.
	var holder_sliced: Node3D = build.call()
	await physics_frame
	await process_frame
	var access := _access_of(holder_sliced)
	access.begin_prepare_access()
	var frames := 0
	while not access.is_access_prepared() and frames < 2000:
		await process_frame
		frames += 1
	check(access.is_access_prepared(), label+": fatiada terminou em %d quadros"%frames)
	var stats: Dictionary = access.last_prepare_stats
	check(float(stats.get("max_slice_ms", 999.0)) <= MAX_SLICE_MS, label+": maior fatia %.2f ms <= %.1f ms"%[float(stats.get("max_slice_ms",-1.0)),MAX_SLICE_MS])
	var got := _signature(access)
	check(got == expected, label+": fatiada publica o mesmo que a síncrona %s != %s"%[str(got),str(expected)])
	access.set_open_amount(1.0)
	await physics_frame
	await physics_frame
	check(access.access_ready, label+": abre depois da fatiada")
	access.restore_exterior()
	report[label] = {"sync_ms":snappedf(sync_ms,.01), "sliced":stats, "signature":got}
	holder_sliced.queue_free()
	await process_frame
	# 3) Síncrona toma o lugar no meio da fatiada: nada em dobro, nada sobra.
	var holder_race: Node3D = build.call()
	await physics_frame
	await process_frame
	var race := _access_of(holder_race)
	race.begin_prepare_access(1)
	await process_frame
	await process_frame
	race.set_open_amount(1.0)
	for frame in 30: await process_frame
	check(race.is_access_prepared() and not race.is_access_preparing(), label+": síncrona encerra a fatiada")
	var raced := _signature(race)
	check(raced == expected, label+": troca no meio não duplica %s != %s"%[str(raced),str(expected)])
	check(race.find_children("OpenedFacadeSolids","",false,false).size() == 1, label+": um só corpo de colisão")
	holder_race.queue_free()
	await process_frame
