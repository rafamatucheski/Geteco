extends RefCounted
## Fronteira de I/O da importação. A origem é somente leitura e a publicação
## usa exclusivamente o contrato atômico do SaveStore em um slot V2 vazio.

const CONVERTER := preload("res://migration/v1/V1SaveConverter.gd")
const STORE := preload("res://runtime/SaveStore.gd")

static func inspect(source_path: String) -> Dictionary:
	var failure := {"ok":false,"ready_for_publication":false,"proposal":{},"warnings":[],"unconverted_fields":[],"incompatibilities":[],"decisions_required":[],"read_error":OK}
	if source_path.is_empty() or not FileAccess.file_exists(source_path):
		failure.read_error = ERR_FILE_NOT_FOUND
		return failure
	var file := FileAccess.open(source_path,FileAccess.READ)
	if file == null:
		failure.read_error = FileAccess.get_open_error()
		return failure
	if file.get_length() > STORE.MAX_BYTES:
		file.close()
		failure.read_error = ERR_INVALID_DATA
		return failure
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK or not parser.data is Dictionary:
		failure.read_error = ERR_PARSE_ERROR
		return failure
	var result: Dictionary = CONVERTER.convert(parser.data)
	result["read_error"] = OK
	return result

static func publish(conversion: Dictionary, slot_id: String, launch: Node) -> Error:
	if conversion.get("ready_for_publication",false) != true or not conversion.get("proposal",{}) is Dictionary:
		return ERR_INVALID_DATA
	var error: Error = launch.prepare_import_destination(slot_id)
	if error != OK: return error
	var store := STORE.new()
	store.path = launch.selected_path
	return store.publish_import_snapshot(conversion.proposal)
