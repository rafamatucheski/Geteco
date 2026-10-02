extends RefCounted
## Shared generation pass over the baked fleet. Never edits the source scenes.
## Geometry/materials are cached; no additional lights, viewports or frame loop.
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const PAINT := preload("res://runtime/VehiclePaint.gd")
const CABINS := {
	"taxi_yellow": [.78,.66,.81,1.32,-.98,-.64,.90,1.20,.12],
	# half width (belt/roof), belt/roof height, windshield bottom/top, rear top/bottom.
	"union_sedan": [.78,.66,.81,1.32,-.98,-.64,.90,1.20,.12],
	"sedan_classic": [.78,.66,.81,1.32,-.98,-.64,.90,1.20,.12],
	"metro_hatch": [.77,.62,.78,1.315,-.94,-.66,1.32,1.52,-.05],
	"ranch_single": [.86,.77,1.02,1.45,-1.10,-.91,.09,.13,-.05],
	"ranch_pickup": [.86,.77,1.02,1.45,-1.10,-.91,.09,.13,-.05],
	"lumber_pickup_4x4": [.86,.77,1.02,1.45,-1.10,-.91,.09,.13,-.05],
	"courier_van": [.90,.84,.99,1.94,-1.72,-1.42,-.47,-.46,-.6],
	"polar_van": [.90,.84,.99,1.94,-1.72,-1.42,-.47,-.46,-.6],
	"police_transport": [.90,.84,.99,1.94,-1.72,-1.42,-.47,-.46,-.6],
}
static var _shapes: Dictionary = {}
static var _materials: Dictionary = {}
static var _cabins: Dictionary = {}
static var _filtered: Dictionary = {}
static var _van_body: ArrayMesh
static var _glass_texture: ImageTexture
static var _lamp_offsets: Dictionary = {}

static func decorate(id: String, model: Node3D) -> void:
	if model.has_meta("fleet_finish"): return
	model.set_meta("fleet_finish",true)
	var source := PAINT.source_for(id)
	var cabin_parts: Dictionary = {}
	var van := id in ["courier_van","polar_van","police_transport"]
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.has_meta("wheel_center") or part.has_meta("heavy_detail"): continue
		for surface in (1 if part.material_override != null else part.mesh.get_surface_count()):
			var original := part.get_active_material(surface) as StandardMaterial3D
			if original == null: continue
			var key := ROLES.key(part,surface)
			var is_glass := "glass" in key or "windshield" in key or key == "window"
			# Old exports have no semantic names, but a distinct glass recipe.
			is_glass = is_glass or (key == "" and original.cull_mode == BaseMaterial3D.CULL_DISABLED and original.metallic >= .3 and original.roughness <= .18 and not original.emission_enabled)
			var is_paint := key == "paint" or (key == "" and not source.is_empty() and original.albedo_color.is_equal_approx(Color.html(source.color)) and is_equal_approx(original.metallic,float(source.metallic)) and is_equal_approx(original.roughness,float(source.roughness)) and not original.emission_enabled)
			if not is_glass and not is_paint: continue
			if is_glass and id in CABINS:
				if not cabin_parts.has(part): cabin_parts[part] = []
				cabin_parts[part].append(surface)
				continue
			var recipe := [original, "glass" if is_glass else "paint"]
			if not _materials.has(recipe):
				var material := original.duplicate() as StandardMaterial3D
				material.resource_name = "glass" if is_glass else "paint"
				material.clearcoat_enabled = true
				material.clearcoat = .65 if is_glass else .15
				material.clearcoat_roughness = .12 if is_glass else .45
				if is_glass:
					material.albedo_color = Color("7896a6")
					material.albedo_texture = _glazing_texture()
					material.metallic = .28
					material.roughness = .12
				else:
					# Broad, subdued paint highlights keep the body color readable on
					# horizontal panels. Preserve authored finishes that are rougher.
					material.roughness = maxf(material.roughness,.6)
					material.metallic_specular = minf(material.metallic_specular,.25)
				_materials[recipe] = material
			if part.material_override != null: part.material_override = _materials[recipe]
			else: part.set_surface_override_material(surface,_materials[recipe])
			if is_paint and van and part.mesh is ArrayMesh and part.mesh.get_surface_count() == 1:
				if _van_body == null: _van_body = _build_van_body()
				part.mesh = _van_body
				part.transform = Transform3D.IDENTITY
			if is_paint and part.mesh is BoxMesh:
				if van and part.mesh.size.is_equal_approx(Vector3(1.8,.95,1.15)):
					# The old solid upper cab buried the entire windshield.
					part.position = Vector3(0,2.015,-.955)
					var roof := BoxMesh.new()
					roof.size = Vector3(1.8,.15,1.09)
					part.mesh = roof
				elif van and part.mesh.size.is_equal_approx(Vector3(1.9,1.185,3.35)):
					var cargo := BoxMesh.new()
					cargo.size = Vector3(1.9,1.185,2.83)
					part.mesh = cargo
					part.position.z = .96
				# Keep all authored extents and axle anchors, soften only box panels.
				var size: Vector3 = part.mesh.size
				if size.x > .09 and size.z > .07:
					if not _shapes.has(size): _shapes[size] = _beveled_box(size)
					part.mesh = _shapes[size]
	if id in CABINS:
		# Replace the rectangular glass walls with one closed tapered greenhouse.
		for part in cabin_parts:
			if part.mesh.get_surface_count() <= cabin_parts[part].size(): part.free()
			else: _remove_glass_surfaces(part,cabin_parts[part])
		for part in model.get_children():
			if not part is MeshInstance3D or part.mesh == null: continue
			var bounds: AABB = part.transform * part.get_aabb()
			# Remove the old floating B pillars and pickup glass fixup borders.
			var old_pillar := id in ["union_sedan","sedan_classic","metro_hatch"] and bounds.size.x < .07 and bounds.size.y > .35 and bounds.size.z < .15 and absf(bounds.get_center().y-1.05) < .03
			if old_pillar or (part.has_meta("fleet_fixup") and bounds.get_center().y > 1.0): part.free()
		if not _cabins.has(id): _cabins[id] = _build_cabin(CABINS[id],id == "metro_hatch",van)
		var glass := MeshInstance3D.new()
		glass.name = "SculptedCabin"
		glass.mesh = _cabins[id]
		glass.set_meta("finish_surface_material_keys",["glass","trim"])
		model.add_child(glass)
	_seat_lenses(id,model)

static func _glazing_texture() -> ImageTexture:
	if _glass_texture != null: return _glass_texture
	# Soft sky bands keep glass readable under the game's flat ambient fill;
	# specular/clearcoat still respond to real lights. Opaque, shared, no probe.
	var image := Image.create(64,64,false,Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var u := x/63.0
			var v := y/63.0
			var band := exp(-pow((u*.6+v-.55)/.14,2.0))*.26
			var value := .35+(1.0-v)*.3+band
			image.set_pixel(x,y,Color(value*.88,value*.96,value))
	_glass_texture = ImageTexture.create_from_image(image)
	return _glass_texture

static func _seat_lenses(id: String, model: Node3D) -> void:
	var parts := model.find_children("*","MeshInstance3D",true,false)
	if not _lamp_offsets.has(id):
		var offsets := {}
		var paint_faces: Array = []
		for part: MeshInstance3D in parts:
			if part.mesh == null or part.has_meta("wheel_center"): continue
			var material := part.get_active_material(0)
			if material == null or material.resource_name != "paint": continue
			var vertices := part.mesh.get_faces()
			for i in vertices.size(): vertices[i] = part.transform*vertices[i]
			paint_faces.append(vertices)
		for part: MeshInstance3D in parts:
			if part.mesh == null or part.mesh.get_surface_count() != 1: continue
			var key := ROLES.key(part,0)
			var material := part.get_active_material(0) as StandardMaterial3D
			if material == null: continue
			var box: AABB = part.transform*part.get_aabb()
			var center := box.get_center()
			var tail := "tail" in key or key == "brake_light" or (key.is_empty() and material.emission_enabled and material.albedo_color.r > .55 and material.albedo_color.g < .35)
			if not tail or center.z <= 0 or box.size.z > .15: continue
			var hit_z := -INF
			for vertices in paint_faces:
				for i in range(0,vertices.size(),3):
					var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(center.x,center.y,20),Vector3.FORWARD,vertices[i],vertices[i+1],vertices[i+2])
					if hit != null: hit_z = maxf(hit_z,hit.z)
			if is_finite(hit_z):
				var shift := hit_z+.012-box.position.z
				if absf(shift) < .2: offsets[str(model.get_path_to(part))] = shift
		_lamp_offsets[id] = offsets
	for path in _lamp_offsets[id]:
		var part := model.get_node_or_null(NodePath(path)) as MeshInstance3D
		if part != null: part.position.z += float(_lamp_offsets[id][path])

static func _remove_glass_surfaces(part: MeshInstance3D, removed: Array) -> void:
	# A merged surface is not a whole vehicle part: preserve bed, bumpers, bars,
	# chrome and indicators that were exported alongside the glazing.
	var source: Mesh = part.mesh
	var roles: Array[String] = []
	var materials: Array[Material] = []
	for i in source.get_surface_count():
		if i not in removed:
			roles.append(ROLES.key(part,i))
			materials.append(part.get_active_material(i))
	if not _filtered.has(source):
		var mesh := ArrayMesh.new()
		for i in source.get_surface_count():
			if i not in removed: mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,source.surface_get_arrays(i))
		_filtered[source] = mesh
	for i in source.get_surface_count(): part.set_surface_override_material(i,null)
	part.mesh = _filtered[source]
	for i in materials.size(): part.set_surface_override_material(i,materials[i])
	for meta in part.get_meta_list():
		if str(meta).ends_with("surface_material_keys") or str(meta).ends_with("surface_material_roles"): part.set_meta(meta,roles)

static func _build_van_body() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for box in [
		[Vector3(0,.72,-1.75),Vector3(1.86,.44,1.25)],
		[Vector3(0,.72,.625),Vector3(1.92,.44,3.5)],
		[Vector3(0,1.5325,.96),Vector3(1.9,1.185,2.83)],
		[Vector3(0,2.015,-.955),Vector3(1.8,.15,1.09)],
	]:
		st.append_from(_beveled_box(box[1]),0,Transform3D(Basis.IDENTITY,box[0]))
	return st.commit()

static func _quad(st: SurfaceTool, points: Array, outward: Vector3) -> void:
	points = points.duplicate()
	var normal: Vector3 = (points[1]-points[0]).cross(points[2]-points[0]).normalized()
	if normal.dot(outward) < 0: points.reverse(); normal = -normal
	# Godot front faces wind clockwise when viewed from outside.
	for i in [0,2,1,0,3,2]:
		st.set_normal(normal)
		st.set_uv([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)][i])
		st.add_vertex(points[i])

static func _ring(x: float, z: float, y: float, bevel: float) -> Array:
	return [Vector3(-x+bevel,y,-z),Vector3(x-bevel,y,-z),Vector3(x,y,-z+bevel),Vector3(x,y,z-bevel),Vector3(x-bevel,y,z),Vector3(-x+bevel,y,z),Vector3(-x,y,z-bevel),Vector3(-x,y,-z+bevel)]

static func _beveled_box(size: Vector3) -> ArrayMesh:
	var half := size*.5
	var b := minf(.065,minf(half.x,half.z)*.22)
	var by := minf(b,half.y*.45)
	var rings := [_ring(half.x-b*.4,half.z-b*.4,-half.y,b),_ring(half.x,half.z,-half.y+by,b),_ring(half.x,half.z,half.y-by,b),_ring(half.x-b*.6,half.z-b*.6,half.y,b)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level in 3:
		for i in 8:
			var next := (i+1)%8
			var center: Vector3 = (rings[level][i]+rings[level][next])*.5
			_quad(st,[rings[level][i],rings[level][next],rings[level+1][next],rings[level+1][i]],Vector3(center.x,0,center.z))
	for cap in [0,3]:
		var normal := Vector3.DOWN if cap == 0 else Vector3.UP
		for i in 8:
			var a: Vector3 = rings[cap][i]
			var bpt: Vector3 = rings[cap][(i+1)%8]
			var c := Vector3(0,a.y,0)
			var triangle := [c,a,bpt] if (a-c).cross(bpt-c).dot(normal) < 0 else [c,bpt,a]
			for p in triangle:
				st.set_normal(normal)
				st.set_uv(Vector2(p.x/size.x+.5,p.z/size.z+.5))
				st.add_vertex(p)
	return st.commit()

static func _build_cabin(p: Array, hatch: bool, van: bool) -> ArrayMesh:
	var glass := StandardMaterial3D.new()
	glass.resource_name = "glass"
	glass.albedo_color = Color("7896a6")
	glass.albedo_texture = _glazing_texture()
	glass.metallic = .28
	glass.roughness = .12
	glass.clearcoat_enabled = true
	glass.clearcoat = .8
	glass.clearcoat_roughness = .08
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var trim := StandardMaterial3D.new()
	trim.resource_name = "trim"
	trim.albedo_color = Color("17212a")
	trim.roughness = .48
	var windows := SurfaceTool.new()
	windows.begin(Mesh.PRIMITIVE_TRIANGLES)
	windows.set_material(glass)
	var borders := SurfaceTool.new()
	borders.begin(Mesh.PRIMITIVE_TRIANGLES)
	borders.set_material(trim)
	var front := [Vector3(-p[0],p[2],p[4]),Vector3(p[0],p[2],p[4]),Vector3(p[1],p[3],p[5]),Vector3(-p[1],p[3],p[5])]
	var rear := [Vector3(p[0],p[2],p[7]),Vector3(-p[0],p[2],p[7]),Vector3(-p[1],p[3],p[6]),Vector3(p[1],p[3],p[6])]
	_window(windows,borders,front,Vector3.FORWARD)
	if not van: _window(windows,borders,rear,Vector3.BACK)
	for side in [-1.0,1.0]:
		var a := Vector3(side*p[0],p[2],p[4])
		var b := Vector3(side*p[0],p[2],p[7])
		var c := Vector3(side*p[1],p[3],p[6])
		var d := Vector3(side*p[1],p[3],p[5])
		if p[6]-p[5] > 1.3:
			var cut: float = p[8]+(.3 if hatch else 0.0)
			var bottom := Vector3(side*p[0],p[2],cut)
			var top := Vector3(side*p[1],p[3],cut)
			_window(windows,borders,[a,bottom,top,d],Vector3(side,0,0))
			_window(windows,borders,[bottom,b,c,top],Vector3(side,0,0))
		else: _window(windows,borders,[a,b,c,d],Vector3(side,0,0))
	var mesh := windows.commit()
	borders.commit(mesh)
	return mesh

static func _window(glass: SurfaceTool, frame: SurfaceTool, corners: Array, normal: Vector3) -> void:
	var middle := Vector3.ZERO
	for p: Vector3 in corners: middle += p*.25
	var inset := []
	for p: Vector3 in corners: inset.append(p.lerp(middle,.09))
	_quad(glass,inset,normal)
	for i in 4: _quad(frame,[corners[i],corners[(i+1)%4],inset[(i+1)%4],inset[i]],normal)
