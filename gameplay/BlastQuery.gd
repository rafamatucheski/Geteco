extends RefCounted
## Uma entrada por corpo/área, antes de dano/filtros. Várias shapes do mesmo RID
## não podem consumir o raio inteiro de uma explosão. 64 é página, não teto de alvos.
const PAGE_SIZE := 64

static func intersect_bodies(space: PhysicsDirectSpaceState3D, query: PhysicsShapeQueryParameters3D) -> Array[Dictionary]:
	var page_query := PhysicsShapeQueryParameters3D.new()
	if query.shape != null: page_query.shape = query.shape
	else: page_query.shape_rid = query.shape_rid
	page_query.transform = query.transform
	page_query.collision_mask = query.collision_mask
	page_query.collide_with_bodies = query.collide_with_bodies
	page_query.collide_with_areas = query.collide_with_areas
	page_query.margin = query.margin
	page_query.motion = query.motion
	var excluded: Array[RID] = query.exclude.duplicate()
	var seen: Dictionary = {}
	for rid: RID in excluded: seen[rid] = true
	var results: Array[Dictionary] = []
	while true:
		page_query.exclude = excluded
		var page: Array[Dictionary] = space.intersect_shape(page_query,PAGE_SIZE)
		for hit: Dictionary in page:
			var rid: RID = hit.rid
			if seen.has(rid): continue
			seen[rid] = true
			excluded.append(rid)
			results.append(hit)
		# Cada página cheia exclui ao menos um RID novo; todas as shapes dele
		# desaparecem da próxima consulta. Colete tudo antes de alterar o mundo.
		if page.size() < PAGE_SIZE: break
	return results
