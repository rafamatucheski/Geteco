extends RefCounted
## Small distant scale cues on the inaccessible gorge floor. One shared feeding
## animation sleeps off screen; there are no actors, physics bodies or AI loops.
const E := preload("res://world/desert/expansion/DesertEcologyGeometry.gd")
const T := preload("res://world/desert/canyon/DesertSmugglerTerrain.gd")
# Camera/terrain rays select exposed lower benches; the near rim must not hide
# all scale cues. The last group stays in the deepest basin for later viewpoints.
const BODY_POINTS := [Vector2(-1357,-701),Vector2(-1365,-707),Vector2(-1371,-657),Vector2(-1336,-590)]
const BIRD_OFFSETS := [Vector3(0,-.68,.25),Vector3(0,.76,-.12),Vector3(1,-.73,-.28),Vector3(2,.74,.16),Vector3(3,-.67,.3),Vector3(3,.69,-.21)]
const OLD_BONE := Color("b9ae8d")
static var _head_mesh: ArrayMesh

static func build() -> Node3D:
	var root := Node3D.new()
	root.name="GorgeScavengerRemains"
	var bodies := E.buffer()
	var birds := E.buffer()
	var locations: Array[Vector3]=[]
	for i in BODY_POINTS.size():
		var point: Vector2=BODY_POINTS[i]
		var prototype := E.buffer()
		_body(prototype,[Color("4a6673"),Color("9c8c70"),Color("765049"),Color("6f7861")][i],i==1)
		_weathered_fragments(prototype,i)
		_append_grounded(bodies,prototype,point,[-.4,.8,1.2,2.4][i])
		locations.append(Vector3(point.x,T.surface_height(point),point.y))
	_add_mesh(root,"FallenTravellers",bodies)
	var heads := Node3D.new()
	heads.name="FeedingHeads"
	root.add_child(heads)
	var animated := Animation.new()
	animated.length=3.2
	animated.loop_mode=Animation.LOOP_LINEAR
	var minimum := Vector3.INF
	var maximum := -Vector3.INF
	for i in BIRD_OFFSETS.size():
		var record: Vector3=BIRD_OFFSETS[i]
		var body: Vector2=BODY_POINTS[int(record.x)]
		var at := body+Vector2(record.y,record.z)
		var toward := (body-at).normalized()
		var yaw := atan2(-toward.x,-toward.y)
		var prototype := E.buffer()
		_bird(prototype)
		_append_grounded(birds,prototype,at,yaw)
		var origin := Vector3(at.x,T.surface_height(at),at.y)
		var neck_anchor := Vector3(0,.35,-.14).rotated(Vector3.UP,yaw)
		var bird_root := Node3D.new()
		bird_root.name="Vulture%d"%i
		bird_root.position=origin+neck_anchor
		bird_root.rotation.y=yaw
		heads.add_child(bird_root)
		var head := MeshInstance3D.new()
		head.name="Head"
		head.mesh=_feeding_head()
		head.material_override=E.material()
		bird_root.add_child(head)
		var track := animated.add_track(Animation.TYPE_VALUE)
		animated.track_set_path(track,NodePath("FeedingHeads/Vulture%d/Head:rotation:x"%i))
		var phase := float(i%3)*.28
		for key in [Vector2(0,0),Vector2(.24+phase,.11),Vector2(.42+phase,-.17),Vector2(.62+phase,.035),Vector2(.82+phase,-.13),Vector2(1.07+phase,0),Vector2(3.2,0)]:
			animated.track_insert_key(track,key.x,key.y)
		minimum=minimum.min(origin-Vector3.ONE)
		maximum=maximum.max(origin+Vector3.ONE)
	_add_mesh(root,"FeedingVultures",birds)
	var library := AnimationLibrary.new()
	library.add_animation("feed",animated)
	var player := AnimationPlayer.new()
	player.name="FeedingAnimation"
	player.add_animation_library("",library)
	player.autoplay="feed"
	root.add_child(player)
	var enabler := VisibleOnScreenEnabler3D.new()
	enabler.name="FeedingVisibility"
	enabler.aabb=AABB(minimum,maximum-minimum)
	enabler.enable_node_path=NodePath("../FeedingAnimation")
	root.add_child(enabler)
	root.set_meta("body_count",BODY_POINTS.size())
	root.set_meta("scavenger_count",BIRD_OFFSETS.size())
	root.set_meta("body_length_metres",1.82)
	root.set_meta("partially_skeletal_bodies",1)
	root.set_meta("loose_bones",8)
	root.set_meta("ground_locations",locations)
	return root

static func _body(data: Dictionary,shirt: Color,weathered := false) -> void:
	var trousers := Color("303946")
	var skin := Color("a17b5c")
	var boots := Color("292d2b")
	if weathered:
		# Collapsed fabric sits underneath the remains; one folded sleeve still
		# covers a few ribs. These are old dry remains, with no added gore.
		E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.025,-.1)),Vector3(.23,.025,.36),shirt.darkened(.13),8,4)
		_ribcage(data)
		E.ellipsoid(data,Transform3D(Basis(Vector3.UP,.18),Vector3(-.18,.105,-.25)),Vector3(.065,.07,.16),shirt,6,3)
	else:
		E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.13,-.1)),Vector3(.23,.125,.36),shirt,8,4)
	E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.12,.24)),Vector3(.22,.11,.16),trousers,8,4)
	if weathered:
		E.branch(data,Vector3(0,.075,-.43),Vector3(0,.11,-.67),.023,.022,OLD_BONE,5)
		_skull(data,Vector3(0,.14,-.775))
	else:
		E.branch(data,Vector3(0,.14,-.43),Vector3(0,.145,-.67),.067,.062,skin)
		E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.145,-.775)),Vector3(.125,.14,.135),skin,8,4)
		E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.21,-.79)),Vector3(.123,.07,.12),Color("39352c"),8,3)
	for side in [-1.0,1.0]:
		var hip := Vector3(side*.105,.11,.27)
		var knee := Vector3(side*.15,.09,.52)
		var ankle := Vector3(side*.19,.075,.78)
		E.branch(data,hip,knee,.102,.085,trousers)
		E.branch(data,knee,ankle,.082,.062,trousers)
		E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(side*.19,.07,.805)),Vector3(.09,.07,.105),boots,6,3)
		var shoulder := Vector3(side*.22,.13,-.31)
		var elbow := Vector3(side*.37,.09,-.08)
		var hand := Vector3(side*.43,.07,.16 if side<0 else -.27)
		E.branch(data,shoulder,elbow,.077,.065,shirt)
		if weathered and side>0:
			E.branch(data,elbow,hand,.018,.014,OLD_BONE,5)
			E.ellipsoid(data,Transform3D(Basis.IDENTITY,hand),Vector3(.04,.023,.057),OLD_BONE,6,3)
		else:
			E.branch(data,elbow,hand,.058,.044,skin)
			E.ellipsoid(data,Transform3D(Basis.IDENTITY,hand),Vector3(.057,.045,.073),skin,6,3)

static func _ribcage(data: Dictionary) -> void:
	E.branch(data,Vector3(0,.055,-.43),Vector3(0,.055,.16),.022,.019,OLD_BONE.darkened(.1),5)
	for row in 5:
		var z := -.34+float(row)*.09
		var width := .15+sin(float(row)/4.0*PI)*.045
		var previous := Vector3(width,.065,z)
		for segment in range(1,9):
			var angle := PI*float(segment)/8.0
			var current := Vector3(cos(angle)*width,.065+sin(angle)*.13,z)
			E.branch(data,previous,current,.011,.010,OLD_BONE,5)
			previous=current
	E.branch(data,Vector3(0,.194,-.33),Vector3(0,.194,.02),.016,.013,OLD_BONE,5)

static func _skull(data: Dictionary,at: Vector3) -> void:
	E.ellipsoid(data,Transform3D(Basis.IDENTITY,at),Vector3(.118,.12,.135),OLD_BONE,8,5)
	E.ellipsoid(data,Transform3D(Basis.IDENTITY,at+Vector3(0,.045,.09)),Vector3(.075,.047,.05),OLD_BONE.darkened(.1),6,3)
	for side in [-1.0,1.0]:
		E.ellipsoid(data,Transform3D(Basis.IDENTITY,at+Vector3(side*.042,.112,-.022)),Vector3(.027,.009,.03),Color("544b3b"),6,3)

static func _weathered_fragments(data: Dictionary,index: int) -> void:
	# The low centres intentionally leave part of these dry bones buried by
	# the same ground-conforming transform as the clothes and bodies.
	for record in [[Vector3(.78,-.011,-.35),Vector3(1.05,-.004,-.14)],[Vector3(-.82,-.014,.42),Vector3(-.58,.004,.66)]]:
		var a: Vector3=record[0]
		var b: Vector3=record[1]
		E.branch(data,a,b,.018,.015,OLD_BONE.darkened(.06*float(index%2)),5)
		for tip: Vector3 in [a,b]: E.ellipsoid(data,Transform3D(Basis.IDENTITY,tip),Vector3(.032,.025,.028),OLD_BONE,6,3)
	if index==2: _skull(data,Vector3(.82,.07,-.57))

static func _bird(data: Dictionary) -> void:
	var feather := Color("2e302a")
	E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.3,0)),Vector3(.17,.19,.27),feather,8,4)
	for side in [-1.0,1.0]:
		E.ellipsoid(data,Transform3D(Basis(Vector3.UP,side*.16),Vector3(side*.13,.28,.025)),Vector3(.073,.13,.26),Color("414239"),8,3)
		E.branch(data,Vector3(side*.085,.23,.03),Vector3(side*.105,.055,-.015),.022,.018,Color("82765e"),5)
		E.branch(data,Vector3(side*.105,.035,-.015),Vector3(side*.105,.025,-.13),.018,.008,Color("756b55"),5)
	E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.22,.265)),Vector3(.115,.05,.12),feather,6,3)
	E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.36,-.16)),Vector3(.105,.08,.105),Color("bab3a0"),8,3)

static func _feeding_head() -> ArrayMesh:
	if _head_mesh!=null: return _head_mesh
	var data := E.buffer()
	var skin := Color("917460")
	E.branch(data,Vector3.ZERO,Vector3(0,-.085,-.15),.042,.035,skin,6)
	E.branch(data,Vector3(0,-.085,-.15),Vector3(0,-.16,-.22),.035,.029,skin,6)
	E.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,-.16,-.225)),Vector3(.055,.057,.068),skin,8,4)
	E.branch(data,Vector3(0,-.175,-.27),Vector3(0,-.21,-.35),.026,.006,Color("bca77b"),5)
	_head_mesh=E.mesh(data)
	return _head_mesh

static func _append_grounded(target: Dictionary,source: Dictionary,at: Vector2,yaw: float) -> void:
	var vertices := PackedVector3Array()
	for v: Vector3 in source.vertices:
		var world := v.rotated(Vector3.UP,yaw)+Vector3(at.x,0,at.y)
		world.y+=T.surface_height(Vector2(world.x,world.z))+.015
		vertices.append(world)
	target.vertices.append_array(vertices)
	target.colors.append_array(source.colors)
	for i in range(0,vertices.size(),3):
		var normal := (vertices[i+2]-vertices[i]).cross(vertices[i+1]-vertices[i]).normalized()
		target.normals.append_array(PackedVector3Array([normal,normal,normal]))

static func _add_mesh(parent: Node3D,label: String,data: Dictionary) -> void:
	var node := MeshInstance3D.new()
	node.name=label
	node.mesh=E.mesh(data)
	node.material_override=E.material()
	parent.add_child(node)
