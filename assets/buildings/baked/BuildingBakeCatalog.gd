extends RefCounted
## Catálogo preguiçoso: não monta geometria nem lê todas as cenas no início da sessão.
const OUTPUT := "res://assets/buildings/baked"
const SOURCES := [
	"res://world/urban_detail/UrbanCommercialBuilding.gd",
	"res://world/urban_detail/UrbanBuildingBase.gd",
	"res://world/urban_detail/HarborV1BuildingProfile.gd",
	"res://assets/urban_detail/UrbanMaterials.gd",
	"res://assets/urban_detail/UrbanSurfaces.gd",
	"res://world/urban_detail/UrbanSignage.gd",
	"res://world/city_look/CityPropKit.gd",
	"res://world/urban_detail/HarborBuildingBatch.gd",
]
static var _manifest: Dictionary = {}
static var _loaded := false
static var _scenes: Dictionary = {}
static var _source_stamp := ""
static var _detail_script: Script
static var _detail_api_loaded := false
static var _detail_api_available := false

static func has_detail_api() -> bool:
	if not _detail_api_loaded:
		_detail_api_loaded = true
		_detail_script = load("res://world/city_look/CityPropKit.gd") as Script
		for method in _detail_script.get_script_method_list():
			if method.name == &"apply_detail_range": _detail_api_available = true
	return _detail_api_available

static func detail_enabled() -> bool:
	return bool(_detail_script.get("detail_range_enabled")) if has_detail_api() else false

static func set_detail_enabled(value: bool) -> void:
	if has_detail_api(): _detail_script.set("detail_range_enabled", value)

static func apply_detail_range(mesh: GeometryInstance3D) -> void:
	# P6 também precisa compilar antes da integração P5. A API é opcional,
	# resolvida como recurso Script, sem depender de uma constante nova na base.
	if has_detail_api(): _detail_script.call("apply_detail_range", mesh)

static func source_stamp() -> String:
	if _source_stamp.is_empty():
		var contents := ""
		for path in SOURCES:
			# Export com scripts binários não conserva a fonte .gd no pacote.
			if not FileAccess.file_exists(path): return ""
			contents += FileAccess.get_file_as_string(path)
		_source_stamp = contents.sha256_text()
	return _source_stamp

static func key(data: Dictionary) -> String:
	# Posição e rotação não mudam a malha local. Nome, semente e tamanho mudam.
	var values := [str(data.get("id", "")), str(data.get("kind", "office")),
		data.size, UrbanBuildingBase.resolved_height(data), int(data.get("variant_seed", 0)),
		Color(data.get("color", "b3955c")), bool(data.get("entrance_north", false)),
		str(data.get("name", "")), str(data.get("original_name", "")), data.has("original_name")]
	return var_to_str(values).sha256_text()

static func create(data: Dictionary) -> UrbanBuildingBase:
	if not _loaded:
		_loaded = true
		var path := OUTPUT + "/manifest.tres"
		if ResourceLoader.exists(path):
			var resource := load(path) as Resource
			if resource != null: _manifest = resource.get_meta("building_manifest", {})
	# Evita esconder mudanças posteriores de outra tarefa em uma cena antiga.
	var stamp := source_stamp()
	if not stamp.is_empty() and _manifest.get("source_stamp", "") != stamp: return null
	var entry: Dictionary = _manifest.get("variants", {}).get(key(data), {})
	var path := str(entry.get("scene", ""))
	if path.is_empty() or not ResourceLoader.exists(path): return null
	if not _scenes.has(path): _scenes[path] = load(path) as PackedScene
	var packed: PackedScene = _scenes[path]
	return packed.instantiate() as UrbanBuildingBase if packed != null else null
