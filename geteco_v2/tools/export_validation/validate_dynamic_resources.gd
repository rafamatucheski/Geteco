extends SceneTree

## Inventories production-time dynamic resources and validates the same paths from
## either the source project or an exported PCK. This script is intentionally kept
## outside production code and is excluded from the Windows package.

const MANIFEST_VERSION := 1
const JSON_PATHS := [
	"res://assets/fleet/catalog.json",
	"res://runtime/VehiclePaintSources.json",
	"res://world/places/OriginalResidentData.json",
	"res://world/regions/OriginalLakeData.json",
	"res://world/regions/OriginalWorldData.json",
	"res://data/campaign/campaign_v1.json",
	"res://data/campaign/first-favors-dialogue.json",
	"res://data/campaign/cobra-dialogue.json",
	"res://audio/mission_voices/recordings.json",
]
const AUDIO_ROOTS := [
	"res://assets/gameplay/audio",
	"res://audio/acoustic",
	"res://audio/footsteps",
	"res://audio/living_city",
	"res://audio/menu",
	"res://audio/mission_voices",
	"res://audio/regional",
	"res://audio/v1_ambience",
	"res://audio/weather",
	"res://cutscenes/opening/v3/audio",
]
const REGION_RESOURCE_ROOTS := [
	"res://assets/regions/source",
	"res://assets/fleet",
	"res://assets/garage_rewards",
	"res://cutscenes/opening/frames",
]
const DYNAMIC_MODEL_PATHS := [
	"res://assets/garage_rewards/ironback.scn",
	"res://assets/regions/source/assets/bank/bank-finished.tscn",
	"res://assets/regions/source/guns/ammunation/AmmunationFacade3D.gd",
	"res://assets/regions/source/world/harbor/HarborPortModel3D.gd",
	"res://assets/regions/source/world/harbor/PortBossGarageArt.gd",
	"res://assets/regions/source/world/harbor/cemetery/CemeteryHouseExterior3D.gd",
	"res://assets/regions/source/world/harbor/cemetery/CemeteryHouseInterior3D.gd",
	"res://assets/regions/source/world/harbor/hospital/HarborHospitalModel3D.gd",
	"res://assets/regions/source/world/harbor/interiors/ClothingInteriorArt3D.gd",
	"res://assets/regions/source/world/harbor/interiors/FireStationArt3D.gd",
	"res://assets/regions/source/world/harbor/interiors/FuelStoreArt3D.gd",
	"res://assets/regions/source/world/harbor/interiors/HarborPoliceStation3D.gd",
	"res://assets/regions/source/world/harbor/interiors/HospitalRoom3D.gd",
	"res://assets/regions/source/world/harbor/residences/ResidenceExterior3D.gd",
	"res://assets/regions/source/world/harbor/residences/ResidenceInterior3D.gd",
	"res://assets/regions/source/world/mountain_pass/LumberjackBunkhouse3D.gd",
	"res://assets/regions/source/world/mountain_pass/MountainBunker3D.gd",
	"res://assets/regions/source/world/mountain_pass/MountainCabin3D.gd",
	"res://assets/regions/source/world/mountain_pass/MountainCabinVariants3D.gd",
	"res://assets/regions/source/world/mountain_pass/MountainMysteryCaveInterior3D.gd",
	"res://assets/regions/source/world/mountain_pass/MountainWaterfallCave3D.gd",
	"res://assets/regions/source/world/mountain_pass/ResortShop3D.gd",
	"res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd",
	"res://assets/regions/source/world/mountain_pass/SummitSkiLodgeInterior3D.gd",
	"res://assets/regions/source/world/mountain_pass/art/review_0908/MountainGunShop3D.gd",
	"res://assets/regions/source/world/mountain_pass/art/winter_props/LumberjackCabin3D.gd",
	"res://world/places/AmmunationModel.gd",
	"res://assets/regions/source/world/harbor/events/BankClerkModel.gd",
	"res://world/places/MedicalResidentModel.gd",
	"res://world/places/ServiceResidentModel.gd",
	"res://world/places/SewerModel.gd",
]
const EXTRA_DYNAMIC_RESOURCES := [
	"res://assets/outfits/dante_outfit_regions.png",
	"res://audio/menu/harbor_night_menu.wav",
]
const RESOURCE_EXTENSIONS := [
	"gd", "gdshader", "glb", "gltf", "jpeg", "jpg", "mp3", "obj", "ogg",
	"png", "res", "scn", "svg", "tres", "tscn", "ttf", "wav", "webp",
]
const AUDIO_EXTENSIONS := ["mp3", "ogg", "wav"]
const RAW_WAV_PREFIX := "res://assets/gameplay/audio/"

var failures: Array[String] = []
var checks := 0
var mode := "source"
var manifest_path := ""
var report_path := ""
var categories: Dictionary = {}
var raw_wav_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_parse_arguments()
	if mode == "source":
		_build_source_manifest()
		if failures.is_empty() and not manifest_path.is_empty():
			_write_manifest()
	elif mode == "package":
		_read_manifest()
	else:
		_fail("[arguments] modo inválido: %s (use source ou package)" % mode)
	if not categories.is_empty():
		_validate_manifest_paths()
		_validate_catalog_contracts()
		_validate_raw_wav_loader()
		if mode == "package":
			_validate_exclusions()
	_write_report()
	var total_paths := 0
	for category in categories:
		total_paths += (categories[category] as Array).size()
	if failures.is_empty():
		print("EXPORT_VALIDATION|PASS|mode=%s|checks=%d|paths=%d" % [mode, checks, total_paths])
	else:
		print("EXPORT_VALIDATION|FAIL|mode=%s|checks=%d|failures=%d|paths=%d" % [mode, checks, failures.size(), total_paths])
		for failure in failures:
			print("EXPORT_VALIDATION|MISSING|" + failure)
	quit(0 if failures.is_empty() else 1)

func _parse_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--manifest="):
			manifest_path = argument.trim_prefix("--manifest=")
		elif argument.begins_with("--report="):
			report_path = argument.trim_prefix("--report=")

func _build_source_manifest() -> void:
	for path in JSON_PATHS:
		_add_path("runtime_json", path)
	for path in DYNAMIC_MODEL_PATHS:
		_add_path("region_and_interior_models", path)
	for path in EXTRA_DYNAMIC_RESOURCES:
		_add_path("other_dynamic_resources", path)
	for root_path in AUDIO_ROOTS:
		for path in _collect_files(root_path, AUDIO_EXTENSIONS):
			_add_path("dynamic_audio", path)
			if path.begins_with(RAW_WAV_PREFIX) and path.get_extension().to_lower() == "wav":
				raw_wav_paths.append(path)
	for root_path in REGION_RESOURCE_ROOTS:
		for path in _collect_files(root_path, RESOURCE_EXTENSIONS):
			var category := "fleet_scenes" if path.begins_with("res://assets/fleet/") and path.ends_with(".scn") else "region_and_interior_resources"
			_add_path(category, path)
	var fleet: Variant = _read_json("res://assets/fleet/catalog.json", "fleet catalog")
	if fleet is Dictionary and fleet.get("vehicles") is Dictionary:
		for id in fleet.vehicles:
			var definition: Variant = fleet.vehicles[id]
			if definition is Dictionary and definition.get("scene") is String:
				_add_path("fleet_scenes", definition.scene)
			else:
				_fail("[fleet] %s não possui scene válida" % id)
	var residents: Variant = _read_json("res://world/places/OriginalResidentData.json", "resident catalog")
	if residents is Array:
		for resident in residents:
			if resident is Dictionary and resident.get("model") is String:
				_add_path("resident_models", resident.model)
	var recordings: Variant = _read_json("res://audio/mission_voices/recordings.json", "voice manifest")
	if recordings is Dictionary:
		for key in recordings:
			if recordings[key] is String:
				_add_path("mission_voice_recordings", recordings[key])
	_sort_manifest()
	raw_wav_paths.sort()

func _collect_files(root_path: String, extensions: Array) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root_path)
	_check(directory != null, "[tree] diretório de produção ausente ou ilegível: " + root_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		if name.begins_with("."):
			name = directory.get_next()
			continue
		var path := root_path.path_join(name)
		if directory.current_is_dir():
			result.append_array(_collect_files(path, extensions))
		elif name.get_extension().to_lower() in extensions:
			result.append(path)
		name = directory.get_next()
	directory.list_dir_end()
	return result

func _write_manifest() -> void:
	var file := FileAccess.open(manifest_path, FileAccess.WRITE)
	if file == null:
		_fail("[manifest] não foi possível gravar %s (erro %s)" % [manifest_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({
		"manifest_version": MANIFEST_VERSION,
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"categories": categories,
		"raw_wav_paths": raw_wav_paths,
	}, "\t"))
	file.close()
	print("EXPORT_VALIDATION|MANIFEST|" + manifest_path)

func _read_manifest() -> void:
	if manifest_path.is_empty():
		_fail("[manifest] --manifest=<arquivo absoluto> é obrigatório no modo package")
		return
	var parsed: Variant = _read_json(manifest_path, "export manifest")
	if not parsed is Dictionary:
		return
	_check(int(parsed.get("manifest_version", -1)) == MANIFEST_VERSION, "[manifest] versão incompatível")
	if parsed.get("categories") is Dictionary:
		categories = parsed.categories
	else:
		_fail("[manifest] campo categories ausente ou inválido")
	if parsed.get("raw_wav_paths") is Array:
		for path in parsed.raw_wav_paths:
			raw_wav_paths.append(str(path))

func _validate_manifest_paths() -> void:
	for category in categories:
		var paths: Variant = categories[category]
		if not paths is Array:
			_fail("[manifest] categoria %s não é uma lista" % category)
			continue
		for value in paths:
			var path := str(value)
			if path.ends_with(".json"):
				_check(FileAccess.file_exists(path), "[%s] JSON ausente: %s" % [category, path])
			elif path.ends_with(".scn") or path.ends_with(".tscn"):
				_check(ResourceLoader.exists(path), "[%s] cena ausente: %s" % [category, path])
				if ResourceLoader.exists(path):
					_check(load(path) is PackedScene, "[%s] recurso não é PackedScene: %s" % [category, path])
			elif path.get_extension().to_lower() in AUDIO_EXTENSIONS:
				_check(ResourceLoader.exists(path), "[%s] áudio ausente: %s" % [category, path])
				if ResourceLoader.exists(path):
					_check(load(path) is AudioStream, "[%s] recurso não é AudioStream: %s" % [category, path])
			else:
				_check(ResourceLoader.exists(path), "[%s] recurso ausente: %s" % [category, path])

func _validate_catalog_contracts() -> void:
	var fleet: Variant = _read_json("res://assets/fleet/catalog.json", "fleet catalog")
	if not fleet is Dictionary or not fleet.get("vehicles") is Dictionary:
		_fail("[fleet] catálogo não contém vehicles")
		return
	var vehicles: Dictionary = fleet.vehicles
	_check(vehicles.size() > 0, "[fleet] catálogo está vazio")
	var paints: Variant = _read_json("res://runtime/VehiclePaintSources.json", "paint catalog")
	_check(paints is Dictionary, "[paint] catálogo não é um dicionário")
	for id in vehicles:
		var definition: Variant = vehicles[id]
		_check(definition is Dictionary, "[fleet] definição inválida: %s" % id)
		if definition is Dictionary:
			var scene := str(definition.get("scene", ""))
			_check(not scene.is_empty(), "[fleet] scene vazia: %s" % id)
			_check(scene in _category_paths("fleet_scenes"), "[fleet] scene fora do manifesto: %s -> %s" % [id, scene])
		if paints is Dictionary:
			_check(paints.has(id), "[paint] veículo sem entrada de pintura: %s" % id)
	var residents: Variant = _read_json("res://world/places/OriginalResidentData.json", "resident catalog")
	_check(residents is Array, "[residents] catálogo não é uma lista")
	if residents is Array:
		for index in residents.size():
			var resident: Variant = residents[index]
			_check(resident is Dictionary, "[residents] entrada %d inválida" % index)
			if resident is Dictionary:
				var model := str(resident.get("model", ""))
				_check(not model.is_empty(), "[residents] entrada %d sem model" % index)
				_check(model in _category_paths("resident_models"), "[residents] modelo fora do manifesto: %s" % model)
	var world_data: Variant = _read_json("res://world/regions/OriginalWorldData.json", "world data")
	_check(world_data is Dictionary, "[world] OriginalWorldData.json não é um dicionário")
	if world_data is Dictionary:
		for key in ["harbor_roads", "mountain_control_points", "harbor_buildings"]:
			_check(world_data.has(key), "[world] chave obrigatória ausente em OriginalWorldData.json: %s" % key)
	var lakes: Variant = _read_json("res://world/regions/OriginalLakeData.json", "lake data")
	_check(lakes is Dictionary and not lakes.is_empty(), "[lakes] OriginalLakeData.json vazio ou inválido")
	for path in ["res://data/campaign/campaign_v1.json", "res://data/campaign/first-favors-dialogue.json", "res://data/campaign/cobra-dialogue.json"]:
		_check(_read_json(path, path) is Dictionary, "[dialogue] JSON inválido: %s" % path)
	var recordings: Variant = _read_json("res://audio/mission_voices/recordings.json", "voice manifest")
	_check(recordings is Dictionary, "[voice] manifesto de vozes inválido")
	if recordings is Dictionary:
		for key in recordings:
			var path := str(recordings[key])
			_check(path in _category_paths("mission_voice_recordings"), "[voice] gravação fora do manifesto: %s" % path)

## Contrato de áudio: o WAV é consumido como recurso importado (`ResourceLoader`), nunca como arquivo bruto. Vale igual na
## árvore e no PCK. O arquivo bruto visível é só informativo: no editor existe, no PCK não, e nenhuma das duas situações reprova.
func _validate_raw_wav_loader() -> void:
	var loader: GDScript = load("res://audio/export_compat/ImportedAudioLoader.gd")
	var combat: GDScript = load("res://gameplay/CombatAudio.gd")
	_check(loader != null and combat != null, "[audio-loader] ImportedAudioLoader/CombatAudio não carregam")
	if loader == null or combat == null:
		return
	loader.clear()
	var raw_visible := 0
	var raw_fallbacks_before := 0
	for path in raw_wav_paths:
		if FileAccess.file_exists(path):
			raw_visible += 1
		_check(ResourceLoader.exists(path, "AudioStream"), "[audio-loader] recurso importado ausente: %s" % path)
		var wav: AudioStreamWAV = loader.wav(path)
		_check(wav != null, "[audio-loader] carregador não devolveu AudioStreamWAV: %s (%s)" % [path, loader.failures.get(path, "sem diagnóstico")])
		if wav == null:
			continue
		_check(wav.get_length() > 0.0, "[audio-loader] duração zero: %s" % path)
		_check(wav.mix_rate > 0 and wav.data.size() > 0, "[audio-loader] WAV sem dados/mix_rate: %s" % path)
		_check(loader.stream(path) == wav, "[audio-loader] cache não devolve a mesma instância: %s" % path)
		var copy: AudioStreamWAV = loader.fresh(path)
		_check(copy != null and copy != wav and is_equal_approx(copy.get_length(), wav.get_length()), "[audio-loader] cópia independente inválida: %s" % path)
	_check(loader.failures.is_empty(), "[audio-loader] falhas acumuladas: %s" % str(loader.failures))
	print("EXPORT_VALIDATION|INFO|audio wavs=%d raw_file_visible=%d raw_fallbacks=%d" % [raw_wav_paths.size(), raw_visible, loader.report().raw_fallbacks])
	# Consumidor produtivo real (`Gameplay` -> `CombatAudio.wav/reload_seconds`): não pode devolver nulo/zero em silêncio.
	for relative in ["reload/pistol_0.wav", "hurt_0.wav", "suppressed_smg_0.wav", "impact_metal_0.wav", "panic_0.wav"]:
		var produced: AudioStream = combat.wav(relative)
		_check(produced != null and produced.get_length() > 0.0, "[audio-loader] CombatAudio.wav(%s) sem áudio" % relative)
	_check(combat.reload_seconds("pistol") >= combat.MIN_RELOAD, "[audio-loader] reload_seconds(pistol) zerado: banco de recarga não carregou")
	# Duração de recarga (V1: take mais longo do banco, mínimo 0,5 s) idêntica pelos dois caminhos.
	for weapon in combat.RELOAD_WEAPONS:
		var longest := 0.0
		for index in combat.RELOAD_TAKES:
			longest = maxf(longest, loader.duration("res://assets/gameplay/audio/reload/%s_%d.wav" % [weapon, index]))
		var expected := maxf(combat.MIN_RELOAD, longest) if longest > 0.0 else 0.0
		_check(is_equal_approx(combat.reload_seconds(weapon), expected), "[audio-loader] reload_seconds(%s)=%f diverge do carregador (%f)" % [weapon, combat.reload_seconds(weapon), expected])

func _validate_exclusions() -> void:
	for path in [
		"res://tests/test_regions.gd",
		"res://tools/bake_vehicles.gd",
		"res://tools/export_validation/validate_dynamic_resources.gd",
		"res://evidence/controls-functional.json",
	]:
		_check(not ResourceLoader.exists(path) and not FileAccess.file_exists(path), "[exclusions] arquivo de desenvolvimento entrou no pacote: %s" % path)
	_check(not FileAccess.file_exists("res://docs/GLOBAL_MIGRATION_STATUS_2026-09-21.md"), "[exclusions] documentação entrou no pacote")

func _read_json(path: String, label: String) -> Variant:
	checks += 1
	if not FileAccess.file_exists(path):
		_fail("[%s] arquivo ausente: %s" % [label, path], false)
		return null
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		_fail("[%s] JSON inválido: %s" % [label, path], false)
	return parsed

func _category_paths(category: String) -> Array:
	var value: Variant = categories.get(category, [])
	return value if value is Array else []

func _add_path(category: String, path: String) -> void:
	if path.is_empty():
		return
	if not categories.has(category):
		categories[category] = []
	var paths: Array = categories[category]
	if path not in paths:
		paths.append(path)

func _sort_manifest() -> void:
	for category in categories:
		(categories[category] as Array).sort()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		_fail(message, false)

func _fail(message: String, count_check := true) -> void:
	if count_check:
		checks += 1
	failures.append(message)
	push_error(message)

func _write_report() -> void:
	if report_path.is_empty():
		return
	var counts := {}
	for category in categories:
		counts[category] = (categories[category] as Array).size()
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("[report] não foi possível gravar %s (erro %s)" % [report_path, FileAccess.get_open_error()])
		return
	file.store_string(JSON.stringify({
		"mode": mode,
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"checks": checks,
		"category_counts": counts,
		"failures": failures,
		"passed": failures.is_empty(),
	}, "\t"))
	file.close()
