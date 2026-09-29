extends SceneTree
## Lista as peças de um carro da frota, já com os acabamentos aplicados em runtime
## (FleetCatalog.create): papel do material, cor, posição, caixa e triângulos.
## Uso: Godot --headless --path . --script res://tools/fleet_ingest/dump_car.gd -- --id=aurora_executive
func _initialize() -> void:
	var id := "aurora_executive"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): id = arg.trim_prefix("--id=")
	var model: Node3D = preload("res://runtime/FleetCatalog.gd").create(id)
	var rows := []
	var total := 0
	var roles := {}
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		if mesh == null: continue
		for s in mesh.get_surface_count():
			var m: Material = node.material_override if node.material_override else mesh.surface_get_material(s)
			var arrays := mesh.surface_get_arrays(s)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			var tris: int = (idx.size() if idx != null and idx.size() > 0 else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
			total += tris
			var box: AABB = node.transform * mesh.get_aabb()
			var role := ""
			var color := ""
			var extra := ""
			if m is StandardMaterial3D:
				role = m.resource_name
				color = m.albedo_color.to_html(false)
				extra = "m%.2f r%.2f%s%s%s" % [m.metallic, m.roughness, " emis" if m.emission_enabled else "", " clear" if m.clearcoat_enabled else "", " alpha" if m.transparency != 0 else ""]
			var metas := []
			for k in node.get_meta_list(): metas.append(str(k) + "=" + str(node.get_meta(k)).left(24))
			rows.append("%-26s tris=%5d ctr=(%5.2f,%5.2f,%5.2f) size=(%4.2f,%4.2f,%4.2f) %s #%s %s %s" % [node.name, tris, box.get_center().x, box.get_center().y, box.get_center().z, box.size.x, box.size.y, box.size.z, role, color, extra, ",".join(metas)])
			roles[role if role != "" else "(sem nome)"] = int(roles.get(role if role != "" else "(sem nome)", 0)) + 1
	for r in rows: print("PART ", r)
	print("TOTAL parts=", rows.size(), " tris=", total, " roles=", roles)
	quit()
