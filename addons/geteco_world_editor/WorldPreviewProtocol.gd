@tool
extends RefCounted
## IPC files are replaced atomically. Windows readers can still see a temporary
## empty/incomplete read during replacement; treat that as pending, not a script error.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {"data":{},"error":""}
	var file := FileAccess.open(path,FileAccess.READ)
	if file == null: return {"data":{},"error":"Não foi possível ler "+path}
	var text := file.get_as_text()
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"data":{},"error":"JSON incompleto em %s (linha %d): %s" % [path,parser.get_error_line(),parser.get_error_message()]}
	if not parser.data is Dictionary: return {"data":{},"error":"Resposta inválida em "+path}
	return {"data":parser.data,"error":""}
