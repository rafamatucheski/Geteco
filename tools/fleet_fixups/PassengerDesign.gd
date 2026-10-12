extends RefCounted
## Authored cosmetic parts, baked once; no runtime generation or processing.
const DARK := Color("171e23")
const METAL := Color("aab6bc")
const PROFILES := {
	"aurora_executive":{"spokes":10,"accent":"bdad87","grille":"vertical","style":"executive"},
	"beach_cabriolet":{"spokes":5,"accent":"d9e2df","grille":"horizontal","style":"cabriolet"},
	"cobra_v8":{"spokes":5,"accent":"a47c51","grille":"split","style":"muscle"},
	"metro_hatch":{"spokes":6,"accent":"abb6be","grille":"horizontal","style":"urban"},
	"monaliza":{"spokes":7,"accent":"c1a36d","grille":"split","style":"gt"},
	"muscle_classic":{"spokes":5,"accent":"c4c8c9","grille":"horizontal","style":"muscle"},
	"nordic_estate":{"spokes":8,"accent":"b9c4c3","grille":"vertical","style":"touring"},
	"orbita_micro":{"spokes":6,"accent":"dfd5b2","grille":"horizontal","style":"urban"},
	"porto_rosso":{"spokes":5,"accent":"b4b6b7","grille":"split","style":"supercar"},
	"sedan_classic":{"spokes":8,"accent":"c4ccc9","grille":"vertical","style":"classic"},
	"sport_estate":{"spokes":10,"accent":"9caeb9","grille":"split","style":"touring_sport"},
	"station_wagon":{"spokes":6,"accent":"bebcb0","grille":"horizontal","style":"touring"},
	"surf_woody_wagon":{"spokes":5,"accent":"c7ac77","grille":"horizontal","style":"wood"},
	"taxi_yellow":{"spokes":8,"accent":"b8c2c6","grille":"vertical","style":"taxi"},
	"union_sedan":{"spokes":10,"accent":"adb9c1","grille":"horizontal","style":"executive"},
	"vale_crossover":{"spokes":6,"accent":"b5b8a7","grille":"split","style":"cross"},
	"vertice_midengine":{"spokes":5,"accent":"b7babc","grille":"split","style":"supercar"}
}
var model: Node3D
var groups := {}
var active := "PassengerDetails"
var color := Color.WHITE
var materials := {}
var profile: Dictionary

func apply(target: Node3D, id: String, spec: Dictionary) -> void:
	model = target
	profile = PROFILES[id]
	groups.clear()
	materials.clear()
	var owns_profile: bool=str(spec.get("id",id))==id
	if owns_profile and id=="vertice_midengine": refine_vertice_source()
	var wheels := {}
	var paint: StandardMaterial3D
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		# Open cockpits expose these already inexpensive seat backs. Simplifying
		# a disconnected upholstery surface erased them in the first art capture.
		for index in part.mesh.get_surface_count():
			var role: String=preload("res://runtime/VehicleSurfaceRoles.gd").key(part,index)
			if "upholstery" in role or "leather" in role or "seat" in role: part.set_meta("batch_ratio",1.0)
		if part.has_meta("wheel_center"):
			var center: Vector3 = part.get_meta("wheel_center")
			var bounds := part.transform * part.mesh.get_aabb()
			if not wheels.has(center): wheels[center] = bounds
			else: wheels[center] = (wheels[center] as AABB).merge(bounds)
			part.free()
		else:
			for index in part.mesh.get_surface_count():
				var source := part.get_active_material(index) as StandardMaterial3D
				if source != null and source.resource_name == "paint" and paint == null: paint=source
	if paint != null: materials["paint"]=paint
	var half := Vector3(float(spec.bounds_size[0]),float(spec.bounds_size[1]),float(spec.bounds_size[2]))*.5
	var center_bounds := Vector3(float(spec.bounds_center[0]),float(spec.bounds_center[1]),float(spec.bounds_center[2]))
	for center: Vector3 in wheels:
		var bounds: AABB = wheels[center]
		var radius := minf(center.y, maxf(bounds.size.y,bounds.size.z)*.5)
		var width := clampf(bounds.size.x,.15,.29)
		build_wheel(center,radius,width,int(profile.spokes),Color(profile.accent))
		# The caliper belongs to the body, so the wheel never spins it.
		active="PassengerDetails"
		var sign_x := signf(center.x)
		box("detail",center+Vector3(sign_x*width*.48,radius*.12,radius*.42),Vector3(.028,radius*.4,radius*.18),Color("a44f35") if profile.style in ["gt","muscle","supercar","touring_sport"] else Color("646c70"))
	details(id,half,center_bounds,wheels)
	if owns_profile:
		if id=="orbita_micro": end_closure(1.7,.44,.51,.075)
		elif id=="vale_crossover": end_closure(2.18,.58,.66,.065)
		elif id=="surf_woody_wagon": end_closure(2.4,.7,.69,.05)
		elif id=="vertice_midengine":
			end_closure(2.18,.64,.52,.06)
			end_closure(-2.34,.3,.39,.06)
	finish(wheels)
	model.set_meta("passenger_redesign_version",1)
	model.set_meta("passenger_design_profile",profile.style)
	model.set_meta("fleet_finish",true)

func end_closure(z: float,width: float,edge_y: float,rise: float) -> void:
	# Legacy end caps ended at the shoulder height, leaving the curved crown
	# open. Match the ten segments of the authored shell and overlap by 1 mm.
	active="PassengerDetails"
	color=Color.WHITE
	var outward:=Vector3(0,0,signf(z))
	var plane:=z+signf(z)*.001
	for i in 10:
		var x0:=lerpf(-width,width,i/10.0)
		var x1:=lerpf(-width,width,(i+1)/10.0)
		var h0:=edge_y+rise*(1.0-pow(x0/width,2.0))
		var h1:=edge_y+rise*(1.0-pow(x1/width,2.0))
		quad("paint",Vector3(x0,edge_y-.002,plane),Vector3(x1,edge_y-.002,plane),Vector3(x1,h1,plane),Vector3(x0,h0,plane),outward)

func refine_vertice_source() -> void:
	# The legacy nose contains inward-facing skin ahead of the wheel opening.
	# Repair its winding offline; retain small islands such as mirror housings.
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null or part.has_meta("wheel_center"): continue
		var role: String=part.get_meta("vertice_midengine_material_key","")
		if role not in ["paint","trim","glass"]: continue
		var rebuilt:=ArrayMesh.new()
		var repaired:=0
		for surface in part.mesh.get_surface_count():
			var tool:=SurfaceTool.new()
			tool.create_from(part.mesh,surface)
			tool.deindex()
			var arrays:=tool.commit_to_arrays()
			var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			if role=="paint":
				for start in range(0,points.size(),3):
					var center: Vector3=part.transform*((points[start]+points[start+1]+points[start+2])/3.0)
					var normal: Vector3=part.transform.basis*(normals[start]+normals[start+1]+normals[start+2]).normalized()
					if center.z>=-.75 or center.y<.3 or center.y>.85: continue
					# Keep the concave wheel opening facing its cavity. The hood
					# above it and the nose must face away from the body's axis.
					if absf(center.x)>.55 and Vector2(center.y-.27,center.z+1.38).length()<.405: continue
					if normal.dot(Vector3(center.x,center.y-.25,minf(center.z+1.7,0.0)))>=0: continue
					for channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_TEX_UV2]:
						if arrays[channel]==null or arrays[channel].size()!=points.size(): continue
						var temp=arrays[channel][start+1]
						arrays[channel][start+1]=arrays[channel][start+2]
						arrays[channel][start+2]=temp
					for offset in 3: arrays[Mesh.ARRAY_NORMAL][start+offset]=-arrays[Mesh.ARRAY_NORMAL][start+offset]
					repaired+=1
			rebuilt.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			rebuilt.surface_set_material(surface,part.mesh.surface_get_material(surface))
		part.mesh=preload("res://tools/fleet_fixups/SpecialMeshReduction.gd").reduce(rebuilt,.2)
		part.set_meta("batch_ratio",1.0)
		if repaired>0: print("PASSENGER_NOSE_WINDING_REPAIRED ",repaired)

func triangle(key: String,a: Vector3,b: Vector3,c: Vector3,outward: Vector3) -> void:
	var bucket := active+"/"+key
	if not groups.has(bucket):
		var st:=SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[bucket]=st
	var st: SurfaceTool=groups[bucket]
	var normal: Vector3=(b-a).cross(c-a).normalized()
	var vertices: Array[Vector3]=[a,b,c]
	if normal.dot(outward)>0: vertices=[a,c,b]
	else: normal=-normal
	for v: Vector3 in vertices:
		st.set_normal(normal)
		st.set_color(color)
		st.set_uv(Vector2(v.z,v.y))
		st.add_vertex(v)

func quad(key: String,a: Vector3,b: Vector3,c: Vector3,d: Vector3,n: Vector3) -> void:
	triangle(key,a,b,c,n)
	triangle(key,a,c,d,n)

func box(key: String,at: Vector3,size: Vector3,tint: Color=Color.WHITE) -> void:
	color=tint
	var p:=at-size*.5
	var q:=at+size*.5
	quad(key,Vector3(p.x,p.y,p.z),Vector3(p.x,q.y,p.z),Vector3(p.x,q.y,q.z),Vector3(p.x,p.y,q.z),Vector3.LEFT)
	quad(key,Vector3(q.x,p.y,p.z),Vector3(q.x,q.y,p.z),Vector3(q.x,q.y,q.z),Vector3(q.x,p.y,q.z),Vector3.RIGHT)
	quad(key,Vector3(p.x,q.y,p.z),Vector3(q.x,q.y,p.z),Vector3(q.x,q.y,q.z),Vector3(p.x,q.y,q.z),Vector3.UP)
	quad(key,Vector3(p.x,p.y,p.z),Vector3(q.x,p.y,p.z),Vector3(q.x,p.y,q.z),Vector3(p.x,p.y,q.z),Vector3.DOWN)
	quad(key,Vector3(p.x,p.y,p.z),Vector3(q.x,p.y,p.z),Vector3(q.x,q.y,p.z),Vector3(p.x,q.y,p.z),Vector3.FORWARD)
	quad(key,Vector3(p.x,p.y,q.z),Vector3(q.x,p.y,q.z),Vector3(q.x,q.y,q.z),Vector3(p.x,q.y,q.z),Vector3.BACK)
	color=Color.WHITE

func beam(key: String,a: Vector3,b: Vector3,width: float,tint: Color) -> void:
	color=tint
	var delta: Vector3=(b-a).normalized()
	var u: Vector3=delta.cross(Vector3.UP).normalized()*width*.5
	if u.length_squared()<.000001: u=Vector3.RIGHT*width*.5
	var v: Vector3=delta.cross(u).normalized()*width*.5
	quad(key,a-u-v,a+u-v,b+u-v,b-u-v,-v)
	quad(key,a-u+v,a+u+v,b+u+v,b-u+v,v)
	quad(key,a-u-v,a-u+v,b-u+v,b-u-v,-u)
	quad(key,a+u-v,a+u+v,b+u+v,b+u-v,u)
	color=Color.WHITE

func ring(key: String,c: Vector3,u: Vector3,v: Vector3,outer: float,inner: float,n: Vector3,tint: Color,segments:=20) -> void:
	color=tint
	for i in segments:
		var a: Vector3=u*cos(TAU*i/segments)+v*sin(TAU*i/segments)
		var b: Vector3=u*cos(TAU*(i+1)/segments)+v*sin(TAU*(i+1)/segments)
		if inner==0: triangle(key,c+a*outer,c+b*outer,c,n)
		else: quad(key,c+a*outer,c+b*outer,c+b*inner,c+a*inner,n)
	color=Color.WHITE

func build_wheel(center: Vector3,radius: float,width: float,spokes: int,accent: Color) -> void:
	active="PassengerWheel_"+str(center)
	var s:=signf(center.x)
	var profile_points: Array[Vector2]=[Vector2(-width*.45,radius*.7),Vector2(-width*.5,radius*.89),Vector2(-width*.35,radius),Vector2(width*.35,radius),Vector2(width*.5,radius*.89),Vector2(width*.51,radius*.7)]
	for j in profile_points.size()-1:
		for i in 20:
			var a:=TAU*i/20.0
			var b:=TAU*(i+1)/20.0
			var p: Vector2=profile_points[j]
			var q: Vector2=profile_points[j+1]
			color=Color("1d252a") if j==2 else Color("2d363d")
			quad("tire",center+Vector3(s*p.x,sin(a)*p.y,cos(a)*p.y),center+Vector3(s*p.x,sin(b)*p.y,cos(b)*p.y),center+Vector3(s*q.x,sin(b)*q.y,cos(b)*q.y),center+Vector3(s*q.x,sin(a)*q.y,cos(a)*q.y),Vector3(s*.35,sin(a),cos(a)))
	var face:=center+Vector3(s*width*.515,0,0)
	ring("wheel",face,Vector3.UP,Vector3.BACK,radius*.73,radius*.64,Vector3(s,0,0),METAL)
	ring("wheel",face-Vector3(s*.01,0,0),Vector3.UP,Vector3.BACK,radius*.65,0,Vector3(s,0,0),DARK)
	ring("wheel",face-Vector3(s*.004,0,0),Vector3.UP,Vector3.BACK,radius*.55,radius*.21,Vector3(s,0,0),Color("667177"))
	for j in spokes:
		var a:=TAU*j/spokes+.1
		var radial:=Vector3(0,sin(a),cos(a))
		var tangent:=Vector3(0,cos(a),-sin(a))
		var at:=face+Vector3(s*.009,0,0)
		color=accent
		quad("wheel",at+radial*radius*.14-tangent*radius*.075,at+radial*radius*.14+tangent*radius*.075,at+radial*radius*.68+tangent*radius*.044,at+radial*radius*.68-tangent*radius*.044,Vector3(s,0,0))
		if spokes<=6: beam("wheel",at+radial*radius*.32+Vector3(s*.003,0,0),at+radial*radius*.58+Vector3(s*.003,0,0),.009,DARK)
	for j in 5:
		var a:=TAU*j/5.0
		ring("wheel",face+Vector3(s*.012,sin(a)*radius*.16,cos(a)*radius*.16),Vector3.UP,Vector3.BACK,radius*.025,0,Vector3(s,0,0),METAL,5)
	ring("wheel",face+Vector3(s*.014,0,0),Vector3.UP,Vector3.BACK,radius*.13,0,Vector3(s,0,0),accent,12)
	ring("wheel",face+Vector3(s*.017,0,0),Vector3.UP,Vector3.BACK,radius*.065,0,Vector3(s,0,0),DARK,10)
	color=Color.WHITE

func details(id: String,half: Vector3,bc: Vector3,wheels: Dictionary) -> void:
	active="PassengerDetails"
	var sporty: bool=profile.style in ["gt","muscle","supercar","touring_sport"]
	var accent:=Color(profile.accent)
	var front:=bc.z-half.z+.035
	var rear:=bc.z+half.z-.032
	var bumper_y:=.32 if sporty else .36
	var span:=half.x*.78
	# Low twin ducts suit the roadsters; sedans retain an upright machined grille.
	if profile.style=="supercar":
		for side in [-1.0,1.0]:
			box("paint",Vector3(side*span*.46,bumper_y+.065,front+.012),Vector3(span*.79,.20,.05))
			color=DARK
			quad("detail",Vector3(side*span*.1,bumper_y-.005,front-.015),Vector3(side*span*.82,bumper_y-.005,front-.015),Vector3(side*span*.74,bumper_y+.14,front-.015),Vector3(side*span*.16,bumper_y+.14,front-.015),Vector3.FORWARD)
			color=Color.WHITE
			for j in 3: box("detail",Vector3(side*span*.46,bumper_y+.027+j*.037,front-.022),Vector3(span*.57,.008,.009),Color("3c464e"))
	else:
		box("detail",Vector3(0,bumper_y+.19,front),Vector3(span*1.33,.24,.028),METAL if not sporty else DARK)
		box("detail",Vector3(0,bumper_y+.19,front-.017),Vector3(span*1.26,.18,.01),DARK)
		if profile.grille=="vertical":
			for j in 11:
				box("detail",Vector3(lerpf(-span*.58,span*.58,j/10.0),bumper_y+.19,front-.027),Vector3(.018,.17,.013),accent)
		else:
			for j in 4:
				box("detail",Vector3(0,bumper_y+.12+j*.045,front-.027),Vector3(span*1.2,.012,.013),accent if not sporty else Color("46555e"))
			if profile.grille=="split": box("detail",Vector3(0,bumper_y+.19,front-.036),Vector3(.065,.18,.028),accent)
	# Lower lip is beveled across its ends instead of a flat projecting plank.
	color=DARK
	quad("detail",Vector3(-span,bumper_y-.08,front+.035),Vector3(span,bumper_y-.08,front+.035),Vector3(span*.9,bumper_y-.12,front-.008),Vector3(-span*.9,bumper_y-.12,front-.008),Vector3(0,-.3,-1))
	color=Color.WHITE
	box("detail",Vector3(0,bumper_y-.071,front+.02),Vector3(span*1.86,.012,.042),DARK if sporty else accent)
	for side in [-1.0,1.0]:
		box("detail",Vector3(side*span*.84,bumper_y+.075,front+.012),Vector3(span*.18,.105,.018),DARK)
		for j in 2: box("detail",Vector3(side*span*.84,bumper_y+.045+j*.045,front-.001),Vector3(span*.14,.008,.013),METAL)
		# Rear exhaust has a dark mouth and a satin rim, grouped with the body.
		var outlet:=Vector3(side*span*.67,bumper_y-.06,rear-.01)
		ring("detail",outlet,Vector3.RIGHT,Vector3.UP,.052,.038,Vector3.BACK,METAL,14)
		ring("detail",outlet-Vector3(0,0,.005),Vector3.RIGHT,Vector3.UP,.038,0,Vector3.BACK,DARK,14)
	box("detail",Vector3(0,bumper_y+.01,rear-.003),Vector3(span*1.65,.18,.02),DARK)
	for x in [-.6,-.3,0.0,.3,.6]:
		box("detail",Vector3(x*span,bumper_y-.035,rear+.004),Vector3(.018,.11,.034),accent if not sporty else Color("3b474f"))
	# Simple lower body accents sit clear of the animated door leaf area.
	var front_axle:=INF
	var rear_axle:=-INF
	var track:=0.0
	for c: Vector3 in wheels:
		front_axle=minf(front_axle,c.z)
		rear_axle=maxf(rear_axle,c.z)
		track=maxf(track,absf(c.x))
	for side in [-1.0,1.0]:
		var x: float=side*minf(half.x-.12,track+.01)
		box("detail",Vector3(x,.255,(front_axle+rear_axle)*.5),Vector3(.028,.08,rear_axle-front_axle-.65),DARK)
		box("detail",Vector3(x+side*.016,.281,(front_axle+rear_axle)*.5),Vector3(.014,.015,rear_axle-front_axle-.73),accent)
	# Distinct practical silhouettes for the touring/urban profiles; existing
	# authored surfboard and taxi sign remain intact in the source geometry.
	if profile.style in ["touring","touring_sport","cross"]:
		var top:=bc.y+half.y
		var geometry:=preload("res://tools/fleet_fixups/FleetGeometry.gd").new(model)
		for side in [-1.0,1.0]:
			beam("detail",Vector3(side*half.x*.57,top-.015,-.50),Vector3(side*half.x*.57,top-.015,half.z*.65),.035,accent)
			for support_z in [-.40,half.z*.58]:
				var start:=Vector3(side*half.x*.57,top+.2,support_z)
				var hit:=geometry.ray(start,Vector3.DOWN)
				if not hit.is_empty():
					var base: Vector3=hit.point
					beam("detail",base+Vector3.UP*.004,Vector3(base.x,top-.015,base.z),.04,DARK)
	if sporty and id not in ["cobra_v8","muscle_classic"]:
		# Rear valance extraction slots, placed below the existing rear glazing.
		for j in 7:
			box("detail",Vector3(lerpf(-span*.7,span*.7,j/6.0),bumper_y+.24,rear-.005),Vector3(.065,.072,.02),DARK)

func material(key: String) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m:=StandardMaterial3D.new()
	m.resource_name=key
	m.vertex_color_use_as_albedo=true
	m.vertex_color_is_srgb=true
	m.albedo_color=Color.WHITE
	m.metallic=.42
	m.roughness=.43
	if key=="tire":
		m.metallic=0.0
		m.roughness=.88
	materials[key]=m
	return m

func finish(wheels: Dictionary) -> void:
	var nodes: Dictionary={}
	for bucket: String in groups:
		var label:=bucket.get_slice("/",0)
		var key:=bucket.get_slice("/",1)
		if not nodes.has(label):
			var node:=MeshInstance3D.new()
			node.name=label.validate_node_name()
			node.mesh=ArrayMesh.new()
			node.set_meta("batch_ratio",1.0)
			model.add_child(node)
			nodes[label]=node
		var node: MeshInstance3D=nodes[label]
		var st: SurfaceTool=groups[bucket]
		st.index()
		st.set_material(material(key))
		st.commit(node.mesh)
		var keys: Array=node.get_meta("passenger_surface_material_keys",[])
		keys.append(key)
		node.set_meta("passenger_surface_material_keys",keys)
	for center: Vector3 in wheels:
		var node: MeshInstance3D=nodes["PassengerWheel_"+str(center)]
		node.set_meta("wheel_center",center)
		node.set_meta("wheel_spins",true)
