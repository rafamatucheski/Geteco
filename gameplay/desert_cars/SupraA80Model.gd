extends RefCounted
## A80 coupe authored in metres, nose at -Z. Shared fleet batches retain paint,
## animated wheels, doors, damage and headlight semantics without per-frame work.
const SHAPE := preload("res://gameplay/desert_cars/DesertCarModel.gd")
const SURFACE := preload("res://gameplay/desert_cars/SupraA80Shape.gd")

static func create(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "ToyotaSupraA80"
	var paint := SHAPE._material(Color(str(s.color)),.32,.32,"paint")
	var trim := SHAPE._material(Color("101619"),.56,.15,"trim")
	var glass := SHAPE._material(Color("233d49"),.16,.40,"glass")
	var rubber := SHAPE._material(Color("14171a"),.90,0,"rubber")
	var alloy := SHAPE._material(Color("b8c4ce"),.20,.82,"wheel_alloy")
	var metal := SHAPE._material(Color("aebbc2"),.25,.78,"alloy")
	var front := SHAPE._material(Color("92aeba"),.18,.38,"headlight")
	var projector := SHAPE._material(Color("cfdae0"),.14,.60,"optic_projector")
	var tail := SHAPE._material(Color("bb2434"),.23,.20,"tail")
	var amber := SHAPE._material(Color("c48237"),.28,.14,"indicator")
	var caliper := SHAPE._material(Color("8f2635"),.44,.24,"brake_caliper")
	var brake_metal := SHAPE._material(Color("58616a"),.44,.65,"brake_disc")
	SURFACE.build(root,s,paint,glass,trim)
	_lamps(root,s,trim,front,projector,tail,amber,metal)
	_fascia(root,s,paint,trim,metal)
	_spoiler(root,s,paint)
	var w := float(s.size[0])
	var l := float(s.size[2])
	var belt := float(s.shoulder)
	for side in [-1.0,1.0]:
		SHAPE._beam(root,"MirrorStalk",Vector3(side*.68,belt+.045,-.63),Vector3(side*.89,belt+.15,-.58),.045,trim)
		_mirror(root,Vector3(side*.94,belt+.17,-.59),side,paint,metal)
		SHAPE._box(root,"FlushDoorHandle",Vector3(.018,.042,.15),Vector3(side*w*.482,belt-.09,.57),trim)
		for z in [l*float(s.cabin_front),l*float(s.door_back)]:
			SHAPE._box(root,"DoorSeam",Vector3(.009,.43,.010),Vector3(side*w*.483,.53,z),trim)
		SHAPE._box(root,"SideSkirt",Vector3(.055,.08,1.73),Vector3(side*w*.482,.245,-.015),paint)
		# The A80's small intake ahead of the rear wheel and body-colour louvre.
		SHAPE._side_panel(root,"QuarterIntake",side*w*.482,[Vector2(.84,.44),Vector2(.905,.465),Vector2(.925,.585),Vector2(.84,.58)],trim)
		SHAPE._beam(root,"QuarterIntakeLip",Vector3(side*w*.485,.435,.833),Vector3(side*w*.485,.584,.833),.019,paint)
		# Wheelbase is independent of overall length; long overhangs identify A80.
		var wheel_spec := s.duplicate(true)
		wheel_spec.size[2] = float(s.wheelbase)/.63
		wheel_spec.style = "gt"
		for axle in [-1.0,1.0]:
			SHAPE._wheel(root,wheel_spec,axle,side,rubber,alloy,trim,metal)
			_brake(root,Vector3(side*w*.445,float(s.wheel_radius),axle*float(s.wheelbase)*.5),side,brake_metal,caliper)
	SHAPE._beam(root,"RearWiper",Vector3(.35,.86,1.61),Vector3(-.08,.91,1.51),.015,trim)
	SHAPE._beam(root,"WindscreenWiper",Vector3(-.49,.846,-.754),Vector3(.18,.858,-.726),.014,trim)
	preload("res://gameplay/desert_cars/DesertCarWheelShape.gd").exhaust(root,Vector3(-.58,.30,2.19),metal)
	SHAPE._batch(root)
	root.set_meta("desert_body_style","coupe")
	root.set_meta("desert_edition","street")
	root.set_meta("vehicle_identity","toyota_supra_a80")
	root.set_meta("vehicle_interior_spec",preload("res://gameplay/desert_cars/DesertCarInterior.gd").spec(s))
	return root

static func _lamps(root: Node3D,s: Dictionary,trim: Material,front: Material,projector: Material,tail: Material,amber: Material,metal: Material) -> void:
	for side in [-1.0,1.0]:
		# An elliptical lens follows every point of the bonnet; no hovering plane.
		var center := Vector2(side*.54,-2.01)
		var housing := SURFACE._tool()
		_deck_ellipse(housing,s,center,Vector2(.239,.153),.007)
		SURFACE._commit(root,"A80HeadlightSeal",housing,trim)
		var lens := SURFACE._tool()
		_deck_ellipse(lens,s,center,Vector2(.221,.136),.011)
		SURFACE._commit(root,"A80Headlight",lens,front)
		var bezel := SURFACE._tool()
		var optics := SURFACE._tool()
		for j in 3:
			var point := center+Vector2(side*(float(j)-1.0)*.13,.015*float(j-1))
			_deck_ellipse(bezel,s,point,Vector2(.058,.074),.014)
			_deck_ellipse(optics,s,point,Vector2(.043,.057),.018)
		SURFACE._commit(root,"A80ProjectorBezels",bezel,trim)
		SURFACE._commit(root,"A80TripleProjectors",optics,projector)
		# Four circular rear lamps, with concentric recessed optical rings.
		for j in 2:
			var center_x: float = side*(.35+float(j)*.225)
			_rear_disc(root,s,"RoundTailHousing",Vector2(center_x,.649),.122,.009,trim)
			_rear_disc(root,s,"RoundTailRim",Vector2(center_x,.649),.103,.013,metal)
			_rear_disc(root,s,"RoundTailLens",Vector2(center_x,.649),.094,.018,tail)
			_rear_disc(root,s,"RoundTailCore",Vector2(center_x,.649),.062,.020,tail)
		# Front bumper indicators and the separate small reverse light.
		_fascia_patch(root,s,"A80FrontIndicator",side*.635,.405,.16,.045,-1.0,.014,amber)
		_fascia_patch(root,s,"ReverseLens",side*.51,.385,.16,.043,1.0,.014,projector)

static func _deck_ellipse(st: SurfaceTool,s: Dictionary,center: Vector2,radii: Vector2,lift: float) -> void:
	# Four rings make the curved transparent lens and its perimeter sit flush.
	for ring in 4:
		for segment in 28:
			var a := float(segment)*TAU/28.0
			var b := float(segment+1)*TAU/28.0
			var inner := float(ring)/4.0
			var outer := float(ring+1)/4.0
			var aa := center+Vector2(cos(a),sin(a))*radii*inner
			var ab := center+Vector2(cos(b),sin(b))*radii*inner
			var bb := center+Vector2(cos(b),sin(b))*radii*outer
			var ba := center+Vector2(cos(a),sin(a))*radii*outer
			SURFACE._quad(st,SURFACE.deck_point(s,aa.x,aa.y)+Vector3.UP*lift,SURFACE.deck_point(s,ab.x,ab.y)+Vector3.UP*lift,SURFACE.deck_point(s,bb.x,bb.y)+Vector3.UP*lift,SURFACE.deck_point(s,ba.x,ba.y)+Vector3.UP*lift,Vector3.UP)

static func _rear_disc(root: Node3D,s: Dictionary,label: String,center: Vector2,radius: float,lift: float,mat: Material) -> void:
	var st := SURFACE._tool()
	var z := float(s.size[2])*.495
	var point := Vector3(center.x,center.y,SURFACE._rounded_z(s,center.x,z)+lift)
	for segment in 32:
		var a := float(segment)*TAU/32.0
		var b := float(segment+1)*TAU/32.0
		var aa := center+Vector2(cos(a),sin(a))*radius
		var bb := center+Vector2(cos(b),sin(b))*radius
		SURFACE._triangle(st,point,Vector3(aa.x,aa.y,SURFACE._rounded_z(s,aa.x,z)+lift),Vector3(bb.x,bb.y,SURFACE._rounded_z(s,bb.x,z)+lift),Vector3.BACK)
	var part := SURFACE._commit(root,label,st,mat)
	if mat.resource_name=="tail": part.set_meta("coupe_damage_material_key","tail")

static func _fascia(root: Node3D,s: Dictionary,paint: Material,trim: Material,metal: Material) -> void:
	# Body-colour bumper remains part of the continuous shell; recesses follow it.
	_fascia_patch(root,s,"A80CentralIntake",0,.365,.98,.19,-1.0,.010,trim)
	for side in [-1.0,1.0]:
		_fascia_patch(root,s,"A80SideIntake",side*.635,.298,.16,.085,-1.0,.013,trim)
		_fascia_patch(root,s,"A80NoseLip",side*.64,.244,.27,.035,-1.0,.012,paint)
	for i in 6:
		_fascia_patch(root,s,"IntercoolerFin",0,.29+float(i)*.026,.69,.008,-1.0,.017,metal)
	_fascia_patch(root,s,"RearPlateRecess",0,.57,.47,.23,1.0,.007,trim)
	var plate := SHAPE._material(Color("d3d9dc"),.72,.03,"plate")
	_fascia_patch(root,s,"RearPlate",0,.57,.34,.105,1.0,.014,plate)
	_fascia_patch(root,s,"FrontPlate",0,.548,.34,.09,-1.0,.011,plate)
	_fascia_patch(root,s,"RearValance",0,.257,1.23,.048,1.0,.009,trim)

static func _fascia_patch(root: Node3D,s: Dictionary,label: String,x: float,y: float,width: float,height: float,end: float,lift: float,mat: Material) -> void:
	var st := SURFACE._tool()
	var z := end*float(s.size[2])*.495
	for i in 12:
		var a := x-width*.5+width*float(i)/12.0
		var b := x-width*.5+width*float(i+1)/12.0
		var za := SURFACE._rounded_z(s,a,z)+end*lift
		var zb := SURFACE._rounded_z(s,b,z)+end*lift
		SURFACE._quad(st,Vector3(a,y-height*.5,za),Vector3(b,y-height*.5,zb),Vector3(b,y+height*.5,zb),Vector3(a,y+height*.5,za),Vector3(0,0,end))
	SURFACE._commit(root,label,st,mat)

static func _spoiler(root: Node3D,_s: Dictionary,paint: Material) -> void:
	# The factory A80 hoop: swept, thick feet and a rounded raised aerofoil.
	var st := SURFACE._tool()
	for side in [-1.0,1.0]:
		var profile := [Vector2(1.76,.78),Vector2(1.94,.78),Vector2(1.965,1.23),Vector2(1.78,1.20)]
		for i in 4:
			var a: Vector2 = profile[i]
			var b: Vector2 = profile[(i+1)%4]
			SURFACE._quad(st,Vector3(side*.692,a.y,a.x),Vector3(side*.692,b.y,b.x),Vector3(side*.758,b.y,b.x),Vector3(side*.758,a.y,a.x),Vector3(0,b.x-a.x,a.y-b.y))
		for x in [side*.692,side*.758]:
			SURFACE._quad(st,Vector3(x,profile[0].y,profile[0].x),Vector3(x,profile[1].y,profile[1].x),Vector3(x,profile[2].y,profile[2].x),Vector3(x,profile[3].y,profile[3].x),Vector3(signf(x)*(1.0 if absf(x)>.72 else -1.0),0,0))
	for i in 24:
		var xa := lerpf(-.79,.79,float(i)/24.0)
		var xb := lerpf(-.79,.79,float(i+1)/24.0)
		for j in 12:
			var a := TAU*float(j)/12.0
			var b := TAU*float(j+1)/12.0
			var top_a := 1.216+.044*(1.0-pow(xa/.79,2.0))
			var top_b := 1.216+.044*(1.0-pow(xb/.79,2.0))
			SURFACE._quad(st,Vector3(xa,top_a+sin(a)*.034,1.86+cos(a)*.17),Vector3(xb,top_b+sin(a)*.034,1.86+cos(a)*.17),Vector3(xb,top_b+sin(b)*.034,1.86+cos(b)*.17),Vector3(xa,top_a+sin(b)*.034,1.86+cos(b)*.17),Vector3(0,sin((a+b)*.5),cos((a+b)*.5)))
	for side in [-1.0,1.0]:
		for j in 12:
			var a := TAU*float(j)/12.0
			var b := TAU*float(j+1)/12.0
			SURFACE._triangle(st,Vector3(side*.79,1.216,1.86),Vector3(side*.79,1.216+sin(a)*.034,1.86+cos(a)*.17),Vector3(side*.79,1.216+sin(b)*.034,1.86+cos(b)*.17),Vector3(side,0,0))
	SURFACE._commit(root,"A80HoopSpoiler",st,paint)

static func _brake(root: Node3D,center: Vector3,side: float,metal: Material,red: Material) -> void:
	var disc := SHAPE._cylinder(root,"BrakeDisc",.19,.016,center+Vector3(side*.076,0,0),metal)
	disc.set_meta("wheel_center",center)
	# Caliper stays fixed to the axle; it is not part of the spinning wheel batch.
	SHAPE._box(root,"BrakeCaliper",Vector3(.035,.12,.07),center+Vector3(side*.086,0,-.17),red)

static func _mirror(root: Node3D,center: Vector3,side: float,paint: Material,metal: Material) -> void:
	var part := MeshInstance3D.new()
	part.name="A80RoundedMirror"
	var sphere := SphereMesh.new()
	sphere.radius=.5
	sphere.height=1.0
	sphere.radial_segments=16
	sphere.rings=8
	part.mesh=sphere
	part.material_override=paint
	part.position=center
	part.scale=Vector3(.20,.115,.25)
	root.add_child(part)
	SHAPE._box(root,"MirrorGlass",Vector3(.018,.060,.14),center+Vector3(side*.081,0,.025),metal)
