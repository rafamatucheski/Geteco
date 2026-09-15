extends SceneTree

var failures := 0

func _init() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func run() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	current_scene = stage
	var player := CharacterBody2D.new()
	player.set_script(load("res://Player.gd"))
	var camera := Camera2D.new()
	camera.name = "Camera"
	player.add_child(camera)
	# Also cover an actor spawned hidden, before ready connects the signal.
	player.hide()
	stage.add_child(player)
	var viewport: SubViewport = player.get("viewport_3d")
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Initially hidden player must not render")
	var physics_enabled := player.is_physics_processing()
	# O Player visível usa UPDATE_WHEN_VISIBLE (só desenha o que aparece na tela);
	# o contrato é voltar a renderizar ao mostrar, não um modo específico.
	player.show()
	check(viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED, "Showing player must resume 3D rendering")
	player.hide()
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Boarding-style hide must stop 3D rendering")
	check(player.is_physics_processing() == physics_enabled, "Visibility toggle must not change physics")
	player.show()
	stage.hide()
	check(viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Hidden ancestor must stop player rendering")
	stage.show()
	check(viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED, "Showing ancestor must restore rendering")
	# Death/arrest show the player, disable physics, then animate via Tween.
	player.hide()
	player.set_physics_process(false)
	player.show()
	check(viewport.render_target_update_mode != SubViewport.UPDATE_DISABLED, "Death/arrest display must not depend on physics")
	var model: Node3D = player.get("model_root")
	var fall := player.create_tween()
	fall.tween_property(model, "rotation:x", 0.5, 0.05)
	await fall.finished
	check(is_equal_approx(model.rotation.x, 0.5), "Visible death-style tween must still complete")
	check(not player.is_physics_processing(), "Render resume must leave disabled physics unchanged")
	stage.queue_free()
	await process_frame
	print("PLAYER_RENDER_VISIBILITY_RESULT failures=%d" % failures)
	quit(0 if failures == 0 else 1)
