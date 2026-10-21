extends SceneTree
## The simple original merge is an independent oracle for the optimized grouping.
class LegacySurface extends "res://world/urban_detail/HarborUrbanSurface3D.gd":
	func _merge_neighbours() -> void:
		var changed := true
		while changed:
			changed = false
			for i in _visible_surfaces.size():
				for j in range(i+1,_visible_surfaces.size()):
					if _visible_surfaces[i].kind != _visible_surfaces[j].kind or _visible_surfaces[i].color != _visible_surfaces[j].color: continue
					if _visible_surfaces[i].get("court",Rect2()) != _visible_surfaces[j].get("court",Rect2()) or _visible_surfaces[i].get("garden",Rect2()) != _visible_surfaces[j].get("garden",Rect2()): continue
					var a: Rect2 = _visible_surfaces[i].rect
					var b: Rect2 = _visible_surfaces[j].rect
					var horizontal := is_equal_approx(a.position.y,b.position.y) and is_equal_approx(a.size.y,b.size.y) and (is_equal_approx(a.end.x,b.position.x) or is_equal_approx(b.end.x,a.position.x))
					var vertical := is_equal_approx(a.position.x,b.position.x) and is_equal_approx(a.size.x,b.size.x) and (is_equal_approx(a.end.y,b.position.y) or is_equal_approx(b.end.y,a.position.y))
					if not horizontal and not vertical: continue
					_visible_surfaces[i].rect = a.merge(b)
					_visible_surfaces.remove_at(j)
					changed = true
					break
				if changed: break

var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures += 1

func run() -> void:
	var legacy := LegacySurface.new()
	var fast = load("res://world/urban_detail/HarborUrbanSurface3D.gd").new()
	var raw = load("res://world/urban_detail/HarborUrbanSurface3D.gd").new()
	legacy.configure()
	fast.configure()
	raw.configure(false)
	check(var_to_bytes(legacy._surfaces) == var_to_bytes(raw._surfaces), "catálogo conserva todos os retângulos autorados sem compor malhas")
	check(var_to_bytes(legacy._visible_surfaces) == var_to_bytes(fast._visible_surfaces), "todos os pisos visíveis mantêm geometria, ordem e acabamento exatos")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1324
	for trial in 12:
		var rows: Array[Dictionary] = []
		for i in 64:
			rows.append({"rect":Rect2(rng.randi_range(-4,4),rng.randi_range(-4,4),rng.randi_range(1,3),1),"kind":"concrete","color":Color.WHITE,"court":Rect2(0,0,trial%3,trial%2),"garden":Rect2()})
		legacy._visible_surfaces = rows.duplicate(true)
		fast._visible_surfaces = rows.duplicate(true)
		legacy._merge_neighbours()
		fast._merge_neighbours()
		check(var_to_bytes(legacy._visible_surfaces) == var_to_bytes(fast._visible_surfaces), "ordem de fusão preservada no conjunto " + str(trial))
	legacy = null
	fast = null
	raw = null
	print("PAVING_PREPARATION ","PASS" if failures == 0 else "FAIL")
	quit(0 if failures == 0 else 1)
