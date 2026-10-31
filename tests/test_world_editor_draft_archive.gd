extends SceneTree
const DATA := preload("res://world/editing/WorldEditData.gd")
const ARCHIVE := preload("res://addons/geteco_world_editor/WorldEditorDraftArchive.gd")
class EditorProbe:
	extends "res://addons/geteco_world_editor/WorldEditor.gd"
	var reports: Array[String] = []
	var copy_calls := 0
	var copy_error := false
	var corrupt_copy := false
	func _report(message: String, _level: String = "info") -> void: reports.append(message)
	func _copy_draft_archive(source: String, destination: String) -> int:
		copy_calls += 1
		if copy_error: return ERR_CANT_CREATE
		if corrupt_copy:
			var file := FileAccess.open(destination,FileAccess.WRITE)
			file.store_string("corrupt fixture")
			file.close()
			return OK
		return DirAccess.copy_absolute(source,destination)
var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func write(path: String, value: String) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(value)
	file.close()
func probe(world_path: String, slot: String) -> EditorProbe:
	var result := EditorProbe.new()
	result.edits_path = world_path
	result.draft_path = slot
	result.expected_hash = DATA.disk_hash(world_path)
	result.document = DATA.empty_document()
	result.saved_document = DATA.empty_document()
	return result
func run() -> void:
	# Toda gravação/cópia fica confinada a fixtures de teste únicas; nenhum rascunho real do usuário é lido.
	var official := DATA.disk_hash()
	var folder := "res://.godot/draft_archive_test_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(folder)
	var world_path := folder+"/world.json"
	var slot := folder+"/draft.json"
	write(world_path,JSON.stringify(DATA.empty_document()))
	var fixture_hash := DATA.disk_hash(world_path)
	var old := {"base_hash":"older-world-version","edits_path":world_path,"document":DATA.empty_document()}
	var old_row := DATA.new_entity("prop",Vector2(30,100))
	old.document.regions.harbor[old_row.id] = old_row
	var bytes := JSON.stringify(old,"  ")+"\n"
	write(slot,bytes)
	var old_hash := DATA.disk_hash(slot)
	var recovery_path := ARCHIVE.archive_path(slot,old_hash)
	var editor := probe(world_path,slot)
	editor._restore_draft()
	check(editor.document==DATA.empty_document() and FileAccess.get_file_as_string(slot)==bytes,"An incompatible draft is not applied or changed during discovery")
	var current_row := DATA.new_entity("prop",Vector2(50,110))
	editor.document.regions.harbor[current_row.id] = current_row
	check(editor._write_draft(),"The first new edit archives the incompatible draft before replacing its slot")
	check(FileAccess.file_exists(recovery_path) and DATA.disk_hash(recovery_path)==old_hash and FileAccess.get_file_as_string(recovery_path)==bytes,"Recovery copy preserves original bytes and verified SHA-256")
	check(editor.reports.any(func(message): return ProjectSettings.globalize_path(recovery_path) in message),"The recovery message includes the verified archive's absolute path")
	var next_session := probe(world_path,slot)
	next_session._restore_draft()
	check(next_session.restored_draft and next_session.document.regions.harbor.has(current_row.id),"The next session recovers the new draft normally")
	next_session.free()
	write(slot,bytes)
	editor.copy_calls = 0
	check(editor._write_draft() and editor.copy_calls==0,"An existing checksum-matched archive is reused without duplicate copies")
	check(DATA.disk_hash(recovery_path)==old_hash,"Reusing an archive preserves its original contents")
	write(slot,bytes)
	write(recovery_path,"tampered fixture")
	check(not editor._write_draft() and FileAccess.get_file_as_string(slot)==bytes,"A mismatched existing archive blocks overwrite of the old draft")
	check(editor.reports.back().contains(ProjectSettings.globalize_path(recovery_path)),"Checksum failures identify the recovery file that needs attention")
	var failed_slot := folder+"/failed-draft.json"
	write(failed_slot,bytes)
	var failing := probe(world_path,failed_slot)
	failing.copy_error = true
	check(not failing._write_draft() and FileAccess.get_file_as_string(failed_slot)==bytes,"Copy failure leaves the incompatible draft byte-for-byte intact")
	check(not FileAccess.file_exists(ARCHIVE.archive_path(failed_slot,old_hash)),"Copy failure never claims an archive exists")
	check(failing.reports.back().contains(ProjectSettings.globalize_path(failed_slot)),"Copy failure reports the untouched original draft path")
	failing.copy_error = false
	failing.corrupt_copy = true
	check(not failing._write_draft() and FileAccess.get_file_as_string(failed_slot)==bytes,"A corrupt copy fails SHA-256 verification and cannot overwrite the original")
	failing.free()
	editor.free()
	check(DATA.disk_hash(world_path)==fixture_hash and DATA.disk_hash()==official,"Draft recovery never changes either the fixture world or the user's official world")
	print("WORLD_EDITOR_DRAFT_ARCHIVE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
