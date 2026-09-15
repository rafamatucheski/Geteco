extends "res://prototypes/living_cast/BaseVehicle3DModel.gd"
## Shared construction tools; the two estates have different body sections,
## cabin proportions, wheel tracks, bumpers, lamps and roof silhouettes.
func sport_body() -> bool: return false

func width_at(z: float) -> float:
	if not sport_body(): return 0.88 - 0.035 * pow(absf(z) / 2.48, 8)
	return 0.94 + 0.065 * (exp(-pow((z+1.48)/0.48,2)) + exp(-pow((z-1.44)/0.48,2))) - 0.10 * pow(absf(z)/2.48,8)

func top_at(x_ratio: float, z: float) -> float:
	if not sport_body(): return 0.91 + 0.015 * (1.0-x_ratio*x_ratio)
	return 0.83 + 0.035 * (1.0-x_ratio*x_ratio) - 0.15 * exp(-pow((z+2.48)/0.42,2)) + 0.065 * absf(x_ratio) * (exp(-pow((z+1.48)/0.50,2)) + exp(-pow((z-1.44)/0.50,2)))

func arch_bottom(z: float) -> float:
	var low := 0.26 if sport_body() else 0.32
	var radius := 0.405 if sport_body() else 0.385
	for axle in [-1.48,1.44]:
		var distance := absf(z-axle)
		if distance < radius: low = maxf(low,0.36 + sqrt(radius*radius-distance*distance))
	return low

func build_shell() -> void:
	var mesh := SurfaceTool.new()
	mesh.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 100:
		var a := lerpf(-2.48,2.48,float(i)/100.0)
		var b := lerpf(-2.48,2.48,float(i+1)/100.0)
		for side in [-1.0,1.0]:
			var p := Vector3(side*width_at(a),top_at(side,a),a)
			var q := Vector3(side*width_at(b),top_at(side,b),b)
			var r := Vector3(side*(width_at(b)-0.02),arch_bottom(b),b)
			var t := Vector3(side*(width_at(a)-0.02),arch_bottom(a),a)
			for point in ([p,q,r,p,r,t] if side<0 else [p,r,q,p,t,r]): mesh.add_vertex(point)
		var p := Vector3(-width_at(a),top_at(-1,a),a)
		var q := Vector3(-width_at(b),top_at(-1,b),b)
		var r := Vector3(width_at(b),top_at(1,b),b)
		var t := Vector3(width_at(a),top_at(1,a),a)
		for point in [p,r,q,p,t,r]: mesh.add_vertex(point)
	mesh.generate_normals()
	mesh_node(mesh.commit(),Vector3.ZERO,paint).name = "EstateShell"
	for z in [-2.48,2.48]:
		var points: Array[Vector3] = [Vector3(-width_at(z),0.3,z),Vector3(width_at(z),0.3,z),Vector3(width_at(z),top_at(1,z),z),Vector3(-width_at(z),top_at(-1,z),z)]
		if z>0: points.reverse()
		surface(points,paint)

func build() -> void:
	var sport := sport_body()
	vehicle_id = "sport_estate" if sport else "nordic_estate"
	paint = mat("paint","45566a" if sport else "b39a65",0.45 if sport else 0.2,0.25 if sport else 0.4)
	var rubber := mat("rubber","151a20",0,0.85)
	var trim := mat("trim","262c32",0.15,0.55)
	var chrome := mat("chrome","b9c3c8",0.8,0.25)
	var glass := mat("glass","213446" if sport else "44616b",0.3,0.18)
	glass.cull_mode = BaseMaterial3D.CULL_DISABLED
	var head := mat("headlight","e4f3ff" if sport else "fff0ca",0.15,0.2,0.5)
	var tail := mat("taillight","d32d36",0.15,0.2,0.55)
	var amber := mat("amber_turn","ec9639",0.1,0.3,0.3)
	build_shell()
	box(Vector3(0,0.27,0),Vector3(1.65,0.08,4.7),rubber)
	var roof_y := 1.39 if sport else 1.57
	var roof_front := -0.54 if sport else -0.68
	var roof_rear := 1.82 if sport else 2.20
	var roof_w := 0.76 if sport else 0.81
	var belt_y := 0.89 if sport else 0.96
	var belt_w := 0.92 if sport else 0.865
	var nose_z := -1.13
	var tail_z := 2.35
	box(Vector3(0,roof_y,(roof_front+roof_rear)/2),Vector3(roof_w*2,0.065,roof_rear-roof_front+0.08),paint).name = "LongEstateRoof"
	# Windshield, then cargo hatch glass. Rear glass reaches the luggage area.
	surface([Vector3(-belt_w,belt_y,nose_z),Vector3(belt_w,belt_y,nose_z),Vector3(roof_w,roof_y-0.02,roof_front),Vector3(-roof_w,roof_y-0.02,roof_front)],glass)
	surface([Vector3(belt_w,belt_y,tail_z),Vector3(-belt_w,belt_y,tail_z),Vector3(-roof_w,roof_y-0.02,roof_rear),Vector3(roof_w,roof_y-0.02,roof_rear)],glass)
	for side in [-1.0,1.0]:
		# Three distinct side windows: front door, rear door, cargo quarter glass.
		var upper := [roof_front,0.22,1.04,roof_rear]
		var lower := [nose_z,0.22,1.04,tail_z]
		for pane in 3:
			surface([Vector3(side*belt_w,belt_y,lower[pane]+0.035),Vector3(side*belt_w,belt_y,lower[pane+1]-0.035),Vector3(side*roof_w,roof_y-0.03,upper[pane+1]-0.035),Vector3(side*roof_w,roof_y-0.03,upper[pane]+0.035)],glass)
		for pillar in 4:
			tube([Vector3(side*belt_w,belt_y,lower[pillar]),Vector3(side*roof_w,roof_y,upper[pillar])],0.035 if pillar<3 else 0.055,paint if pillar in [0,3] else trim)
		tube([Vector3(side*belt_w,belt_y,nose_z),Vector3(side*belt_w,belt_y,tail_z)],0.018,trim if sport else chrome)
		for door_z in [-0.1,0.87]:
			box(Vector3(side*(width_at(door_z)+0.006),0.80,door_z),Vector3(0.035,0.045,0.17),chrome).set_meta("door_trim",true)
		box(Vector3(side*1.02,0.98,-0.90),Vector3(0.19,0.10,0.20),trim if sport else paint).set_meta("door_trim",true)
		# Rails stay close to the roof, preserving the low estate silhouette.
		tube([Vector3(side*0.64,roof_y+0.075,roof_front+0.20),Vector3(side*0.64,roof_y+0.075,roof_rear-0.12)],0.022,trim if sport else chrome)
		box(Vector3(side*(0.97 if sport else 0.89),0.40 if sport else 0.59,0),Vector3(0.055,0.08,2.1 if sport else 4.68),trim)
		for axle in [-1.48,1.44]:
			add_wheel(side*(0.965 if sport else 0.855),0.36,axle,0.36 if sport else 0.34,0.255 if sport else 0.205,0.28 if sport else 0.205,5 if sport else 8,"aeb9c4" if sport else "d1cbbd")
	if sport:
		# Broad black intake, slim lights, diffuser and roof spoiler.
		box(Vector3(0,0.48,-2.49),Vector3(1.10,0.30,0.035),trim)
		for x in [-0.76,0.76]:
			box(Vector3(x,0.42,-2.47),Vector3(0.30,0.20,0.04),rubber)
			box(Vector3(x,0.70,-2.46),Vector3(0.37,0.065,0.045),head)
			box(Vector3(x,0.88,2.49),Vector3(0.39,0.065,0.045),tail)
		box(Vector3(0,0.29,-2.49),Vector3(1.89,0.055,0.20),trim)
		box(Vector3(0,0.38,2.49),Vector3(1.78,0.16,0.12),rubber)
		box(Vector3(0,roof_y+0.025,roof_rear+0.06),Vector3(1.63,0.065,0.26),paint)
		add_exhaust_dual(0.70,0.34,2.55,0.085)
	else:
		# Upright nose, rectangular lamps and thick unpainted impact bumpers.
		box(Vector3(0,0.70,-2.50),Vector3(0.69,0.24,0.05),trim)
		for i in 9: box(Vector3(-0.30+float(i)*0.075,0.70,-2.535),Vector3(0.015,0.21,0.018),chrome)
		for side in [-1.0,1.0]:
			box(Vector3(side*0.62,0.73,-2.50),Vector3(0.38,0.22,0.05),head)
			box(Vector3(side*0.83,0.73,-2.49),Vector3(0.075,0.22,0.055),amber)
			box(Vector3(side*0.81,1.09,2.43),Vector3(0.12,0.55,0.09),tail)
			box(Vector3(side*0.81,1.09,2.485),Vector3(0.12,0.085,0.018),amber)
		for z in [-2.53,2.53]: box(Vector3(0,0.43,z),Vector3(1.85,0.18,0.19),trim)
		box(Vector3(0,0.84,2.50),Vector3(0.31,0.04,0.035),chrome)
		add_exhaust_dual(0.62,0.28,2.53,0.035)
	# Visible cargo floor behind the rear seats, not a sedan trunk deck.
	box(Vector3(0,0.88,1.70),Vector3(1.35,0.04,1.12),trim)
