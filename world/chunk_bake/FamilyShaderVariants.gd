extends RefCounted
## Variantes de shader dos materiais "família" da fusão por trecho (ChunkCellMerge). Cada combinação nova de
## opções do StandardMaterial3D (cor no vértice, normal, triplanar...) compila um shader no primeiro desenho:
## com cache frio a travessia porto -> serra teve 9 quadros acima de 250 ms e pico de 1,3 s, contra nenhum sem
## a fusão (benchmark de 15/10). O que define a variante são só as opções inteiras/booleanas, não as cores.
##
## A lista que vai no jogo (data/family_shader_variants.json) é gerada montando todos os trechos com
## tests/measure/collect_family_variants.gd; variante nova vista em jogo vai para user:// e é aquecida da
## próxima vez. FamilyVariantPrewarm desenha todas atrás da cortina de carregamento.
const SHIPPED_PATH := "res://data/family_shader_variants.json"
const USER_PATH := "user://family_shader_variants.json"
## Não mudam o código do shader.
const SKIP := ["render_priority", "resource_local_to_scene", "resource_name", "resource_path", "resource_scene_unique_id", "script"]
static var seen := {}
static var _known_loaded := false
static var _known := {}

static func variant_of(material: StandardMaterial3D) -> Dictionary:
	var result := {}
	for property in material.get_property_list():
		if not (int(property.usage) & PROPERTY_USAGE_STORAGE) or String(property.name) in SKIP: continue
		if int(property.type) == TYPE_BOOL or int(property.type) == TYPE_INT: result[String(property.name)] = material.get(property.name)
	return result

static func key_of(variant: Dictionary) -> String:
	var names := variant.keys()
	names.sort()
	var parts := PackedStringArray()
	for name in names: parts.append("%s=%s" % [name, variant[name]])
	return "|".join(parts).sha256_text()

## Chamado quando a fusão cria um material família. Variante que não estava na lista vai para user://.
static func note(material: StandardMaterial3D) -> void:
	var variant := variant_of(material)
	var key := key_of(variant)
	if seen.has(key): return
	seen[key] = variant
	_load_known()
	if _known.has(key): return
	_known[key] = variant
	if Engine.is_editor_hint() or OS.has_feature("editor"): return
	var file := FileAccess.open(USER_PATH, FileAccess.WRITE)
	if file == null: return
	var user_only := {}
	var shipped := _read(SHIPPED_PATH)
	for item in _known: if not shipped.has(item): user_only[item] = _known[item]
	file.store_string(JSON.stringify(user_only))

static func known() -> Dictionary:
	_load_known()
	return _known

static func build(variant: Dictionary) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	for name in variant: material.set(name, variant[name])
	return material

static func _load_known() -> void:
	if _known_loaded: return
	_known_loaded = true
	_known = _read(SHIPPED_PATH)
	var extra := _read(USER_PATH)
	for key in extra: _known[key] = extra[key]

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary: return {}
	# JSON devolve números como float: as opções inteiras voltam a ser int.
	var result := {}
	for key in parsed:
		var variant := {}
		for name in parsed[key]:
			var value: Variant = parsed[key][name]
			variant[name] = int(value) if value is float else value
		result[key] = variant
	return result
