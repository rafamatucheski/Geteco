extends RefCounted
## Authored silhouettes, open wheel arches and material batches. All geometry is
## built once per catalog ID; the fleet keeps its normal paint, doors and wheels.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
static func create(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "DesertCar"
	if s.is_empty(): return root
	var w := float(s["size"][0])
	var l := float(s["size"][2])
	var body := str(s.body)
	var style := str(s.get("style","street"))
	var shoulder := float(s.get("shoulder",.78))
	var radius := float(s.wheel_radius)
	var paint := _material(Color(str(s.color)),.29,.48,"paint")
	var rubber := _material(Color("14191d"),.90,0.0,"rubber")
	var metal := _material(Color("9ca7ac"),.23,.82,"alloy")
	var dark := _material(Color("202a31"),.55,.25,"trim")
	var glass := _material(Color("24434f"),.16,.42,"glass")
	var rim_color := Color("c3a965") if style=="rally" else (Color("d4dad8") if style=="drag" else (Color("849096") if style=="gt" else Color("b3bcc2")))
	var wheel_metal := _material(rim_color,.23,.77,"wheel_alloy")
	var accent := _material(Color(str(s.get("livery_color","6f7f84"))),.36,.35,"body_accent")
	var front := l*float(s.cabin_front)
	var back := l*float(s.cabin_back)
	var door_back := l*float(s.door_back)
	# Narrower hood/boot shoulders and a faceted nose stop the shell looking like
	# a single box. The sides stay planar where the real door cutter needs them.
	if body=="coupe":
		preload("res://gameplay/desert_cars/DesertZShape.gd").build(root,s,paint,glass,dark)
	else:
		_body(root,s,paint)
		preload("res://gameplay/desert_cars/DesertCarCabin.gd").create(root,s,paint,glass,dark)
	for side in [-1.0,1.0]:
		# The mounting foot sits below the sloped A-pillar. A horizontal stalk at
		# mirror height would begin in empty air on the tapered cabin.
		_beam(root,"MirrorStem",Vector3(side*w*.390,shoulder+.065,front+.17),Vector3(side*w*.510,shoulder+.185,front+.13),.044,dark)
		_box(root,"Mirror",Vector3(.135,.10,.18),Vector3(side*w*.515,shoulder+.185,front+.13),paint)
		# Reflective metal avoids including an exterior mirror in the cabin's
		# glazing bounds, without adding another material batch to every car.
		_box(root,"MirrorGlass",Vector3(.012,.065,.13),Vector3(side*w*.553,shoulder+.19,front+.145),metal)
		_box(root,"DoorHandle",Vector3(.022,.038,.145),Vector3(side*w*.488,shoulder-.105,door_back-.16),metal)
		_box(root,"DoorSeam",Vector3(.012,shoulder-radius*.83-.075,.013),Vector3(side*w*.484,(shoulder+radius*.83)*.5-.035,door_back),dark)
		_box(root,"DoorLeadingSeam",Vector3(.011,shoulder-radius*.86-.11,.010),Vector3(side*w*.484,(shoulder+radius*.86)*.5-.04,front),dark)
		var sill_height := .095 if style!="street" else .055
		_box(root,"SideSkirt",Vector3(.065,sill_height,l*.40),Vector3(side*w*.485,radius*.87+sill_height*.25,0),dark if style!="street" else paint)
		if style!="street":
			_box(root,"SkirtAccent",Vector3(.010,.025,l*.40),Vector3(side*w*.522,radius*.94,.01),accent)
		if body=="sedan":
			_box(root,"RearDoorHandle",Vector3(.022,.038,.14),Vector3(side*w*.488,shoulder-.105,back-.12),metal)
			_box(root,"RearDoorSeam",Vector3(.012,shoulder-radius-.06,.012),Vector3(side*w*.484,(shoulder+radius)*.5-.02,back-.03),dark)
		if body=="muscle":
			for fin in 3:
				_box(root,"QuarterLouvre",Vector3(.017,.04,.22),Vector3(side*w*.417,shoulder+.12+float(fin)*.058,l*.285-float(fin)*.036),dark)
		if body=="hatch":
			_box(root,"RearQuarterIntake",Vector3(.024,.13,.25),Vector3(side*w*.486,shoulder-.115,l*.226),dark)
			for fin in 3:
				_box(root,"HatchIntakeSlat",Vector3(.030,.017,.23),Vector3(side*w*.497,shoulder-.157+fin*.041,l*.226),paint)
	if body!="coupe": _fascia(root,s,paint,metal,dark)
	_body_details(root,s,paint,metal,dark,accent)
	for axle in [-1.0,1.0]:
		for side in [-1.0,1.0]:
			if body!="coupe": _arch(root,s,axle,side,dark if body=="pickup" else paint)
			_wheel(root,s,axle,side,rubber,wheel_metal,dark,metal)
	# Consolidate before vinyl so its vertex colours and door semantics stay intact.
	_batch(root)
	preload("res://gameplay/desert_cars/DesertCarLivery.gd").apply(root,s)
	root.set_meta("desert_body_style",body)
	root.set_meta("desert_edition",style)
	root.set_meta("vehicle_interior_spec",preload("res://gameplay/desert_cars/DesertCarInterior.gd").spec(s))
	return root

static func _body(root: Node3D,s: Dictionary,paint: Material) -> void:
	var w := float(s["size"][0])
	var l := float(s["size"][2])
	var shoulder := float(s.shoulder)
	var radius := float(s.wheel_radius)
	var body := str(s.body)
	var sill := radius*.72
	var nose_y := shoulder*(.72 if body=="coupe" else (.90 if body=="pickup" else .85))
	var tail_y := shoulder*(.88 if body=="coupe" else .96)
	var z_flat := l*float(s.hood_flat_front)
	var top := [Vector2(-l*.495,nose_y),Vector2(z_flat,shoulder-.045),Vector2(l*.435,shoulder-.045),Vector2(l*.49,tail_y)]
	var profile: Array = top.duplicate()
	profile.append(Vector2(l*.485,sill))
	# Genuine concave openings: the side skin never covers the upper tyre.
	var arch_radius := radius+.036
	var start := asin((sill-radius)/arch_radius)
	for axle in [1.0,-1.0]:
		for segment in 15:
			var angle := lerpf(start,PI-start,float(segment)/14.0)
			profile.append(Vector2(axle*l*.315+cos(angle)*arch_radius,radius+sin(angle)*arch_radius))
	profile.append(Vector2(-l*.485,sill))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var polygon := PackedVector2Array(profile)
	var triangles := Geometry2D.triangulate_polygon(polygon)
	for side in [-1.0,1.0]:
		for i in range(0,triangles.size(),3):
			var a := Vector3(side*w*.48,profile[triangles[i]].y,profile[triangles[i]].x)
			var b := Vector3(side*w*.48,profile[triangles[i+1]].y,profile[triangles[i+1]].x)
			var c := Vector3(side*w*.48,profile[triangles[i+2]].y,profile[triangles[i+2]].x)
			_triangle(st,a,b,c,Vector3(side,0,0))
	# Close the nose, tail and underbody; leave the upper edge for the inset deck.
	for i in range(3,profile.size()):
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[(i+1)%profile.size()]
		# The lower contour runs rear -> front. Its outward normal is the
		# opposite of the old winding, which culled both end panels from outside.
		var outward := Vector3(0,b.x-a.x,-(b.y-a.y)).normalized()
		_quad(st,Vector3(-w*.48,a.y,a.x),Vector3(w*.48,a.y,a.x),Vector3(w*.48,b.y,b.x),Vector3(-w*.48,b.y,b.x),outward)
	# The inset deck is 45 mm above the side contour. Close its end bevel,
	# otherwise the engine bay / boot can be seen through a full-width slit.
	for end in [-1,1]:
		if body=="pickup" and end>0: continue # Open bed has its authored tailgate.
		var edge: Vector2 = top[0] if end<0 else top[-1]
		_quad(st,Vector3(-w*.48,edge.y,edge.x),Vector3(w*.48,edge.y,edge.x),Vector3(w*.425,edge.y+.045,edge.x),Vector3(-w*.425,edge.y+.045,edge.x),Vector3(0,0,end))
	for side in [-1.0,1.0]:
		for i in range(top.size()-1):
			var a: Vector2 = top[i]
			var b: Vector2 = top[i+1]
			_quad(st,Vector3(side*w*.48,a.y,a.x),Vector3(side*w*.48,b.y,b.x),Vector3(side*w*.425,b.y+.045,b.x),Vector3(side*w*.425,a.y+.045,a.x),Vector3(side,.6,0).normalized())
	for i in range(top.size()-1):
		var a: Vector2 = top[i]
		var b: Vector2 = top[i+1]
		# The truck's bed has an open, lower floor, not a painted solid deck.
		if body=="pickup" and i==1: b=Vector2(l*.075,b.y)
		if body=="pickup" and i>1: continue
		# The cabin is hollow: keep the hood and boot, but no horizontal slab at
		# the occupants' shoulders under the windscreen and side windows.
		var cabin_front := l*float(s.cabin_front)
		var cabin_back := l*float(s.cabin_back)
		var spans := [Vector2(a.x,minf(b.x,cabin_front)),Vector2(maxf(a.x,cabin_back),b.x)]
		for span: Vector2 in spans:
			if span.y<=span.x: continue
			var y0 := lerpf(a.y,b.y,(span.x-a.x)/(b.x-a.x))+.045
			var y1 := lerpf(a.y,b.y,(span.y-a.x)/(b.x-a.x))+.045
			_quad(st,Vector3(-w*.425,y0,span.x),Vector3(w*.425,y0,span.x),Vector3(w*.425,y1,span.y),Vector3(-w*.425,y1,span.y),Vector3.UP)
	_mesh(root,"BodyShell",st,paint)

static func _fascia(root: Node3D,s: Dictionary,paint: Material,metal: Material,dark: Material) -> void:
	var first_part := root.get_child_count()
	var w := float(s["size"][0])
	var l := float(s["size"][2])
	var shoulder := float(s.shoulder)
	var radius := float(s.wheel_radius)
	var body := str(s.body)
	var lamp := _material(Color("ebe3c8"),.22,.10,"headlight")
	var red := _material(Color("a72224"),.24,.14,"tail")
	var amber := _material(Color("d98637"),.30,.05,"indicator")
	var plate := _material(Color("d8d3bd"),.70,0.0,"plate")
	for end in [-1.0,1.0]:
		_box(root,"Plate",Vector3(.34,.105,.025),Vector3(0,radius+.085,end*l*.496),plate)
		var bumper_height := .12 if body!="pickup" else .18
		_box(root,"Bumper",Vector3(w*.93,bumper_height,.14),Vector3(0,radius+.045,end*l*.475),metal if body in ["muscle","pickup"] else dark)
	match body:
		"muscle":
			_box(root,"DeepGrille",Vector3(w*.87,.205,.035),Vector3(0,shoulder-.15,-l*.497),dark)
			for row in 4:
				_box(root,"GrilleLouvre",Vector3(w*.43,.014,.018),Vector3(0,shoulder-.22+row*.041,-l*.502),metal)
			for side in [-1.0,1.0]:
				for pair in 2:
					var x: float = side*(w*.265+pair*.215)
					_disc_front(root,"HeadlampRim",.107,.04,Vector3(x,shoulder-.13,-l*.499),metal)
					_disc_front(root,"Headlamp",.083,.047,Vector3(x,shoulder-.13,-l*.501),lamp)
				_box(root,"TailLamp",Vector3(w*.28,.095,.030),Vector3(side*w*.30,shoulder-.115,l*.491),red).set_meta("coupe_damage_material_key","tail")
		"coupe":
			_box(root,"WideIntake",Vector3(w*.60,.13,.045),Vector3(0,radius+.065,-l*.490),dark)
			for side in [-1.0,1.0]:
				var eye := _box(root,"SweptHeadlamp",Vector3(w*.25,.060,.17),Vector3(side*w*.31,shoulder-.14,-l*.459),lamp)
				eye.rotation.y=side*.19
				_box(root,"TailLamp",Vector3(w*.29,.065,.036),Vector3(side*w*.29,shoulder-.10,l*.482),red).set_meta("coupe_damage_material_key","tail")
				_box(root,"FrontBrakeDuct",Vector3(.16,.11,.042),Vector3(side*w*.39,radius+.072,-l*.480),dark)
		"hatch":
			_box(root,"UpperGrille",Vector3(w*.30,.09,.036),Vector3(0,shoulder-.13,-l*.493),dark)
			_box(root,"LowerGrille",Vector3(w*.66,.14,.036),Vector3(0,radius+.14,-l*.493),dark)
			for side in [-1.0,1.0]:
				_box(root,"Headlamp",Vector3(w*.255,.145,.065),Vector3(side*w*.30,shoulder-.135,-l*.477),lamp)
				_box(root,"TailLamp",Vector3(.13,.255,.05),Vector3(side*w*.365,shoulder-.125,l*.477),red).set_meta("coupe_damage_material_key","tail")
				_box(root,"Indicator",Vector3(.058,.10,.025),Vector3(side*w*.418,shoulder-.14,-l*.481),amber)
		"pickup":
			_box(root,"TruckGrilleFrame",Vector3(w*.56,.26,.07),Vector3(0,shoulder-.20,-l*.483),metal)
			_box(root,"TruckGrille",Vector3(w*.50,.20,.078),Vector3(0,shoulder-.20,-l*.485),dark)
			for row in 3:
				_box(root,"TruckGrilleBar",Vector3(w*.49,.025,.022),Vector3(0,shoulder-.26+row*.065,-l*.53+.19),metal)
			for side in [-1.0,1.0]:
				_box(root,"Headlamp",Vector3(w*.20,.20,.068),Vector3(side*w*.365,shoulder-.195,-l*.483),lamp)
				_box(root,"TailLamp",Vector3(.12,.245,.042),Vector3(side*w*.41,shoulder-.14,l*.485),red).set_meta("coupe_damage_material_key","tail")
		_:
			_box(root,"SedanGrilleFrame",Vector3(w*.39,.15,.05),Vector3(0,shoulder-.155,-l*.490),paint)
			_box(root,"SedanGrille",Vector3(w*.33,.11,.06),Vector3(0,shoulder-.155,-l*.492),dark)
			_box(root,"SedanIntercooler",Vector3(w*.48,.15,.035),Vector3(0,radius+.085,-l*.494),dark)
			for side in [-1.0,1.0]:
				_box(root,"Headlamp",Vector3(w*.245,.105,.060),Vector3(side*w*.31,shoulder-.125,-l*.480),lamp)
				_box(root,"TailLamp",Vector3(w*.27,.108,.039),Vector3(side*w*.32,shoulder-.135,l*.484),red).set_meta("coupe_damage_material_key","tail")
				_box(root,"SedanBrakeDuct",Vector3(.17,.13,.045),Vector3(side*w*.37,radius+.10,-l*.478),dark)
	# The nose and tail are sloped. Fractions of total length placed lenses
	# behind the skin on some models and suspended beyond it on others.
	# Mount the actual outward face onto that panel, including its tilt.
	for index in range(first_part,root.get_child_count()):
		var part := root.get_child(index) as MeshInstance3D
		var label := str(part.get_meta("authored_label",part.name))
		var proud := .006
		if label=="HeadlampRim": proud=.008
		elif part.material_override.resource_name in ["headlight","tail"]: proud=.014
		elif label in ["TruckGrilleFrame","SedanGrilleFrame"]: proud=.004
		elif "Grille" in label and ("Bar" in label or "Louvre" in label): proud=.013
		elif label=="Bumper": proud=.030
		elif label=="Plate": proud=.038
		_fit_fascia_part(part,s,signf(part.position.z),proud)

static func _fit_fascia_part(part: MeshInstance3D,s: Dictionary,end: float,proud: float) -> void:
	var shoulder := float(s.shoulder)
	var length := float(s["size"][2])
	var bottom := float(s.wheel_radius)*.72
	var top := shoulder*(.90 if s.body=="pickup" else .85) if end<0 else shoulder*.96
	var low_z := end*length*.485
	var high_z := end*length*(.495 if end<0 else .49)
	var slope := (high_z-low_z)/(top-bottom)
	var tilt := Basis(Vector3.RIGHT,atan(slope))
	var extent := (Transform3D(part.basis,Vector3.ZERO)*part.mesh.get_aabb()).size*.5
	# Round optical glass and its larger rim share one mounting centre.
	if part.mesh is CylinderMesh and part.material_override.resource_name=="headlight": extent.y=.107
	var x := clampf(part.position.x,-float(s["size"][0])*.48+extent.x+.012,float(s["size"][0])*.48-extent.x-.012)
	var y := clampf(part.position.y,bottom+extent.y+.012,top-extent.y-.012)
	var face := Vector3(x,y,low_z+(y-bottom)*slope+end*proud)
	part.position=face-tilt*Vector3(0,0,end*extent.z)
	part.basis=tilt*part.basis

static func _body_details(root: Node3D,s: Dictionary,paint: Material,metal: Material,dark: Material,accent: Material) -> void:
	var w := float(s["size"][0])
	var h := float(s["size"][1])
	var l := float(s["size"][2])
	var radius := float(s.wheel_radius)
	var shoulder := float(s.shoulder)
	var body := str(s.body)
	var style := str(s.style)
	if body=="pickup":
		_box(root,"BedFloor",Vector3(w*.81,.055,l*.38),Vector3(0,shoulder-.25,l*.275),dark)
		for rib in 7:
			_box(root,"BedRib",Vector3(.025,.024,l*.34),Vector3((rib-3)*w*.095,shoulder-.21,l*.275),metal)
		for side in [-1.0,1.0]:
			_box(root,"BedRail",Vector3(.10,.22,l*.40),Vector3(side*w*.445,shoulder+.035,l*.272),paint)
			_box(root,"BedRailCap",Vector3(.13,.035,l*.40),Vector3(side*w*.445,shoulder+.16,l*.272),dark)
			_box(root,"RunningBoard",Vector3(.17,.09,l*.33),Vector3(side*w*.50,radius*.93,-l*.08),dark)
			_beam(root,"BedRack",Vector3(side*w*.37,shoulder,l*.095),Vector3(side*w*.37,h*.89,l*.12),.074,dark)
		_box(root,"BedRackCross",Vector3(w*.74,.075,.075),Vector3(0,h*.89,l*.12),dark)
		_box(root,"Tailgate",Vector3(w*.84,.30,.08),Vector3(0,shoulder-.005,l*.461),paint)
		_box(root,"TailgateHandle",Vector3(.23,.055,.022),Vector3(0,shoulder+.065,l*.506-.025),dark)
	elif body=="muscle":
		_box(root,"HoodScoop",Vector3(.53,.11,.64),Vector3(0,shoulder+.055,-l*.28),paint if style=="street" else dark)
		_box(root,"HoodScoopMouth",Vector3(.44,.065,.025),Vector3(0,shoulder+.065,-l*.348),dark)
		for side in [-1.0,1.0]:
			_box(root,"QuarterVent",Vector3(.022,.09,.29),Vector3(side*w*.485,shoulder-.105,l*.233),dark)
	elif body=="hatch":
		_box(root,"HatchLip",Vector3(w*.79,.055,.155),Vector3(0,h-.045,l*.31),paint)
		_box(root,"HatchHandle",Vector3(.20,.04,.03),Vector3(0,shoulder+.035,l*.405),dark)
	elif body=="sedan":
		for side in [-1.0,1.0]:
			_box(root,"SideMoulding",Vector3(.018,.031,l*.78),Vector3(side*w*.486,shoulder-.055,0),metal)
			_box(root,"SedanWingStay",Vector3(.095,.20,.16),Vector3(side*w*.34,shoulder+.11,l*.405),paint)
			_box(root,"HoodExtractor",Vector3(.24,.014,.29),Vector3(side*w*.20,shoulder+.012,-l*.305),dark)
			for slit in 4:
				_box(root,"HoodExtractorFin",Vector3(.21,.018,.022),Vector3(side*w*.20,shoulder+.023,-l*.330+slit*.062),paint)
		_box(root,"SedanWing",Vector3(w*.81,.065,.20),Vector3(0,shoulder+.225,l*.405),paint)
	elif body=="coupe":
		var wing_y := shoulder+.25 if style=="gt" else shoulder+.10
		var wing_z := l*.408
		for side in [-1.0,1.0]:
			_box(root,"SpoilerStay",Vector3(.055,wing_y-shoulder,.10),Vector3(side*w*.285,(wing_y+shoulder)*.5,wing_z),dark)
			if style=="gt": _box(root,"WingEndplate",Vector3(.032,.145,.34),Vector3(side*w*.46,wing_y+.025,wing_z),accent)
		_box(root,"Spoiler",Vector3(w*.94,.05,.28 if style=="gt" else .15),Vector3(0,wing_y,wing_z),dark if style=="gt" else paint)
	if style in ["gt","drag","rally"]:
		_box(root,"FrontSplitter",Vector3(w*.96,.045,.20),Vector3(0,radius*.78,-l*.471),dark)
		_box(root,"SplitterAccent",Vector3(w*.88,.018,.020),Vector3(0,radius*.83,-l*.495),accent)
		if style=="gt":
			for side in [-1.0,1.0]:
				_box(root,"FrontCanard",Vector3(.18,.025,.32),Vector3(side*w*.464,radius+.06,-l*.410),dark)
			for fin in 5:
				_box(root,"DiffuserFin",Vector3(.025,.13,.36),Vector3((fin-2)*w*.115,radius*.79,l*.443),dark)
		elif style=="rally":
			for axle in [-1.0,1.0]:
				for side in [-1.0,1.0]:
					_box(root,"MudFlap",Vector3(.18,.22,.027),Vector3(side*w*.455,radius*.68,axle*l*.315+radius*.83),dark)
			_box(root,"RallyRoofVent",Vector3(.36,.085,.21),Vector3(0,h+.015,-l*.025),dark)
		elif style=="drag":
			_box(root,"Ducktail",Vector3(w*.90,.095,.16),Vector3(0,shoulder+.04,l*.442),paint)
			for side in [-1.0,1.0]:
				_box(root,"SideExhaust",Vector3(.065,.07,.39),Vector3(side*w*.49,radius*.76,l*.185),metal)
	for side in [-1.0,1.0] if body=="coupe" else [1.0]:
		preload("res://gameplay/desert_cars/DesertCarWheelShape.gd").exhaust(root,Vector3(side*w*.30,radius*.79,l*.48),metal)

static func _arch(root: Node3D,s: Dictionary,axle: float,side: float,mat: Material) -> void:
	var w := float(s["size"][0])
	var l := float(s["size"][2])
	var radius := float(s.wheel_radius)
	var inner := radius+.036
	var outer := inner+(.045 if s.body=="pickup" else .028)
	var start := asin((radius*.72-radius)/inner)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in 14:
		var a := lerpf(start,PI-start,float(segment)/14.0)
		var b := lerpf(start,PI-start,float(segment+1)/14.0)
		var origin := Vector3(side*w*.483,radius,axle*l*.315)
		_quad(st,origin+Vector3(0,sin(a)*inner,cos(a)*inner),origin+Vector3(0,sin(b)*inner,cos(b)*inner),origin+Vector3(0,sin(b)*outer,cos(b)*outer),origin+Vector3(0,sin(a)*outer,cos(a)*outer),Vector3(side,0,0))
	_mesh(root,"ArchLip",st,mat)

static func _wheel(root: Node3D,s: Dictionary,axle: float,side: float,rubber: Material,alloy: Material,_dark: Material,metal: Material) -> void:
	var w := float(s["size"][0])
	var l := float(s["size"][2])
	var radius := float(s.wheel_radius)
	var style := str(s.style)
	var center := Vector3(side*w*.445,radius,axle*l*.315)
	var width := .31 if style=="drag" and axle>0 else (.27 if s.body=="pickup" else .24)
	var rim_ratio := .72 if style=="gt" else (.56 if s.body=="pickup" else .64)
	var start_count := root.get_child_count()
	_tyre(root,radius,width,center,rubber,rim_ratio)
	preload("res://gameplay/desert_cars/DesertCarWheelShape.gd").rim(root,radius*rim_ratio,width+.008,center,alloy)
	var outer_x := side*(width*.5+.004)
	var spoke_count := 8 if style=="rally" else (6 if s.body=="pickup" else 5)
	for spoke in spoke_count:
		var a := float(spoke)*TAU/float(spoke_count)
		# Both ends overlap their supports, including the wider GT rim.
		var spoke_inner := radius*.10
		var spoke_outer := radius*rim_ratio*.98
		var spoke_center := (spoke_inner+spoke_outer)*.5
		var p := center+Vector3(outer_x+side*.004,sin(a)*spoke_center,cos(a)*spoke_center)
		var blade := _box(root,"WheelSpoke",Vector3(.023,radius*(.10 if style=="rally" else .14),spoke_outer-spoke_inner),p,alloy)
		blade.rotation.x=-a
		var bolt := center+Vector3(outer_x+side*.025,sin(a)*radius*.14,cos(a)*radius*.14)
		_box(root,"WheelBolt",Vector3(.012,.026,.026),bolt,metal)
	preload("res://gameplay/desert_cars/DesertCarWheelShape.gd").hub(root,radius*.16,side,center+Vector3(outer_x+side*.015,0,0),alloy)
	if s.body=="pickup" or style=="rally":
		for tread in 20:
			var a := TAU*float(tread)/20.0
			var block := _box(root,"TreadBlock",Vector3(width*.93,.035,.080),center+Vector3(0,cos(a)*(radius-.008),sin(a)*(radius-.008)),rubber)
			block.rotation.x=a
	for i in range(start_count,root.get_child_count()): root.get_child(i).set_meta("wheel_center",center)

static func _tyre(root: Node3D,radius: float,width: float,center: Vector3,mat: Material,rim_ratio := .64) -> void:
	# Rounded shoulders and inset sidewalls read as rubber, rather than a black
	# disc pasted onto the fender. Twenty-four segments keep its runtime bounded.
	# The bead follows each rim: a fixed .68R left visible gaps on .56R/.64R wheels.
	var bead := radius*rim_ratio*.97
	var section := [Vector2(-width*.5,bead),Vector2(-width*.5,radius*.89),Vector2(-width*.36,radius),Vector2(width*.36,radius),Vector2(width*.5,radius*.89),Vector2(width*.5,bead)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 24:
		var a := TAU*float(i)/24.0
		var b := TAU*float(i+1)/24.0
		for j in range(section.size()-1):
			var p: Vector2 = section[j]
			var q: Vector2 = section[j+1]
			var outward := Vector3(-(q.y-p.y),sin((a+b)*.5)*(q.x-p.x),cos((a+b)*.5)*(q.x-p.x)).normalized()
			_quad(st,center+Vector3(p.x,sin(a)*p.y,cos(a)*p.y),center+Vector3(p.x,sin(b)*p.y,cos(b)*p.y),center+Vector3(q.x,sin(b)*q.y,cos(b)*q.y),center+Vector3(q.x,sin(a)*q.y,cos(a)*q.y),outward)
	_mesh(root,"Tyre",st,mat)

static func _material(color: Color,roughness: float,metallic: float,semantic := "") -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color=color
	mat.roughness=roughness
	mat.metallic=metallic
	mat.resource_name=semantic
	return mat

static func _box(root: Node3D,label: String,size: Vector3,at: Vector3,mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name=label
	node.set_meta("authored_label",label) # Consumed before material batching.
	var mesh := BoxMesh.new()
	mesh.size=size
	node.mesh=mesh
	node.material_override=mat
	node.position=at
	root.add_child(node)
	return node

static func _cylinder(root: Node3D,label: String,radius: float,width: float,at: Vector3,mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name=label
	node.set_meta("authored_label",label)
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=width
	mesh.radial_segments=24
	mesh.rings=1
	node.mesh=mesh
	node.material_override=mat
	node.rotation.z=PI*.5
	node.position=at
	root.add_child(node)
	return node

static func _disc_front(root: Node3D,label: String,radius: float,width: float,at: Vector3,mat: Material) -> void:
	var node := _cylinder(root,label,radius,width,at,mat)
	node.rotation=Vector3(PI*.5,0,0)

static func _triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,outward: Vector3) -> void:
	var normal := (c-a).cross(b-a).normalized()
	var points := [a,b,c]
	if normal.dot(outward)<0.0:
		points=[a,c,b]
		normal=-normal
	for point: Vector3 in points:
		st.set_normal(normal)
		st.set_uv(Vector2(point.z,point.y))
		st.add_vertex(point)

static func _quad(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,outward: Vector3) -> void:
	_triangle(st,a,b,c,outward)
	_triangle(st,a,c,d,outward)

static func _mesh(root: Node3D,label: String,st: SurfaceTool,mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name=label
	node.mesh=st.commit()
	node.material_override=mat
	root.add_child(node)
	return node

static func _side_panel(root: Node3D,label: String,x: float,poly: Array,mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1,poly.size()-1):
		_triangle(st,Vector3(x,poly[0].y,poly[0].x),Vector3(x,poly[i].y,poly[i].x),Vector3(x,poly[i+1].y,poly[i+1].x),Vector3(signf(x),0,0))
	_mesh(root,label,st,mat)

static func _sloped_glass(root: Node3D,label: String,width: float,bottom: Vector2,top: Vector2,mat: Material) -> void:
	var gap := top-bottom
	var node := _box(root,label,Vector3(width,gap.length(),.020),Vector3(0,(top.y+bottom.y)*.5,(top.x+bottom.x)*.5),mat)
	node.rotation.x=atan2(gap.x,gap.y)

static func _beam(root: Node3D,label: String,a: Vector3,b: Vector3,width: float,mat: Material) -> void:
	var direction := b-a
	var node := _box(root,label,Vector3(width,direction.length(),width),(a+b)*.5,mat)
	node.quaternion=Quaternion(Vector3.UP,direction.normalized())

static func _batch(root: Node3D) -> void:
	var groups := {}
	var original := root.get_children()
	for part: MeshInstance3D in original:
		var material := part.material_override
		var wheel: Variant = part.get_meta("wheel_center") if part.has_meta("wheel_center") else null
		var key := str(material.get_instance_id())+":"+str(wheel)
		# Equipment derives the projector mount and damage side from each mesh's
		# bounds. Merging both lenses moves that mount to the car's centre.
		if material.resource_name == "headlight":
			var center := part.transform * part.mesh.get_aabb().get_center()
			key += ":headlight:" + str(signf(center.x))
		if not groups.has(key):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[key]={"tool":st,"material":material,"wheel":wheel,"name":part.name,"tail":part.get_meta("coupe_damage_material_key","")=="tail"}
		var tool: SurfaceTool = groups[key].tool
		for surface in part.mesh.get_surface_count():
			var arrays := MESH_ARRAYS.arrays_of(part.mesh, surface)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV]!=null else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX]!=null else PackedInt32Array()
			var vertex_indices: Array[int] = []
			if indices.is_empty():
				for vertex_index in positions.size(): vertex_indices.append(vertex_index)
			else:
				for vertex_index in indices: vertex_indices.append(vertex_index)
			for index in vertex_indices:
				tool.set_normal((part.basis*normals[index]).normalized())
				tool.set_uv(uvs[index] if index<uvs.size() else Vector2.ZERO)
				tool.add_vertex(part.transform*positions[index])
	for part in original:
		root.remove_child(part)
		part.free()
	for group: Dictionary in groups.values():
		var tool: SurfaceTool = group.tool
		tool.index()
		var part := _mesh(root,str(group.name),tool,group.material)
		if group.wheel!=null: part.set_meta("wheel_center",group.wheel)
		if group.tail: part.set_meta("coupe_damage_material_key","tail")
