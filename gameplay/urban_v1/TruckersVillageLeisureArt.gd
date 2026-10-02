extends Node3D
## A hand-built horseshoe court and ordinary shared-yard possessions.
## Static detail joins the village batches; only a throw or a lid uses a tween.
signal throw_finished

const ORIGIN := Vector3(-330,0,108)
const PLAY_POINT := Vector3(-302,0,84)
const TARGET_POINT := Vector3(-302,0,73)
const CACHE_POINT := Vector3(-330.5,0,94)
const COURT := Rect2(25.2,-36.5,5.6,12.0)
const CACHE_LOCAL := Vector3(-.5,0,-15.5)
var _throws: Array[MeshInstance3D] = []
var _throw_serial := 0
var _flight: Tween
var _lid_tween: Tween
var _lid: Node3D
var _cache_open := false
var _active := true
var _flight_mesh: MeshInstance3D
var _flight_start := Vector3.ZERO
var _flight_end := Vector3.ZERO
var _flight_height := 3.0
static var _horseshoe_mesh: ArrayMesh
static var _iron_paint: StandardMaterial3D

static func build(v: Node3D) -> Node3D:
	var art := load("res://gameplay/urban_v1/TruckersVillageLeisureArt.gd").new() as Node3D
	art.name = "TruckersVillageLeisureArt"
	v.add_child(art)
	art._build_court(v)
	art._build_common_yard(v)
	art._build_windmill(v)
	art._build_dynamic()
	return art

func _build_court(v: Node3D) -> void:
	# A straight boundary belongs to this intentionally level playing court.
	# Earth shares the village's filtered material and has no shadow/collider.
	var polygon := PackedVector2Array([
		COURT.position,COURT.position+Vector2(COURT.size.x,0),
		COURT.end,COURT.position+Vector2(0,COURT.size.y)])
	preload("res://gameplay/urban_v1/TruckersVillageGround.gd")._flat(v,"HorseshoeCourtEarth",polygon,preload("res://world/urban_detail/RuralGroundMaterial.gd").material(),.031)
	var plots: Array = v.get_meta("earth_plots",[])
	plots.append(polygon)
	v.set_meta("earth_plots",plots)
	for x in [COURT.position.x,COURT.end.x]:
		for index in 3:
			var z := COURT.position.y+2.0+float(index)*4.0
			v._box(Vector3(x,.085,z),Vector3(.15,.17,3.96),"73624a")
			v._solid("HorseshoeCourtRail",Vector3(x,.085,z),Vector3(.15,.17,3.96))
		for z in [COURT.position.y,COURT.position.y+4,COURT.position.y+8,COURT.end.y]:
			v._box(Vector3(x,.13,z),Vector3(.22,.26,.22),"635e4c")
			v._solid("HorseshoeCourtPeg",Vector3(x,.13,z),Vector3(.22,.26,.22))
	# The front stays completely open so the player can step across the line.
	v._box(Vector3(28,.09,COURT.position.y),Vector3(5.6,.18,.15),"73624a")
	v._solid("HorseshoeCourtBack",Vector3(28,.09,COURT.position.y),Vector3(5.6,.18,.15))
	for z in [-35.0,-25.3]:
		for x in [-.62,.0,.62]:
			v._box(Vector3(28+x,.06,z),Vector3(.57,.04,.40),"a49673")
	v._cylinder(TARGET_POINT-ORIGIN+Vector3(0,.33,0),.075,.66,"797d6d")
	v._cylinder(TARGET_POINT-ORIGIN+Vector3(0,.54,0),.079,.18,"b4aa87")
	v._solid("HorseshoeTargetStake",TARGET_POINT-ORIGIN+Vector3(0,.33,0),Vector3(.16,.66,.16))
	# A row of extra stakes, spare shoes and a bench read as a game without signs.
	for x in [22.40,22.72,23.04]:
		v._cylinder(Vector3(x,.58,-24.6),.045,.72,"797d6d")
	v._box(Vector3(22.72,.45,-24.6),Vector3(1.0,.11,.22),"635e4c")
	for x in [22.25,23.19]: v._box(Vector3(x,.225,-24.6),Vector3(.12,.45,.22),"635e4c")
	v._solid("HorseshoeSpareRack",Vector3(22.72,.49,-24.6),Vector3(1.1,.98,.34))
	v._bench(Vector3(22.2,0,-27.3))
	_crate(v,Vector3(22.2,0,-22.2),Vector3(1.18,.58,.82))
	for index in 3:
		var at := Vector3(21.9+float(index)*.28,.60,-22.2)
		var yaw := .22*index
		for segment in 12:
			var angle := -.83*PI+float(segment)*1.66*PI/11.0
			var offset := Basis(Vector3.UP,yaw)*Vector3(sin(angle)*.14,0,-cos(angle)*.14)
			v._box(at+offset,Vector3(.065,.04,.053),"797d6d",Vector3(0,yaw-angle,0))

func _build_common_yard(v: Node3D) -> void:
	_bicycle(v,Vector3(-7.4,0,-23.9))
	_crate(v,Vector3(-7.0,0,-20.6),Vector3(1.1,.64,.82))
	_crate(v,Vector3(-6.05,0,-20.7),Vector3(.72,.45,.72))
	for x in [-7.28,-6.96,-6.64]:
		v._cylinder(Vector3(x,.72,-20.6),.11,.16,"b4aa87")
		v._box(Vector3(x+.025,.82,-20.6),Vector3(.06,.10,.05),"54665e")
	# A woven basket is solid only as a complete object; small handles have no
	# separate collision. The coffee-table approaches remain wider than a person.
	v._cylinder(Vector3(-1.45,.24,-25.8),.36,.48,"8b7556")
	for y in [.13,.25,.37,.48]: v._cylinder(Vector3(-1.45,y,-25.8),.37,.04,"73624a")
	v._solid("VillageMarketBasket",Vector3(-1.45,.27,-25.8),Vector3(.76,.54,.76))
	for x in [-.23,.23]: v._box(Vector3(-1.45+x,.57,-25.8),Vector3(.04,.28,.045),"8b7556")
	v._box(Vector3(-1.45,.70,-25.8),Vector3(.50,.04,.045),"8b7556")

func _build_windmill(v: Node3D) -> void:
	var at := Vector3(-2,0,-16.6)
	# The old garden windmill is static, with no new lighting or idle animation.
	for x in [-.50,.50]:
		for z in [-.50,.50]:
			v._box(at+Vector3(x,1.70,z),Vector3(.12,3.4,.12),"797d6d")
	for y in [.45,1.65,2.9]:
		for z in [-.50,.50]: v._box(at+Vector3(0,y,z),Vector3(1.1,.10,.10),"635e4c")
		for x in [-.50,.50]: v._box(at+Vector3(x,y,0),Vector3(.10,.10,1.1),"635e4c")
	for z in [-.50,.50]:
		for angle in [-.68,.68]: v._box(at+Vector3(0,1.6,z),Vector3(.075,1.72,.075),"797d6d",Vector3(0,0,angle))
	v._solid("VillageGardenWindmill",at+Vector3(0,1.8,0),Vector3(1.14,3.6,1.14))
	var hub := at+Vector3(0,3.42,.06)
	v._cylinder(hub,.18,.30,"795b48",Vector3(PI*.5,0,0))
	for index in 10:
		var angle := float(index)*TAU/10.0+.12
		var along := Vector3(sin(angle),cos(angle),0)
		v._box(hub+along*.48,Vector3(.055,.92,.04),"797d6d",Vector3(0,0,-angle))
		v._box(hub+along*.96+Vector3(0,0,.06),Vector3(.33,.58,.08),"8b7556" if index%3==0 else "797d6d",Vector3(0,.12,-angle-.12))
	# A shallow raised garden has an irregular flower grouping and visible boards.
	var garden := Vector3(-4.15,0,-16.6)
	v._box(garden+Vector3(0,.14,0),Vector3(1.42,.28,2.05),"635e4c")
	for x in [-.75,.75]: v._box(garden+Vector3(x,.24,0),Vector3(.08,.26,2.2),"8b7556")
	for z in [-1.08,1.08]: v._box(garden+Vector3(0,.24,z),Vector3(1.58,.26,.08),"8b7556")
	v._solid("VillageWindmillGarden",garden+Vector3(0,.37,0),Vector3(1.6,.74,2.25))
	for index in 7:
		var p := garden+Vector3(-.39+float(index%2)*.7,.54,-.77+float(index)*.25)
		v._cylinder(p,.032,.54,"54665e")
		v._box(p+Vector3(.11,-.04,0),Vector3(.31,.065,.13),"54665e",Vector3(0,.4,.32))
		v._cylinder(p+Vector3(0,.27,0),.115,.10,"b4aa87" if index%2 else "ac8d72")
	# Weathered metal toolbox: the lid belongs to the dynamic child, while the
	# complete lower volume always remains physical, including after opening.
	v._box(CACHE_LOCAL+Vector3(0,.18,0),Vector3(.90,.36,.62),"54665e")
	for x in [-.38,.38]: v._box(CACHE_LOCAL+Vector3(x,.18,0),Vector3(.055,.34,.65),"797d6d")
	v._box(CACHE_LOCAL+Vector3(0,.23,.33),Vector3(.11,.17,.04),"795b48")
	v._solid("VillageWindmillCache",CACHE_LOCAL+Vector3(0,.22,0),Vector3(.95,.44,.68))

func _bicycle(v: Node3D,at: Vector3) -> void:
	for z in [-.72,.72]:
		var wheel := at+Vector3(0,.49,z)
		for index in 16:
			var angle := float(index)*TAU/16.0
			v._box(wheel+Vector3(0,cos(angle)*.43,sin(angle)*.43),Vector3(.09,.05,.18),"30352f",Vector3(angle,0,0))
		for angle in [0.0,PI*.25,PI*.5,PI*.75]: v._box(wheel,Vector3(.035,.78,.025),"797d6d",Vector3(angle,0,0))
	var front := at+Vector3(0,.49,.72)
	var rear := at+Vector3(0,.49,-.72)
	var pedal := at+Vector3(0,.38,-.08)
	var saddle := at+Vector3(0,.96,-.27)
	var handle := at+Vector3(0,1.05,.56)
	for line in [[rear,pedal],[rear,saddle],[pedal,saddle],[saddle,handle],[handle,pedal],[front,handle]]:
		var midpoint: Vector3 = (line[0]+line[1])*.5
		var direction: Vector3 = line[1]-line[0]
		v._box(midpoint,Vector3(.065,direction.length(),.065),"795b48",Vector3(atan2(direction.z,direction.y),0,0))
	v._box(saddle+Vector3(0,.035,0),Vector3(.28,.10,.37),"30352f")
	v._box(handle+Vector3(0,.1,0),Vector3(.62,.055,.055),"797d6d")
	v._box(pedal,Vector3(.49,.055,.13),"797d6d")
	# A full thin envelope prevents walking through its frame and handlebar.
	v._solid("VillageParkedBicycle",at+Vector3(0,.57,0),Vector3(.66,1.14,2.35))

func _crate(v: Node3D,at: Vector3,size: Vector3) -> void:
	v._box(at+Vector3(0,.045,0),Vector3(size.x,.09,size.z),"635e4c")
	for y in [size.y*.27,size.y*.74]:
		for x in [-size.x*.5,size.x*.5]: v._box(at+Vector3(x,y,0),Vector3(.075,size.y*.3,size.z),"8b7556")
		for z in [-size.z*.5,size.z*.5]: v._box(at+Vector3(0,y,z),Vector3(size.x,size.y*.3,.075),"8b7556")
	for x in [-size.x*.43,size.x*.43]:
		for z in [-size.z*.43,size.z*.43]: v._box(at+Vector3(x,size.y*.5,z),Vector3(.085,size.y,.085),"73624a")
	v._solid("VillageMarketCrate",at+Vector3(0,size.y*.5,0),size+Vector3(.10,0,.10))

func _build_dynamic() -> void:
	for index in 3:
		var shoe := MeshInstance3D.new()
		shoe.name = "ThrownHorseshoe%d"%index
		shoe.mesh = _shoe_mesh()
		shoe.material_override = _iron_material()
		shoe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		shoe.visible = false
		add_child(shoe)
		_throws.append(shoe)
	_lid = Node3D.new()
	_lid.name = "WindmillCacheLid"
	_lid.position = CACHE_LOCAL+Vector3(0,.38,-.31)
	add_child(_lid)
	var lid := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.94,.055,.66)
	lid.mesh = mesh
	lid.position = Vector3(0,0,.31)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color("607052")
	paint.roughness = .88
	lid.material_override = paint
	_lid.add_child(lid)

func begin_round() -> void:
	if _flight != null and _flight.is_valid(): _flight.kill()
	_throw_serial = 0
	for shoe in _throws: shoe.visible = false

func animate_throw(strength: float,hit: bool) -> void:
	if not _active or _throws.is_empty(): return
	if _flight != null and _flight.is_valid(): _flight.kill()
	if _throw_serial%3==0:
		for shoe in _throws: shoe.visible = false
	_flight_mesh = _throws[_throw_serial%3]
	_flight_start = PLAY_POINT-ORIGIN+Vector3(0,1.1,0)
	_flight_end = TARGET_POINT-ORIGIN+Vector3(0,.105+float(_throw_serial%3)*.045,0)
	if not hit:
		_flight_end += Vector3(.76 if _throw_serial%2 else -.76,0,clampf((.70-strength)*5.0,-1.0,2.5))
	_flight_height = 2.2+clampf(strength,0,1)*1.5
	_flight_mesh.visible = true
	_move_throw(0.0)
	_throw_serial += 1
	_flight = create_tween()
	_flight.tween_method(_move_throw,0.0,1.0,1.12)
	_flight.finished.connect(func(): throw_finished.emit())

func _move_throw(weight: float) -> void:
	if not is_instance_valid(_flight_mesh): return
	_flight_mesh.position = _flight_start.lerp(_flight_end,weight)+Vector3.UP*sin(weight*PI)*_flight_height
	_flight_mesh.rotation = Vector3(TAU*3.0*weight,weight*.34,0)

func set_cache_open(open: bool) -> void:
	_cache_open = open
	if not is_instance_valid(_lid): return
	if _lid_tween != null and _lid_tween.is_valid(): _lid_tween.kill()
	if not _active:
		_lid.rotation.x = -1.9 if open else 0.0
		return
	_lid_tween = create_tween()
	_lid_tween.tween_property(_lid,"rotation:x",-1.9 if open else 0.0,.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func set_region_active(active: bool) -> void:
	_active = active
	visible = active
	if active: return
	if _flight != null and _flight.is_valid(): _flight.kill()
	if _lid_tween != null and _lid_tween.is_valid(): _lid_tween.kill()
	if is_instance_valid(_lid): _lid.rotation.x = -1.9 if _cache_open else 0.0
	for shoe in _throws: shoe.visible = false

static func _iron_material() -> StandardMaterial3D:
	if _iron_paint == null:
		_iron_paint = StandardMaterial3D.new()
		_iron_paint.albedo_color = Color("a79b7c")
		_iron_paint.metallic = .32
		_iron_paint.roughness = .68
	return _iron_paint

static func _shoe_mesh() -> ArrayMesh:
	if _horseshoe_mesh != null: return _horseshoe_mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in 12:
		var angle := -.83*PI+float(index)*1.66*PI/11.0
		var block := BoxMesh.new()
		block.size = Vector3(.105,.065,.085)
		var at := Vector3(sin(angle)*.23,0,-cos(angle)*.23)
		surface.append_from(block,0,Transform3D(Basis(Vector3.UP,-angle),at))
	_horseshoe_mesh = surface.commit()
	return _horseshoe_mesh
