extends SceneTree

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.size = Vector2i(1280, 720)
	var zone := DriftChallengeZone.new()
	root.add_child(zone)
	zone.set_process(false)
	zone.position = Vector2(400, 360)
	zone._card.layer.visible = true
	zone._card.title.text = "Drift · Pátio Westgate"
	zone._card.value.text = "Drift livre · 25 s"
	zone._card.detail.text = "%s\nDerrape dentro do círculo. $150 por 1.000 pts; sem meta mínima." % zone._controls()
	zone._card.hint.text = "[E] Começar desafio"
	for i in 5: await process_frame
	zone.UI.animate(zone, zone._card, 0.0)
	zone.queue_redraw()
	for i in 3: await process_frame
	var bounds: Rect2 = zone._card.panel.get_global_rect()
	var fits := bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= 1280 and bounds.end.y <= 720
	print("DRIFT_CARD fits=", fits, " bounds=", bounds)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/geteco/artifacts/drift-card-0911.png")
	quit(0 if fits else 1)
