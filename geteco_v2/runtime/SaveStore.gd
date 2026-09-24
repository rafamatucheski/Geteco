extends RefCounted
const STATE := preload("res://runtime/GameState.gd")
const PATH := "user://GetecoV2/progress.json"
const MAX_BYTES := 2097152
var path := PATH
var recovered_backup := false
var recovered_temp := false
static func read_valid(source: String) -> Dictionary:
	var file := FileAccess.open(source,FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES: return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return {}
	var probe = STATE.new()
	return parser.data if probe.restore_snapshot(parser.data) else {}
func load_into(state) -> Dictionary:
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
	var data: Dictionary = state.snapshot()
	if not STATE.new().restore_snapshot(data): return ERR_INVALID_DATA
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
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if not file: return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data,"\t"))
	file.flush()
	result = file.get_error()
	file.close()
	if result != OK: return result
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

func _preserve(source: String, label: String) -> Error:
	if not FileAccess.file_exists(source): return OK
	var destination := source+"."+label+"."+str(Time.get_ticks_usec())
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(source),ProjectSettings.globalize_path(destination))
