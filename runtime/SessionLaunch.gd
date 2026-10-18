extends Node
## Slot selection survives scene replacement; original progress stays separate.
const STORE = preload("res://runtime/SaveStore.gd")
const SLOT_IDS := ["slot_01", "slot_02", "slot_03", "slot_04", "slot_05"]
var selected_path: String = STORE.PATH
var direct_start_consumed := false
## Aviso para a sessão mostrar depois de carregar um slot recuperado; ela consome e limpa.
var recovery_notice := ""
## Planos de recuperação por slot, válidos enquanto as três cópias não mudarem no disco:
## a busca valida o save dezenas de vezes e o menu lista os slots mais de uma vez.
var _recovery_cache: Dictionary = {}
const RECOVERY_LABELS := {"@place": "local salvo", "@combat": "vida e procura", "services": "serviços",
	"robberies": "assaltos", "arrival": "chegada", "garage_rewards": "prêmios da garagem", "cold": "frio da serra",
	"mission_world": "guincho", "urban_operations": "porto e cemitério", "activities": "atividades",
	"vehicles": "carros", "rewards": "achados", "fishing": "pesca", "motocross": "motocross", "skate": "skate",
	"jessica": "Jessica", "digo": "Digo", "mountain_progression": "serra", "wine_cellar": "adega"}

static func recovery_names(dropped: Array) -> String:
	var names: Array[String] = []
	for key in dropped: names.append(str(RECOVERY_LABELS.get(str(key), str(key))))
	return ", ".join(names)

func _recovery_stamp(path: String) -> String:
	var parts: Array[String] = []
	for source in [path, path + ".bak", path + ".tmp"]:
		parts.append(str(FileAccess.get_modified_time(source)) if FileAccess.file_exists(source) else "-")
	return "|".join(parts)

func _recovery_plan(path: String) -> Dictionary:
	var stamp := _recovery_stamp(path)
	var cached: Dictionary = _recovery_cache.get(path, {})
	if cached.get("stamp", "") != stamp:
		cached = {"stamp": stamp, "plan": STORE.recovery_plan(path)}
		_recovery_cache[path] = cached
	return cached.plan

func _ready() -> void:
	# O editor de mundo abre o jogo com o documento ainda não salvo ("Jogar aqui").
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--edits="): continue
		var loaded: Dictionary = preload("res://world/editing/WorldEditData.gd").read_document(argument.trim_prefix("--edits="))
		if str(loaded.error).is_empty(): Engine.set_meta("geteco_world_edit_document",loaded.document)
		else: push_error("Editor de mundo: "+str(loaded.error))

func slot_path(id: String) -> String:
	if id == "progress": return STORE.PATH
	if id not in SLOT_IDS: return ""
	return "user://GetecoV2/saves/" + id + ".json"

func list_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in ["progress"] + SLOT_IDS:
		var path := slot_path(id)
		var data: Dictionary = STORE.read_valid(path)
		var backup := false
		var temporary := false
		if data.is_empty():
			data = STORE.read_valid(path + ".bak")
			backup = not data.is_empty()
		if data.is_empty():
			data = STORE.read_valid(path + ".tmp")
			temporary = not data.is_empty()
		var exists := FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") or FileAccess.file_exists(path + ".tmp")
		var reusable: bool = id != "progress" and data.is_empty() and FileAccess.file_exists(path+".tmp") and not FileAccess.file_exists(path) and not FileAccess.file_exists(path+".bak")
		var selected := path + (".tmp" if temporary else (".bak" if backup else ""))
		var recovery := {}
		if data.is_empty() and exists and not reusable:
			recovery = _recovery_plan(path)
			if not recovery.is_empty():
				data = recovery.data
				selected = str(recovery.source)
		var modified := FileAccess.get_modified_time(selected) if not data.is_empty() else 0
		var label := "Progresso anterior" if id == "progress" else "Slot " + str(SLOT_IDS.find(id) + 1)
		if not exists: label += " · Vazio"
		elif reusable: label += " · Salvamento incompleto — disponível para novo jogo"
		elif data.is_empty(): label += " · Incompatível ou incompleto — preservado"
		else:
			label += " · " + str(data.get("region_id", "Harbor")).capitalize()
			label += " · R$ %d" % int(data.get("economy", {}).get("balance", 0))
			label += "\n" + Time.get_datetime_string_from_unix_time(modified).replace("T", " ") + " UTC"
			if backup: label += " · Recuperar backup"
			if temporary: label += " · Recuperar temporário"
			if not recovery.is_empty(): label += String(TranslationServer.translate(" · Recuperável — volta ao padrão: %s")) % recovery_names(recovery.dropped)
		result.append({"id": id, "path": path, "valid": not data.is_empty(), "exists": exists, "backup":backup,
			"temporary":temporary,"reusable":reusable,"modified": modified, "label": label,
			"region": str(data.get("region_id", "harbor")), "recoverable": not recovery.is_empty(),
			"recovery_dropped": recovery.get("dropped", [])})
	return result

func latest_slot() -> Dictionary:
	var latest: Dictionary = {}
	for row in list_slots():
		# Continuar nunca recupera às cegas: o slot recuperável pede escolha no Carregar.
		if row.valid and not row.recoverable and (latest.is_empty() or row.modified > latest.modified): latest = row
	return latest

func prepare(id: String, new_game: bool) -> Error:
	for row in list_slots():
		if row.id != id: continue
		if new_game:
			if id == "progress" or (row.exists and not row.reusable): return ERR_ALREADY_EXISTS
			if row.reusable:
				var preserved := _preserve_orphan_temporary(row.path)
				if preserved != OK: return preserved
		if not new_game and not row.valid: return ERR_FILE_CORRUPT
		if not new_game and row.recoverable:
			var recovered := _publish_recovery(row.path)
			if recovered != OK: return recovered
		selected_path = row.path
		return OK
	return ERR_INVALID_PARAMETER

func _publish_recovery(path: String) -> Error:
	# Refaz o plano na hora da escolha: o disco pode ter mudado depois da listagem.
	_recovery_cache.erase(path)
	var plan := _recovery_plan(path)
	if plan.is_empty(): return ERR_FILE_CORRUPT
	var store = STORE.new()
	store.path = path
	var result: Error = store.publish_recovery(plan)
	_recovery_cache.erase(path)
	if result != OK: return result
	recovery_notice = String(TranslationServer.translate("Save recuperado. Voltaram ao padrão: %s. As cópias originais ficaram ao lado do arquivo (.pre-recovery).")) % recovery_names(plan.dropped)
	push_warning("Save recuperado em %s; blocos redefinidos: %s" % [path, plan.dropped])
	return OK

func _preserve_orphan_temporary(path: String) -> Error:
	# Recheck at selection time; listing never moves files. A recoverable save
	# or any primary/backup must not become a new-game destination.
	var temporary := path+".tmp"
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak") or not STORE.read_valid(temporary).is_empty(): return ERR_ALREADY_EXISTS
	var stem := temporary+".corrupt."+str(Time.get_ticks_usec())
	var destination := stem
	var suffix := 0
	while FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
		suffix += 1
		destination = stem+"."+str(suffix)
	return _archive_temporary(temporary,destination)

func _archive_temporary(source: String, destination: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(destination))

func prepare_import_destination(id: String) -> Error:
	# Import is intentionally split in two: this autoload reserves only an empty
	# V2 destination. A future adapter may then publish an in-memory schema-3
	# snapshot through SaveStore.publish_import_snapshot without touching V1.
	if id not in SLOT_IDS: return ERR_INVALID_PARAMETER
	for row in list_slots():
		if row.id != id: continue
		if row.exists: return ERR_ALREADY_EXISTS
		selected_path = row.path
		return OK
	return ERR_INVALID_PARAMETER
