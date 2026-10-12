extends SceneTree
const BELT = preload("res://gameplay/BeltFlashlight.gd")
var failures := 0
class Player extends Node3D:
	var visual: Node3D
class Game extends Node3D:
	var player
	var state = preload("res://runtime/GameState.gd").new()
	var world: Node3D
	var health := 100.0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func run() -> void:
	var game := Game.new()
	game.world = game
	root.add_child(game)
	game.player = Player.new()
	game.add_child(game.player)
	game.player.visual = Node3D.new()
	game.player.add_child(game.player.visual)
	var belt := BELT.new()
	belt.gameplay = game
	game.add_child(belt)
	check(not belt.toggle(), "unowned cannot activate")
	game.state.economy.spend(game.state.economy.balance, "test_empty")
	check(not belt.purchase() and not belt.owned, "insufficient funds reject purchase")
	game.state.economy.grant_reward("test_belt_money", 300)
	check(belt.purchase() and game.state.economy.balance == 0, "purchase costs exactly 300")
	check(not belt.purchase() and game.state.economy.balance == 0, "no duplicate purchase")
	await process_frame
	check(belt.lamp.is_visible_in_tree(), "illuminates unarmed")
	game.state.grant_weapon("pistol")
	game.state.equip_weapon("pistol")
	await process_frame
	check(belt.lamp.is_visible_in_tree(), "equipped weapon preserves belt light")
	var data := belt.snapshot()
	belt.toggle()
	check(not belt.lamp.visible, "toggle switches off")
	belt.restore(data)
	check(belt.owned and belt.enabled and belt.lamp.visible, "restore ownership and activation")
	check(not BELT.valid({"owned":false,"enabled":true}), "invalid activation rejected")
	game.player.visual.rotation.y = PI / 2
	await process_frame
	check(belt.global_position.distance_to(game.player.global_position) < 1.1 and belt.lamp.shadow_enabled, "waist attachment and wall shadows")
	game.free()
	quit(1 if failures else 0)
