extends SceneTree
## Sessão viva para testes: sobe o mundo REAL uma vez e fica rodando; cada arquivo solto em `evidence/live/inbox/*.gd`
## é executado dentro dela, sem reabrir o jogo. O arquivo define `func run(world, tree) -> void` (pode usar `await`);
## o que for impresso por `Live.say(...)` vai para `evidence/live/outbox/<nome>.txt`, e o script é movido para `done/`.
## Para encerrar: soltar um arquivo `stop` na inbox. Sem save, sem tela de chegada; renderizado (não usar --headless).
## Uso: "$GODOT" --path . --script res://tests/live/live_session.gd -- --no-save --skip-arrival
const BASE := "res://evidence/live"
var world: Node
var log_lines: PackedStringArray = []

func _initialize() -> void: run.call_deferred()

func _dir(name: String) -> String: return ProjectSettings.globalize_path("%s/%s" % [BASE, name])

func run() -> void:
	for sub in ["inbox", "outbox", "done"]: DirAccess.make_dir_recursive_absolute(_dir(sub))
	world = load("res://Main.tscn").instantiate()
	world.set_meta("skip_arrival", true)
	root.add_child(world)
	var deadline := Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if world.session != null and world.session.ready_for_play: break
	_write("_ready", "mundo pronto" if world.session != null and world.session.ready_for_play else "mundo NÃO ficou pronto")
	print("LIVE pronto; solte scripts em ", _dir("inbox"))
	while true:
		await create_timer(0.5).timeout
		if FileAccess.file_exists(_dir("inbox") + "/stop"):
			DirAccess.remove_absolute(_dir("inbox") + "/stop")
			break
		for file in DirAccess.get_files_at(_dir("inbox")):
			if file.ends_with(".gd"): await _execute(file)
	quit(0)

func say(text: Variant) -> void: log_lines.append(str(text))

func _write(name: String, text: String) -> void:
	var out := FileAccess.open(_dir("outbox") + "/%s.txt" % name, FileAccess.WRITE)
	out.store_string(text)

func _execute(file: String) -> void:
	var path := _dir("inbox") + "/" + file
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	log_lines = PackedStringArray()
	var started := Time.get_ticks_msec()
	if script.reload() != OK:
		_write(file.get_basename(), "ERRO de compilação em %s" % file)
	else:
		var instance = script.new()
		instance.set("live", self)
		# `run` pode usar await: espera terminar, com limite de 5 min.
		await instance.run(world, self)
		_write(file.get_basename(), "\n".join(log_lines) + "\n(%d ms)" % (Time.get_ticks_msec() - started))
	DirAccess.rename_absolute(path, _dir("done") + "/" + file)
