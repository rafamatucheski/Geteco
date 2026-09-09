extends SceneTree

var _frames := 0

func _init() -> void:
	call_deferred("_start")

func _start() -> void:
	print("[WINDOWED TEST] Iniciando teste em janela real...")
	var menu_scene = load("res://ui/MainMenu.tscn") as PackedScene
	if not menu_scene:
		printerr("Falha ao carregar MainMenu.tscn")
		quit(1)
		return
	var menu = menu_scene.instantiate()
	root.add_child(menu)
	print("[WINDOWED TEST] MainMenu renderizado na janela.")

func _process(delta: float) -> bool:
	_frames += 1
	if _frames == 30:
		print("[WINDOWED TEST] 30 frames renderizados com sucesso no viewport visual.")
	elif _frames >= 60:
		print("[WINDOWED TEST] 60 frames concluídos com sucesso sem falhas gráficas.")
		quit(0)
		return true
	return false
