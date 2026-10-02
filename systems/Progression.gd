extends RefCounted

## Data only: no scene references, autoloads or per-frame processing.
const Sequence := preload("res://data/GarageSequence.gd")
const VERSION := 1
const DEFAULT_SAVE := "user://GetecoV2/progress.json"
const LOCATIONS := ["harbor_street", "harbor_garage"]
const WEAPONS := ["pistol", "shotgun", "rifle", "grenade", "knife"]
const PART := "garage_part"
const MAX_BYTES := 65536

var _state: Dictionary = _initial_state()
var location_id: String:
	get: return _state.location_id
var stage: String:
	get: return _state.phase
var part_available: bool:
	get: return _state.phase == "collect_part"

static func _initial_state() -> Dictionary:
	return {"schema_version": VERSION, "game": "geteco_v2", "mission_id": Sequence.ID,
		"phase": "meet_maciota", "location_id": "harbor_street", "inventory": {},
		"equipped_weapon": "", "completed_missions": []}

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func objective() -> String:
	return Sequence.OBJECTIVES[_state.phase]

func set_location(p_location_id: String) -> bool:
	if not LOCATIONS.has(p_location_id):
		return false
	_state.location_id = p_location_id
	if p_location_id == "harbor_garage":
		_state.equipped_weapon = ""
	return true

func weapons_allowed() -> bool:
	return _state.location_id != "harbor_garage"

func equip_weapon(weapon_id: String) -> bool:
	if not weapons_allowed():
		return false
	if weapon_id != "" and (not WEAPONS.has(weapon_id) or int(_state.inventory.get(weapon_id, 0)) < 1):
		return false
	_state.equipped_weapon = weapon_id
	return true

func can_attack() -> bool:
	# Future melee, firearm and explosive consumers must all check this gate.
	return weapons_allowed()

func interact(target_id: String) -> Dictionary:
	if _state.location_id != "harbor_garage":
		return _reply(false, "", "", false)
	var phase: String = _state.phase
	match target_id:
		"maciota":
			if phase == "meet_maciota":
				_state.phase = "talk_mechanic"
				return _reply(true, Sequence.GREETING + "\n\n" + Sequence.REQUEST, "Maciota", true)
			if phase == "return_maciota":
				_state.inventory.erase(PART)
				_state.phase = "complete"
				_state.completed_missions.append(Sequence.ID)
				return _reply(true, Sequence.THANKS, "Maciota", true)
			return _reply(true, Sequence.THANKS if phase == "complete" else Sequence.REQUEST, "Maciota", false)
		"mechanic":
			if phase == "meet_maciota":
				return _reply(true, "Fala primeiro com o Maciota.", "Mecânico", false)
			if phase == "talk_mechanic":
				_state.phase = "collect_part"
				return _reply(true, Sequence.MECHANIC_REQUEST, "Mecânico", true)
			return _reply(true, "Pode levar a peça." if phase == "collect_part" else "Tudo certo por aqui.", "Mecânico", false)
		"workbench":
			if phase != "collect_part":
				return _reply(false, "", "", false)
			_state.inventory[PART] = 1
			_state.phase = "return_maciota"
			return _reply(true, "Peça coletada.", "", true)
	return _reply(false, "", "", false)

func _reply(ok: bool, message: String, speaker: String, changed: bool) -> Dictionary:
	return {"ok": ok, "message": message, "speaker": speaker, "changed": changed}

static func validate_snapshot(data: Dictionary) -> bool:
	for key in ["schema_version", "game", "mission_id", "phase", "location_id", "inventory", "equipped_weapon", "completed_missions"]:
		if not data.has(key):
			return false
	if not _is_integer(data.schema_version) or int(data.schema_version) != VERSION:
		return false
	if data.game != "geteco_v2" or data.mission_id != Sequence.ID:
		return false
	if not data.phase is String or not Sequence.PHASES.has(data.phase):
		return false
	if not data.location_id is String or not LOCATIONS.has(data.location_id):
		return false
	if not data.inventory is Dictionary or not data.equipped_weapon is String or not data.completed_missions is Array:
		return false
	for item in data.inventory:
		if not item is String or (item != PART and not WEAPONS.has(item)):
			return false
		var count: Variant = data.inventory[item]
		if not _is_integer(count) or float(count) < 1 or float(count) > 999:
			return false
	if data.equipped_weapon != "" and (not WEAPONS.has(data.equipped_weapon) or not data.inventory.has(data.equipped_weapon)):
		return false
	var carrying_part: bool = data.inventory.has(PART)
	if carrying_part != (data.phase == "return_maciota"):
		return false
	if carrying_part and int(data.inventory[PART]) != 1:
		return false
	if data.phase == "complete":
		return data.completed_missions == [Sequence.ID]
	return data.completed_missions.is_empty()

static func _is_integer(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	return is_finite(float(value)) and float(value) == floorf(float(value))

func restore_snapshot(data: Dictionary) -> bool:
	if not validate_snapshot(data):
		return false
	_state = data.duplicate(true)
	# JSON numbers are floats; normalize to stable runtime/schema integers.
	_state.schema_version = VERSION
	for item in _state.inventory:
		_state.inventory[item] = int(_state.inventory[item])
	# Never trust a saved weapon restriction flag. Derive it from location.
	set_location(_state.location_id)
	return true

static func _read_valid(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {}
	var parsed: Variant = parser.data
	if not parsed is Dictionary:
		return {}
	return parsed if validate_snapshot(parsed) else {}

func load_game(path: String = DEFAULT_SAVE) -> Dictionary:
	var data := _read_valid(path)
	if not data.is_empty():
		restore_snapshot(data)
		return {"ok": true, "status": "loaded"}
	var backup := _read_valid(path + ".bak")
	if not backup.is_empty():
		restore_snapshot(backup)
		return {"ok": true, "status": "recovered_backup"}
	return {"ok": false, "status": "invalid" if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak") else "missing"}

func save_game(path: String = DEFAULT_SAVE) -> Error:
	if not validate_snapshot(_state):
		return ERR_INVALID_DATA
	var directory := ProjectSettings.globalize_path(path.get_base_dir())
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return error
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(snapshot(), "\t"))
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK:
		return error
	if _read_valid(temporary).is_empty():
		return ERR_FILE_CORRUPT
	var absolute := ProjectSettings.globalize_path(path)
	var backup := absolute + ".bak"
	# Rotate only validated old data; a corrupt primary cannot poison a backup.
	if FileAccess.file_exists(path):
		if not _read_valid(path).is_empty():
			if FileAccess.file_exists(backup):
				error = DirAccess.remove_absolute(backup)
				if error != OK:
					return error
			error = DirAccess.rename_absolute(absolute, backup)
		else:
			error = DirAccess.remove_absolute(absolute)
		if error != OK:
			return error
	# Same-directory rename publishes the complete file. Interruption after
	# rotation recovers the valid backup; partial temporary files are ignored.
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), absolute)
