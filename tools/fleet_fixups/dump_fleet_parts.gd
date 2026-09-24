extends SceneTree
## Lista as peças de um veículo baked (material, centro, tamanho, metas) para diagnosticar geometria.
## Uso: --script res://tools/fleet_fixups/dump_fleet_parts.gd -- <id> [id ...]
func _initialize() -> void:
	for id in OS.get_cmdline_user_args():
		var model: Node3D = (load("res://assets/fleet/%s.scn" % id) as PackedScene).instantiate()
		print("== ",id)
		for part in model.get_children():
			if not part is MeshInstance3D: continue
			var box: AABB = part.transform * part.get_aabb()
			var material = part.material_override
			if material == null and part.mesh and part.mesh.get_surface_count() > 0: material = part.mesh.surface_get_material(0)
			var label: String = str(material.resource_name) if material else "-"
			var col: String = (material.albedo_color.to_html(false) if material is StandardMaterial3D else "")
			var metas := []
			for key in part.get_meta_list(): metas.append("%s=%s" % [key, part.get_meta(key)])
			print("%s|%s|%s|c=(%.2f,%.2f,%.2f) s=(%.2f,%.2f,%.2f)|%s|%s" % [part.name, label, col, box.get_center().x, box.get_center().y, box.get_center().z, box.size.x, box.size.y, box.size.z, part.mesh.get_class(), " ".join(metas)])
		model.free()
	quit()
