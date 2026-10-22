extends RefCounted
const STATE := preload("res://runtime/GameState.gd")
const STALL_WORK := preload("res://runtime/StallWorkTrace.gd")
const PATH := "user://GetecoV2/progress.json"
const MAX_BYTES := 2097152
var path := PATH
var recovered_backup := false
var recovered_temp := false
## Verificação por bytes (21/10): cada gravação validava o estado na memória e depois relia,
## interpretava e validava o temporário, o principal e o backup (GameState.restore_snapshot 4 vezes e
## JSON 3 vezes por save). Release, bancada --benchmark-save, preset Média: 22,8 ms por salvamento
## automático (p50, 15 chamadas); na partida de 21/10 (binário do editor) 32–36 ms, até 4 no mesmo quadro.
## Agora:
##  - o JSON exato é interpretado e validado UMA vez na memória, antes de tocar em arquivo: é o mesmo
##    teste que read_valid(temp) fazia depois (o que será carregado) e cobre a validação do dicionário;
##  - o temporário é conferido byte a byte pelo MESMO handle da escrita. Reabrir um arquivo recém-gravado
##    é o que custava (6,4 ms no release; 17 ms medidos em Python): o antivírus examina o arquivo na
##    primeira abertura de dados depois da escrita; a data de modificação vem de stat e não abre o arquivo;
##  - principal e backup que esta store gravou e não mudaram desde então (mesma data de modificação E
##    mesmo tamanho; os dois vêm de stat, 0,3 ms cada, sem disparar o exame) valem sem reabrir; mudou por
##    fora, primeiro save da sessão ou depois de qualquer load_into(): read_valid() como antes.
##    A data tem resolução de 1 s: o tamanho cobre a corrupção típica (gravação interrompida, truncada).
## GETECO_SAVE_VERIFY=0 volta ao caminho antigo para A/B no mesmo export.
var _primary_mark := PackedInt64Array()
var _backup_mark := PackedInt64Array()
static func _mark(source: String) -> PackedInt64Array:
	var mtime := int(FileAccess.get_modified_time(source))
	var size := int(FileAccess.get_size(source))
	return PackedInt64Array([mtime, size]) if mtime > 0 and size > 0 else PackedInt64Array()
static func byte_verify_enabled() -> bool:
	return OS.get_environment("GETECO_SAVE_VERIFY") != "0"
## Mesmo critério de read_valid(), sobre o buffer em memória.
static func bytes_valid(encoded: PackedByteArray) -> bool:
	if encoded.size() > MAX_BYTES: return false
	var parser := JSON.new()
	if parser.parse(encoded.get_string_from_utf8()) != OK or not parser.data is Dictionary: return false
	return STATE.new().restore_snapshot(parser.data)
## Arquivo que esta store gravou e conferiu, intocado desde então (stat, sem abrir), ou válido por read_valid().
static func _still_valid(source: String, mark: PackedInt64Array) -> bool:
	if not mark.is_empty() and _mark(source) == mark: return true
	return not read_valid(source).is_empty()
static func read_valid(source: String) -> Dictionary:
	var file := FileAccess.open(source,FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return {}
	var probe = STATE.new()
	return parser.data if probe.restore_snapshot(parser.data) else {}
func load_into(state) -> Dictionary:
	# Quem recarrega pode ter mexido nos arquivos (recuperação, teste): o próximo save confere de novo.
	_primary_mark = PackedInt64Array()
	_backup_mark = PackedInt64Array()
	for candidate in [{"path":path,"source":"primary"},{"path":path+".bak","source":"backup"},{"path":path+".tmp","source":"temporary"}]:
		var data := read_valid(candidate.path)
		if not data.is_empty():
			if not state.restore_snapshot(data): continue
			recovered_backup = candidate.source == "backup"
			recovered_temp = candidate.source == "temporary"
			return {"ok":true,"recovered":candidate.source != "primary","source":candidate.source,
				"migrated":int(data.schema_version) < STATE.SCHEMA_VERSION}
	return {"ok":false,"invalid":FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak") or FileAccess.file_exists(path+".tmp")}
func save(state) -> Error:
	var by_bytes := byte_verify_enabled()
	var trace := STALL_WORK.begin()
	var data: Dictionary = state.snapshot()
	STALL_WORK.finish("save.snapshot", trace)
	var accepted := true
	if not by_bytes:
		trace = STALL_WORK.begin()
		accepted = STATE.new().restore_snapshot(data)
		STALL_WORK.finish("save.validate", trace)
		if not accepted: return ERR_INVALID_DATA
	# Check the exact UTF-8 payload before changing recovery files or creating a
	# temporary that read_valid() could never accept. Reuse these same bytes.
	trace = STALL_WORK.begin()
	var encoded := JSON.stringify(data,"\t").to_utf8_buffer()
	STALL_WORK.finish("save.encode", trace)
	if encoded.size() > MAX_BYTES: return ERR_INVALID_DATA
	if by_bytes:
		trace = STALL_WORK.begin()
		accepted = bytes_valid(encoded)
		STALL_WORK.finish("save.validate_bytes", trace)
		if not accepted: return ERR_INVALID_DATA
	var result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if result != OK: return result
	var temp := path+".tmp"
	if recovered_temp:
		result = _promote_recovered_temp()
		if result != OK: return result
	elif FileAccess.file_exists(temp):
		# Inspect before replacing an abandoned temporary. Invalid content is
		# preserved for diagnosis instead of being silently truncated.
		var suffix := "preserved" if not read_valid(temp).is_empty() else "corrupt"
		result = _preserve(temp,suffix)
		if result != OK: return result
	var file := FileAccess.open(temp,FileAccess.WRITE_READ if by_bytes else FileAccess.WRITE)
	if not file: return FileAccess.get_open_error()
	trace = STALL_WORK.begin()
	file.store_buffer(encoded)
	file.flush()
	result = file.get_error()
	STALL_WORK.finish("save.write", trace)
	var written := true
	if by_bytes and result == OK:
		# Conferência pelo mesmo handle (comentário no topo): sem reabrir o arquivo recém-gravado.
		trace = STALL_WORK.begin()
		file.seek(0)
		written = file.get_length() == encoded.size() and file.get_buffer(encoded.size()) == encoded
		STALL_WORK.finish("save.verify_temp", trace)
	file.close()
	if result != OK: return result
	if by_bytes: return _commit_by_bytes(temp) if written else ERR_FILE_CORRUPT
	if read_valid(temp).is_empty(): return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if read_valid(path).is_empty():
			if not recovered_backup or read_valid(path+".bak").is_empty(): return ERR_FILE_CORRUPT
			var preserved := path+".corrupt."+str(Time.get_ticks_usec())
			result = DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(preserved))
			if result != OK: return result
		else:
			if FileAccess.file_exists(path+".bak"):
				# A malformed backup is evidence, not disposable scratch data.
				if read_valid(path+".bak").is_empty(): result = _preserve(path+".bak","corrupt")
				else: result = DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
				if result != OK: return result
			result = DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(path+".bak"))
			if result != OK: return result
	result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
	if result == OK:
		recovered_backup = false
		recovered_temp = false
	return result

## Final de save() com a verificação por bytes (comentário no topo). Mesma ordem de renomeações e
## mesmos códigos de erro do caminho antigo; só muda como temporário, principal e backup são conferidos.
func _commit_by_bytes(temp: String) -> Error:
	var primary_mark := _primary_mark
	var backup_mark := _backup_mark
	# Até a última renomeação dar certo, nenhuma marca vale: o próximo save reinterpreta os arquivos.
	_primary_mark = PackedInt64Array()
	_backup_mark = PackedInt64Array()
	var result := OK
	var backup_after := PackedInt64Array()
	var trace := STALL_WORK.begin()
	if FileAccess.file_exists(path):
		var primary_ok := _still_valid(path, primary_mark)
		STALL_WORK.finish("save.verify_primary", trace)
		if not primary_ok:
			if not recovered_backup or not _still_valid(path+".bak", backup_mark): return ERR_FILE_CORRUPT
			var preserved := path+".corrupt."+str(Time.get_ticks_usec())
			result = DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(preserved))
			if result != OK: return result
			backup_after = _mark(path+".bak")
		else:
			if FileAccess.file_exists(path+".bak"):
				# A malformed backup is evidence, not disposable scratch data.
				trace = STALL_WORK.begin()
				var backup_ok := _still_valid(path+".bak", backup_mark)
				STALL_WORK.finish("save.verify_backup", trace)
				if not backup_ok: result = _preserve(path+".bak","corrupt")
				else: result = DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".bak"))
				if result != OK: return result
			result = DirAccess.rename_absolute(ProjectSettings.globalize_path(path),ProjectSettings.globalize_path(path+".bak"))
			if result != OK: return result
			# O principal conferido virou o backup (renomear mantém data e tamanho).
			backup_after = _mark(path+".bak")
	trace = STALL_WORK.begin()
	result = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
	STALL_WORK.finish("save.rotate", trace)
	if result == OK:
		recovered_backup = false
		recovered_temp = false
		_primary_mark = _mark(path)
		_backup_mark = backup_after
	return result

func publish_import_snapshot(data: Dictionary) -> Error:
	# Publication boundary for a future V1 converter. The caller supplies an
	# in-memory V2 snapshot; this method never opens, renames or deletes a V1 file.
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak") or FileAccess.file_exists(path+".tmp"):
		return ERR_ALREADY_EXISTS
	var staged = STATE.new()
	if not staged.restore_snapshot(data): return ERR_INVALID_DATA
	recovered_backup = false
	recovered_temp = false
	return save(staged)

func _promote_recovered_temp() -> Error:
	var temp := path+".tmp"
	if read_valid(temp).is_empty(): return ERR_FILE_CORRUPT
	if FileAccess.file_exists(path):
		if not read_valid(path).is_empty(): return ERR_ALREADY_EXISTS
		var preserve_result := _preserve(path,"corrupt")
		if preserve_result != OK: return preserve_result
	var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
	if result == OK: recovered_temp = false
	return result

# --- Recuperação ---------------------------------------------------------------------------
# Um validador novo ou mais rígido (ou um bloco corrompido) fazia GameState recusar o arquivo
# inteiro, e o slot ficava "Incompatível ou incompleto" para sempre (revisão cruzada de
# 18/10/2026). A recuperação procura o menor conjunto de blocos opcionais que, voltando ao
# estado de um save antigo (sem a chave), torna o arquivo válido outra vez. Carteira,
# campanha e abertura nunca são descartadas: sem elas não há recuperação. Só o menu aplica o
# plano, com o que será redefinido escrito no slot; as cópias originais ficam ao lado.
const RECOVERY_LOCATION := "@place"
const RECOVERY_COMBAT := "@combat"
## Blocos caros de perder ficam por último na busca cumulativa.
const RECOVERY_LAST := ["rewards", "vehicles"]

static func _accepts(data: Dictionary) -> bool:
	return STATE.new().restore_snapshot(data)

static func _without(data: Dictionary, dropped: Array) -> Dictionary:
	var result := data.duplicate(true)
	for key in dropped:
		match str(key):
			RECOVERY_LOCATION: result.place_id = ""
			RECOVERY_COMBAT: result.combat = {}
			_: result.world.erase(key)
	return result

## {"data": snapshot válido, "dropped": [chaves]} ou {} quando nada salva o arquivo.
## "dropped" vazio quer dizer que o arquivo já era válido.
static func recover_snapshot(data: Dictionary) -> Dictionary:
	if data.get("game") != "geteco_v2" or not data.get("world") is Dictionary: return {}
	if _accepts(data): return {"data": data, "dropped": []}
	var trace := STALL_WORK.begin()
	var candidates: Array = [RECOVERY_LOCATION, RECOVERY_COMBAT]
	var keys: Array = data.world.keys().map(func(key): return str(key))
	keys.sort()
	for key in keys:
		if key not in RECOVERY_LAST: candidates.append(key)
	for key in RECOVERY_LAST:
		if key in keys: candidates.append(key)
	var plan := {}
	# Um bloco só é o caso comum: um sistema mudou de formato ou ficou corrompido.
	for key in candidates:
		var trial := _without(data, [key])
		if _accepts(trial):
			plan = {"data": trial, "dropped": [key]}
			break
	if plan.is_empty():
		var dropped: Array = []
		var trial := data
		var accepted := false
		for key in candidates:
			dropped.append(key)
			trial = _without(data, dropped)
			if _accepts(trial):
				accepted = true
				break
		if accepted:
			# Devolve o que não precisava sair.
			for key in dropped.duplicate():
				if dropped.size() <= 1: break
				var fewer: Array = dropped.filter(func(other): return other != key)
				var attempt := _without(data, fewer)
				if _accepts(attempt):
					dropped = fewer
					trial = attempt
			plan = {"data": trial, "dropped": dropped}
	STALL_WORK.finish_slow("save.recover_snapshot", trace, 2000)
	return plan

static func _read_json(source: String) -> Dictionary:
	var file := FileAccess.open(source, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return {}
	return parser.data

## Plano para um slot sem nenhuma cópia válida: usa a primeira cópia ainda legível
## (principal, backup, temporário) que a recuperação consegue salvar.
static func recovery_plan(slot: String) -> Dictionary:
	for source in [slot, slot + ".bak", slot + ".tmp"]:
		var data := _read_json(source)
		if data.is_empty(): continue
		var plan := recover_snapshot(data)
		if plan.is_empty() or plan.dropped.is_empty(): continue
		plan.source = source
		return plan
	return {}

## Publica o snapshot recuperado como save principal do slot. Nada é apagado: as cópias
## antigas viram `<arquivo>.pre-recovery.<ticks>` ao lado e voltam ao lugar se a gravação falhar.
func publish_recovery(plan: Dictionary) -> Error:
	if not plan.get("data") is Dictionary: return ERR_INVALID_DATA
	var staged = STATE.new()
	if not staged.restore_snapshot(plan.data): return ERR_INVALID_DATA
	var stamp := str(Time.get_ticks_usec())
	var moved: Array[String] = []
	var result: Error = OK
	for source in [path, path + ".bak", path + ".tmp"]:
		if not FileAccess.file_exists(source): continue
		result = DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(source + ".pre-recovery." + stamp))
		if result != OK: break
		moved.append(source)
	if result == OK:
		recovered_backup = false
		recovered_temp = false
		result = save(staged)
	if result != OK:
		for source in moved:
			if FileAccess.file_exists(source): continue
			DirAccess.rename_absolute(ProjectSettings.globalize_path(source + ".pre-recovery." + stamp), ProjectSettings.globalize_path(source))
	return result

func _preserve(source: String, label: String) -> Error:
	if not FileAccess.file_exists(source): return OK
	var destination := source+"."+label+"."+str(Time.get_ticks_usec())
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(destination))
