@tool
extends RefCounted
## Preserve an incompatible draft before its autosave slot can be reused.
const DATA := preload("res://world/editing/WorldEditData.gd")

static func archive_path(path: String, digest: String) -> String:
	return path+".conflict-"+digest+".json"

static func protect(path: String, base_hash: String, edits_path: String, copier := Callable()) -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":true,"archive_path":"","source_hash":""}
	var original := FileAccess.get_file_as_bytes(path)
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(original)
	var digest := hashing.finish().hex_encode()
	var parsed: Variant = JSON.parse_string(original.get_string_from_utf8())
	var compatible: bool = parsed is Dictionary and parsed.get("base_hash","")==base_hash and parsed.get("edits_path",edits_path)==edits_path
	if compatible: compatible = DATA.validate_document(parsed.get("document")).is_empty()
	if compatible: return {"ok":true,"archive_path":"","source_hash":digest}
	var destination := archive_path(path,digest)
	if FileAccess.file_exists(destination):
		if FileAccess.get_sha256(destination)!=digest: return {"ok":false,"archive_path":destination,"error":"O arquivo de recuperação existente não confere com o SHA-256 do rascunho."}
		if FileAccess.get_sha256(path)!=digest: return {"ok":false,"archive_path":destination,"error":"O rascunho mudou durante a verificação."}
		return {"ok":true,"archive_path":destination,"existing":true,"source_hash":digest}
	var temporary := destination+".%d_%d.tmp" % [OS.get_process_id(),Time.get_ticks_usec()]
	var copied: int = copier.call(path,temporary) if copier.is_valid() else DirAccess.copy_absolute(path,temporary)
	if copied!=OK: return {"ok":false,"archive_path":destination,"error":"Não foi possível copiar o rascunho: "+error_string(copied)}
	if FileAccess.get_sha256(temporary)!=digest or FileAccess.get_sha256(path)!=digest:
		return {"ok":false,"archive_path":destination,"error":"A cópia do rascunho não passou na verificação SHA-256. Temporário: "+temporary}
	var moved := DirAccess.rename_absolute(temporary,destination)
	if moved!=OK: return {"ok":false,"archive_path":destination,"error":"Não foi possível publicar o arquivo de recuperação: "+error_string(moved)}
	if FileAccess.get_sha256(destination)!=digest: return {"ok":false,"archive_path":destination,"error":"O arquivo de recuperação publicado não confere com o SHA-256."}
	return {"ok":true,"archive_path":destination,"existing":false,"source_hash":digest}
