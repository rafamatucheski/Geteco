extends SceneTree
## A tela de carregamento aberta pelo menu (na raiz) sobrevive à troca de cena, o mundo
## a adota, a barra passa pelas etapas reais do build e ela sai quando o mundo assenta.
## --no-save --skip-arrival obrigatórios.

var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	print(("PASS " if ok else "FAIL ") + label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args(): quit(2); return
	var curtain = load("res://runtime/StartupCurtain.gd").new()
	curtain.variant = 2
	root.add_child(curtain)
	curtain.set_stage(.08, "Carregando o mundo…")
	await process_frame
	change_scene_to_file("res://Main.tscn")
	var adopted := false
	var stages := {}
	var peak := 0.0
	for i in 2400:
		await process_frame
		if not is_instance_valid(curtain): break
		if current_scene != null and curtain.get_parent() != root: adopted = adopted or curtain.get_parent() == current_scene
		stages[curtain._stage.text] = true
		peak = maxf(peak, curtain._target)
	check(adopted, "mundo adotou a cortina do menu")
	check(stages.size() >= 5, "etapas mostradas: %s" % ", ".join(stages.keys()))
	check(peak >= 1.0, "barra chegou ao fim")
	check(not is_instance_valid(curtain), "cortina saiu depois de o mundo assentar")
	var extra := 0
	for child in root.get_children(): if child.name.begins_with("LoadingCurtain"): extra += 1
	check(extra == 0, "nenhuma cortina duplicada ficou na raiz")
	print("LOADING_HANDOFF ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
