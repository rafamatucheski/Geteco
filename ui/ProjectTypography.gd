extends Node
## One bundled family for menus, HUD, world text and runtime-created controls.
const REGULAR := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Regular.ttf")
const MEDIUM := preload("res://assets/fonts/barlow/BarlowSemiCondensed-Medium.ttf")
const SEMIBOLD := preload("res://assets/fonts/barlow/BarlowSemiCondensed-SemiBold.ttf")
const ITALIC := preload("res://assets/fonts/barlow/BarlowSemiCondensed-MediumItalic.ttf")

func _enter_tree() -> void:
	# Covers procedural draw_string and default Label3D/TextMesh consumers too.
	ThemeDB.fallback_font = REGULAR
