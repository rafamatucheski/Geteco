extends Node3D
## Fixed territories, two shared animal meshes, and bounded wind details.
## No navigation agents, combat actors, rigid bodies, audio loops or scene scans.
const G := preload("res://world/desert/expansion/DesertEcologyGeometry.gd")
const FLORA := preload("res://world/desert/expansion/DesertEcologyFlora.gd")
const LAYOUT := preload("res://world/desert/DesertLayout.gd")
const ACTIVE_RANGE := 72.0
const KEEP_RANGE := 85.0
const TERRITORY_RADIUS := 4.0
const THINK_INTERVAL := .25
var _height := Callable()
var _clearance := Callable()
var _focus := Vector3.INF
var _clock := 0.0
var _think_clock := 0.0
var _activation_clock := 0.0
var _animals: Array[Dictionary]=[]
var _tumbleweeds: Array[Dictionary]=[]
var _dust: MultiMeshInstance3D
var _wind_index := -1
var _active := false
var _query := PhysicsShapeQueryParameters3D.new()
var _territory_shape := CylinderShape3D.new()
var _step_shape := SphereShape3D.new()
static var _rabbit_mesh: ArrayMesh
static var _lizard_mesh: ArrayMesh
static var _twig_mesh: ArrayMesh
static var _dust_material: ShaderMaterial

static func locations() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for i in FLORA.ANIMAL_PATCHES.size():
		var p: Vector2=FLORA.ANIMAL_PATCHES[i]
		result.append({"id":"desert_ecology_%d"%i,"kind":"jackrabbit" if i%2==0 else "lizard","position":Vector3(p.x,0,p.y),"approach":Vector3(p.x+30,0,p.y+8),"radius":TERRITORY_RADIUS})
	for i in FLORA.WIND_PATCHES.size():
		var p: Vector2=FLORA.WIND_PATCHES[i]
		result.append({"id":"desert_wind_%d"%i,"kind":"dust_devil_tumbleweed","position":Vector3(p.x,0,p.y),"approach":Vector3(p.x+25,0,p.y+8),"radius":16.0})
	return result

func configure(height_callable: Callable,clearance_callable := Callable()) -> void:
	_height=height_callable
	_clearance=clearance_callable
	name="DesertEcologyLife"
	_territory_shape.radius=TERRITORY_RADIUS+.55
	_territory_shape.height=1.0
	_step_shape.radius=.23
	_query.collision_mask=7
	_query.collide_with_areas=false
	suspend()

func set_focus(point: Vector3) -> void:
	if not _height.is_valid() or not LAYOUT.contains(point):
		suspend()
		return
	_focus=point
	if _animals.is_empty(): _build()
	_active=true
	visible=true
	set_physics_process(true)

func suspend() -> void:
	_active=false
	visible=false
	set_physics_process(false)
	_activation_clock=1.0
	_think_clock=0.0
	_wind_index=-1
	for animal in _animals:
		animal.active=false
		(animal.node as Node3D).visible=false
	for weed in _tumbleweeds: (weed.node as Node3D).visible=false
	if _dust!=null: _dust.visible=false

func diagnostics() -> Dictionary:
	var live := 0
	var animals: Array[Dictionary]=[]
	for animal in _animals:
		if bool(animal.active): live+=1
		animals.append({"species":"jackrabbit" if animal.rabbit else "lizard","active":animal.active,"territory":animal.anchor,"position":(animal.node as Node3D).position})
	return {"active":_active,"processing":is_physics_processing(),"ground_animals":live,"animal_capacity":_animals.size(),"territory_radius":TERRITORY_RADIUS,"animals":animals,"wind_patch":_wind_index,"dust_visible":_dust!=null and _dust.visible}

func _build() -> void:
	for i in FLORA.ANIMAL_PATCHES.size():
		var root := Node3D.new()
		root.name="DesertJackrabbit%d"%i if i%2==0 else "DesertLizard%d"%i
		root.visible=false
		root.set_meta("desert_ecology_animal",true)
		add_child(root)
		var skin := _mesh_node("Body",_rabbit() if i%2==0 else _lizard())
		root.add_child(skin)
		var anchor: Vector2=FLORA.ANIMAL_PATCHES[i]
		_animals.append({"node":root,"skin":skin,"rabbit":i%2==0,"anchor":anchor,"active":false,"phase":float(i)*1.73,"travel":0.0,"target":Vector3.ZERO,"last_ground":0.0,"moving":false})
	for i in 2:
		var node := _mesh_node("RollingDryBush%d"%i,_tumbleweed())
		node.visible=false
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		_tumbleweeds.append({"node":node,"phase":float(i)*2.93,"target":Vector3.ZERO,"active":false})
	_make_dust()

func _physics_process(delta: float) -> void:
	_clock+=delta
	_activation_clock+=delta
	_think_clock+=delta
	if _activation_clock>=1.0:
		_activation_clock=0.0
		_update_activation()
	if _think_clock>=THINK_INTERVAL:
		var step := minf(_think_clock,.5)
		_think_clock=0.0
		_think(step)
	for animal in _animals:
		if not bool(animal.active): continue
		var node: Node3D=animal.node
		var target: Vector3=animal.target
		var movement_vector := target-node.position
		movement_vector.y=0
		var moving := movement_vector.length_squared()>.00015
		if moving:
			var speed := 1.35 if animal.rabbit else .34
			node.position=node.position.move_toward(target,speed*delta)
			node.rotation.y=lerp_angle(node.rotation.y,atan2(-movement_vector.x,-movement_vector.z),minf(delta*8,1.0))
		var skin: Node3D=animal.skin
		# Small fore/hind-foot lift reads as a hop at real hare proportions.
		skin.position.y=absf(sin(_clock*13.0+float(animal.phase)))*.055 if moving and animal.rabbit else 0.0
		skin.rotation.x=sin(_clock*13.0+float(animal.phase))*.075 if moving and animal.rabbit else 0.0
		skin.rotation.y=sin(_clock*9.0+float(animal.phase))*.055 if moving and not animal.rabbit else 0.0
	_update_wind(delta)

func _update_activation() -> void:
	var focus2 := Vector2(_focus.x,_focus.z)
	for i in _animals.size():
		var animal: Dictionary=_animals[i]
		var anchor: Vector2=animal.anchor
		var distance := anchor.distance_to(focus2)
		if bool(animal.active):
			if distance>KEEP_RANGE:
				animal.active=false
				(animal.node as Node3D).visible=false
			continue
		# Activation happens beyond the close gameplay view; never under Dante's feet.
		if distance>ACTIVE_RANGE or distance<24.0: continue
		if not _clear_ground(anchor,TERRITORY_RADIUS+.55): continue
		var y := float(_height.call(anchor))
		var level := true
		for offset in [Vector2(4,0),Vector2(-4,0),Vector2(0,4),Vector2(0,-4)]:
			if absf(float(_height.call(anchor+offset))-y)>.18: level=false
		if not level or not _unoccupied(anchor,y,true): continue
		var node: Node3D=animal.node
		node.position=Vector3(anchor.x,y,anchor.y)
		node.reset_physics_interpolation()
		node.visible=true
		animal.active=true
		animal.target=node.position
		animal.last_ground=y
		animal.travel=0.0
	_wind_index=-1
	var nearest := 100.0
	for i in FLORA.WIND_PATCHES.size():
		var point: Vector2=FLORA.WIND_PATCHES[i]
		var distance := point.distance_to(focus2)
		if distance<nearest and _clear_ground(point,16.0):
			nearest=distance
			_wind_index=i

func _think(step: float) -> void:
	for animal in _animals:
		if not bool(animal.active): continue
		var node: Node3D=animal.node
		var anchor: Vector2=animal.anchor
		var phase: float=animal.phase
		var wary := node.position.distance_to(_focus)<6.0
		var moving := sin(_clock*.47+phase)>-.15 or wary
		animal.moving=moving
		if not moving: continue
		animal.travel=float(animal.travel)+step*(.32 if animal.rabbit else .09)
		var travel: float=animal.travel
		var p := anchor+Vector2(sin(travel+phase),cos(travel*.83+phase))*(2.25 if animal.rabbit else 1.6)
		if wary:
			var away := (Vector2(node.position.x,node.position.z)-Vector2(_focus.x,_focus.z)).normalized()
			p=(p+away*1.1-anchor).limit_length(TERRITORY_RADIUS)+anchor
		var y := float(_height.call(p))
		# One small query per active creature at 4 Hz handles new vehicles/solid props.
		if _clear_ground(p,.35) and absf(y-float(animal.last_ground))<.2 and _unoccupied(p,y,false):
			animal.target=Vector3(p.x,y,p.y)
			animal.last_ground=y
	for weed in _tumbleweeds:
		weed.active=false
		if _wind_index<0: continue
		var phase: float=weed.phase
		var anchor: Vector2=FLORA.WIND_PATCHES[_wind_index]
		var p := anchor+Vector2(sin(_clock*.055+phase)*11,cos(_clock*.073+phase)*7)
		var y := float(_height.call(p))
		if _clear_ground(p,.60) and _unoccupied(p,y,false):
			weed.target=Vector3(p.x,y+.43,p.y)
			weed.active=true

func _clear_ground(p: Vector2,radius: float) -> bool:
	if not LAYOUT.BOUNDS.grow(-40.0-radius).has_point(p) or not LAYOUT.road_clear(p,radius+3): return false
	return not _clearance.is_valid() or bool(_clearance.call(p,radius))

func _unoccupied(p: Vector2,y: float,whole_territory: bool) -> bool:
	if not is_inside_tree() or get_world_3d()==null: return false
	if whole_territory:
		_query.shape=_territory_shape
	else:
		_query.shape=_step_shape
	_query.transform=Transform3D(Basis.IDENTITY,Vector3(p.x,y+(.55 if whole_territory else .27),p.y))
	return get_world_3d().direct_space_state.intersect_shape(_query,1).is_empty()

func _update_wind(delta: float) -> void:
	for weed in _tumbleweeds:
		var node: Node3D=weed.node
		var enabled := _wind_index>=0 and bool(weed.active)
		if enabled:
			if not node.visible or node.position.distance_squared_to(weed.target)>100:
				node.position=weed.target
				node.reset_physics_interpolation()
			else: node.position=node.position.move_toward(weed.target,delta*1.1)
			node.rotate_z(-delta*1.3)
			node.rotate_x(delta*.44)
		node.visible=enabled
	if _dust==null: return
	# Uma coluna curta de borda suave a cada 52 segundos, com nascimento/morte suaves.
	# A geometria são 14 quads pequenos, não uma camada de transparência de tela inteira.
	var age := fposmod(_clock+4.0,52.0)
	var envelope := smoothstep(0.0,3.0,age)*(1.0-smoothstep(13.0,19.0,age))
	_dust.visible=_wind_index>=0 and envelope>.001
	if not _dust.visible: return
	var anchor: Vector2=FLORA.WIND_PATCHES[_wind_index]
	var ground := float(_height.call(anchor))
	var center := Vector3(anchor.x+sin(_clock*.031)*3.0,ground,anchor.y+cos(_clock*.037)*2.0)
	for i in 14:
		var rise := fposmod(float(i)/14.0+_clock*.15,1.0)
		var angle := _clock*1.45+float(i)*2.399963
		var width := .55+rise*1.4
		var at := center+Vector3(cos(angle)*(.15+rise*.55),.15+rise*4.5,sin(angle)*(.15+rise*.55))
		var size := Vector3(width,1.0+rise*.75,1)
		_dust.multimesh.set_instance_transform(i,Transform3D(Basis.from_scale(size),at))
		_dust.multimesh.set_instance_color(i,Color(.65,.55,.40,.09*envelope*sin(rise*PI)))

func _make_dust() -> void:
	if _dust_material==null:
		_dust_material=ShaderMaterial.new()
		_dust_material.shader=preload("res://world/desert/desert_dust.gdshader")
	var quad := QuadMesh.new()
	quad.size=Vector2(1,1)
	var batch := MultiMesh.new()
	batch.transform_format=MultiMesh.TRANSFORM_3D
	batch.use_colors=true
	batch.mesh=quad
	batch.instance_count=14
	_dust=MultiMeshInstance3D.new()
	_dust.name="OccasionalDustDevil"
	_dust.multimesh=batch
	_dust.material_override=_dust_material
	_dust.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dust.visible=false
	add_child(_dust)

static func _mesh_node(label: String,shape: ArrayMesh) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name=label
	node.mesh=shape
	node.material_override=G.material()
	return node

static func _rabbit() -> ArrayMesh:
	if _rabbit_mesh!=null: return _rabbit_mesh
	var data := G.buffer()
	var fur := Color("9c8b70")
	var pale := Color("c9b99a")
	G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.215,.015)),Vector3(.12,.15,.23),fur,10,6)
	G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.275,-.225)),Vector3(.078,.090,.102),fur.lightened(.045),9,5)
	G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.236,-.307)),Vector3(.049,.039,.051),pale,8,4)
	G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.229,-.354)),Vector3(.019,.012,.012),Color("51493b"),6,3)
	G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.235,.242)),Vector3(.052,.059,.059),pale,7,4)
	for side in [-1.0,1.0]:
		var ear_basis := Basis(Vector3.FORWARD,-side*.15)*Basis(Vector3.RIGHT,-.12)
		var ear := Transform3D(ear_basis,Vector3(side*.041,.430,-.19))
		G.ellipsoid(data,ear,Vector3(.030,.151,.022),fur,7,5)
		G.ellipsoid(data,ear.translated_local(Vector3(0,.009,-.014)),Vector3(.014,.114,.009),Color("b29a7f"),6,4)
		G.ellipsoid(data,ear.translated_local(Vector3(0,.127,0)),Vector3(.022,.027,.018),Color("615949"),6,3)
		G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(side*.070,.295,-.255)),Vector3(.007,.009,.007),Color("201e1a"),6,3)
		G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(side*.095,.146,.105)),Vector3(.064,.107,.098),fur.darkened(.025),8,5)
		G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(side*.095,.039,.045)),Vector3(.037,.036,.090),pale,7,4)
		G.branch(data,Vector3(side*.069,.164,-.119),Vector3(side*.075,.04,-.135),.028,.020,fur,6)
		G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(side*.075,.025,-.161)),Vector3(.026,.024,.057),pale,7,3)
	_rabbit_mesh=G.mesh(data)
	return _rabbit_mesh

static func _lizard() -> ArrayMesh:
	if _lizard_mesh!=null: return _lizard_mesh
	var data := G.buffer()
	var sand := Color("9c845c")
	var dark := Color("6b5d43")
	G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.067,0)),Vector3(.049,.036,.124),sand,9,5)
	G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(0,.075,-.136)),Vector3(.045,.026,.060),sand.lightened(.09),8,4)
	var tail := [Vector3(0,.060,.095),Vector3(.008,.044,.19),Vector3(.034,.029,.29),Vector3(.020,.018,.38)]
	for i in 3: G.branch(data,tail[i],tail[i+1],.028-float(i)*.008,.017-float(i)*.007,sand,6)
	for side in [-1.0,1.0]:
		G.ellipsoid(data,Transform3D(Basis.IDENTITY,Vector3(side*.035,.088,-.151)),Vector3(.007,.006,.007),Color("28291e"),6,3)
		for leg in 2:
			var z := -.06+float(leg)*.135
			var knee := Vector3(side*.095,.040,z+.026)
			var foot := Vector3(side*.112,.009,z+.076)
			G.branch(data,Vector3(side*.025,.066,z),knee,.012,.009,sand,5)
			G.branch(data,knee,foot,.009,.005,sand,5)
			for toe in 3: G.branch(data,foot,foot+Vector3(side*(.02+float(toe)*.004),-.003,-.014+float(toe)*.017),.003,.001,dark,3)
	for i in 5:
		var z := -.074+float(i)*.035
		G.branch(data,Vector3(-.024,.096,z),Vector3(.024,.096,z+.006),.009,.006,dark,4)
	_lizard_mesh=G.mesh(data)
	return _lizard_mesh

static func _tumbleweed() -> ArrayMesh:
	if _twig_mesh!=null: return _twig_mesh
	var data := G.buffer()
	var straw := Color("998466")
	for i in 19:
		var phase := float(i)*2.399963
		var tilt := -.83+float(i)*.091
		var axis := Vector3(cos(phase)*cos(tilt),sin(tilt),sin(phase)*cos(tilt))
		var cross := axis.cross(Vector3.UP).normalized()
		var a := axis*-.30+cross*.08
		var b := axis*.40+cross*.02
		G.branch(data,a,b,.011,.006,straw if i%2 else straw.darkened(.13),4)
		for fork in 2:
			var base := a.lerp(b,.36+float(fork)*.35)
			G.branch(data,base,(base+cross*(.16 if fork==0 else -.18)+Vector3.UP*.06).limit_length(.44),.006,.002,straw,3)
	_twig_mesh=G.mesh(data)
	return _twig_mesh
