extends SceneTree
# Mede quanto o fundo dos pneus fica acima (+) ou abaixo (-) do chão (y=0 do corpo
# do veículo) para cada arquivo da frota. O hull de colisão apoia em y=0.

func _initialize() -> void:
	var catalog = preload("res://runtime/FleetCatalog.gd")
	var ids: Array = catalog.all().keys()
	ids.sort()
	var bad := 0
	for id in ids:
		var veh: CharacterBody3D = preload("res://scripts/Vehicle.gd").new()
		veh.archetype = id
		root.add_child(veh)
		var visual: Node3D = veh.visual
		if visual == null: continue
		var low := INF
		var wheels := 0
		for part in visual.find_children("*","MeshInstance3D",true,false):
			if not part.has_meta("wheel_center"): continue
			wheels += 1
			var box: AABB = part.get_aabb()
			var t: Transform3D = _rel(veh, part)
			for i in 8:
				low = minf(low, (t * box.get_endpoint(i)).y)
		var any_low := INF
		for part2 in visual.find_children("*", "MeshInstance3D", true, false):
			var box2: AABB = part2.get_aabb()
			var t2: Transform3D = _rel(veh, part2)
			for i in 8:
				any_low = minf(any_low, (t2 * box2.get_endpoint(i)).y)
		var flag := "" if absf(low) < 0.03 else "  <<<"
		if flag != "": bad += 1
		print("%-28s rodas=%d fundo_pneu=%+.3f fundo_malha=%+.3f%s" % [id, wheels, low if low < INF else 0.0, any_low, flag])
		veh.queue_free()
	print("fora de +-3cm: ", bad)
	quit(0)

func _rel(top: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var c: Node = n
	while c != null and c != top:
		if c is Node3D: t = (c as Node3D).transform * t
		c = c.get_parent()
	return t
