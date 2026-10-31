@tool
extends SceneTree
## Rode no editor .NET real: --editor --script res://tests/capture/test_terrain3d_dock_lifecycle.gd.
## O registro do EditorDock não pode ser exercitado pelo host de jogo standalone.
const ASSET_DOCK := preload("res://addons/terrain_3d/src/asset_dock.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func run() -> void:
	if not Engine.is_editor_hint():
		push_error("Terrain3D dock lifecycle requires --editor.")
		quit(2)
		return
	var plugin := EditorPlugin.new()
	root.add_child(plugin)
	for index in 3:
		var panel := ASSET_DOCK.new()
		panel.plugin = plugin
		var wrapper: MarginContainer = ClassDB.instantiate("EditorDock")
		wrapper.title = "Terrain3D lifecycle fixture"
		wrapper.dock_icon = load("res://addons/terrain_3d/icons/terrain3d.svg")
		wrapper.add_child(panel)
		panel._dock = wrapper
		plugin.add_dock(wrapper)
		# Deixa a notificação de entrada na árvore do painel terminar antes de desmontá-lo.
		await process_frame
		panel.remove_dock(true)
		check(not is_instance_valid(wrapper), "Unregistering Terrain3D also frees its EditorDock wrapper")
		check(is_instance_valid(panel) and panel.get_parent() == null, "The panel remains available for the plugin's separate cleanup")
		check(panel._dock == null, "Cleanup clears the stale wrapper reference")
		panel.remove_dock(true)
		panel.free()
	plugin.free()
	await process_frame
	print("TERRAIN3D_DOCK_LIFECYCLE checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
