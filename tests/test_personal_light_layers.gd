extends SceneTree
const LAYERS := preload("res://gameplay/PersonalLightLayers.gd")
class Game extends Node3D:
	var player := Node3D.new()
	var gun := Node3D.new()
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func run() -> void:
	var game := Game.new()
	root.add_child(game)
	game.add_child(game.player)
	game.add_child(game.gun)
	var body := MeshInstance3D.new()
	game.player.add_child(body)
	var helper := LAYERS.new()
	helper.gameplay = game
	game.add_child(helper)
	check(body.layers & LAYERS.PLAYER_LAYER != 0 and body.layers & LAYERS.SHADOW_MASK == 0,"wearer excluded only from personal shadow maps")
	check(body.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON,"wearer keeps world shadows")
	var new_outfit := MeshInstance3D.new()
	game.player.add_child(new_outfit)
	var new_weapon := MeshInstance3D.new()
	game.gun.add_child(new_weapon)
	check(new_outfit.layers == body.layers and new_weapon.layers == body.layers,"new outfit and weapon inherit personal shadow exclusion")
	var capture_only := MeshInstance3D.new()
	capture_only.layers = LAYERS.CAPTURE_LAYERS
	game.player.add_child(capture_only)
	check(capture_only.layers == LAYERS.CAPTURE_LAYERS,"capture-only proxies stay out of the main camera")
	var hidden := MeshInstance3D.new()
	hidden.layers = 0
	game.player.add_child(hidden)
	check(hidden.layers == 0,"hidden geometry is not made visible")
	var wall := MeshInstance3D.new()
	game.add_child(wall)
	check(wall.layers & LAYERS.SHADOW_MASK != 0,"walls still block the personal lights")
	body.layers |= LAYERS.CAPTURE_LAYERS
	check(body.layers & LAYERS.SHADOW_MASK == 0,"reflection capture bits cannot reintroduce self shadows")
	var scene_light := OmniLight3D.new()
	game.add_child(scene_light)
	check(scene_light.light_cull_mask & body.layers != 0 and scene_light.shadow_caster_mask & body.layers != 0,"scene lights still illuminate and cast wearer shadows")
	helper.queue_free()
	await process_frame
	var later := MeshInstance3D.new()
	game.player.add_child(later)
	check(later.layers == 1,"helper disconnects on unload")
	game.free()
	quit(1 if failures else 0)
