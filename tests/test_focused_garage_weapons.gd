extends "res://tests/test_garage_weapon_restrictions.gd"
func _initialize() -> void: isolated.call_deferred()
func isolated() -> void:
 root.get_node("SaveManager")._save_dir="D:/geteco/artifacts/focused-repair/saves/"
 await run()
