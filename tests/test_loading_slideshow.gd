extends SceneTree
## Real-time slideshow, stalled progress, paused tree, and immediate release.
var failures: Array[String] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failures.append(message)

func run() -> void:
	root.size = Vector2i(1280, 720)
	var curtain = load("res://runtime/StartupCurtain.gd").new()
	root.add_child(curtain)
	curtain.set_stage(.25, "Teste")
	var art = curtain._root.get_node("Artwork")
	var seen := {}
	var first: int = art.current_index
	var began := Time.get_ticks_usec()
	var captures := {}
	var out := "res://evidence/loading-slideshow/preview-fifteen"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	paused = true
	# Wait for the actual loop: screenshot readbacks and first-use GPU uploads can
	# pause the main thread; artwork deliberately clamps such deltas to avoid cuts.
	# Fifteen visible slides require 105 seconds, excluding those stalls.
	while art.transitions < 15 and Time.get_ticks_usec() - began < 180000000:
		await process_frame
		seen[art.current_index] = true
		if DisplayServer.get_name() != "headless" and art._elapsed > 1.0 and not captures.has(art.current_index):
			var index: int = art.current_index
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(out+"/slide-%d.png" % index)
			captures[index] = true
	check(seen.size() == 15, "quinze artes alternam mesmo com progresso parado e árvore pausada")
	check(art.transitions >= 15 and art.current_index == first, "sequência aleatória completa retorna à primeira arte sem repetir antes")
	check(is_equal_approx(curtain._shown, .25), "barra mantém o progresso real sem inventar avanço")
	curtain.set_stage(.1, "Etapa antiga")
	check(is_equal_approx(curtain._target, .25), "progresso não retrocede")
	check(curtain._root.find_child("Brand", true, false).text == "HARBOR", "marca correta")
	var release := Time.get_ticks_usec()
	curtain.lift(1)
	while is_instance_valid(curtain):
		await process_frame
		if Time.get_ticks_usec()-release > 2000000: break
	check(not is_instance_valid(curtain), "libera o jogo sem esperar o ciclo das artes")
	var invisible = load("res://runtime/StartupCurtain.gd").new()
	invisible.stage_only = true
	root.add_child(invisible)
	check(invisible._root == null and invisible.get_child_count() == 0, "cortina de diagnóstico do menu não duplica artes")
	invisible.queue_free()
	for region in ["mountain", "desert"]:
		var regional = load("res://runtime/StartupCurtain.gd").new()
		regional.variant = regional.variant_for(region)
		root.add_child(regional)
		var regional_art = regional._root.get_node("Artwork")
		check(regional_art.current_index == (3 if region == "mountain" else 7), "primeira arte corresponde à região " + region)
		regional.queue_free()
	paused = false
	print("LOADING_SLIDESHOW_TEST ", "PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
