@tool
extends RefCounted
const CACHE_REVISION := "terrain-map-2"
## Rasterizes only authored terrain triangles. Transparent pixels expose the map
## outside the actual surface; scenery and buildings never enter this image.
static func revision(document: Dictionary, area: String) -> String:
	var brushes := {}
	for id in document.get("regions",{}).get(area,{}):
		var row: Dictionary = document.regions[area][id]
		if row.get("type","") == "terrain": brushes[id] = row
	return CACHE_REVISION+":"+str(brushes.hash())

static func write(source: Node3D, paths: Array[String], folder: String, generation: int, area: String, tree: SceneTree, progress: Callable, cancelled: Callable, document: Dictionary = {}) -> Array:
	var tiles: Array = []
	var inverse := source.global_transform.affine_inverse()
	var fields := {}
	for target in ["mountain","motocross"]:
		var field := preload("res://world/editing/WorldTerrainEdits.gd").new()
		field.configure(document,target,area)
		fields[target] = field
	var paint_colors := [Color("5e7a45"),Color("8b6245"),Color("cbb379"),Color("929089"),Color("6c7376"),Color("dee5e5"),Color("484d50")]
	var grass_image: Image
	var earth_image: Image
	if not fields.mountain.brushes.is_empty() or not fields.motocross.brushes.is_empty():
		grass_image = Image.load_from_file("res://assets/materials/woodland/woodland.png")
		earth_image = Image.load_from_file("res://assets/materials/woodland/earth.png")
	for index in paths.size():
		if cancelled.call(): return []
		var node := source.get_node_or_null(paths[index]) as MeshInstance3D
		if node == null or node.mesh == null: continue
		var field = fields["motocross" if node.name in [&"QuarryHills",&"DirtTrack",&"SculptedBanks"] else "mountain"]
		var source_ids: Array[String] = []
		var owner: Node = node
		while owner != null:
			for key in ["editor_id","world_edit_piece_id"]:
				var id := str(owner.get_meta(key,""))
				if key == "world_edit_piece_id" and not id.is_empty() and not id.begins_with("piece/"): id = "piece/"+id
				if not id.is_empty() and id not in source_ids: source_ids.append(id)
			if owner == source: break
			owner = owner.get_parent()
		progress.call("Desenhando relevo 2D",index,paths.size(),false)
		var transform := inverse*node.global_transform
		var bounds: AABB = transform*node.mesh.get_aabb()
		if bounds.size.x < .01 or bounds.size.z < .01: continue
		var size := Vector2i(clampi(ceili(bounds.size.x*2.0),16,256),clampi(ceili(bounds.size.z*2.0),16,256))
		var image := Image.create(size.x,size.y,false,Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		var heights := PackedFloat32Array()
		heights.resize(size.x*size.y)
		heights.fill(-INF)
		var faces: PackedVector3Array = node.mesh.get_faces()
		var began := Time.get_ticks_usec()
		for face in range(0,faces.size()-2,3):
			var a: Vector3 = transform*faces[face]
			var b: Vector3 = transform*faces[face+1]
			var c: Vector3 = transform*faces[face+2]
			var ab := Vector2(b.x-a.x,b.z-a.z)
			var ac := Vector2(c.x-a.x,c.z-a.z)
			var determinant := ab.cross(ac)
			if absf(determinant) < .00001: continue
			var extent := Vector2(bounds.size.x,bounds.size.z)
			var origin := Vector2(bounds.position.x,bounds.position.z)
			var lower := Vector2(minf(a.x,minf(b.x,c.x)),minf(a.z,minf(b.z,c.z)))
			var upper := Vector2(maxf(a.x,maxf(b.x,c.x)),maxf(a.z,maxf(b.z,c.z)))
			var lo := Vector2i(((lower-origin)/extent*Vector2(size)).floor()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
			var hi := Vector2i(((upper-origin)/extent*Vector2(size)).ceil()).clamp(Vector2i.ZERO,size-Vector2i.ONE)
			var normal := (b-a).cross(c-a).normalized()
			if normal.y < 0: normal = -normal
			var shade := clampf(.50+normal.dot(Vector3(-.4,.8,-.45).normalized())*.5,.25,1.0)
			for z in range(lo.y,hi.y+1):
				for x in range(lo.x,hi.x+1):
					var at := origin+(Vector2(x,z)+Vector2.ONE*.5)/Vector2(size)*extent
					var delta := at-Vector2(a.x,a.z)
					var u := delta.cross(ac)/determinant
					var v := ab.cross(delta)/determinant
					if u < -.00001 or v < -.00001 or u+v > 1.00001: continue
					var height := a.y+(b.y-a.y)*u+(c.y-a.y)*v
					var pixel := z*size.x+x
					if height < heights[pixel]: continue
					heights[pixel] = height
					var color := Color("6f8461")
					if area == "desert": color = Color("c5a66b")
					elif area == "mountain": color = Color("81958a").lerp(Color("d5dddd"),clampf(height/10.0,0,1))
					elif node.name in [&"QuarryHills",&"DirtTrack",&"SculptedBanks"]: color = Color("9a805c").lerp(Color("b9a383"),clampf(height/14.0,0,1))
					if not field.brushes.is_empty():
						var weights: PackedFloat32Array = field.paint_weights(at,node.name == &"DirtTrack")
						var remaining := 1.0
						var painted := Color(0,0,0,1)
						var finishes: Array = paint_colors
						var coverage := 0.0
						for weight in weights: coverage += weight
						if coverage > .001 and grass_image != null and earth_image != null:
							finishes = material_samples(at,grass_image,earth_image)
						for material in weights.size():
							remaining -= weights[material]
							painted += finishes[material]*weights[material]
						color = color*maxf(0,remaining)+painted
					var contour := .86 if fposmod(height,2.0) < .14 else 1.0
					image.set_pixel(x,z,Color(color.r*shade*contour,color.g*shade*contour,color.b*shade*contour,1))
			if Time.get_ticks_usec()-began > 6000:
				await tree.process_frame
				if cancelled.call(): return []
				progress.call("Desenhando relevo 2D",index,paths.size(),false)
				began = Time.get_ticks_usec()
		var path := folder+"/topo_%d_%d.png" % [generation,index]
		if image.save_png(path) == OK: tiles.append({"path":path,"bounds":[bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z],"height":bounds.position.y,"source_ids":source_ids})
		await tree.process_frame
	tiles.sort_custom(func(a,b): return float(a.height) < float(b.height))
	progress.call("Relevo 2D pronto",paths.size(),paths.size(),true)
	return tiles

static func sample_repeat(image: Image, point: Vector2) -> Color:
	return image.get_pixel(posmod(floori(point.x*image.get_width()),image.get_width()),posmod(floori(point.y*image.get_height()),image.get_height()))

## Same source textures, world UV scales and material formulas as
## world/editing/terrain_paint.gdshaderinc. Height shading stays readable in 2D.
static func material_samples(point: Vector2, grass_image: Image, earth_image: Image) -> Array:
	var grass := sample_repeat(grass_image,point*.16)
	var earth := sample_repeat(earth_image,point*.045).lerp(sample_repeat(earth_image,point*.65),.32)
	var grain := sample_repeat(earth_image,point*1.25).r
	var luminance := earth.r*.299+earth.g*.587+earth.b*.114
	return [grass,earth,Color(.68,.58,.39)*(.76+luminance*.9),Color(.40,.43,.40)*(.72+grain*.8),Color(.38,.42,.42)*(.72+grain*.6),Color(.79,.83,.82)*(.93+grain*.12),Color(.14,.16,.16)*(.82+grain*.3)]
