extends SceneTree
const CANVAS := preload("res://addons/geteco_world_editor/WorldMapCanvas.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func row(id: String, at: float, height: float) -> Dictionary:
	return {"id":id,"type":"piece","position":[at,0],"size":[2,2],"rotation":0.0,"parts":[[at-1,-1,2,2,height,"ffffff"]]}

func run() -> void:
	var canvas := CANVAS.new()
	root.add_child(canvas)
	canvas.size = Vector2(512,512)
	canvas.center = Vector2(64,0)
	canvas.zoom = 1
	canvas.objects = {"piece/a":row("piece/a",0,5),"piece/b":row("piece/b",10,1)}
	canvas.rebuild_context()
	var untouched: int = canvas.context_owner_parts["piece/b"][0]
	canvas._part_triangles(untouched)
	var old_slot: int = canvas.context_owner_parts["piece/a"][0]
	canvas.objects["piece/a"] = row("piece/a",128,0)
	canvas.update_context(["piece/a"])
	check(canvas.context_owner_parts["piece/b"][0] == untouched, "Moving one piece preserves other geometry slots")
	check(canvas.context_triangles.has(untouched), "Moving one piece preserves unrelated triangulation cache")
	check(old_slot not in canvas.context_cells.get(Vector2i.ZERO,[]), "Moved piece leaves its old spatial cells")
	check(old_slot in canvas.context_cells.get(Vector2i(2,0),[]), "Moved piece enters its destination spatial cells")
	var visible: Array = canvas._visible_parts()
	check(visible.find(old_slot) < visible.find(untouched), "Incremental geometry keeps height drawing order")
	canvas.objects.erase("piece/a")
	canvas.update_context(["piece/a"])
	check(not canvas.context_owner_parts.has("piece/a") and old_slot not in canvas._visible_parts(), "Deletion removes geometry from picking and drawing cells")
	canvas.objects["piece/a"] = row("piece/a",20,7)
	canvas.update_context(["piece/a"])
	check(canvas.context_parts.size() == 2 and canvas.context_owner_parts["piece/a"].size() == 1, "Undo reuses slots without accumulating deleted geometry")
	canvas.free()
	print("WORLD_EDITOR_CONTEXT_UPDATES checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
