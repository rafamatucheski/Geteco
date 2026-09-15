extends Node3D
## Z33 coupe. Front -Z; dimensions in metres; animated hinges and wheels.
var doors: Array[Node3D] = []
var wheels: Array[Node3D] = []
var occupants: Array[Node3D] = []

func material(color: String, metal := 0.0, rough := .4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color)
	m.metallic = metal
	m.roughness = rough
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func box(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = mat
	mesh.position = at
	parent.add_child(mesh)
	return mesh

func surface(parent: Node3D, vertices: Array, mat: Material, smooth := false) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0 if smooth else -1)
	for i in range(0,vertices.size(),3):
		var a: Vector3 = vertices[i]
		var b: Vector3 = vertices[i+1]
		var c: Vector3 = vertices[i+2]
		var outward := (a+b+c)/3.0-Vector3(0,.4,0)
		if (b-a).cross(c-a).dot(outward) < 0:
			st.add_vertex(a)
			st.add_vertex(c)
			st.add_vertex(b)
		else:
			st.add_vertex(a)
			st.add_vertex(b)
			st.add_vertex(c)
	st.generate_normals()
	if smooth: st.index()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat
	parent.add_child(node)

func quad(out: Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	out.append_array([a,b,c,a,c,d])

func width(z: float) -> float:
	return .895 + .048*exp(-pow((z-1.25)/.62,2)) + .032*exp(-pow((z+1.30)/.56,2)) - .17*pow(absf(z)/2.22,6)

func deck(z: float) -> float:
	return .79 - .14*pow(absf(z)/2.22,3)

func top(x: float, z: float) -> Vector3:
	return Vector3(x,deck(z)+.037*(1.0-pow(x/width(z),2)),rounded_end(x,z))

func rounded_end(x: float,z: float) -> float:
	return z-signf(z)*.14*pow(x/width(z),2)*pow(absf(z)/2.2,10)

func _ready() -> void:
	var green := material("397c21",.5,.29)
	var black := material("101418",.12,.42)
	var carbon := material("252b2d",.35,.36)
	var glass := material("182831",.4,.16)
	var bronze := material("a58b54",.72,.26)
	var silver := material("aab4ba",.75,.23)
	var purple := material("613188",.35,.3)
	# Continuous shoulders and wheel openings cut into the actual body surface.
	var body: Array = []
	var hood: Array = []
	for i in 120:
		var z0 := lerpf(-2.2,2.15,float(i)/120)
		var z1 := lerpf(-2.2,2.15,float(i+1)/120)
		for j in 24:
			var u0 := lerpf(-1.,1.,float(j)/24)
			var u1 := lerpf(-1.,1.,float(j+1)/24)
			var target := hood if z0 < -.83 and absf(u0) < .75 and absf(u1) <= .75 else body
			quad(target,top(u0*width(z0),z0),top(u1*width(z0),z0),top(u1*width(z1),z1),top(u0*width(z1),z1))
		for side in [-1,1]:
			for j in 8:
				var t0 := float(j)/8
				var t1 := float(j+1)/8
				quad(body,flank(side,z0,t0),flank(side,z1,t0),flank(side,z1,t1),flank(side,z0,t1))
	surface(self,body,green,true)
	surface(self,hood,carbon,true)
	# Rounded roof crown, windscreen and hatch: smooth cross-sections.
	var stations := [Vector3(.76,.82,-.88),Vector3(.66,1.13,-.49),Vector3(.60,1.27,-.20),Vector3(.60,1.30,.18),Vector3(.62,1.26,.52),Vector3(.69,1.08,.97),Vector3(.78,.82,1.49)]
	for i in stations.size()-1:
		var roof: Array = []
		var a: Vector3 = stations[i]
		var b: Vector3 = stations[i+1]
		for j in 20:
			var u := lerpf(-1.,1.,float(j)/20)
			var v := lerpf(-1.,1.,float(j+1)/20)
			quad(roof,Vector3(a.x*u,a.y+.045*(1-u*u),a.z),Vector3(a.x*v,a.y+.045*(1-v*v),a.z),Vector3(b.x*v,b.y+.045*(1-v*v),b.z),Vector3(b.x*u,b.y+.045*(1-u*u),b.z))
		surface(self,roof,green if i in [2,3] else glass,true)
		for side in [-1,1]:
			var panel: Array = []
			quad(panel,Vector3(side*a.x,a.y,a.z),Vector3(side*b.x,b.y,b.z),Vector3(side*.855,.795,b.z),Vector3(side*.855,.795,a.z))
			surface(self,panel,green)
	for side in [-1,1]:
		var hinge := Node3D.new()
		hinge.position = Vector3(side*.88,.0,-.79)
		add_child(hinge)
		doors.append(hinge)
		var door_mesh: Array = []
		quad(door_mesh,Vector3(side*.018,.34,.0),Vector3(side*.025,.34,1.42),Vector3(side*.019,.79,1.42),Vector3(side*.009,.79,0))
		surface(hinge,door_mesh,green)
		# Inset side glazing with a broad C pillar and slim A pillar.
		var window: Array = []
		quad(window,Vector3(side*(-.027),.827,.09),Vector3(side*(-.224),1.205,.58),Vector3(side*(-.24),1.227,1.02),Vector3(side*(-.17),1.12,1.38))
		quad(window,Vector3(side*(-.027),.827,.09),Vector3(side*(-.17),1.12,1.38),Vector3(side*(-.035),.827,1.40),Vector3(side*(-.027),.827,.10))
		surface(hinge,window,glass)
		box(hinge,Vector3(.035,.13,.045),Vector3(side*.044,.715,1.28),silver)
		var mirror := box(hinge,Vector3(.17,.085,.20),Vector3(side*.115,.88,.19),green)
		mirror.rotation.y = side*.18
		vinyl(hinge,side*.032,[Vector2(.07,.40),Vector2(.53,.47),Vector2(.20,.58),Vector2(.81,.53),Vector2(.57,.70),Vector2(1.31,.64),Vector2(1.08,.52),Vector2(1.39,.43),Vector2(.91,.44),Vector2(1.13,.37)],purple)
		box(self,Vector3(.13,.10,1.75),Vector3(side*.92,.245,0),green)
		box(self,Vector3(.15,.025,1.85),Vector3(side*.93,.19,0),black)
		# Flush swept headlight lens, laid on the hood's curved surface.
		var light_outline := [Vector2(side*.56,-2.06),Vector2(side*.74,-1.94),Vector2(side*.82,-1.37),Vector2(side*.68,-1.48)]
		var lens: Array = []
		for p in light_outline: lens.append(top(p.x,p.y)+Vector3(0,.012,0))
		surface(self,[lens[0],lens[1],lens[2],lens[0],lens[2],lens[3]],silver)
		for z in [-1.83,-1.60]:
			var projector := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = .06
			ball.height = .035
			projector.mesh = ball
			projector.position = top(side*.71,z)+Vector3(0,.025,0)
			projector.material_override = material("e0eff5",.35,.16)
			add_child(projector)
		var tail: Array = []
		quad(tail,top(side*.63,2.12)+Vector3(0,.012,0),top(side*.76,2.02)+Vector3(0,.012,0),top(side*.79,1.66)+Vector3(0,.012,0),top(side*.69,1.85)+Vector3(0,.012,0))
		surface(self,tail,material("ab1525",.3,.2))
		for axle in [-1.32,1.32]: wheel(side,axle,black,bronze,silver)
		box(self,Vector3(.045,.29,.10),Vector3(side*.56,1.015,1.82),carbon)
		box(self,Vector3(.035,.13,.36),Vector3(side*.89,1.18,1.82),carbon)
		cylinder(self,.066,.19,Vector3(side*.61,.26,2.19),silver,Vector3(PI/2,0,0))
		cylinder(self,.049,.005,Vector3(side*.61,.26,2.29),black,Vector3(PI/2,0,0))
		var person := Node3D.new()
		person.position = Vector3(side*.36,.73,.15)
		add_child(person)
		occupants.append(person)
		box(person,Vector3(.30,.29,.22),Vector3.ZERO,material("6d2d82" if side == -1 else "323c49"))
		box(person,Vector3(.18,.20,.19),Vector3(0,.25,0),material("ba8a67"))
		person.hide()
	# Bumper ends follow the shell rather than protruding rectangular blocks.
	for end in [-1,1]:
		var bumper: Array = []
		var z := -2.2 if end == -1 else 2.15
		for j in 32:
			var u := lerpf(-1.,1.,float(j)/32)
			var v := lerpf(-1.,1.,float(j+1)/32)
			quad(bumper,Vector3(u*width(z),.22,rounded_end(u*width(z),z)),Vector3(v*width(z),.22,rounded_end(v*width(z),z)),top(v*width(z),z),top(u*width(z),z))
		surface(self,bumper,green,true)
	box(self,Vector3(.94,.205,.018),Vector3(0,.395,-2.213),black)
	for side in [-1,1]:
		var intake := box(self,Vector3(.19,.17,.019),Vector3(side*.64,.39,rounded_end(side*.64,-2.2)-.013),black)
		intake.rotation.y = side*.27
	box(self,Vector3(.78,.12,.020),Vector3(0,.375,-2.225),silver)
	for i in 5: box(self,Vector3(.78,.009,.023),Vector3(0,.325+i*.023,-2.24),black)
	box(self,Vector3(1.66,.034,.17),Vector3(0,.205,-2.16),carbon)
	box(self,Vector3(1.79,.045,.33),Vector3(0,1.155,1.82),carbon)
	for side in [-1,1]:
		for i in 4:
			var z := -1.1-i*.095
			var vent := box(self,Vector3(.24,.012,.040),top(side*.34,z)+Vector3(0,.012,0),black)
			vent.rotation.x = -.04
	box(self,Vector3(1.04,.12,.025),Vector3(0,.30,2.168),carbon)

func flank(side: int,z: float,t: float) -> Vector3:
	var bottom := .24
	for axle in [-1.32,1.32]:
		var dz := absf(z-axle)
		if dz < .415: bottom = maxf(bottom,.35+sqrt(.415*.415-dz*dz))
	var y := lerpf(bottom,deck(z),t)
	var x := side*(width(z)+.022*sin(t*PI)-.025*(1-t))
	return Vector3(x,y,rounded_end(x,z))

func cylinder(parent: Node3D,radius: float,height: float,at: Vector3,mat: Material,rot: Vector3) -> void:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 48
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	node.rotation = rot
	parent.add_child(node)

func wheel(side: int,axle: float,rubber: Material,alloy: Material,disc: Material) -> void:
	var node := Node3D.new()
	node.position = Vector3(side*.77,.35,axle)
	add_child(node)
	wheels.append(node)
	var tire := MeshInstance3D.new()
	var tire_ring := TorusMesh.new()
	tire_ring.inner_radius = .277
	tire_ring.outer_radius = .35
	tire_ring.rings = 48
	tire_ring.ring_segments = 16
	tire.mesh = tire_ring
	tire.material_override = rubber
	tire.scale.y = .235 / (.35-.277)
	tire.rotation.z = PI/2
	node.add_child(tire)
	# Rotor sits inside the rim barrel, behind the spokes.
	cylinder(node,.225,.018,Vector3(side*.080,0,0),disc,Vector3(0,0,PI/2))
	cylinder(node,.075,.024,Vector3(side*.096,0,0),material("323739",.6),Vector3(0,0,PI/2))
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = .258
	torus.outer_radius = .284
	torus.rings = 48
	torus.ring_segments = 12
	rim.mesh = torus
	rim.material_override = alloy
	rim.rotation.z = PI/2
	rim.position.x = side*.15
	node.add_child(rim)
	for k in 5:
		var a := k*TAU/5
		var spoke := box(node,Vector3(.035,.23,.043),Vector3(side*.157,cos(a)*.13,sin(a)*.13),alloy)
		spoke.rotation.x = a
	cylinder(node,.06,.035,Vector3(side*.17,0,0),alloy,Vector3(0,0,PI/2))
	# Caliper is fixed to the suspension; only rotor and wheel rotate.
	box(self,Vector3(.040,.14,.075),Vector3(side*.864,.36,axle+.19),material("b12420",.25))

func vinyl(parent: Node3D,x: float,outline: Array,paint: Material) -> void:
	var points := PackedVector2Array(outline)
	var vertices: Array = []
	for i in Geometry2D.triangulate_polygon(points): vertices.append(Vector3(x,points[i].y,points[i].x))
	surface(parent,vertices,paint)

func door(index: int,opened: bool) -> void:
	create_tween().tween_property(doors[index],"rotation:y",(-.9 if index == 0 else .9) if opened else 0.0,.32)

func roll(distance: float) -> void:
	for w in wheels: w.rotation.x += distance/.35

func steer(angle: float) -> void:
	for w in wheels:
		if w.position.z < 0: w.rotation.y = -angle
