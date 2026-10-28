extends SceneTree
## Varredura dos caches de compilação depois de um quadro grande (StallLog, 28/10): monta um shader_cache e um
## cache de driver falsos em user:// com um arquivo velho e um novo e confere que só o novo entra no registro.

class Capture:
	extends RefCounted
	var lines: Array[String] = []
	func enqueue(line: String) -> void: lines.append(line)

var failures := 0

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		print("STALL_COMPILE_CACHE FAIL ", label)

func _initialize() -> void:
	var logger: Node = load("res://runtime/StallLog.gd").new()
	var capture := Capture.new()
	logger.set("_writer", capture)
	var now := int(Time.get_unix_time_from_system())
	# Raiz isolada: o shader_cache real do usuário é lido pelo jogo e não pode ganhar arquivo de teste.
	var root := ProjectSettings.globalize_path("user://tests/stall-compile-cache")
	var version := root.path_join("shader_cache/SceneForwardClusteredShaderRD/abcdef0123456789")
	var driver := root.path_join("driver/GLCache/x")
	DirAccess.make_dir_recursive_absolute(version)
	DirAccess.make_dir_recursive_absolute(driver)
	_touch(version.path_join("velho.vulkan.cache"), "a")
	_touch(version.path_join("novo.vulkan.cache"), "abcd")
	_touch(driver.path_join("cache.bin"), "xy")
	logger.set("_cache_root_override", root.path_join("shader_cache"))
	OS.set_environment("__GL_SHADER_DISK_CACHE_PATH", root.path_join("driver"))
	# O arquivo "velho" fica antes da janela: since = agora + 2 só deixa passar o que for gravado depois.
	OS.delay_msec(2100)
	_touch(version.path_join("novo.vulkan.cache"), "abcde")
	_touch(driver.path_join("cache.bin"), "xyz")
	logger.call("_finish_compile_scan", logger.call("_scan_compile_caches", {"slow_t": 12.5, "slow_frame": 99, "since": now + 2}))
	check(capture.lines.size() == 1, "um registro gravado")
	if capture.lines.size() == 1:
		var record: Dictionary = JSON.parse_string(capture.lines[0])
		print("STALL_COMPILE_CACHE ", capture.lines[0])
		check(str(record.get("type")) == "slow_compile_cache", "tipo do registro")
		var shaders: Array = record.get("godot_shaders", [])
		check(shaders.size() == 1, "só o shader novo entra")
		if shaders.size() == 1:
			check(str(shaders[0].file) == "novo" and str(shaders[0].shader) == "SceneForwardClusteredShaderRD", "nome do shader novo")
			check(int(shaders[0].bytes) == 5, "tamanho do shader novo")
		var drivers: Array = record.get("driver_files", [])
		check(drivers.size() == 1 and str(drivers[0].file) == "GLCache/x/cache.bin", "arquivo do driver com caminho relativo")
	# Caminho do jogo: tarefa de fundo, registro gravado depois na thread principal.
	_logger = logger
	_capture = capture
	logger.set("_cache_scan_running", true)
	WorkerThreadPool.add_task(logger.get("_scan_compile_caches_task").bind({"slow_t": 13.0, "slow_frame": 100, "since": now + 2}))

var _logger: Node
var _capture: Capture
var _waited := 0

func _process(_delta: float) -> bool:
	_waited += 1
	if _capture.lines.size() < 2 and _waited < 600: return false
	check(_capture.lines.size() == 2, "a tarefa de fundo grava o registro")
	check(not bool(_logger.get("_cache_scan_running")), "a tarefa de fundo libera a próxima varredura")
	if _capture.lines.size() == 2:
		var record: Dictionary = JSON.parse_string(_capture.lines[1])
		check(float(record.get("slow_t")) == 13.0 and (record.get("godot_shaders", []) as Array).size() == 1, "registro da tarefa de fundo")
	OS.set_environment("__GL_SHADER_DISK_CACHE_PATH", "")
	_logger.free()
	print("STALL_COMPILE_CACHE checks failures=%d" % failures)
	quit(1 if failures > 0 else 0)
	return true

func _touch(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
