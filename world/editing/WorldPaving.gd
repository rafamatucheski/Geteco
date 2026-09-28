@tool
extends RefCounted
const SURFACE := preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
static func catalog() -> Dictionary:
	var source := SURFACE.new()
	source.configure()
	var rows := {}
	for index in source._surfaces.size():
		var item: Dictionary = source._surfaces[index]
		if item.kind == "grass": continue
		var rect: Rect2 = item.rect
		var id := "paving/%d" % index
		rows[id] = {"id":id,"type":"ground","paving":true,"label":"Calçada / piso existente","position":[rect.get_center().x,rect.get_center().y],"size":[rect.size.x,rect.size.y],"rotation":0.0,"surface":"concrete" if item.kind == "concrete" else "pavers","color":item.color.to_html(false)}
	return rows

static func apply(surface: RefCounted, changes: Dictionary) -> void:
	var changed := false
	for id in changes:
		if str(id).begins_with("paving/"): changed = true; break
	if not changed: return
	var originals := catalog()
	for index in range(surface._surfaces.size()-1,-1,-1):
		var id := "paving/%d" % index
		if not originals.has(id) or not changes.has(id): continue
		var row: Dictionary = changes[id]
		if row.get("deleted",false):
			surface._surfaces.remove_at(index)
			continue
		var center := Vector2(row.position[0],row.position[1])
		var size := Vector2(row.size[0],row.size[1])
		var replacement: Dictionary = surface._surfaces[index].duplicate()
		replacement.color = Color(row.get("color",originals[id].color))
		if row.surface != originals[id].surface:
			replacement.kind = "concrete" if row.surface == "concrete" else "stone"
		surface._surfaces.remove_at(index)
		# Preserve the sewer opening even when an edited rectangle crosses it.
		for piece in surface._carved(Rect2((center-size*.5)/SURFACE.SCALE,size/SURFACE.SCALE)):
			var item := replacement.duplicate()
			item.rect = Rect2(piece.position*SURFACE.SCALE,piece.size*SURFACE.SCALE)
			surface._surfaces.insert(index,item)
	surface._compose_visible_surfaces()
