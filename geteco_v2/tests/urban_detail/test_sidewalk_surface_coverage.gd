extends SceneTree
## Every authored finish must retain last-painted V1 precedence, without
## positive-area coplanar overlaps, including when clipped at chunk borders.
const SURFACE = preload("res://world/urban_detail/HarborUrbanSurface3D.gd")
var failed := 0

func _initialize() -> void:
	var factory = SURFACE.new()
	factory.configure()
	for bounds in [Rect2(-10,-290,440,455),Rect2(90,85,40,45),Rect2(130,85,40,45)]:
		var parent := Node3D.new()
		factory.build_chunk(parent,bounds)
		var pieces: Array[Dictionary] = []
		for node in parent.get_children():
			var vertices: PackedVector3Array = node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var material = node.mesh.surface_get_material(0)
			for i in range(0,vertices.size(),6):
				var a := Vector2(vertices[i].x,vertices[i].z)
				var b := Vector2(vertices[i+1].x,vertices[i+1].z)
				pieces.append({"rect":Rect2(a,b-a),"color":material.albedo_color})
		for i in pieces.size():
			for j in range(i+1,pieces.size()):
				if pieces[i].rect.intersection(pieces[j].rect).get_area()>0.000001:
					failed+=1
		# Interior samples avoid ambiguous shared edges. Compare original paint
		# order, independently of the renderer's grouping or tessellation.
		for x in range(int(bounds.position.x),int(bounds.end.x),2):
			for y in range(int(bounds.position.y),int(bounds.end.y),2):
				var point := Vector2(x+.371,y+.613)
				if not bounds.has_point(point): continue
				var expected = null
				for source in factory._surfaces:
					if source.rect.has_point(point): expected=source.color
				var actual = null
				for piece in pieces:
					if piece.rect.has_point(point): actual=piece.color
				if actual!=expected: failed+=1
		parent.free()
	print("SIDEWALK_COVERAGE failures=",failed)
	quit(1 if failed else 0)
