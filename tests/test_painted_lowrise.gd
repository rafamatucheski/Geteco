extends SceneTree

## Pacotes baixos (18/10): mercearia, estação, galpão, oficina e garagem montam o kit no
## lugar da caixa antiga, com uma entrada de verdade (folha que abre) no vão pintado,
## soleira rente ao chão, largura igual à do catálogo e corte da entrada no meio da folha.
## GETECO_PAINTED_LOWRISE=0 devolve os seis à geometria antiga.

const CATALOG := preload("res://world/places/harbor_buildings/HarborBuildingCatalog.gd")
const PORT := preload("res://world/regions/OriginalSouthPort.gd")

func _init() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json")).get("harbor_buildings", [])
	var by_id := {}
	for r in rows: by_id[str(r.get("id", ""))] = r
	for record in PORT.records():
		if str(record.id).begins_with("PortBuilding"):
			by_id[str(record.id)] = {"id": str(record.id), "kind": str(record.model_kind), "position": record.position, "size": (record.footprint as Rect2).size / 16.0}
	var failures: Array = []
	var checks := 0
	for id in PaintedHarborHouses.LOWRISE:
		var style: String = PaintedHarborHouses.LOWRISE[id]
		var row: Dictionary = by_id.get(id, {})
		checks += 1
		if row.is_empty(): failures.append("%s: sem registro" % id); continue
		checks += 1
		if PaintedHarborHouses.style_for(id, str(row.kind)) != style: failures.append("%s: style_for" % id)
		var building: Node3D = UrbanBuildingFactory.build_building(row)
		root.add_child(building)
		await process_frame
		var kits := building.find_children("PaintedFacade_" + style, "Node3D", true, false)
		checks += 1
		if kits.size() != 1: failures.append("%s: %d kits" % [id, kits.size()]); building.queue_free(); continue
		var kit: Node3D = kits[0]
		var def: Dictionary = CATALOG.for_source(id)
		checks += 1
		if def.is_empty() or absf(float(def.size.x) - float(building.building_size.x)) > 0.01:
			failures.append("%s: largura do catálogo %s != prédio %s" % [id, def.get("size", "?"), building.building_size.x])
			building.queue_free(); continue
		# Uma folha de entrada (walk_in) e o corte do catálogo no meio dela.
		var walk_ins: Array = []
		for anchor in kit.find_children("Doorway_front*", "Node3D", false, false):
			if anchor.get_meta("walk_in", false): walk_ins.append(anchor)
		checks += 1
		if walk_ins.size() != 1: failures.append("%s: %d entradas walk_in" % [id, walk_ins.size()]); building.queue_free(); continue
		var anchor: Node3D = walk_ins[0]
		var door: Node3D = anchor.get_node("Door")
		var leaf_w: float = (door.get_node("Hinge").get_child(0).mesh as QuadMesh).size.x
		var center_x: float = (building.to_local(anchor.global_position)).x + leaf_w * 0.5
		checks += 1
		if absf(center_x - float(def.entrance_local.x)) > 0.05:
			failures.append("%s: entrada do catálogo x=%.2f, folha em x=%.2f" % [id, def.entrance_local.x, center_x])
		checks += 1
		var sill: float = anchor.global_position.y - building.global_position.y
		if absf(sill) > 0.08: failures.append("%s: soleira a %.2f m do chão" % [id, sill])
		print("LOWRISE %s %s largura=%.2f folha=%.2f m x=%.2f soleira=%.3f" % [id, style, building.building_size.x, leaf_w, center_x, sill])
		building.queue_free()
		await process_frame
	OS.set_environment("GETECO_PAINTED_LOWRISE", "0")
	for id in PaintedHarborHouses.LOWRISE:
		checks += 1
		if not PaintedHarborHouses.style_for(id, "x").is_empty(): failures.append("%s: interruptor não desliga" % id)
	OS.set_environment("GETECO_PAINTED_LOWRISE", "")
	print("PAINTED_LOWRISE checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
