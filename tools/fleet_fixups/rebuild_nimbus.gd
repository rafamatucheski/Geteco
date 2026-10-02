extends SceneTree
## Offline art pass. Retains wheel meshes/anchors and the chassis; replaces only the
## Nimbus shell. Re-running produces the same shell without accumulating parts.
const PATH := "res://assets/fleet/nimbus_minivan.scn"
var model: Node3D
var batches := {}
var materials := {}

func _initialize() -> void: run.call_deferred()

func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3) -> void:
	if not batches.has(key): batches[key] = []
	var points := [a,b,c,a,c,d]
	# Godot front faces are clockwise.
	if (b-a).cross(c-a).dot(outward) > 0: points = [a,c,b,a,d,c]
	batches[key].append_array(points)

func box(key: String, center: Vector3, size: Vector3) -> void:
	var p := center-size*.5
	var q := center+size*.5
	quad(key,Vector3(p.x,p.y,p.z),Vector3(p.x,q.y,p.z),Vector3(p.x,q.y,q.z),Vector3(p.x,p.y,q.z),Vector3.LEFT)
	quad(key,Vector3(q.x,p.y,p.z),Vector3(q.x,q.y,p.z),Vector3(q.x,q.y,q.z),Vector3(q.x,p.y,q.z),Vector3.RIGHT)
	quad(key,Vector3(p.x,q.y,p.z),Vector3(q.x,q.y,p.z),Vector3(q.x,q.y,q.z),Vector3(p.x,q.y,q.z),Vector3.UP)
	quad(key,Vector3(p.x,p.y,p.z),Vector3(q.x,p.y,p.z),Vector3(q.x,p.y,q.z),Vector3(p.x,p.y,q.z),Vector3.DOWN)
	quad(key,Vector3(p.x,p.y,p.z),Vector3(q.x,p.y,p.z),Vector3(q.x,q.y,p.z),Vector3(p.x,q.y,p.z),Vector3.FORWARD)
	quad(key,Vector3(p.x,p.y,q.z),Vector3(q.x,p.y,q.z),Vector3(q.x,q.y,q.z),Vector3(p.x,q.y,q.z),Vector3.BACK)

func panel(key: String, corners: Array, u0: float, u1: float, v0: float, v1: float, normal: Vector3) -> void:
	var pts := []
	for uv in [Vector2(u0,v0),Vector2(u1,v0),Vector2(u1,v1),Vector2(u0,v1)]:
		pts.append((corners[0] as Vector3).lerp(corners[1],uv.x).lerp((corners[3] as Vector3).lerp(corners[2],uv.x),uv.y))
	quad(key,pts[0],pts[1],pts[2],pts[3],normal)

func window_frame(corners: Array, normal: Vector3, edge := .065) -> void:
	panel("paint",corners,0,1,0,.14,normal)
	panel("paint",corners,0,1,.92,1,normal)
	panel("paint",corners,0,edge,.14,.92,normal)
	panel("paint",corners,1-edge,1,.14,.92,normal)
	panel("trim",corners,edge,1-edge,.14,.17,normal)
	panel("trim",corners,edge,1-edge,.89,.92,normal)
	panel("trim",corners,edge,edge+.018,.17,.89,normal)
	panel("trim",corners,1-edge-.018,1-edge,.17,.89,normal)
	panel("glass",corners,edge+.018,1-edge-.018,.17,.89,normal)

func width(z: float) -> float:
	if z < -2.10: return lerpf(.83,.99,clampf((z+2.46)/.36,0,1))
	if z > 2.24: return lerpf(.99,.88,clampf((z-2.24)/.18,0,1))
	return .99

func belt(z: float) -> float:
	return lerpf(.86,1.03,clampf((z+2.46)/.75,0,1))

func bottom(z: float) -> float:
	var y := .40
	for axle in [-1.55,1.48]:
		var dz: float = absf(z-axle)
		if dz < .44: y = maxf(y,.38+sqrt(.44*.44-dz*dz))
	return y

func run() -> void:
	model = (load(PATH) as PackedScene).instantiate()
	for child in model.get_children():
		if not child is MeshInstance3D: continue
		var key: String = str(child.get_meta("nimbus_minivan_material_key",""))
		if child.material_override != null: materials[key] = child.material_override
		if child.has_meta("wheel_center"): continue
		var bounds: AABB = child.transform*child.get_aabb()
		if key == "rubber" and bounds.end.y < .32: continue
		model.remove_child(child)
		child.free()
	# Continuous belt and sill with real wheel openings, not black rectangles.
	var stations: Array[float] = [-2.46,-2.30,-2.10,-1.99,-1.95,-1.88,-1.78,-1.67,-1.55,-1.43,-1.32,-1.22,-1.15,-1.11,-.61,.30,1.04,1.08,1.15,1.25,1.36,1.48,1.60,1.71,1.81,1.88,1.92,2.05,2.24,2.42]
	for side in [-1.0,1.0]:
		for i in stations.size()-1:
			var za := stations[i]
			var zb := stations[i+1]
			var wa: float = width(za)*side
			var wb: float = width(zb)*side
			quad("paint",Vector3(wa,bottom(za),za),Vector3(wb,bottom(zb),zb),Vector3(wb,belt(zb)-.07,zb),Vector3(wa,belt(za)-.07,za),Vector3(side,0,0))
			quad("paint",Vector3(wa,belt(za)-.07,za),Vector3(wb,belt(zb)-.07,zb),Vector3(wb*.97,belt(zb),zb),Vector3(wa*.97,belt(za),za),Vector3(side,1,0))
			quad("trim",Vector3(wa,bottom(za),za),Vector3(wb,bottom(zb),zb),Vector3(wb*.90,bottom(zb),zb),Vector3(wa*.90,bottom(za),za),Vector3(0,-1,0))
		# Painted pillars separate the three side windows; upper body tapers inwards.
		var spans := [[-1.72,-.61,-1.18,-.61],[-.61,.94,-.61,.94],[.94,2.24,.94,2.05]]
		for span in spans:
			window_frame([Vector3(side*width(span[0])*.97,1.03,span[0]),Vector3(side*width(span[1])*.97,1.03,span[1]),Vector3(side*.84,1.74,span[3]),Vector3(side*.84,1.74,span[2])],Vector3(side,0,0))
		box("trim",Vector3(side*.993,.65,.18),Vector3(.025,.065,1.65))
		box("chrome",Vector3(side*1.005,.96,.18),Vector3(.014,.018,3.6))
		for z in [-.76,.09]: box("chrome",Vector3(side*1.009,.90,z),Vector3(.045,.045,.17))
		# Door shut lines below the windows, with a sliding track on the rear door.
		for z in [-.61,.94]: box("trim",Vector3(side*.995,.69,z),Vector3(.009,.49,.010))
		box("trim",Vector3(side*.995,.90,1.43),Vector3(.012,.018,.83))
		box("trim",Vector3(side*1.03,1.10,-1.64),Vector3(.17,.045,.055))
		box("paint",Vector3(side*1.105,1.14,-1.65),Vector3(.19,.14,.20))
		box("glass",Vector3(side*1.105,1.14,-1.544),Vector3(.15,.10,.008))
	# Short sloping bonnet joins the windshield without the old projecting slabs.
	for i in range(3):
		var za: float = [-2.46,-2.30,-2.10][i]
		var zb: float = [-2.30,-2.10,-1.72][i]
		quad("paint",Vector3(-width(za)*.97,belt(za),za),Vector3(width(za)*.97,belt(za),za),Vector3(width(zb)*.97,belt(zb),zb),Vector3(-width(zb)*.97,belt(zb),zb),Vector3.UP)
	window_frame([Vector3(-.9603,1.03,-1.72),Vector3(.9603,1.03,-1.72),Vector3(.84,1.74,-1.18),Vector3(-.84,1.74,-1.18)],Vector3(0,1,-1),.045)
	# Crown roof with rounded shoulders, swept front/rear corners. No roof rails.
	var xs := [-.84,-.78,-.64,0.0,.64,.78,.84]
	var ys := [1.74,1.81,1.85,1.865,1.85,1.81,1.74]
	var zs := [-1.18,-1.09,-.94,-.88,-.94,-1.09,-1.18]
	var ze := [2.05,2.09,2.12,2.13,2.12,2.09,2.05]
	for i in 6:
		quad("paint",Vector3(xs[i],ys[i],zs[i]),Vector3(xs[i+1],ys[i+1],zs[i+1]),Vector3(xs[i+1],ys[i+1],ze[i+1]),Vector3(xs[i],ys[i],ze[i]),Vector3.UP)
		quad("paint",Vector3(xs[i],1.74,-1.18),Vector3(xs[i+1],1.74,-1.18),Vector3(xs[i+1],ys[i+1],zs[i+1]),Vector3(xs[i],ys[i],zs[i]),Vector3.FORWARD)
		quad("paint",Vector3(xs[i],1.74,2.05),Vector3(xs[i+1],1.74,2.05),Vector3(xs[i+1],ys[i+1],ze[i+1]),Vector3(xs[i],ys[i],ze[i]),Vector3.BACK)
	var hatch_width := width(2.24)*.97
	window_frame([Vector3(-hatch_width,1.03,2.24),Vector3(hatch_width,1.03,2.24),Vector3(.84,1.74,2.05),Vector3(-.84,1.74,2.05)],Vector3.BACK,.12)
	# Rounded tail under the hatch, narrower glass and integrated vertical lights.
	quad("paint",Vector3(-.88,.40,2.42),Vector3(.88,.40,2.42),Vector3(.8536,1.03,2.42),Vector3(-.8536,1.03,2.42),Vector3.BACK)
	quad("paint",Vector3(-.8536,1.03,2.42),Vector3(.8536,1.03,2.42),Vector3(hatch_width,1.03,2.24),Vector3(-hatch_width,1.03,2.24),Vector3.UP)
	quad("paint",Vector3(-.83,.40,-2.46),Vector3(.83,.40,-2.46),Vector3(.8051,.86,-2.46),Vector3(-.8051,.86,-2.46),Vector3.FORWARD)
	box("trim",Vector3(0,.47,-2.47),Vector3(1.66,.17,.12))
	box("trim",Vector3(0,.47,2.43),Vector3(1.77,.16,.12))
	box("trim",Vector3(0,.72,-2.469),Vector3(.72,.19,.022))
	for y in [.66,.72,.78]: box("chrome",Vector3(0,y,-2.483),Vector3(.65,.012,.012))
	box("trim",Vector3(0,.78,2.432),Vector3(.43,.16,.015))
	box("chrome",Vector3(0,.91,2.434),Vector3(.49,.035,.015))
	box("trim",Vector3(.16,1.25,2.192),Vector3(.51,.022,.025))
	for side in [-1.0,1.0]:
		box("headlight",Vector3(side*.62,.76,-2.477),Vector3(.34,.145,.032))
		flush("headlight")
		box("taillight",Vector3(side*.745,.815,2.435),Vector3(.135,.29,.037))
		flush("taillight")
	for key in batches.keys(): flush(key)
	model.set_meta("nimbus_shell_revision",1)
	var packed := PackedScene.new()
	assert(packed.pack(model) == OK)
	assert(ResourceSaver.save(packed,PATH,ResourceSaver.FLAG_BUNDLE_RESOURCES) == OK)
	print("NIMBUS rebuilt meshes=",model.get_child_count())
	model.free()
	quit()

func flush(key: String) -> void:
	if not batches.has(key) or batches[key].is_empty(): return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in batches[key]: st.add_vertex(v)
	st.generate_normals()
	st.index()
	var part := MeshInstance3D.new()
	part.mesh = st.commit()
	part.material_override = materials[key]
	part.set_meta("nimbus_minivan_material_key",key)
	if key == "paint": part.set_meta("nimbus_minivan_damage_body",true)
	if key in ["headlight","taillight"]: part.set_meta("nimbus_minivan_lamp",true)
	if key == "chrome": part.set_meta("door_trim",true)
	model.add_child(part)
	part.owner = model
	batches[key] = []
