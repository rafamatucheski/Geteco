extends SceneTree
## Custo da primeira Label3D com fonte padrão (cai na fonte do sistema) contra a fonte do jogo.
func _initialize() -> void:
	root.size = Vector2i(1280, 720)
	run.call_deferred()
func run() -> void:
	var font := load("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf") as Font
	for case in [["fonte do jogo", font, "Largada"], ["fonte padrão", null, "Largada"], ["padrão acentos", null, "Pódio ação"]]:
		var began := Time.get_ticks_usec()
		var label := Label3D.new()
		label.text = case[2]
		label.font_size = 64
		if case[1] != null: label.font = case[1]
		root.add_child(label)
		await process_frame
		await process_frame
		print("%s: %.1f ms" % [case[0], (Time.get_ticks_usec() - began) / 1000.0])
	quit(0)
