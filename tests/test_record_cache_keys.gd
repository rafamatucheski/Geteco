extends SceneTree
## Chave e escolha do cache de registros do NativeRegion. Prédios guardam id e posição em `data`;
## sem isso todos caíam na mesma chave e um reaproveitaria os nós de outro (pego em 2026-10-13).
## Uso: "$GODOT" --path . --script res://tests/test_record_cache_keys.gd
const REGION := preload("res://world/regions/NativeRegion.gd")
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func run() -> void:
	var region = REGION.new()
	region.region_id = "harbor"
	var fire := {"kind":"building","data":{"id":"NorthFireStation","position":Vector3(367.5,0,-85.6)}}
	var court := {"kind":"building","data":{"id":"BridgeCourtWest","position":Vector3(307.8,0,-140.0)}}
	var plain := {"kind":"building","data":{"id":"SomeOtherBuilding","position":Vector3(10,0,10)}}
	var cargo := {"kind":"south_port_model","id":"SantaMareCargo3D","model_kind":"ship_cargo","position":Vector3(302.7,0,182.1)}
	var crane := {"kind":"south_port_model","id":"QuaysideCrane3D0","model_kind":"crane","position":Vector3(300,0,170)}
	var supplies := {"kind":"south_port_model","id":"PalletsAndDrums3D0","model_kind":"supplies","position":Vector3(260,0,310)}
	var ship_detail := {"kind":"south_port_ship_detail","position":Vector3(300,0,180)}
	# Poste do porto acende luz local (city_local_light_source): segue montado ao vivo.
	var floodlight := {"kind":"south_port_model","id":"PortFloodlight0","model_kind":"floodlight","position":Vector3(228,0,212)}
	check(region._record_cache_key(fire) != region._record_cache_key(court), "Prédios diferentes têm chaves diferentes")
	check(region._is_cached_record(fire) and region._is_cached_record(court), "Os prédios medidos entram no cache")
	check(not region._is_cached_record(plain), "Prédio comum segue sendo montado ao vivo")
	check(region._is_cached_record(cargo), "A carga do navio entra no cache")
	# Guindastes, paletes e o acabamento do navio pesavam 15-87 ms ao entrar no cais (release de 15/10).
	check(region._is_cached_record(crane) and region._is_cached_record(supplies) and region._is_cached_record(ship_detail), "Guindastes, paletes e acabamento do navio entram no cache")
	check(not region._is_cached_record(floodlight), "Outros modelos do porto seguem ao vivo")
	region.free()
	print("RECORD_CACHE_KEYS ", "PASS" if failures.is_empty() else "FALHOU", " failures=", failures)
	quit(0 if failures.is_empty() else 1)
