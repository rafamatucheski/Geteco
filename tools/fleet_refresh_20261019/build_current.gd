extends SceneTree
## Deterministic candidate authoring. Production is never overwritten by this
## script: the coordinator installs reviewed candidates after baseline capture.
const MESH=preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const ROLES=preload("res://runtime/VehicleSurfaceRoles.gd")
const OUT="res://artifacts/car-fleet-implementation-20261019/candidates"
const ORIGINALS="res://artifacts/car-fleet-implementation-20261019/originals-current"
const FAMILIES={"sedan_classic":"popular","union_sedan":"traditional","aurora_executive":"executive","metro_hatch":"popular","station_wagon":"traditional","desert_faisca":"sport","desert_faisca_rally":"sport","ranch_single":"work","ranch_pickup":"work"}

func _initialize() -> void: run.call_deferred()

func warp(p: Vector3,id: String) -> Vector3:
	var q:=p
	if id=="sedan_classic":
		# Short overhangs and a taller, upright popular cabin. Axles and the
		# complete door opening retain their X/Z positions.
		if absf(q.z)>1.75: q.z=signf(q.z)*(1.75+(absf(q.z)-1.75)*.68)
		if q.y>.78: q.y=.78+(q.y-.78)*1.14
	elif id=="union_sedan":
		# Strong traditional three-box profile: distinct horizontal rear deck
		# and broad shoulders, with its original front door kept intact.
		if q.y>.80 and q.z>.28:
			q.z+=.12*clampf((q.y-.80)/.58,0,1)*clampf((q.z-.28)/.50,0,1)
	elif id=="aurora_executive":
		# Low formal roof and a longer upper rear cabin. No physical wheelbase
		# or steering change accompanies the optical stretch.
		if q.y>.82:
			var h:=clampf((q.y-.82)/.62,0,1)
			q.y=.82+(q.y-.82)*.86
			if q.z>.30: q.z+=.15*h*clampf((q.z-.30)/.5,0,1)
	elif id=="metro_hatch":
		# Upright utilitarian tail, away from the sport hatch's raked rear glass.
		if q.z>.55 and q.y>.86:
			q.z+=.13*clampf((q.y-.86)/.5,0,1)*clampf((q.z-.55)/.4,0,1)
	elif id in ["desert_faisca","desert_faisca_rally"]:
		if q.y>.82:
			var h:=clampf((q.y-.82)/.70,0,1)
			q.y=.82+(q.y-.82)*.89
			if q.z>.4: q.z-=.24*h*clampf((q.z-.4)/.65,0,1)
	return q

func component_root(parents: PackedInt32Array,index: int) -> int:
	while parents[index]!=index: index=parents[index]
	return index

func lamp_mask(part: MeshInstance3D,arrays: Array,role: String,id: String) -> PackedByteArray:
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var mask:=PackedByteArray()
	mask.resize(vertices.size())
	if id!="aurora_executive" or role in ["paint","glass","roof_paint"]: return mask
	# Identify closed, disconnected light housings within consolidated trim.
	# Semantic lenses alone are insufficient: their black frames share large
	# body surfaces with unrelated details. Connectivity keeps those intact.
	var parents:=PackedInt32Array()
	parents.resize(vertices.size())
	var points:={}
	for i in vertices.size():
		parents[i]=i
		var p:=part.transform*vertices[i]
		var key:=Vector3i(roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000))
		if points.has(key): parents[i]=points[key]
		else: points[key]=i
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
	var count:=indices.size() if not indices.is_empty() else vertices.size()
	for first in range(0,count,3):
		var a:=indices[first] if not indices.is_empty() else first
		for offset in [1,2]:
			var b: int=indices[first+offset] if not indices.is_empty() else first+offset
			parents[component_root(parents,b)]=component_root(parents,a)
	var components:={}
	for i in vertices.size():
		var key:=component_root(parents,i)
		var p:=part.transform*vertices[i]
		components[key]=(components[key] as AABB).expand(p) if components.has(key) else AABB(p,Vector3.ZERO)
	var selected:={}
	for key in components:
		var box: AABB=components[key]
		var c:=box.get_center()
		if absf(c.z)<2.4 or absf(c.x)<.15 or c.y<.58 or box.size.x>.85 or box.size.y>.35 or box.size.z>.18: continue
		selected[key]=true
		print("AURORA_LAMP_COMPONENT ",role," ",box)
	for i in vertices.size():
		if selected.has(component_root(parents,i)): mask[i]=1
	return mask

func deform(part: MeshInstance3D,id: String) -> void:
	if part.mesh==null or part.has_meta("wheel_center"): return
	var fresh:=ArrayMesh.new()
	for surface in part.mesh.get_surface_count():
		var arrays:=part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
		var role: String=ROLES.key(part,surface)
		var lamps:=lamp_mask(part,arrays,role,id)
		var tail_bounds: Dictionary={}
		if ROLES.is_tail_lens(role):
			for p: Vector3 in vertices:
				var v:=part.transform*p
				var side:=signf(v.x)
				tail_bounds[side]=(tail_bounds[side] as AABB).expand(v) if tail_bounds.has(side) else AABB(v,Vector3.ZERO)
		for i in vertices.size():
			var p: Vector3=part.transform*vertices[i]
			var q:=warp(p,id)
			# Lens geometry changes keep the existing semantic material, state
			# and surface count; unrelated trim cannot become emissive.
			if ROLES.is_tail_lens(role) and id in ["sedan_classic","union_sedan","aurora_executive"]:
				var box: AABB=tail_bounds[signf(p.x)]
				var c:=box.get_center()
				var desired:=Vector2(.14,.23) if id=="sedan_classic" else (Vector2(.43,.12) if id=="union_sedan" else Vector2(.48,.065))
				q.x=c.x+(p.x-c.x)*desired.x/maxf(box.size.x,.001)
				q.y=c.y+(p.y-c.y)*desired.y/maxf(box.size.y,.001)
			if lamps[i]==1:
				var lens:=ROLES.is_tail_lens(role) or ROLES.is_headlight_lens(role) or role in ["lens","indicator"]
				# Keep the useful lens area, while seating the overly tall black
				# frame below the deck edge. Material/state/source counts survive.
				q.y-=.15 if p.z>0 else .14
				if not lens: q.y=(.51 if p.z>0 else .525)+(warp(p,id).y-.66)*.52
				# The old rear lamps sat above the deck and in front of its end
				# cap. Lowering them also requires seating their Z on the outside
				# face. Lenses stand 1 cm proud of trim, clear of coplanar shimmer.
				q.z+=(.075 if lens else .065) if p.z>0 else -.04
			vertices[i]=part.transform.affine_inverse()*q
			if i<normals.size():
				# Differential of the same warp keeps normals attached to the
				# transformed panels without changing indices or smoothing seams.
				var eps:=.001
				var jac:=Basis((warp(p+Vector3.RIGHT*eps,id)-warp(p-Vector3.RIGHT*eps,id))/(eps*2),(warp(p+Vector3.UP*eps,id)-warp(p-Vector3.UP*eps,id))/(eps*2),(warp(p+Vector3.BACK*eps,id)-warp(p-Vector3.BACK*eps,id))/(eps*2))
				normals[i]=(part.basis.transposed()*jac.inverse().transposed()*part.basis.inverse().transposed()*normals[i]).normalized()
				if lamps[i]==1 and not (ROLES.is_tail_lens(role) or ROLES.is_headlight_lens(role) or role in ["lens","indicator"]):
					normals[i]=(normals[i]/Vector3(1,.52,1)).normalized()
		arrays[Mesh.ARRAY_VERTEX]=vertices
		arrays[Mesh.ARRAY_NORMAL]=normals
		fresh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		fresh.surface_set_material(surface,part.get_active_material(surface))
	part.material_override=null
	for surface in part.get_surface_override_material_count(): part.set_surface_override_material(surface,null)
	part.mesh=fresh
	part.set_meta("batch_ratio",1.0)

func synchronize_role_maps(target: Node3D) -> Dictionary:
	var result:={}
	for part: MeshInstance3D in target.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null: continue
		# bake() writes the final material order here, but copies other metadata
		# aliases from preserved Body nodes. Utility originals carry a second
		# utility_surface_material_keys array. Rebuild every alias from the final
		# semantic order so lookup order cannot select an obsolete surface map.
		var canonical: Array=part.get_meta("batch_surface_material_keys",[])
		assert(canonical.size()==part.mesh.get_surface_count())
		for key in part.get_meta_list():
			if str(key).ends_with("surface_material_keys") or str(key).ends_with("surface_material_roles"):
				part.set_meta(key,canonical.duplicate())
		var rows:=[]
		for index in canonical.size():
			var mat:=part.get_active_material(index) as StandardMaterial3D
			rows.append({"surface":index,"role":canonical[index],"material_name":mat.resource_name if mat!=null else "","albedo":mat.albedo_color.to_html() if mat!=null else "","emissive":mat.emission_enabled if mat!=null else false})
		result[str(part.name)]=rows
	return result

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ORIGINALS))
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUT+"/current-manifest.json")) if FileAccess.file_exists(OUT+"/current-manifest.json") else {}
	var only:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): only=arg.trim_prefix("--id=")
		if arg.begins_with("--ids="): only=arg.trim_prefix("--ids=")
	for id: String in FAMILIES:
		if not only.is_empty() and id not in only.split(","): continue
		var original_path:=ORIGINALS+"/"+id+".scn"
		# Re-author from the immutable baseline even after production install.
		# Re-running must never compound the roof/overhang deformation.
		var source_path:=original_path if FileAccess.file_exists(original_path) else "res://assets/fleet/redesigned/"+id+".scn"
		var model: Node3D=(load(source_path) as PackedScene).instantiate()
		if not FileAccess.file_exists(original_path): MESH.save_model(model,original_path)
		var before: Dictionary=MESH.counts(model)
		for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false): deform(part,id)
		var cabin: Dictionary=model.get_meta("vehicle_interior_spec",{}).duplicate(true)
		if not cabin.is_empty():
			var original_roof:=float(cabin.get("roof",1.4))
			var original_belt:=float(cabin.get("belt",.82))
			for key in ["roof","belt","roof_trim_y"]:
				if cabin.has(key): cabin[key]=warp(Vector3(0,float(cabin[key]),0),id).y
			for key in ["rear","rear_top","roof_rear"]:
				if cabin.has(key): cabin[key]=warp(Vector3(0,original_belt if key=="rear" else original_roof,float(cabin[key])),id).z
			model.set_meta("vehicle_interior_spec",cabin)
		if id=="aurora_executive":
			# Its chassis spans Y=.205..275. The cabin carpet is .03 high and
			# centered at floor-.01. A 1 cm pad above that deck also keeps the
			# actual skinned shoe sole clear (floor=.30 left it at Y=.2699).
			# Inheriting the generic .12 floor put Dante's shoe below the hull.
			cabin["floor"]=.31
			cabin["seat_floor"]=.31
			model.set_meta("vehicle_interior_spec",cabin)
		preload("res://tools/fleet_refresh_20261019/CurrentFleetCraft.gd").new().replace_wheels(model,FAMILIES[id])
		model.set_meta("fleet_refresh_20261019",true)
		model.set_meta("fleet_wheel_family",FAMILIES[id])
		var baked: Node3D=MESH.bake(model,1.0,id)
		var surface_map:=synchronize_role_maps(baked)
		var after: Dictionary=MESH.counts(baked)
		var destination:=OUT+"/"+id+".scn"
		var error:=MESH.save_model(baked,destination)
		report[id]={"before":before,"after":after,"path":destination,"save_error":error,"wheel_family":FAMILIES[id],"surface_map":surface_map}
		print("FLEET_REFRESH ",id," ",JSON.stringify(report[id]))
		baked.free()
		model.free()
	var file:=FileAccess.open(OUT+"/current-manifest.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	quit()
