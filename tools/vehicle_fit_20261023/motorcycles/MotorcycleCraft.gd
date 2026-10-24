extends "res://tools/fleet_fixups/PassengerDesign.gd"
## Offline closed shells and wheelsets. No runtime code, lights or handling changes.
var id: String
func apply_fit(target: Node3D,archetype: String) -> void:
	model=target; id=archetype; groups.clear(); materials.clear()
	var paint_mat: StandardMaterial3D
	var rolling:={}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh==null: continue
		if part.has_meta("motorcycle_grip"):
			part.set_meta("batch_group",str(part.name)); part.set_meta("batch_group_meta",{"motorcycle_grip":part.get_meta("motorcycle_grip")})
			continue
		if part.get_meta("motorcycle_rider",false):
			part.set_meta("batch_group",str(part.name)); part.set_meta("batch_group_meta",{"motorcycle_rider":true})
			continue
		if part.has_meta("wheel_center") and bool(part.get_meta("wheel_spins",false)):
			rolling[part.get_meta("wheel_center")]=part.mesh.get_aabb().size.x
			part.free(); continue
		var updated:=ArrayMesh.new(); var keys: Array[String]=[]
		for surface in part.mesh.get_surface_count():
			var role: String=preload("res://runtime/VehicleSurfaceRoles.gd").key(part,surface)
			var mat:=part.get_active_material(surface) as StandardMaterial3D
			if str(part.name)=="Body" and ((id=="bike_sport" and surface==8) or (id=="bike_cruiser" and surface==6)): continue
			if role=="paint" and str(part.name)=="Body":
				paint_mat=mat; continue
			var arrays:=part.mesh.surface_get_arrays(surface)
			if id=="bike_sport" and str(part.name)=="Body" and surface==2: arrays=remove_obsolete_cap(arrays)
			if str(part.name)=="Body" and surface==1: arrays=stow_stand(arrays)
			updated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			updated.surface_set_material(updated.get_surface_count()-1,mat)
			keys.append(role)
		part.mesh=updated
		part.material_override=null
		part.set_meta("batch_surface_material_keys",keys)
		# The rear brake and fender are static and share Body instead of creating
		# an unnecessary rear steering group. Geometry and axle anchor stay put.
		if part.has_meta("wheel_center") and (part.get_meta("wheel_center") as Vector3).z>0:
			part.remove_meta("wheel_center"); part.remove_meta("wheel_spins")
	materials["paint"]=paint_mat
	active="NewBody"
	if id=="bike_sport": sport_shells()
	elif id=="bike_cruiser": cruiser_shells()
	else: urban_shells()
	mounts()
	for center: Vector3 in rolling: wheelset(center,float(rolling[center]))
	finish(rolling)
	model.set_meta("motorcycle_fit_version",2)
	model.set_meta("motorcycle_stand_stowed",true)
	model.set_meta("motorcycle_design",{"bike_sport":"Vortex integrated sport fairing","bike_cruiser":"Ironhorse sculpted touring tank","bike_urban":"Cometa sculpted commuter tank"}[id])

func loft(key: String,sections: Array,tint:=Color.WHITE,segments:=12,shift:=Vector3.ZERO) -> void:
	color=tint
	for i in sections.size()-1:
		var a: Vector4=sections[i]; var b: Vector4=sections[i+1]
		for j in segments:
			var t0:=TAU*j/segments; var t1:=TAU*(j+1)/segments
			var p0:=profile_point(a,t0)+shift; var p1:=profile_point(a,t1)+shift
			var q0:=profile_point(b,t0)+shift; var q1:=profile_point(b,t1)+shift
			var n:=Vector3(cos((t0+t1)*.5),sin((t0+t1)*.5),0)
			quad(key,p0,p1,q1,q0,n)
	for end in [0,sections.size()-1]:
		var s: Vector4=sections[end]; var c:=Vector3(0,(s.z+s.w)*.5,s.x)+shift
		for j in segments: triangle(key,c,profile_point(s,TAU*j/segments)+shift,profile_point(s,TAU*(j+1)/segments)+shift,Vector3.FORWARD if end==0 else Vector3.BACK)
	color=Color.WHITE
func profile_point(s: Vector4,a: float) -> Vector3:
	return Vector3(cos(a)*s.y,(s.z+s.w)*.5+sin(a)*(s.w-s.z)*.5,s.x)

func sport_shells() -> void:
	# A closed tank with a rounded shoulder, neck and knee recess.
	loft("paint",[Vector4(-.48,.075,.78,.91),Vector4(-.39,.18,.77,1.00),Vector4(-.24,.225,.76,1.075),Vector4(-.04,.22,.77,1.06),Vector4(.14,.135,.78,.94),Vector4(.21,.105,.79,.86)])
	# Joined upper front and side shell replaces the disconnected block below.
	loft("paint",[Vector4(-.696,.285,.81,1.03),Vector4(-.64,.285,.81,1.105),Vector4(-.53,.29,.69,1.10),Vector4(-.37,.275,.44,.94),Vector4(-.17,.285,.355,.83),Vector4(.12,.26,.36,.80),Vector4(.34,.15,.47,.79)])
	# A tapered tail hugs the original saddle underside; lenses retain location.
	loft("paint",[Vector4(.12,.135,.72,.785),Vector4(.37,.165,.73,.802),Vector4(.59,.118,.76,.81),Vector4(.64,.08,.767,.80)])
	active="NewBody"
	for side in [-1.0,1.0]:
		box("detail",Vector3(side*.287,.65,-.17),Vector3(.012,.065,.23),Color("1c282f"))
		for j in 3:
			beam("detail",Vector3(side*.294,.67-j*.045,-.29),Vector3(side*.273,.66-j*.045,-.05),.014,Color("202b32"))
	cap(Vector3(0,1.052,-.16),.038,.021)
	# Existing windscreen, lenses and mirrors remain untouched.

func cruiser_shells() -> void:
	loft("paint",[Vector4(-.49,.065,.77,.865),Vector4(-.41,.15,.745,.94),Vector4(-.27,.215,.735,.985),Vector4(-.05,.235,.74,.975),Vector4(.14,.18,.75,.89),Vector4(.23,.08,.76,.79)],Color.WHITE,14)
	loft("paint",[Vector4(.57,.09,.745,.79),Vector4(.67,.18,.75,.84),Vector4(.84,.185,.75,.85),Vector4(.94,.12,.755,.815)],Color.WHITE,12)
	cap(Vector3(0,.963,-.12),.043,.021)
	for side in [-1.0,1.0]:
		# Small touring cases have bevelled edges and sit on actual frame rails.
		loft("detail",[Vector4(.13,.065,.40,.67),Vector4(.20,.105,.355,.74),Vector4(.69,.105,.355,.74),Vector4(.78,.075,.40,.69)],Color("29333a"),12,Vector3(side*.245,0,0))
		beam("detail",Vector3(side*.19,.72,.19),Vector3(side*.19,.72,.70),.025,Color("4d5a60"))
		box("detail",Vector3(side*.352,.62,.45),Vector3(.012,.025,.07),Color("82959e"))
		# Slim chrome knee trim follows the rounded flank instead of a floating box.
		beam("detail",Vector3(side*.219,.825,-.18),Vector3(side*.215,.825,.04),.016,METAL)
		beam("detail",Vector3(side*.17,.73,.64),Vector3(side*.17,.73,.88),.02,Color("4d5a60"))

func urban_shells() -> void:
	loft("paint",[Vector4(-.39,.055,.78,.86),Vector4(-.32,.145,.75,.95),Vector4(-.19,.185,.745,1.005),Vector4(.02,.175,.75,.98),Vector4(.14,.105,.765,.86)],Color.WHITE,12)
	# Closed beveled side covers meet the saddle rails and conceal the battery.
	for side in [-1.0,1.0]:
		var sections: Array=[Vector4(.04,.135,.58,.77),Vector4(.12,.165,.52,.77),Vector4(.32,.145,.535,.76),Vector4(.41,.08,.60,.75)]
		if side<0: loft("paint",sections)
		beam("detail",Vector3(side*.169,.66,.13),Vector3(side*.152,.66,.28),.012,Color("aab8bc"))
	loft("paint",[Vector4(.36,.11,.705,.765),Vector4(.54,.14,.72,.79),Vector4(.64,.08,.756,.795)])
	cap(Vector3(0,.983,-.16),.031,.016)

func mounts() -> void:
	active="NewBody"
	if id!="bike_sport":
		# Closed bracket meets both lamp housing and steering-head clamp.
		var lamp: Vector3=Vector3(0,1.0,-.72) if id=="bike_cruiser" else Vector3(0,.965,-.56)
		var clamp: Vector3=Vector3(0,.9,-.50) if id=="bike_cruiser" else Vector3(0,.88,-.40)
		for side in [-1.0,1.0]:
			beam("detail",lamp+Vector3(side*.09,0,0),clamp+Vector3(side*.09,0,0),.025,Color("4e5c62"))
	# Indicators and licence plate connect to the saddle frame with real stalks.
	var tail_y: float=.66 if id=="bike_cruiser" else .74
	for side in [-1.0,1.0]:
		beam("detail",Vector3(side*.08,tail_y,.71),Vector3(side*.19,tail_y,.71),.018,Color("28343b"))
	beam("detail",Vector3(0,tail_y+.005,.58),Vector3(0,tail_y-.11,.805),.025,Color("28343b"))

func wheelset(center: Vector3,source_width: float) -> void:
	active="PassengerWheel_"+str(center)
	var radius: float=center.y
	var width: float=clampf(source_width*.95,.12,.17)
	var sections: Array[Vector2]=[Vector2(-.5,.70),Vector2(-.53,.88),Vector2(-.35,1),Vector2(.35,1),Vector2(.53,.88),Vector2(.5,.70)]
	for j in sections.size()-1:
		for k in 24:
			var a:=TAU*k/24.0; var b:=TAU*(k+1)/24.0
			var u: Vector2=sections[j]; var v: Vector2=sections[j+1]
			color=Color("20272b") if j==2 else Color("303a40")
			tire_quad(center,sections[j],sections[j+1],a,b,width,radius)
	for side in [-1.0,1.0]:
		var face:=center+Vector3(side*width*.51,0,0)
		ring("wheel",face,Vector3.UP,Vector3.BACK,radius*.72,radius*.60,Vector3(side,0,0),METAL,24)
		ring("wheel",face-Vector3(side*.014,0,0),Vector3.UP,Vector3.BACK,radius*.61,radius*.58,Vector3(side,0,0),Color("172228"),24)
		var spokes:=7 if id=="bike_cruiser" else 5
		for k in spokes:
			var angle:=TAU*k/spokes
			var u:=Vector3(0,sin(angle),cos(angle)); var v:=Vector3(0,cos(angle),-sin(angle))
			color=Color("a6b6bd")
			quad("wheel",face+u*radius*.16-v*radius*.06,face+u*radius*.16+v*radius*.06,face+u*radius*.67+v*radius*.035,face+u*radius*.67-v*radius*.035,Vector3(side,0,0))
		ring("wheel",face+Vector3(side*.005,0,0),Vector3.UP,Vector3.BACK,radius*.19,0,Vector3(side,0,0),METAL,12)
		ring("wheel",face-Vector3(side*.004,0,0),Vector3.UP,Vector3.BACK,radius*.53,radius*.24,Vector3(side,0,0),Color("7c8b93"),24)
		# Ventilation holes are colour in the metal surface, behind the spokes.
		for hole in 12:
			var angle:=TAU*hole/12.0+.08
			var at:=face-Vector3(side*.0035,0,0)+Vector3(0,sin(angle),cos(angle))*radius*.43
			ring("wheel",at,Vector3.UP,Vector3.BACK,radius*.025,0,Vector3(side,0,0),Color("2a363d"),5)
	color=Color.WHITE

func cap(base: Vector3,radius: float,height: float) -> void:
	# The lower edge intersects the tank, eliminating the floating ring.
	for k in 16:
		var a:=TAU*k/16.0; var b:=TAU*(k+1)/16.0
		var u:=Vector3(cos(a)*radius,0,sin(a)*radius)
		var v:=Vector3(cos(b)*radius,0,sin(b)*radius)
		color=Color("69777d")
		quad("detail",base+u,base+v,base+v+Vector3.UP*height,base+u+Vector3.UP*height,(u+v).normalized())
	ring("detail",base+Vector3.UP*height,Vector3.RIGHT,Vector3.BACK,radius,0,Vector3.UP,Color("98a9b1"),16)

func tire_quad(center: Vector3,u: Vector2,v: Vector2,a: float,b: float,width: float,radius: float) -> void:
	var points: Array[Vector3]=[center+Vector3(u.x*width,sin(a)*u.y*radius,cos(a)*u.y*radius),center+Vector3(u.x*width,sin(b)*u.y*radius,cos(b)*u.y*radius),center+Vector3(v.x*width,sin(b)*v.y*radius,cos(b)*v.y*radius),center+Vector3(v.x*width,sin(a)*v.y*radius,cos(a)*v.y*radius)]
	var radial_u: float=sqrt(maxf(0.0,1.0-pow(absf(u.x)/.57,2)))
	var radial_v: float=sqrt(maxf(0.0,1.0-pow(absf(v.x)/.57,2)))
	var normals: Array[Vector3]=[Vector3(u.x*1.8,sin(a)*radial_u,cos(a)*radial_u).normalized(),Vector3(u.x*1.8,sin(b)*radial_u,cos(b)*radial_u).normalized(),Vector3(v.x*1.8,sin(b)*radial_v,cos(b)*radial_v).normalized(),Vector3(v.x*1.8,sin(a)*radial_v,cos(a)*radial_v).normalized()]
	var bucket:=active+"/tire"
	if not groups.has(bucket):
		var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); groups[bucket]=st
	var st: SurfaceTool=groups[bucket]
	var order: Array[int]=[0,1,2,0,2,3]
	if (points[1]-points[0]).cross(points[2]-points[0]).dot(normals[0])>0: order=[0,2,1,0,3,2]
	for index: int in order:
		st.set_normal(normals[index]); st.set_color(color); st.set_uv(Vector2(points[index].z,points[index].y)); st.add_vertex(points[index])

func remove_obsolete_cap(arrays: Array) -> Array:
	# The former tank crown sat at y1.10. Its silver filler cap shares trim2
	# with the engine; remove only that closed component, keeping the hardware.
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var old: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var fresh:=PackedInt32Array()
	var removed:=0
	for first in range(0,old.size(),3):
		var obsolete:=true
		for k in 3:
			var p: Vector3=vertices[old[first+k]]
			obsolete=obsolete and absf(p.x)<.047 and p.y>1.095 and p.y<1.105 and p.z>-.127 and p.z<-.033
		if obsolete: removed+=1
		else:
			for k in 3: fresh.append(old[first+k])
	assert(removed>0,"Former filler cap must be found in original sport trim")
	print("OBSOLETE_SPORT_CAP_REMOVED triangles=",removed)
	arrays[Mesh.ARRAY_INDEX]=fresh
	return arrays

func component_root(parents: PackedInt32Array,index: int) -> int:
	while parents[index]!=index: index=parents[index]
	return index

func stow_stand(arrays: Array) -> Array:
	# Find only the disconnected stand touching the floor. Reorient that solid
	# around its own upper mounting face; all other trim, pivots and contacts
	# are copied unchanged. The gameplay bike stays upright while parked.
	var points: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var parents:=PackedInt32Array(); parents.resize(points.size()); var welded:={}
	for i in points.size():
		var key:=points[i].snapped(Vector3.ONE*.0001)
		parents[i]=welded[key] if welded.has(key) else i
		if not welded.has(key): welded[key]=i
	for first in range(0,indices.size(),3):
		for k in [1,2]: parents[component_root(parents,indices[first+k])]=component_root(parents,indices[first])
	var boxes:={}
	for i in points.size():
		var key:=component_root(parents,i)
		boxes[key]=(boxes[key] as AABB).expand(points[i]) if boxes.has(key) else AABB(points[i],Vector3.ZERO)
	var selected:=-1
	for key in boxes:
		var box: AABB=boxes[key]
		if box.position.y<.08 and box.end.y<.45 and box.size.y>.25:
			assert(selected==-1,"Exactly one grounded stand component")
			selected=key
	assert(selected!=-1,"Original grounded side stand found")
	var center:=Vector3.ZERO; var count:=0
	for i in points.size():
		if component_root(parents,i)!=selected: continue
		center+=points[i]; count+=1
	center/=float(count)
	# Power iteration gives the shaft direction independently of node names
	# and face tessellation. Choose the direction from the hinge to the foot.
	var axis:=Vector3(-.22,-.335,.12).normalized()
	for _iteration in 12:
		var next:=Vector3.ZERO
		for i in points.size():
			if component_root(parents,i)!=selected: continue
			var q:=points[i]-center
			next+=q*q.dot(axis)
		axis=next.normalized()
	if axis.y>0: axis=-axis
	var minimum:=INF
	for i in points.size():
		if component_root(parents,i)==selected: minimum=minf(minimum,(points[i]-center).dot(axis))
	var hinge:=Vector3.ZERO; var face_count:=0
	for i in points.size():
		if component_root(parents,i)==selected and (points[i]-center).dot(axis)<minimum+.0005:
			hinge+=points[i]; face_count+=1
	hinge/=float(face_count)
	var folded:=Vector3(-.065,-.015,.41).normalized()
	var turn:=Basis(Quaternion(axis,folded))
	var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
	for i in points.size():
		if component_root(parents,i)!=selected: continue
		points[i]=hinge+turn*(points[i]-hinge)
		if i<normals.size(): normals[i]=(turn*normals[i]).normalized()
	arrays[Mesh.ARRAY_VERTEX]=points; arrays[Mesh.ARRAY_NORMAL]=normals
	print("MOTORCYCLE_STAND_STOWED ",id," hinge=",hinge," vertices=",count)
	return arrays
