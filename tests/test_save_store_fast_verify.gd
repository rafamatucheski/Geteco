extends SceneTree
## Contrato da verificação por bytes do SaveStore (21/10/2026): o caminho rápido (padrão) e o antigo
## (GETECO_SAVE_VERIFY=0) deixam os MESMOS arquivos e devolvem os MESMOS resultados em gravação normal,
## principal corrompido por fora, backup corrompido e recuperação pelo backup. Sem Main nem tempos.
const STATE := preload("res://runtime/GameState.gd")
const STORE := preload("res://runtime/SaveStore.gd")
var checks := 0
var failures: Array[String] = []
var save_root := ""

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func _balance(file_path: String) -> int:
	var data := STORE.read_valid(file_path)
	return int(data.economy.get("balance", -1)) if not data.is_empty() and data.get("economy") is Dictionary else -1

func _names(folder: String) -> Array:
	var names: Array = []
	for name_value in DirAccess.get_files_at(folder):
		# Sufixos de preservação levam o relógio: compara só o tipo do arquivo.
		var parts: PackedStringArray = name_value.split(".")
		while parts.size() > 2 and parts[-1].is_valid_int(): parts.remove_at(parts.size() - 1)
		names.append(".".join(parts))
	names.sort()
	return names

func _garbage(file_path: String) -> void:
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string("{ interrupted")
	file.close()

## Uma sequência inteira num modo; devolve o que um observador de fora veria.
func _scenario(mode: String) -> Dictionary:
	OS.set_environment("GETECO_SAVE_VERIFY", "0" if mode == "old" else "1")
	var folder := save_root + "/" + mode
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var store = STORE.new()
	store.path = folder + "/progress.json"
	var state = STATE.new()
	var out := {}
	state.economy.grant_reward("first", 20)
	out.first = store.save(state)
	state.economy.grant_reward("second", 30)
	out.second = store.save(state)
	state.economy.grant_reward("third", 40)
	out.third = store.save(state)
	out.balances_after_saves = [_balance(store.path), _balance(store.path + ".bak")]
	out.files_after_saves = _names(folder)
	# Principal estragado por fora logo depois de salvar (mesmo segundo): o save seguinte recusa.
	_garbage(store.path)
	state.economy.grant_reward("fourth", 50)
	out.after_primary_garbage = store.save(state)
	out.files_after_primary_garbage = _names(folder)
	out.backup_after_primary_garbage = _balance(store.path + ".bak")
	# Recupera pelo backup e volta a salvar, preservando a evidência do principal estragado.
	var loaded = STATE.new()
	var recovered: Dictionary = store.load_into(loaded)
	out.recovered = [recovered.get("ok", false), recovered.get("source", "")]
	loaded.economy.grant_reward("fifth", 60)
	out.after_recovery = store.save(loaded)
	out.balances_after_recovery = [_balance(store.path), _balance(store.path + ".bak")]
	out.files_after_recovery = _names(folder)
	# Backup estragado por fora: vira evidência ".corrupt" e o save segue.
	_garbage(store.path + ".bak")
	loaded.economy.grant_reward("sixth", 70)
	out.after_backup_garbage = store.save(loaded)
	out.balances_after_backup_garbage = [_balance(store.path), _balance(store.path + ".bak")]
	out.files_after_backup_garbage = _names(folder)
	# Mesmo conteúdo regravado por fora mais de 1 s depois: continua válido, o save segue.
	OS.delay_msec(1100)
	var same := FileAccess.get_file_as_bytes(store.path)
	var rewrite := FileAccess.open(store.path, FileAccess.WRITE)
	rewrite.store_buffer(same)
	rewrite.close()
	loaded.economy.grant_reward("seventh", 80)
	out.after_identical_rewrite = store.save(loaded)
	out.final_balances = [_balance(store.path), _balance(store.path + ".bak")]
	out.final_files = _names(folder)
	return out

func run() -> void:
	save_root = "user://tests/save_fast_verify_%d" % Time.get_ticks_usec()
	var previous := OS.get_environment("GETECO_SAVE_VERIFY")
	var fast := _scenario("fast")
	var old := _scenario("old")
	OS.set_environment("GETECO_SAVE_VERIFY", previous)
	check(fast.first == OK and fast.second == OK and fast.third == OK, "rápido: três saves normais")
	check(fast.balances_after_saves == [90, 50], "rápido: principal com o mais novo e backup com o anterior")
	check(fast.files_after_saves == ["progress.json", "progress.json.bak"], "rápido: sem temporário sobrando")
	check(fast.after_primary_garbage == ERR_FILE_CORRUPT, "rápido: principal estragado por fora é recusado")
	check(fast.backup_after_primary_garbage == 50, "rápido: backup intacto quando o principal estragou")
	check(fast.recovered == [true, "backup"], "rápido: carga recupera pelo backup")
	check(fast.after_recovery == OK and fast.balances_after_recovery[0] == 110, "rápido: salva depois de recuperar")
	check(fast.files_after_recovery.has("progress.json.corrupt"), "rápido: evidência do principal estragado preservada")
	check(fast.after_backup_garbage == OK and fast.files_after_backup_garbage.has("progress.json.bak.corrupt"), "rápido: backup estragado vira evidência")
	check(fast.after_identical_rewrite == OK and fast.final_balances == [260, 180], "rápido: regravação idêntica por fora continua válida")
	for key in fast:
		check(typeof(fast[key]) == typeof(old[key]) and fast[key] == old[key], "mesmo resultado nos dois caminhos: " + str(key))
	print("SAVE_STORE_FAST_VERIFY %s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
