extends SceneTree

## Os cinco prÃ©dios comerciais do porto (lavanderia, marcenaria, mercado, escritÃ³rio de
## frete, aquÃ¡rio) montam a fachada pintada e nÃ£o a geometria antiga/assada.

const IDS := {"Laundry": "lavanderia", "UnionWorkshop": "oficina-artesao", "MarketHall": "mercado-municipal",
	"FreightOffice": "escritorio-frete", "Aquarium": "aquario", "MaritimeMuseum": "museu-maritimo", "ColdStorage": "camara-fria"}

func _init() -> void:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json")).get("harbor_buildings", [])
	var failures: Array = []
	var checks := 0
	for id in IDS:
		var style: String = IDS[id]
		checks += 1
		if PaintedHarborHouses.style_for(id, "x") != style: failures.append("%s: style_for" % id)
		var row := {}
		for r in rows:
			if str(r.get("id", "")) == id: row = r
		if row.is_empty(): failures.append("%s: sem linha em OriginalWorldData" % id); continue
		var building: Node3D = UrbanBuildingFactory.build_building(row)
		root.add_child(building)
		await process_frame
		checks += 1
		var painted := building.find_children("PaintedFacade_" + style, "Node3D", true, false)
		if painted.is_empty(): failures.append("%s: sem PaintedFacade_%s" % [id, style])
		building.queue_free()
	print("PAINTED_HARBOR_BUILDINGS checks=%d failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)
