extends SceneTree
const EDIT := preload("res://addons/geteco_world_editor/World3DEdit.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	root.size = Vector2i(1280,720)
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	camera.far = 9000
	scene.add_child(camera)
	camera.current = true
	var edit := EDIT.new()
	edit.editor = {"canvas":{"objects":{},"selected_id":""}}
	edit.preview = {"camera":camera}
	for spec in [["front",-5.0],["back",-10.0],["distant",-3000.0]]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		mesh.position.z = spec[1]
		mesh.set_meta("editor_id",spec[0])
		scene.add_child(mesh)
		edit.editor.canvas.objects[spec[0]] = {"id":spec[0]}
	await process_frame
	edit.index_nodes(scene,"")
	var at := Vector2(root.size)*.5
	check(edit.pick(at) == "front", "3D click selects nearest visible piece")
	edit.editor.canvas.selected_id = "front"
	check(edit.pick(at,true) == "back", "Alt click reaches the piece behind selected geometry")
	edit.editor.canvas.selected_id = "back"
	check(edit.pick(at,true) == "distant", "Picking covers the same distance as the visible camera")
	edit.editor.canvas.selected_id = "distant"
	check(edit.pick(at,true) == "front", "Alt selection wraps through intersected pieces")
	edit.editor.canvas.objects.erase("front")
	edit.editor.canvas.objects.erase("back")
	check(edit.pick(at) == "distant", "A distant visible piece remains selectable on its own")
	edit.free()
	scene.free()
	print("WORLD_EDITOR_3D_SELECTION checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
