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
		# Triângulos reais de cada acabamento (a malha é recortada e indexada desde 2026-10-13: uma camada de
		# chão só; não dá mais para ler retângulos de 6 em 6 vértices).
		var pieces: Array[Dictionary] = []
		for node in parent.get_children():
			var faces: PackedVector3Array = node.mesh.get_faces()
			var material = node.mesh.surface_get_material(0)
			for i in range(0,faces.size(),3):
				pieces.append({"a":Vector2(faces[i].x,faces[i].z),"b":Vector2(faces[i+1].x,faces[i+1].z),"c":Vector2(faces[i+2].x,faces[i+2].z),"color":material.albedo_color,"node":node})
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
				var owners := {}
				for piece in pieces:
					if Geometry2D.point_is_inside_triangle(point,piece.a,piece.b,piece.c):
						actual=piece.color
						owners[piece.node] = true
				# Sem sobreposição coplanar de área positiva entre acabamentos diferentes.
				if owners.size() > 1: failed+=1
				if actual!=expected: failed+=1
		parent.free()
	print("SIDEWALK_COVERAGE failures=",failed)
	quit(1 if failed else 0)
