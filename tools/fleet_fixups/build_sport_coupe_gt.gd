extends SceneTree
## Offline, deterministic authoring. No geometry generation or detail loops at runtime.
## Default writes a candidate. --install explicitly replaces the production asset.
const OUTPUT := "res://assets/fleet/sport_coupe.scn"
var groups := {}
var model: Node3D
var active := "Shell"
var tint := Color.WHITE
var materials := {}
const DARK := Color("10171c")
const METAL := Color("9eaeb7")
const GOLD := Color("ba9865")

func _initialize() -> void: run.call_deferred()

func triangle(key: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var bucket := active + "/" + key
	if not groups.has(bucket):
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		groups[bucket] = tool
	var tool: SurfaceTool = groups[bucket]
	var n := (b-a).cross(c-a).normalized()
	var points := [a,b,c]
	if n.dot(outward) > 0: points = [a,c,b]
	else: n = -n
	for p: Vector3 in points:
		tool.set_normal(n)
		tool.set_color(tint)
		tool.set_uv(Vector2(p.z,p.y))
		tool.add_vertex(p)

func quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	triangle(key,a,b,c,normal)
	triangle(key,a,c,d,normal)

func box(key: String, at: Vector3, size: Vector3, color := Color.WHITE) -> void:
	tint = color
	var p := at-size*.5
	var q := at+size*.5
	quad(key,Vector3(p.x,p.y,p.z),Vector3(p.x,q.y,p.z),Vector3(p.x,q.y,q.z),Vector3(p.x,p.y,q.z),Vector3.LEFT)
	quad(key,Vector3(q.x,p.y,p.z),Vector3(q.x,q.y,p.z),Vector3(q.x,q.y,q.z),Vector3(q.x,p.y,q.z),Vector3.RIGHT)
	quad(key,Vector3(p.x,q.y,p.z),Vector3(q.x,q.y,p.z),Vector3(q.x,q.y,q.z),Vector3(p.x,q.y,q.z),Vector3.UP)
	quad(key,Vector3(p.x,p.y,p.z),Vector3(q.x,p.y,p.z),Vector3(q.x,p.y,q.z),Vector3(p.x,p.y,q.z),Vector3.DOWN)
	quad(key,Vector3(p.x,p.y,p.z),Vector3(q.x,p.y,p.z),Vector3(q.x,q.y,p.z),Vector3(p.x,q.y,p.z),Vector3.FORWARD)
	quad(key,Vector3(p.x,p.y,q.z),Vector3(q.x,p.y,q.z),Vector3(q.x,q.y,q.z),Vector3(p.x,q.y,q.z),Vector3.BACK)
	tint = Color.WHITE

func beam(key: String, a: Vector3, b: Vector3, width: float, color := Color.WHITE) -> void:
	tint = color
	var along := (b-a).normalized()
	var u := along.cross(Vector3.UP).normalized() * width*.5
	if u.length_squared() < .0000001: u = Vector3.RIGHT*width*.5
	var v := along.cross(u).normalized()*width*.5
	quad(key,a-u-v,a+u-v,b+u-v,b-u-v,-v)
	quad(key,a-u+v,a+u+v,b+u+v,b-u+v,v)
	quad(key,a-u-v,a-u+v,b-u+v,b-u-v,-u)
	quad(key,a+u-v,a+u+v,b+u+v,b+u-v,u)
	tint = Color.WHITE

func panel(key: String, corners: Array, u0: float, u1: float, v0: float, v1: float, normal: Vector3) -> void:
	var pts := []
	for uv in [Vector2(u0,v0),Vector2(u1,v0),Vector2(u1,v1),Vector2(u0,v1)]:
		pts.append((corners[0] as Vector3).lerp(corners[1],uv.x).lerp((corners[3] as Vector3).lerp(corners[2],uv.x),uv.y))
	quad(key,pts[0],pts[1],pts[2],pts[3],normal)

func glazing(corners: Array, normal: Vector3) -> void:
	for rect in [Vector4(0,1,0,.065),Vector4(0,1,.95,1),Vector4(0,.05,.065,.95),Vector4(.95,1,.065,.95)]:
		panel("paint",corners,rect.x,rect.y,rect.z,rect.w,normal)
	tint = DARK
	panel("detail",corners,.05,.95,.065,.095,normal)
	panel("detail",corners,.05,.95,.92,.95,normal)
	panel("detail",corners,.05,.065,.095,.92,normal)
	panel("detail",corners,.935,.95,.095,.92,normal)
	tint = Color.WHITE
	panel("glass",corners,.065,.935,.095,.92,normal)

func width(z: float) -> float:
	if z < -1.8: return lerpf(.83,.99,clampf((z+2.23)/.43,0,1))
	if z > 1.85: return lerpf(1.01,.86,clampf((z-1.85)/.38,0,1))
	if z < -.725: return .91 + .115*exp(-pow((z+1.28)/.42,2))
	if z > .81: return .93 + .095*exp(-pow((z-1.22)/.45,2))
	return .90

func belt(z: float) -> float:
	return .82 + .115*exp(-pow((z+1.28)/.44,2)) + .08*exp(-pow((z-1.22)/.50,2)) - .11*clampf((-z-1.85)/.38,0,1)

func bottom(z: float) -> float:
	var y := .245
	for axle in [-1.28,1.22]:
		var dz: float = absf(z-axle)
		if dz < .418: y = maxf(y,.36+sqrt(.418*.418-dz*dz))
	return y

func outer_side(s: float, za: float, zb: float, door: bool) -> void:
	var lo_a := .245 if door else bottom(za)
	var lo_b := .245 if door else bottom(zb)
	var top_a := .815 if door else belt(za)
	var top_b := .815 if door else belt(zb)
	# Three longitudinal surfaces shape a recessed sill and a rounded shoulder.
	quad("paint",Vector3(s*(width(za)-.035),lo_a,za),Vector3(s*(width(zb)-.035),lo_b,zb),Vector3(s*width(zb),maxf(lo_b,.65),zb),Vector3(s*width(za),maxf(lo_a,.65),za),Vector3(s,0,0))
	quad("paint",Vector3(s*width(za),maxf(lo_a,.65),za),Vector3(s*width(zb),maxf(lo_b,.65),zb),Vector3(s*(width(zb)-.055),top_b,zb),Vector3(s*(width(za)-.055),top_a,za),Vector3(s,.3,0))
	# Return lip makes the open wheel arch read as a real edge.
	if not door:
		tint = DARK
		quad("detail",Vector3(s*(width(za)-.035),lo_a,za),Vector3(s*(width(zb)-.035),lo_b,zb),Vector3(s*(width(zb)-.11),lo_b+.018,zb),Vector3(s*(width(za)-.11),lo_a+.018,za),Vector3(0,-1,0))
		tint = Color.WHITE

func body() -> void:
	var stations: Array[float] = [-2.23,-2.12,-1.96,-1.80,-1.698,-1.67,-1.60,-1.50,-1.39,-1.28,-1.17,-1.06,-.96,-.89,-.862,-.725,.81,.802,.83,.90,1.0,1.11,1.22,1.33,1.44,1.54,1.61,1.638,1.80,1.96,2.12,2.23]
	stations.sort()
	for s in [-1.0,1.0]:
		active = "Shell"
		for i in stations.size()-1:
			var za := stations[i]
			var zb := stations[i+1]
			if za >= -.725 and zb <= .81: continue
			outer_side(s,za,zb,false)
		# Door is authored as a complete removable leaf, including glass and mirror.
		active = "DoorL" if s < 0 else "DoorR"
		outer_side(s,-.720,.800,true)
		# The upper triangular shoulder connects narrow glazing to the broad body.
		quad("paint",Vector3(s*.845,.815,-.720),Vector3(s*.845,.815,.800),Vector3(s*.765,.815,.32),Vector3(s*.75,.81,-.73),Vector3(s,1,0))
		glazing([Vector3(s*.75,.81,-.73),Vector3(s*.765,.815,.32),Vector3(s*.60,1.25,.24),Vector3(s*.60,1.25,-.30)],Vector3(s,0,0))
		# Thin interior return and finished door card, no overlapping external skin.
		tint = Color("252b2d")
		quad("detail",Vector3(s*.84,.275,-.715),Vector3(s*.84,.275,.795),Vector3(s*.81,.79,.795),Vector3(s*.81,.79,-.715),Vector3(-s,0,0))
		tint = Color.WHITE
		beam("detail",Vector3(s*.855,.815,.800),Vector3(s*.872,.253,.800),.010,DARK)
		box("detail",Vector3(s*.912,.702,.55),Vector3(.027,.033,.18),METAL)
		box("detail",Vector3(s*.917,.692,.55),Vector3(.026,.011,.13),DARK)
		beam("detail",Vector3(s*.80,.85,-.61),Vector3(s*.96,.88,-.58),.037,DARK)
		box("paint",Vector3(s*.982,.91,-.58),Vector3(.10,.095,.19))
		box("detail",Vector3(s*.984,.91,-.479),Vector3(.075,.065,.009),METAL)
		# Two quiet gold coachlines set into the dark rocker; geometry, no labels.
		box("detail",Vector3(s*.882,.295,.04),Vector3(.012,.08,1.47),DARK)
		box("detail",Vector3(s*.890,.32,.04),Vector3(.010,.011,1.40),GOLD)
		active = "Shell"
		# Recessed jambs behind the physical shutline: no daylight through the seam.
		box("detail",Vector3(s*.846,.53,-.725),Vector3(.03,.57,.024),DARK)
		box("detail",Vector3(s*.846,.53,.81),Vector3(.03,.57,.024),DARK)
		glazing([Vector3(s*.765,.815,.33),Vector3(s*.82,.85,1.14),Vector3(s*.61,1.255,.61),Vector3(s*.60,1.25,.27)],Vector3(s,0,0))
		quad("paint",Vector3(s*.845,.815,.81),Vector3(s*(width(1.17)-.055),belt(1.17),1.17),Vector3(s*.82,.85,1.14),Vector3(s*.765,.815,.33),Vector3(s,1,0))
		# Wheel arch edging and three extraction slits on each rear shoulder.
		active = "Details"
		for axle in [-1.28,1.22]:
			for j in 16:
				var a := float(j)*PI/16.0
				var b := float(j+1)*PI/16.0
				var za: float = axle+cos(a)*.424
				var zb: float = axle+cos(b)*.424
				beam("detail",Vector3(s*(width(za)-.031),.36+sin(a)*.424,za),Vector3(s*(width(zb)-.031),.36+sin(b)*.424,zb),.018,DARK)
		for j in 3:
			var z := 1.72 + j*.082
			box("detail",Vector3(s*(width(z)-.02),.72,z),Vector3(.018,.12,.037),DARK)
		# Fixed calipers sit behind the wheel spokes, never spin with the tyre.
		for z in [-1.28,1.22]: box("detail",Vector3(s*.986,.41,z+.145),Vector3(.024,.15,.077),Color("c35830"))
	active = "Shell"
	# Longitudinal hood strips; fenders flow into the wheel shoulders.
	var zs := [-2.23,-2.12,-1.96,-1.80,-1.60,-1.40,-1.20,-1.0,-.85,-.73]
	var xs := [-1.0,-.90,-.72,-.57,0.0,.57,.72,.90,1.0]
	for j in zs.size()-1:
		for i in xs.size()-1:
			quad("paint",hood(xs[i],zs[j]),hood(xs[i+1],zs[j]),hood(xs[i+1],zs[j+1]),hood(xs[i],zs[j+1]),Vector3.UP)
	glazing([Vector3(-.75,.81,-.73),Vector3(.75,.81,-.73),Vector3(.60,1.25,-.30),Vector3(-.60,1.25,-.30)],Vector3(0,1,-1))
	var rx := [-.61,-.55,-.40,0.0,.40,.55,.61]
	var ry := [1.25,1.29,1.315,1.327,1.315,1.29,1.25]
	for i in 6:
		quad("paint",Vector3(rx[i],ry[i],-.30),Vector3(rx[i+1],ry[i+1],-.30),Vector3(rx[i+1],ry[i+1],.61),Vector3(rx[i],ry[i],.61),Vector3.UP)
		quad("paint",Vector3(rx[i],1.25,-.30),Vector3(rx[i+1],1.25,-.30),Vector3(rx[i+1],ry[i+1],-.30),Vector3(rx[i],ry[i],-.30),Vector3.FORWARD)
		quad("paint",Vector3(rx[i],1.25,.61),Vector3(rx[i+1],1.25,.61),Vector3(rx[i+1],ry[i+1],.61),Vector3(rx[i],ry[i],.61),Vector3.BACK)
	glazing([Vector3(-.82,.85,1.14),Vector3(.82,.85,1.14),Vector3(.61,1.25,.61),Vector3(-.61,1.25,.61)],Vector3(0,1,1))
	for j in range(6):
		var za := lerpf(1.14,2.23,j/6.0)
		var zb := lerpf(1.14,2.23,(j+1)/6.0)
		quad("paint",Vector3(-(width(za)-.055),belt(za),za),Vector3(width(za)-.055,belt(za),za),Vector3(width(zb)-.055,belt(zb),zb),Vector3(-(width(zb)-.055),belt(zb),zb),Vector3.UP)
	# Front and rear bumper painted corners with a recessed dark center.
	for front in [true,false]:
		var z := -2.235 if front else 2.235
		var n := Vector3.FORWARD if front else Vector3.BACK
		quad("paint",Vector3(-.83,.60,z),Vector3(.83,.60,z),Vector3(.83,.72 if front else .81,z),Vector3(-.83,.72 if front else .81,z),n)
		for s in [-1.0,1.0]:
			quad("paint",Vector3(s*.67,.28,z),Vector3(s*.86,.30,z),Vector3(s*.84,.60,z),Vector3(s*.67,.60,z),n)
		box("paint",Vector3(0,.29,z),Vector3(1.65,.055,.065))
	active = "Details"
	box("detail",Vector3(0,.231,0),Vector3(1.54,.025,3.8),DARK)
	# Recessed bumper cavities, vertical dividers and splitter lips.
	for front in [true,false]:
		var z := -2.223 if front else 2.223
		box("detail",Vector3(0,.446,z),Vector3(1.35,.255,.018),DARK)
		box("detail",Vector3(0,.245,z),Vector3(1.77,.035,.15),Color("242b2f"))
		for x in [-.35,.35]:
			active="Shell"
			box("paint",Vector3(x,.446,z+(-.025 if front else .025)),Vector3(.055,.255,.06))
		active="Details"
		for y in [.37,.40,.43,.46,.49,.52]: box("detail",Vector3(0,y,z+(-.015 if front else .015)),Vector3(1.27,.007,.012),Color("293136"))
	# Bonnet shutlines and a small physical crest.
	for s in [-1.0,1.0]:
		for j in 7:
			var za := lerpf(-2.10,-.78,j/7.0)
			var zb := lerpf(-2.10,-.78,(j+1)/7.0)
			beam("detail",hood(s*.56,za)+Vector3.UP*.006,hood(s*.56,zb)+Vector3.UP*.006,.006,DARK)
	box("detail",Vector3(0,.771,-1.93),Vector3(.047,.012,.069),GOLD)
	# Engine grille with raised louvres and dark holes beneath.
	box("detail",Vector3(0,.884,1.64),Vector3(1.15,.018,.48),DARK)
	for j in 9: box("detail",Vector3(0,.906,1.44+j*.046),Vector3(1.13,.018,.022),Color("40494c"))
	# Sculpted ducktail, compact supports and contrasting trailing lip.
	active = "Shell"
	for s in [-1.0,1.0]: box("paint",Vector3(s*.57,.94,2.03),Vector3(.075,.23,.13))
	quad("paint",Vector3(-.92,.99,1.91),Vector3(.92,.99,1.91),Vector3(.89,1.105,2.21),Vector3(-.89,1.105,2.21),Vector3.UP)
	quad("paint",Vector3(-.89,1.105,2.21),Vector3(.89,1.105,2.21),Vector3(.89,1.04,2.23),Vector3(-.89,1.04,2.23),Vector3.BACK)
	quad("paint",Vector3(-.92,.99,1.91),Vector3(.92,.99,1.91),Vector3(.89,1.04,2.23),Vector3(-.89,1.04,2.23),Vector3.DOWN)
	for s in [-1.0,1.0]: triangle("paint",Vector3(s*.92,.99,1.91),Vector3(s*.89,1.105,2.21),Vector3(s*.89,1.04,2.23),Vector3(s,0,0))
	active = "Details"
	box("detail",Vector3(0,1.111,2.205),Vector3(1.80,.017,.052),DARK)
	for x in [-.56,.56]:
		box("detail",Vector3(x,.305,2.26),Vector3(.21,.105,.06),METAL)
		box("detail",Vector3(x,.305,2.293),Vector3(.16,.065,.01),DARK)
	# Wipers lie on the windshield; no floating cylinders.
	for x in [-.36,.30]: beam("detail",Vector3(x-.12,.855,-.685),Vector3(x+.21,.875,-.664),.013,DARK)
	# Wheel tubs close the view through the car while keeping an actual arch gap.
	for s in [-1.0,1.0]:
		for z in [-1.28,1.22]:
			tint=DARK
			var center := Vector3(s*.77,.36,z)
			for i in 12:
				var a:=PI*i/12.0
				var b:=PI*(i+1)/12.0
				triangle("detail",center+Vector3(0,sin(a)*.432,cos(a)*.432),center+Vector3(0,sin(b)*.432,cos(b)*.432),center,Vector3(s,0,0))
			quad("detail",center+Vector3(0,0,-.432),center+Vector3(0,0,.432),center+Vector3(0,-.115,.432),center+Vector3(0,-.115,-.432),Vector3(s,0,0))
			tint=Color.WHITE

func hood(u: float,z: float) -> Vector3:
	var center_y := lerpf(.72,.81,clampf((z+2.23)/1.5,0,1))
	var rise := pow(absf(u),2.3)*(belt(z)-center_y)
	return Vector3(u*(width(z)-.055),center_y+rise,z)

func ellipse(key: String, center: Vector3, axis_u: Vector3, axis_v: Vector3, outer: float, inner: float, normal: Vector3, color: Color, segments := 24) -> void:
	tint = color
	for i in segments:
		var a := TAU*i/segments
		var b := TAU*(i+1)/segments
		var da := axis_u*cos(a)+axis_v*sin(a)
		var db := axis_u*cos(b)+axis_v*sin(b)
		if inner==0.0: triangle(key,center+da*outer,center+db*outer,center,normal)
		else: quad(key,center+da*outer,center+db*outer,center+db*inner,center+da*inner,normal)
	tint = Color.WHITE

func lamps() -> void:
	for s in [-1.0,1.0]:
		var center := Vector3(s*.685,.836,-1.824)
		var u := Vector3(.15,0,0)
		var v := Vector3(0,.145,.103)
		var n := Vector3(0,.58,-.82)
		# A closed, painted nacelle seats the lens in the fender. The reverse
		# camera sees bodywork, not the back of a floating emissive disc.
		active="Shell"
		for i in 24:
			var a:=TAU*i/24.0
			var b:=TAU*(i+1)/24.0
			var pa:=center+(u*cos(a)+v*sin(a))*1.21
			var pb:=center+(u*cos(b)+v*sin(b))*1.21
			var za:=pa.z+.14
			var zb:=pb.z+.14
			var qa:=hood(pa.x/(width(za)-.055),za)+Vector3.UP*.002
			var qb:=hood(pb.x/(width(zb)-.055),zb)+Vector3.UP*.002
			quad("paint",pa,pb,qb,qa,Vector3(cos(a),sin(a),.35))
		active = "Details"
		ellipse("detail",center,u,v,1.20,1.0,n,DARK)
		ellipse("detail",center+n*.002,u,v,1.05,.92,n,METAL)
		active = "HeadlightL" if s < 0 else "HeadlightR"
		ellipse("headlight",center+n*.005,u,v,.925,0,n,Color.WHITE)
		active = "Details"
		# Lens ribs are shallow and broad enough to stay stable at gameplay distance.
		for x in [-.065,0.0,.065]: beam("detail",center+Vector3(x,-.094,-.068)+n*.008,center+Vector3(x,.094,.068)+n*.008,.006,Color("9dafb4"))
		box("detail",Vector3(s*.756,.562,-2.246),Vector3(.13,.038,.016),Color("b77637"))
	active = "Tail"
	box("tail",Vector3(0,.692,2.247),Vector3(1.54,.10,.022))
	active = "Details"
	box("detail",Vector3(0,.758,2.248),Vector3(1.62,.020,.023),DARK)
	box("detail",Vector3(0,.626,2.248),Vector3(1.62,.020,.023),DARK)
	for x in [-.52,-.26,0.0,.26,.52]: box("detail",Vector3(x,.692,2.262),Vector3(.014,.10,.012),DARK)
	box("detail",Vector3(0,.487,2.249),Vector3(.32,.105,.015),Color("b8bdb5"))

func wheels() -> void:
	for s in [-1.0,1.0]:
		for z in [-1.28,1.22]:
			active = "Wheel_%s_%s" % ["L" if s < 0 else "R","F" if z < 0 else "R"]
			var c := Vector3(s*.86,.36,z)
			var profile := [Vector2(-.105,.27),Vector2(-.105,.32),Vector2(-.075,.354),Vector2(.075,.354),Vector2(.119,.32),Vector2(.122,.256)]
			for j in profile.size()-1:
				for i in 24:
					var a := TAU*i/24.0
					var b := TAU*(i+1)/24.0
					var pa: Vector2 = profile[j]
					var pb: Vector2 = profile[j+1]
					tint = Color("1b2025") if j==2 else Color("262c31")
					quad("wheel",c+Vector3(s*pa.x,sin(a)*pa.y,cos(a)*pa.y),c+Vector3(s*pa.x,sin(b)*pa.y,cos(b)*pa.y),c+Vector3(s*pb.x,sin(b)*pb.y,cos(b)*pb.y),c+Vector3(s*pb.x,sin(a)*pb.y,cos(a)*pb.y),Vector3(s*.3,sin(a),cos(a)))
			var face := c+Vector3(s*.126,0,0)
			ellipse("wheel",face,Vector3.UP,Vector3.BACK,.262,.231,Vector3(s,0,0),METAL)
			ellipse("wheel",face-Vector3(s*.016,0,0),Vector3.UP,Vector3.BACK,.231,0,Vector3(s,0,0),DARK)
			ellipse("wheel",face+Vector3(s*.001,0,0),Vector3.UP,Vector3.BACK,.207,.079,Vector3(s,0,0),Color("53585a"))
			# Five tapered forged spokes, each split by a dark channel.
			for j in 5:
				var a := TAU*j/5.0+.12
				var radial := Vector3(0,sin(a),cos(a))
				var tangent := Vector3(0,cos(a),-sin(a))
				var at := face+Vector3(s*.009,0,0)
				tint = GOLD
				quad("wheel",at+radial*.055-tangent*.035,at+radial*.055+tangent*.035,at+radial*.237+tangent*.026,at+radial*.237-tangent*.026,Vector3(s,0,0))
				beam("wheel",at+radial*.105+Vector3(s*.003,0,0),at+radial*.212+Vector3(s*.003,0,0),.012,DARK)
				# Lug bolts and rotor perforations are baked into the same draw.
				ellipse("wheel",at+radial*.048,Vector3.UP,Vector3.BACK,.008,0,Vector3(s,0,0),METAL,6)
			for j in 15:
				var a := TAU*j/15.0
				ellipse("wheel",face+Vector3(s*.003,sin(a)*.175,cos(a)*.175),Vector3.UP,Vector3.BACK,.011,0,Vector3(s,0,0),DARK,5)
			ellipse("wheel",face+Vector3(s*.018,0,0),Vector3.UP,Vector3.BACK,.068,0,Vector3(s,0,0),GOLD,16)
			ellipse("wheel",face+Vector3(s*.020,0,0),Vector3.UP,Vector3.BACK,.030,0,Vector3(s,0,0),DARK,12)
			tint = Color.WHITE

func material(key: String) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.vertex_color_use_as_albedo = true
	m.roughness = .57
	m.albedo_color = Color.WHITE
	if key == "paint":
		m.albedo_color = Color("b83632")
		m.metallic = .3
		m.roughness = .40
		m.metallic_specular = .32
	elif key == "glass":
		m.albedo_color = Color("334f60")
		m.metallic = .4
		m.roughness = .20
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif key in ["wheel","detail"]:
		m.metallic = .35
		m.roughness = .48
	elif key in ["headlight","tail"]:
		m.albedo_color = Color("d3e3e6") if key == "headlight" else Color("a82425")
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = .3 if key == "headlight" else .65
		m.roughness = .22
	materials[key] = m
	return m

func soften(tool: SurfaceTool) -> SurfaceTool:
	# Average coincident corners within 50 degrees. The body remains low polygon;
	# smooth normals replace the dense tessellation formerly used for curves.
	var mesh := tool.commit()
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var neighbors := {}
	for i in points.size():
		var key := Vector3i((points[i]*100000).round())
		if not neighbors.has(key): neighbors[key]=[]
		neighbors[key].append(i)
	var smoothed := normals.duplicate()
	for i in points.size():
		var normal := Vector3.ZERO
		for j: int in neighbors[Vector3i((points[i]*100000).round())]:
			if normals[i].dot(normals[j]) > .6428: normal += normals[j]
		smoothed[i]=normal.normalized()
	arrays[Mesh.ARRAY_NORMAL]=smoothed
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var output := SurfaceTool.new()
	output.create_from(result,0)
	return output

func run() -> void:
	model = Node3D.new()
	model.name = "InfernusGT"
	model.set_meta("fleet_finish",true)
	model.set_meta("sport_coupe_gt_version",1)
	body()
	lamps()
	wheels()
	var nodes := {}
	for bucket: String in groups:
		var parts := bucket.split("/")
		var label := parts[0]
		var key := parts[1]
		if not nodes.has(label):
			var node := MeshInstance3D.new()
			node.name = label
			node.mesh = ArrayMesh.new()
			model.add_child(node)
			node.owner = model
			nodes[label] = node
		var node: MeshInstance3D = nodes[label]
		var tool: SurfaceTool = groups[bucket]
		tool.index()
		if key=="paint": tool=soften(tool)
		tool.set_material(material(key))
		tool.commit(node.mesh)
		var keys: Array = node.get_meta("gt_surface_material_keys",[])
		keys.append(key)
		node.set_meta("gt_surface_material_keys",keys)
	for label: String in nodes:
		var node: MeshInstance3D = nodes[label]
		if label.begins_with("Door"):
			node.set_meta("coupe_gt_door_side",-1 if label=="DoorL" else 1)
		if label.begins_with("Wheel"):
			node.set_meta("wheel_center",Vector3(-.86 if "_L_" in label else .86,.36,-1.28 if label.ends_with("_F") else 1.22))
			node.set_meta("wheel_spins",true)
		if label=="Tail":
			node.set_meta("coupe_damage_material_key","tail")
			node.material_override = material("tail")
	var destination := OUTPUT if "--install" in OS.get_cmdline_user_args() else "res://evidence/sport-coupe-redesign/candidate.scn"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir()))
	var packed := PackedScene.new()
	var result := packed.pack(model)
	if result == OK: result = ResourceSaver.save(packed,destination,ResourceSaver.FLAG_BUNDLE_RESOURCES)
	var tris := 0
	var surfaces := 0
	for node: MeshInstance3D in nodes.values():
		surfaces += node.mesh.get_surface_count()
		tris += node.mesh.get_faces().size()/3
	print("SPORT_GT_BAKED path=",destination," meshes=",nodes.size()," surfaces=",surfaces," triangles=",tris," status=",result)
	model.free()
	quit(0 if result==OK else 1)
