extends SceneTree
## Offline extraction of complete damage panels from the current authored fleet.
## Never overwrites the original presentation. No cutting runs during gameplay.
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const OUTPUT := "res://assets/fleet/breakaway"
const SOURCES := {
	"sport_coupe": "res://assets/fleet/sport_coupe.scn",
	"monaliza": "res://assets/fleet/redesigned/monaliza.scn",
	"metro_hatch": "res://assets/fleet/redesigned/metro_hatch.scn",
	"police_cruiser": "res://assets/fleet/redesigned/police_cruiser.scn",
}
## Per-model extraction regions isolate the engine cover and low bumper bodies;
## lamps/glass, wheels and authored door leaves remain untouched. Model metres.
const PROFILES := {
	"sport_coupe": {"hood": AABB(Vector3(-.72,.70,-1.98),Vector3(1.44,.36,1.20)), "front": -2.12, "rear": 2.14, "bumper_top": .59},
	"monaliza": {"hood": AABB(Vector3(-.73,.70,-2.06),Vector3(1.46,.46,1.25)), "front": -2.19, "rear": 2.17, "bumper_top": .64},
	"metro_hatch": {"hood": AABB(Vector3(-.64,.70,-1.65),Vector3(1.28,.46,1.02)), "front": -1.72, "rear": 1.69, "bumper_top": .65},
	"police_cruiser": {"hood": AABB(Vector3(-.74,.70,-2.10),Vector3(1.48,.50,1.30)), "front": -2.19, "rear": 2.18, "bumper_top": .67},
}
var failures: Array[String] = []
var steel: StandardMaterial3D
var hardware_vertices: Array = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	steel = StandardMaterial3D.new()
	steel.resource_name = "damage_hardware"
	steel.vertex_color_use_as_albedo = true
	steel.albedo_color = Color.WHITE
	steel.metallic = .45
	steel.roughness = .68
	var manifest := {"version":1, "models":{}}
	var only := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--only="): only = argument.trim_prefix("--only=")
	if not only.is_empty():
		if not SOURCES.has(only): fail("unsupported --only model "+only); quit(1); return
		if FileAccess.file_exists(OUTPUT.path_join("manifest.json")):
			var previous: Variant = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT.path_join("manifest.json")))
			if not previous is Dictionary or not previous.get("models") is Dictionary:
				fail("cannot preserve existing manifest for targeted bake"); quit(1); return
			manifest = previous
	for id: String in SOURCES:
		if not only.is_empty() and id != only: continue
		# The canonical factory also applies any model-specific finishing pass.
		# VehiclePanelCatalog is selected by Vehicle, not by this factory.
		var model := FLEET.create(id)
		if model == null: fail(id + " missing source"); continue
		var report := prepare(model,id)
		if report.is_empty(): model.free(); continue
		model.set_meta("breakaway_geometry_version",1)
		model.set_meta("breakaway_source_sha256",FileAccess.get_sha256(SOURCES[id]))
		own(model,model)
		var packed := PackedScene.new()
		var result := packed.pack(model)
		if result == OK: result = ResourceSaver.save(packed,OUTPUT.path_join(id+".scn"),ResourceSaver.FLAG_BUNDLE_RESOURCES)
		if result != OK: fail(id+" save status="+str(result))
		report["source"] = SOURCES[id]
		report["source_sha256"] = FileAccess.get_sha256(SOURCES[id])
		manifest.models[id] = report
		print("BREAKAWAY_GEOMETRY ",id," ",JSON.stringify(report))
		model.free()
	var file := FileAccess.open(OUTPUT.path_join("manifest.json"),FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(manifest,"\t")); file.close()
	print("BREAKAWAY_GEOMETRY_RESULT failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func fail(message: String) -> void:
	failures.append(message)
	push_error(message)

func own(node: Node, ancestor: Node) -> void:
	for child in node.get_children():
		child.owner = ancestor
		own(child,ancestor)

func relative(model: Node3D, node: Node3D) -> Transform3D:
	var result := node.transform
	var parent := node.get_parent()
	while parent != model and parent is Node3D:
		result = parent.transform * result
		parent = parent.get_parent()
	return result

func prepare(model: Node3D, id: String) -> Dictionary:
	hardware_vertices.clear()
	var original_counts := count_geometry(model)
	var config: Dictionary = PROFILES[id]
	var zones := {"hood": config.hood,
		"bumper_front":AABB(Vector3(-2,.12,-4),Vector3(4,float(config.bumper_top)-.12,4+float(config.front))),
		"bumper_rear":AABB(Vector3(-2,.12,float(config.rear)),Vector3(4,float(config.bumper_top)-.12,4-float(config.rear)))}
	var buckets := {"hood":{}, "bumper_front":{}, "bumper_rear":{}}
	var removed_area := {"hood":0.0,"bumper_front":0.0,"bumper_rear":0.0}
	var source_area := 0.0
	var kept_area := 0.0
	var source_triangles := 0
	var changed_nodes := 0
	for node: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if node.mesh == null or node.has_meta("wheel_center") or node.has_meta("coupe_gt_door_side") or node.has_meta("new_civilian_door_side"): continue
		var xf := relative(model,node)
		var rebuilt := ArrayMesh.new()
		var role_keys: Array = []
		var changed := false
		for surface in node.mesh.get_surface_count():
			var role := ROLES.key(node,surface)
			var material := node.get_active_material(surface)
			var arrays := node.mesh.surface_get_arrays(surface)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else points.size()
			var keep: Array = []
			var surface_changed := false
			var eligible := role.get_slice("#",0) in ["paint","detail","trim","rubber","chrome","alloy"]
			for first in range(0,count,3):
				var polygon: Array = []
				for offset in 3:
					var index := indices[first+offset] if not indices.is_empty() else first+offset
					polygon.append(vertex(arrays,index,xf))
				var area := polygon_area(polygon)
				source_area += area
				source_triangles += 1
				var fragments: Array = [polygon]
				if eligible:
					for panel_id: String in zones:
						var remaining: Array = []
						for fragment: Array in fragments:
							var normal := ((fragment[1][0] as Vector3)-(fragment[0][0] as Vector3)).cross((fragment[2][0] as Vector3)-(fragment[0][0] as Vector3)).normalized()
							if panel_id == "hood" and absf(normal.y) < .50: remaining.append(fragment); continue
							if panel_id == "hood" and id == "sport_coupe" and not sport_hood_skin(fragment,role): remaining.append(fragment); continue
							var split := clip_box(fragment,zones[panel_id])
							var inside: Array = split[0]
							if not inside.is_empty():
								surface_changed = true
								removed_area[panel_id] += polygon_area(inside)
								add_bucket(buckets[panel_id],material,role,inside)
							remaining.append_array(split[1])
						fragments = remaining
				for fragment: Array in fragments:
					kept_area += polygon_area(fragment)
					append_fan(keep,fragment)
			if keep.is_empty(): changed = true; continue
			if not surface_changed:
				rebuilt.add_surface_from_arrays(node.mesh.surface_get_primitive_type(surface),arrays)
			else:
				changed = true
				# Convert split vertices back to the source node's local frame.
				var inverse := xf.affine_inverse()
				for v: Array in keep:
					v[0] = inverse * (v[0] as Vector3)
					v[1] = (xf.basis.transposed() * (v[1] as Vector3)).normalized()
					var tangent: Vector4 = v[5]
					var tangent_direction := (inverse.basis * Vector3(tangent.x,tangent.y,tangent.z)).normalized()
					v[5] = Vector4(tangent_direction.x,tangent_direction.y,tangent_direction.z,tangent.w)
				rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,to_arrays(keep))
			rebuilt.surface_set_material(rebuilt.get_surface_count()-1,material)
			role_keys.append(role)
		if changed:
			changed_nodes += 1
			if rebuilt.get_surface_count() == 0: node.free(); continue
			# Captured active materials are now on rebuilt; clear old overrides while
			# their original surface indices are still valid, before compaction.
			for surface in node.get_surface_override_material_count(): node.set_surface_override_material(surface,null)
			node.mesh = rebuilt
			node.material_override = null
			set_roles(node,role_keys)
	var sum_removed: float = removed_area.hood+removed_area.bumper_front+removed_area.bumper_rear
	var conservation_error := absf(source_area-kept_area-sum_removed)
	if conservation_error > .001: fail(id+" exterior area conservation="+str(conservation_error)); return {}
	var report := {"source_triangles":source_triangles,"modified_nodes":changed_nodes,"exterior_area_error":conservation_error,"parts":{}}
	for panel_id: String in buckets:
		if float(removed_area[panel_id]) < .045:
			fail(id+" missing meaningful panel "+panel_id+" area="+str(removed_area[panel_id])); return {}
		var panel := MeshInstance3D.new()
		panel.name = "Breakaway_"+panel_id
		panel.mesh = build_panel(buckets[panel_id],panel_id)
		var roles: Array = []
		for entry: Dictionary in buckets[panel_id].values(): roles.append(entry.role)
		roles.append("damage_hardware")
		set_roles(panel,roles)
		var bounds := panel.mesh.get_aabb()
		var pivot := Vector3(0,bounds.get_center().y,bounds.end.z) if panel_id == "hood" else bounds.get_center()
		panel.set_meta("breakaway_part_id",panel_id)
		panel.set_meta("breakaway_pivot",pivot)
		panel.set_meta("breakaway_bounds",bounds)
		panel.set_meta("breakaway_local_direction",Vector3.UP if panel_id == "hood" else (Vector3.FORWARD if panel_id == "bumper_front" else Vector3.BACK))
		model.add_child(panel)
		report.parts[panel_id] = {"area":removed_area[panel_id],"triangles":panel.mesh.get_faces().size()/3,"bounds":str(bounds)}
		if panel_id == "hood": add_engine_bay(model,bounds)
		else: add_bumper_support(model,bounds,panel_id)
	attach_hardware(model,"BreakawayHardware",hardware_vertices)
	report["geometry_before"] = original_counts
	report["geometry_after"] = count_geometry(model)
	return report

## The coupe author merges painted headlamp nacelles into Shell. A box alone
## also extracts their inner halves. Select the actual bonnet skin using the
## author's hood(u,z) surface (build_sport_coupe_gt.gd), keeping those lamp
## supports and trim on the car. The authored crest is the one raised detail.
func sport_hood_skin(polygon: Array, role: String) -> bool:
	var crest := role.get_slice("#",0) == "detail"
	for item: Array in polygon:
		var point: Vector3 = item[0]
		crest = crest and absf(point.x) <= .06 and point.z >= -1.98 and point.z <= -1.88
	if crest: return true
	var tolerance := .003 if role.get_slice("#",0) == "paint" else .010
	for item: Array in polygon:
		var point: Vector3 = item[0]
		var z := point.z
		var width := lerpf(.83,.99,clampf((z+2.23)/.43,0,1)) if z < -1.8 else .91+.115*exp(-pow((z+1.28)/.42,2))
		var center_y := lerpf(.72,.81,clampf((z+2.23)/1.5,0,1))
		var belt := .82+.115*exp(-pow((z+1.28)/.44,2))+.08*exp(-pow((z-1.22)/.50,2))-.11*clampf((-z-1.85)/.38,0,1)
		var skin_y := center_y+pow(absf(point.x/(width-.055)),2.3)*(belt-center_y)
		if absf(point.y-skin_y)>tolerance: return false
	return true

func count_geometry(model: Node3D) -> Dictionary:
	var counts := {"meshes":0,"surfaces":0,"triangles":0}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		counts.meshes += 1
		counts.surfaces += part.mesh.get_surface_count()
		counts.triangles += part.mesh.get_faces().size()/3
	return counts

func set_roles(node: MeshInstance3D, roles: Array) -> void:
	for meta in node.get_meta_list():
		if str(meta).ends_with("surface_material_keys") or str(meta).ends_with("surface_material_roles") or str(meta).ends_with("material_key") or str(meta).ends_with("material_role"): node.remove_meta(meta)
	node.set_meta("breakaway_surface_material_keys",roles)

func vertex(arrays: Array, index: int, xf: Transform3D) -> Array:
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
	var tangent := Vector4.ZERO
	if index*4+3 < tangents.size():
		var direction := (xf.basis*Vector3(tangents[index*4],tangents[index*4+1],tangents[index*4+2])).normalized()
		tangent = Vector4(direction.x,direction.y,direction.z,tangents[index*4+3])
	return [xf*(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[index],(xf.basis.inverse().transposed()*normals[index]).normalized() if index<normals.size() else Vector3.UP,uv[index] if index<uv.size() else Vector2.ZERO,colors[index] if index<colors.size() else Color.WHITE,uv2[index] if index<uv2.size() else Vector2.ZERO,tangent]

func interpolate(a: Array,b: Array,t: float) -> Array:
	var ta: Vector4=a[5]
	var tb: Vector4=b[5]
	var direction:=Vector3(ta.x,ta.y,ta.z).lerp(Vector3(tb.x,tb.y,tb.z),t).normalized()
	return [(a[0] as Vector3).lerp(b[0],t),((a[1] as Vector3).lerp(b[1],t)).normalized(),(a[2] as Vector2).lerp(b[2],t),(a[3] as Color).lerp(b[3],t),(a[4] as Vector2).lerp(b[4],t),Vector4(direction.x,direction.y,direction.z,ta.w)]

func split_plane(polygon: Array, axis: int, value: float) -> Array:
	var above: Array = []
	var below: Array = []
	for i in polygon.size():
		var a: Array = polygon[i]
		var b: Array = polygon[(i+1)%polygon.size()]
		var da: float = (a[0] as Vector3)[axis]-value
		var db: float = (b[0] as Vector3)[axis]-value
		if da>=0: above.append(a)
		else: below.append(a)
		if (da>=0)!=(db>=0):
			var mid := interpolate(a,b,da/(da-db))
			above.append(mid)
			below.append(mid)
	return [above,below]

func clip_box(polygon: Array, box: AABB) -> Array:
	var current := polygon
	var outside: Array = []
	for axis in 3:
		for high in [false,true]:
			var pieces := split_plane(current,axis,box.end[axis] if high else box.position[axis])
			var kept: Array = pieces[1] if high else pieces[0]
			var dropped: Array = pieces[0] if high else pieces[1]
			if dropped.size()>=3: outside.append(dropped)
			current = kept
			if current.size()<3: return [[],[polygon]]
	return [current,outside]

func polygon_area(polygon: Array) -> float:
	var result := 0.0
	for i in range(1,polygon.size()-1): result += ((polygon[i][0] as Vector3)-(polygon[0][0] as Vector3)).cross((polygon[i+1][0] as Vector3)-(polygon[0][0] as Vector3)).length()*.5
	return result

func append_fan(destination: Array, polygon: Array) -> void:
	for i in range(1,polygon.size()-1):
		for j in [0,i,i+1]: destination.append((polygon[j] as Array).duplicate())

func add_bucket(bucket: Dictionary, material: Material, role: String, polygon: Array) -> void:
	var key := str(material.get_instance_id())+"/"+role if material != null else role
	if not bucket.has(key): bucket[key] = {"material":material,"role":role,"vertices":[]}
	append_fan(bucket[key].vertices,polygon)

func to_arrays(vertices: Array) -> Array:
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var colors := PackedColorArray()
	var tangents := PackedFloat32Array()
	var has_tangents := false
	for v: Array in vertices:
		points.append(v[0]); normals.append(v[1]); uv.append(v[2]); colors.append(v[3]); uv2.append(v[4])
		var tangent: Vector4=v[5]
		tangents.append_array(PackedFloat32Array([tangent.x,tangent.y,tangent.z,tangent.w]))
		has_tangents=has_tangents or absf(tangent.w)>.5
	var result: Array = []
	result.resize(Mesh.ARRAY_MAX)
	result[Mesh.ARRAY_VERTEX]=points; result[Mesh.ARRAY_NORMAL]=normals
	result[Mesh.ARRAY_TEX_UV]=uv; result[Mesh.ARRAY_TEX_UV2]=uv2; result[Mesh.ARRAY_COLOR]=colors
	if has_tangents: result[Mesh.ARRAY_TANGENT]=tangents
	return result

func subdivide(a: Array,b: Array,c: Array,out: Array,depth: int = 0) -> void:
	var distances := [(a[0] as Vector3).distance_squared_to(b[0]),(b[0] as Vector3).distance_squared_to(c[0]),(c[0] as Vector3).distance_squared_to(a[0])]
	var longest := 0
	for i in range(1,3):
		if distances[i] > distances[longest]: longest=i
	if distances[longest]<=.09 or depth>=7:
		out.append(a); out.append(b); out.append(c); return
	var points := [a,b,c]
	var x: Array=points[longest]
	var y: Array=points[(longest+1)%3]
	var z: Array=points[(longest+2)%3]
	var mid:=interpolate(x,y,.5)
	subdivide(x,mid,z,out,depth+1)
	subdivide(mid,y,z,out,depth+1)

func build_panel(bucket: Dictionary, panel_id: String) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var underside: Array = []
	for group: Dictionary in bucket.values():
		var original: Array=group.vertices
		var refined: Array=[]
		for i in range(0,original.size(),3): subdivide(original[i],original[i+1],original[i+2],refined)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,to_arrays(refined))
		mesh.surface_set_material(mesh.get_surface_count()-1,group.material)
		for i in range(0,refined.size(),3):
			for j in [0,2,1]:
				var vertex_data: Array=(refined[i+j] as Array).duplicate()
				vertex_data[0]=(vertex_data[0] as Vector3)-(vertex_data[1] as Vector3)*.018
				vertex_data[1]=-(vertex_data[1] as Vector3)
				vertex_data[3]=Color("343b40") if panel_id=="hood" else Color("252b2f")
				underside.append(vertex_data)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,to_arrays(underside))
	mesh.surface_set_material(mesh.get_surface_count()-1,steel)
	return mesh

func add_box(vertices: Array, center: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size=size
	var arrays:=mesh.get_mesh_arrays()
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	for index in indices:
		var item:=vertex(arrays,index,Transform3D(Basis.IDENTITY,center))
		item[3]=color
		vertices.append(item)

func attach_hardware(model: Node3D,label: String,vertices: Array) -> void:
	var node:=MeshInstance3D.new()
	node.name=label
	node.set_meta("breakaway_hardware",true)
	var mesh:=ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,to_arrays(vertices))
	mesh.surface_set_material(0,steel)
	node.mesh=mesh
	set_roles(node,["damage_hardware"])
	model.add_child(node)

func add_engine_bay(model: Node3D,hood: AABB) -> void:
	var vertices: Array=[]
	var width:=hood.size.x
	var length:=hood.size.z
	var center:=hood.get_center()
	var base:=hood.position.y-.28
	add_box(vertices,Vector3(center.x,base,center.z),Vector3(width*.98,.07,length*.98),Color("141b20"))
	for side in [-1,1]: add_box(vertices,Vector3(center.x+side*width*.46,base+.10,center.z),Vector3(.065,.20,length*.96),Color("3c464d"))
	add_box(vertices,Vector3(center.x,base+.12,center.z+.02),Vector3(width*.47,.18,length*.56),Color("505960"))
	add_box(vertices,Vector3(center.x,base+.23,center.z+.02),Vector3(width*.36,.055,length*.47),Color("222b30"))
	for index in 5: add_box(vertices,Vector3(center.x-width*.14+index*width*.07,base+.262,center.z+.02),Vector3(.018,.012,length*.39),Color("78848a"))
	add_box(vertices,Vector3(center.x+width*.33,base+.12,center.z-.09),Vector3(width*.17,.15,length*.29),Color("151d23"))
	add_box(vertices,Vector3(center.x-width*.33,base+.10,center.z+.14),Vector3(width*.17,.12,length*.24),Color("acb5af"))
	add_box(vertices,Vector3(center.x,base+.10,hood.position.z+.06),Vector3(width*.82,.15,.07),Color("2e383f"))
	hardware_vertices.append_array(vertices)

func add_bumper_support(model: Node3D,bounds: AABB,panel_id: String) -> void:
	var vertices: Array=[]
	var center:=bounds.get_center()
	var inward:=.12 if panel_id=="bumper_front" else -.12
	add_box(vertices,Vector3(center.x,center.y,center.z+inward),Vector3(bounds.size.x*.82,.085,.075),Color("39444b"))
	for side in [-1,1]: add_box(vertices,Vector3(side*bounds.size.x*.27,center.y,center.z+inward*1.6),Vector3(.065,.10,.15),Color("202b31"))
	hardware_vertices.append_array(vertices)
