extends SceneTree
const WRITER := preload("res://runtime/StallLogWriter.gd")

class BlockedWriter extends "res://runtime/StallLogWriter.gd":
	var entered := Semaphore.new()
	var release := Semaphore.new()
	var blocked_once := false
	func _store_batch(lines: Array[String]) -> void:
		if not blocked_once:
			blocked_once = true
			entered.post()
			release.wait()
		super._store_batch(lines)

var failures := 0
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	var path := "res://evidence/stall-logs/writer-test-%d-%d.log" % [OS.get_process_id(), Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var writer := BlockedWriter.new()
	check(writer.start(path) == OK, "arquivo de evidência abre")
	writer.enqueue("first")
	writer.entered.wait()
	# Disco deliberadamente bloqueado na thread: produtor precisa continuar.
	var began := Time.get_ticks_usec()
	for i in WRITER.MAX_PENDING: writer.enqueue("record-%d" % i)
	check(Time.get_ticks_usec()-began < 100000, "produtor avança enquanto escrita está bloqueada")
	check(not writer.enqueue("overflow"), "fila tem limite sem bloquear produtor")
	check(writer.stats().dropped_records == 1, "perda é explícita")
	writer.release.post()
	writer.stop()
	var file := FileAccess.open(path, FileAccess.READ)
	var lines := file.get_as_text().strip_edges().split("\n")
	file.close()
	check(lines.size() == WRITER.MAX_PENDING+2, "encerramento drena fila e aviso de perda")
	check(lines[0] == "first" and lines[1] == "record-0" and lines[WRITER.MAX_PENDING] == "record-%d" % (WRITER.MAX_PENDING-1), "ordem preservada inclusive último registro")
	check(JSON.parse_string(lines[-1]).type == "writer_dropped", "perda registrada no arquivo")
	writer.stop()
	check(not writer.enqueue("after-stop"), "encerramento repetido é seguro e recusa novas linhas")
	print("STALL_LOG_WRITER checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
