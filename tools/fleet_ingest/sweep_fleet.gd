extends SceneTree
## Cria todos os carros da frota e lista peças (fábrica -> jogo) e casco corrigido.
func _initialize() -> void:
	var ids: Array = preload("res://runtime/FleetCatalog.gd").all().keys()
	ids.sort()
	var before := 0
	var after := 0
	for id in ids:
		var spec: Dictionary = preload("res://runtime/FleetCatalog.gd").spec(id)
		var raw := 0
		if spec.has("scene") and load(spec.scene) is PackedScene:
			var r: Node3D = (load(spec.scene) as PackedScene).instantiate()
			raw = r.find_children("*", "MeshInstance3D", true, false).size()
			r.free()
		var m: Node3D = preload("res://runtime/FleetCatalog.gd").create(id)
		if m == null: continue
		var n := m.find_children("*", "MeshInstance3D", true, false).size()
		before += raw
		after += n
		print("SWEEP ", id, " ", raw, " -> ", n, " hull_fixed=", preload("res://runtime/FleetSpeedPass.gd")._hulls.get(id) != null)
		m.free()
	print("SWEEP_TOTAL ", before, " -> ", after)
	quit()
