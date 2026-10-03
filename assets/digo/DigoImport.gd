@tool
extends EditorScenePostImport
## Bake garment membership in vertex alpha before skinning. No runtime image reads.
func _post_import(scene: Node) -> Object:
	var image := Image.load_from_file("res://assets/digo/digo_Image_0.jpg")
	for visual: MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
		var original := visual.mesh
		var mesh := ArrayMesh.new()
		for surface in original.get_surface_count():
			var arrays := original.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var parents := PackedInt32Array()
			var welded := {}
			var torso_seed := 0
			for i in vertices.size(): parents.append(i)
			for i in vertices.size():
				var key := (vertices[i] * 100000.0).round()
				if welded.has(key): parents[_root(parents,i)] = _root(parents,welded[key])
				else: welded[key] = i
				if absf(vertices[i].x)<.12 and vertices[i].y>1.1 and vertices[i].y<1.3: torso_seed = i
			for i in range(0,indices.size(),3):
				parents[_root(parents,indices[i])] = _root(parents,indices[i+1])
				parents[_root(parents,indices[i+1])] = _root(parents,indices[i+2])
			var torso_component := _root(parents,torso_seed)
			var colors := PackedColorArray()
			for i in vertices.size():
				var p := vertices[i]
				var uv := uvs[i]
				var texel := image.get_pixel(clampi(int(uv.x*image.get_width()),0,image.get_width()-1),clampi(int(uv.y*image.get_height()),0,image.get_height()-1))
				var torso := absf(p.x) < .23
				var red := texel.r > texel.g * 1.75
				var garment := _root(parents,i) == torso_component and (torso or (red and absf(p.x)<.345))
				colors.append(Color(1,1,1,1 if garment else 0))
			arrays[Mesh.ARRAY_COLOR] = colors
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			mesh.surface_set_material(surface,original.surface_get_material(surface))
		visual.mesh = mesh
	return scene

func _root(parents: PackedInt32Array, index: int) -> int:
	while parents[index] != index: index = parents[index]
	return index
