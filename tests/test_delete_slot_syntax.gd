extends SceneTree
## Carrega os scripts do apagar-save para pegar erro de sintaxe; não toca nos saves do jogador.
func _init() -> void:
	var ok := load("res://runtime/SessionLaunch.gd") != null and load("res://ui/MainMenu.gd") != null
	print("delete_slot scripts: ", "OK" if ok else "FALHOU")
	quit(0 if ok else 1)
