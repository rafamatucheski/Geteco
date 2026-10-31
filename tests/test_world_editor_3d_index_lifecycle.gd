extends SceneTree
const EDIT := preload("res://addons/geteco_world_editor/World3DEdit.gd")
const INDEX := preload("res://addons/geteco_world_editor/World3DEditIndex.gd")
var checks := 0
var failures := 0

class Junction:
	extends RefCounted
	func cancel() -> void: pass

class OwnerEditor:
	extends Node
	var canvas := {"objects":{"visible":{},"hidden":{}}}
	var junction_editor := Junction.new()

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var owner_editor := OwnerEditor.new()
	var edit := EDIT.new()
	edit.editor = owner_editor
	var source := Node3D.new()
	source.visible = false
	root.add_child(source)
	var visible_mesh := MeshInstance3D.new()
	visible_mesh.mesh = BoxMesh.new()
	visible_mesh.set_meta("editor_id","visible")
	source.add_child(visible_mesh)
	var hidden := Node3D.new()
	hidden.visible = false
	source.add_child(hidden)
	var hidden_mesh := MeshInstance3D.new()
	hidden_mesh.mesh = BoxMesh.new()
	hidden_mesh.set_meta("editor_id","hidden")
	hidden.add_child(hidden_mesh)
	check(await INDEX.rebuild(weakref(edit),weakref(source),self), "Hidden replacement geometry can be indexed before swapping views")
	check(edit.meshes.size() == 1 and edit.groups.has("visible") and not edit.groups.has("hidden"), "Index preserves authored hidden subtrees")
	# Uma árvore grande demais finita força pelo menos um limite de fatia. Fechar o
	# controle enquanto o job independente espera precisa devolver false sem retomá-lo.
	for i in 50000: source.add_child(Node3D.new())
	edit.call_deferred("free")
	var result: bool = await INDEX.rebuild(weakref(edit),weakref(source),self)
	check(not result, "Closing the editor cancels a 3D index job safely")
	source.free()
	owner_editor.free()
	print("WORLD_EDITOR_3D_INDEX_LIFECYCLE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
