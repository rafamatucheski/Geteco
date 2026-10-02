extends SceneTree
## Integração dos donos produtivos, sem Main, montar regiões novas ou warmup.
const PRODUCTION := preload("res://runtime/ProductionWorld.gd")
const CONTROLLER := preload("res://gameplay/dispatch/DispatchController.gd")
const UNIT := preload("res://gameplay/dispatch/DispatchUnit.gd")
const CONNECTION := preload("res://world/regions/WorldConnection3D.gd")

class WorldProbe extends Node3D:
	var production: Node
	var player: Node3D

class RegionProbe extends "res://world/regions/NativeRegion.gd":
	# Suprime apenas o foco automático; prepare_data/admission/trim são produtivos.
	func _ready() -> void: pass

var checks := 0
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures.append(label)

func add_region(scene: Node3D, id: String) -> RegionProbe:
	var region := RegionProbe.new()
	region.region_id = id
	region.prepare_data()
	region.set_process(false)
	region.set_physics_process(false)
	scene.add_child(region)
	return region

func run() -> void:
	var scene := WorldProbe.new()
	root.add_child(scene)
	var production := PRODUCTION.new()
	production.world = scene
	# Rotas e seus consumidores não participam da admissão física desta fixture.
	production.traffic_routes = null
	production.state.set_location("harbor")
	production.set_process(false)
	production.set_physics_process(false)
	scene.production = production
	scene.add_child(production)
	var harbor := add_region(scene,"harbor")
	var mountain := add_region(scene,"mountain")
	production.regions = {"harbor":harbor,"mountain":mountain}
	production.region = harbor
	var controller := CONTROLLER.new()
	controller.world = scene
	controller.set_physics_process(false)
	scene.add_child(controller)
	var car := CharacterBody3D.new()
	car.position = Vector3(455,0,-285)
	car.rotation.y = -PI*.5
	scene.add_child(car)
	var unit := UNIT.new()
	unit.vehicle = car
	var ahead: Vector3 = car.global_position-car.global_basis.z*12.0
	var key: Vector2i = harbor._cell(car.global_position)
	check(CONNECTION.logical_region(car.global_position) == "harbor" and CONNECTION.logical_region(ahead) == "mountain", "corpo/antecipação ficam em lados distintos")
	check(key == mountain._cell(ahead), "ambos donos compartilham os mesmos índices de célula")
	controller._prepare_unit_ground(unit)
	check(harbor.chunks.has(key) and mountain.chunks.has(key), "admissão produtiva prepara ambos donos, mesmo jogador em Harbor")
	if harbor.chunks.has(key) and mountain.chunks.has(key):
		var h_id: int = harbor.chunks[key].get_instance_id()
		var m_id: int = mountain.chunks[key].get_instance_id()
		var job_count: int = harbor.build_jobs.size()+mountain.build_jobs.size()
		controller._prepare_unit_ground(unit)
		check(harbor.chunks[key].get_instance_id() == h_id and mountain.chunks[key].get_instance_id() == m_id and harbor.build_jobs.size()+mountain.build_jobs.size() == job_count, "memo reutiliza os mesmos chunks sem duplicar jobs")
		production.region = mountain
		controller._prepare_unit_ground(unit)
		check(harbor.chunks[key].get_instance_id() == h_id and mountain.chunks[key].get_instance_id() == m_id, "troca da região do jogador não troca donos físicos")
		car.position.x = 457
		controller._prepare_unit_ground(unit)
		check(controller._prepared_ground_cells[unit.get_instance_id()].size() == 1, "cruzar a costura sem mudar índices mantém apenas o dono necessário")
		mountain._trim_chunks(Vector2i(50,50))
		check(not mountain.chunks.has(key), "poda produtiva remove chunk memorizado")
		controller._prepare_unit_ground(unit)
		check(mountain.chunks.has(key) and mountain.chunks[key].get_instance_id() != m_id, "mesma posição admite chunk novamente depois da poda")
		production.region = harbor
		production._unmount_region("mountain")
		var h_count: int = harbor.chunks.size()
		controller._prepare_unit_ground(unit)
		check(not production.regions.has("mountain") and production._region_cache.has("mountain") and harbor.chunks.size() == h_count, "owner ausente não monta cache nem usa a região do jogador")
		var remounted: Node3D = production._mount_region_now("mountain",Vector3.INF)
		check(remounted == mountain and mountain.chunks.is_empty(), "remount produtivo preserva owner e libera chunks antigos")
		controller._prepare_unit_ground(unit)
		check(mountain.chunks.has(key), "memo revalida chunks ao remount do mesmo owner")
		var replacement := add_region(scene,"mountain")
		production.regions["mountain"] = replacement
		controller._prepare_unit_ground(unit)
		check(replacement.chunks.has(key), "owner novo com mesmos índices recebe admissão")
	scene.free()
	print("%s DISPATCH_GROUND_OWNERS checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL",checks,failures])
	quit(0 if failures.is_empty() else 1)
