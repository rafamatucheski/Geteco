extends Node3D
## Continuous secret-tunnel stage. It stays in the production World3D, but is
## authored below and away from streamed streets so the walk down is visible
## without creating an isolated interior scene.

const RAT := preload("res://gameplay/urban_v1/SecretTunnelRat.gd")
const TUNNEL_AUDIO := preload("res://gameplay/urban_v1/SecretTunnelAudio.gd")
const UNDERGROUND_ENVIRONMENT := preload("res://gameplay/urban_v1/SecretUndergroundEnvironment.gd")
# The first basement occupies roughly y 0 .. -4.3. The hidden shelf opens at
# its rear landing; this second flight reaches the deeper network at y ~ -9.
const WORLD_ORIGIN := Vector3(-409.4,-8.86,99.65)
const WORLD_YAW := PI
const ENTRY_POINT := Vector3(0,4.55,7.2)
const EXIT_POINT := Vector3(0,4.55,8.0)
const HQ_CENTER := Vector3(58.0,0,2.0)
const UNDERGROUND_LAYER := 1 << 18

var session
var player: Node3D
var solids: Array[StaticBody3D] = []
var rats: Array[CharacterBody3D] = []
var lights: Array[OmniLight3D] = []
var audio_zone: Node3D
var tunnel_camera: Camera3D
var _previous_camera: Camera3D
var sealed_open := false
var vault_open := false
var console_node: Node3D
var console_body: StaticBody3D
var gate_body: StaticBody3D
var gate_halves: Array[Node3D] = []
var vault_door: Node3D
var vault_portal: Node3D
var _access_tween: Tween
var _active := false
var _flicker_clock := 0.0
var _rng := RandomNumberGenerator.new()
var _materials := {}
var _batches := {}

func configure(owner_session) -> void:
	session = owner_session
	player = session.world.player if session!=null else null
	_rng.seed = 195107
	_build()
	set_enabled(false)

func entry_global() -> Vector3:
	return to_global(ENTRY_POINT)

func exit_global() -> Vector3:
	return to_global(EXIT_POINT)

func headquarters_global() -> Vector3:
	return to_global(HQ_CENTER)

func sealed_sector_global() -> Vector3:
	return to_global(HQ_CENTER+Vector3(0,.04,-8.2))

func network_console_global() -> Vector3:
	return to_global(HQ_CENTER+Vector3(0,.04,-5.85))

func route_console_global() -> Vector3:
	return to_global(HQ_CENTER+Vector3(5.15,.04,-2.1))

func route_arrival_global() -> Vector3:
	return to_global(HQ_CENTER+Vector3(0,.04,4.8))

# Pedestal do teclado do cofre, no fundo do setor lacrado.
func vault_console_global() -> Vector3:
	return to_global(HQ_CENTER+Vector3(.9,.04,-12.5))

func vault_arrival_global() -> Vector3:
	return to_global(HQ_CENTER+Vector3(1.4,.04,-12.2))

func vault_door_global() -> Vector3:
	return to_global(HQ_CENTER+Vector3(.9,1.5,-14.55))

# O quadro de rede tapava a entrada do setor lacrado: com a energia do setor ele
# sobe para o teto e o portão de grades se abre. Só muda visual e colisão.
func set_sealed_access(open: bool,animate := false) -> void:
	sealed_open = open
	_apply_open_colliders()
	if not is_instance_valid(console_node): return
	var raise := 2.9 if open else 0.0
	var slide := 1.95 if open else 0.0
	if is_instance_valid(_access_tween): _access_tween.kill()
	if not animate:
		console_node.position.y = raise
		for index in gate_halves.size(): gate_halves[index].position.x = slide*(-1.0 if index == 0 else 1.0)
		return
	_access_tween = create_tween().set_parallel(true)
	_access_tween.tween_property(console_node,"position:y",raise,1.6).set_trans(Tween.TRANS_SINE)
	for index in gate_halves.size():
		_access_tween.tween_property(gate_halves[index],"position:x",slide*(-1.0 if index == 0 else 1.0),1.8).set_trans(Tween.TRANS_SINE).set_delay(.6)

# A porta do cofre recua para dentro da parede e revela o vão iluminado.
func set_vault_open(open: bool,animate := false) -> void:
	vault_open = open
	if not is_instance_valid(vault_door): return
	var depth := -.62 if open else 0.0
	vault_portal.visible = open
	if not animate:
		vault_door.position.z = depth
		return
	create_tween().tween_property(vault_door,"position:z",depth,1.4).set_trans(Tween.TRANS_SINE)

# Viagens que saem do túnel para um lugar (esgoto, forte) devolvem a câmera do mundo,
# não a do porão registrada na descida: senão o lugar de destino fica sem imagem.
func set_return_camera(camera: Camera3D) -> void:
	_previous_camera = camera

func _apply_open_colliders() -> void:
	if is_instance_valid(console_body): console_body.collision_layer = 0 if sealed_open or not visible else 1
	if is_instance_valid(gate_body): gate_body.collision_layer = 0 if sealed_open or not visible else 1

func contains(point: Vector3) -> bool:
	var local := to_local(point)
	if local.y <= -1.0 or local.y >= 6.5:
		return false
	# The cellar overlaps the broad underground rectangle. Only the authored
	# landing and stair may claim the higher level and switch cameras there.
	if local.y >= 3.55:
		return absf(local.x) <= 1.9 and local.z >= -.8 and local.z <= 8.35
	var xz := Vector2(local.x,local.z)
	return Rect2(-2.0,-2.0,4.0,10.35).has_point(xz) \
		or Rect2(-2.95,-12.5,5.9,11.2).has_point(xz) \
		or Rect2(-.5,-15.15,37.0,6.3).has_point(xz) \
		or Rect2(32.85,-12.5,6.3,15.0).has_point(xz) \
		or Rect2(35.5,-1.15,21.2,6.3).has_point(xz) \
		or Rect2(50.2,-5.8,15.8,15.6).has_point(xz) \
		or Rect2(55.55,-13.0,4.9,7.4).has_point(xz)

func set_enabled(value: bool) -> void:
	visible = value
	for body in solids: body.collision_layer = 1 if value else 0
	_apply_open_colliders()
	set_process(value and is_instance_valid(player))
	if not value: _set_occupied(false)

func _process(delta: float) -> void:
	if not is_instance_valid(player): return
	var occupied := contains(player.global_position)
	_set_occupied(occupied)
	if not occupied: return
	var local := to_local(player.global_position)
	var focus := Vector3(clampf(local.x,-1.0,68.0),.65,clampf(local.z,-12.0,7.0))
	var in_headquarters := local.x >= 49.5 and local.z >= -13.0 and local.z <= 9.5
	var target_size := 20.0 if in_headquarters else 15.0
	tunnel_camera.size = lerpf(tunnel_camera.size,target_size,1.0-exp(-4.2*delta))
	# Dedicated render layers let this use the project's readable isometric
	# angle while the streamed surface remains excluded from the cutaway.
	tunnel_camera.global_position = to_global(focus+Vector3(0,18.0,15.0))
	tunnel_camera.look_at(to_global(focus),Vector3.UP)
	_flicker_clock -= delta
	if _flicker_clock <= 0.0:
		_flicker_clock = .09
		for index in lights.size():
			var base := float(lights[index].get_meta("base_energy",1.0))
			var fault := index in [1,3]
			lights[index].light_energy = base*(_rng.randf_range(.45,1.04) if fault else _rng.randf_range(.96,1.02))

func _set_occupied(value: bool) -> void:
	if _active == value: return
	_active = value
	for rat in rats: rat.set_active(value)
	if is_instance_valid(audio_zone): audio_zone.set_active(value)
	if value:
		_enable_player_underground_layer()
		_previous_camera = get_viewport().get_camera_3d()
		if is_instance_valid(player) and player.get("camera")!=null: player.camera = tunnel_camera
		tunnel_camera.make_current()
	elif is_instance_valid(_previous_camera):
		_previous_camera.make_current()
		if is_instance_valid(player) and player.get("camera")!=null: player.camera = _previous_camera

func _exit_tree() -> void:
	_set_occupied(false)

func _build() -> void:
	name = "SecretTunnel"
	position = WORLD_ORIGIN
	rotation.y = WORLD_YAW
	_build_stairs()
	_build_old_tunnel()
	_build_headquarters()
	preload("res://gameplay/urban_v1/SecretHeadquartersProps.gd").build(self)
	_build_sealed_sector()
	# Rocha ao redor das salas (sem colisão) e a cenografia dos segredos; antes
	# uma laje escura lisa deixava o corte da câmera preto fora dos ambientes.
	preload("res://gameplay/urban_v1/SecretTunnelDecor.gd").build(self)
	_flush()
	_build_camera()
	_build_wildlife()
	audio_zone = TUNNEL_AUDIO.new()
	add_child(audio_zone)
	audio_zone.configure(player)
	_apply_underground_layer(self)

func _build_stairs() -> void:
	# A masonry stair descends 4.5 m. The treads are visual; one hidden ramp owns
	# smooth actor collision so feet cannot snag on fourteen separate boxes.
	for step in 14:
		var z := 5.7-float(step)*.58
		var y := 4.18-float(step)*.32
		_box(Vector3(0,y,z),Vector3(3.4,.22,.64),"454b45")
	# Landing aligns with the opening behind the cellar bookshelf.
	_box(Vector3(0,4.48,7.15),Vector3(3.4,.20,2.45),"454b45")
	_solid("EntryLanding",Vector3(0,4.37,7.15),Vector3(3.3,.20,2.45))
	var angle := atan2(4.48,8.1)
	# Bury the lower end beneath the floor while keeping the upper landing
	# fixed. An exposed box end traps a walking capsule on the return climb.
	var buried_toe := .40
	var ramp_center := Vector3(0,2.18,1.95)-Vector3(0,sin(angle),cos(angle))*buried_toe*.5
	_solid("StairRamp",ramp_center,Vector3(3.25,.18,9.25+buried_toe),Vector3(-angle,0,0))
	for side in [-1.0,1.0]:
		_box(Vector3(side*1.82,2.15,1.85),Vector3(.34,4.9,9.6),"4a514b")
		_solid("StairWall",Vector3(side*1.82,2.15,1.85),Vector3(.34,4.9,9.6))
		_box(Vector3(side*1.82,4.0,7.15),Vector3(.34,2.1,2.45),"4a514b")
		_solid("EntryWall",Vector3(side*1.82,4.0,7.15),Vector3(.34,2.1,2.45))
	# Broken cap stones leave a wide camera cutaway while preserving the sense
	# of a low ceiling along both edges.
	for side in [-1.0,1.0]: _box(Vector3(side*1.55,4.85,1.9),Vector3(.72,.35,9.6),"343b37")
	_light(Vector3(1.18,4.2,5.1),Color("d2a45f"),3.6,.82)

func _build_old_tunnel() -> void:
	# The dogleg stays below the village and away from the western coast: short
	# west descent, long north gallery, broken service bend, then the HQ.
	# Side-specific end openings keep every dogleg physically traversable.
	_corridor_z(Vector3(0,0,-7.0),10.0,0,1,0)
	_corridor_x(Vector3(18.0,0,-12.0),36.0,1,1,1)
	_corridor_z(Vector3(36.0,0,-5.0),14.0,2,-1,1)
	# The final walls stop at the west face of the HQ instead of partitioning it.
	_corridor_x(Vector3(46.0,0,2.0),20.0,3,-1,0,5.35)
	_rock(Vector3(-1.8,.18,-8.5),Vector3(.72,.38,.58),.47)
	_rock(Vector3(14.0,.16,-10.1),Vector3(.62,.32,.48),.9)
	_rock(Vector3(35.1,.18,-7.0),Vector3(.74,.40,.55),-.4)
	_rock(Vector3(47.0,.14,3.65),Vector3(.54,.28,.42),.2)
	_pipe(Vector3(-2.35,2.35,-9.0),Vector3(-2.35,2.35,-13.0),.09,"6f6657")
	_pipe_support(Vector3(-2.48,2.35,-9.8),Vector3(.18,.48,.11))
	_pipe_support(Vector3(-2.48,2.35,-11.7),Vector3(.18,.48,.11))
	_pipe(Vector3(9.0,2.35,-14.3),Vector3(25.0,2.35,-14.3),.09,"6f6657")
	for x in [11.0,15.0,19.0,23.0]: _pipe_support(Vector3(x,2.35,-14.47),Vector3(.11,.48,.18))
	_pipe(Vector3(38.3,2.35,-8.0),Vector3(38.3,2.35,-1.0),.09,"6f6657")
	for z in [-6.8,-4.2,-1.6]: _pipe_support(Vector3(38.47,2.35,z),Vector3(.18,.48,.11))
	_light(Vector3(1.95,2.55,-9.0),Color("d0a15e"),4.4,.70)
	_light(Vector3(18.0,2.45,-14.2),Color("9cae86"),4.1,.56)
	_light(Vector3(40.0,2.4,3.9),Color("c38b55"),3.8,.48)

func _corridor_z(center: Vector3,length: float,variant: int,open_negative_side := 0,open_positive_side := 0) -> void:
	_box(center+Vector3(0,-.12,0),Vector3(5.2,.20,length),"50564e")
	_solid("TunnelFloor",center+Vector3(0,-.20,0),Vector3(5.2,.22,length))
	for side in [-1.0,1.0]:
		var offset: float = float(side)*(2.7+(.22 if variant%2 else 0.0))
		var min_cut := 3.05 if open_negative_side == int(side) else 0.0
		var max_cut := 3.05 if open_positive_side == int(side) else 0.0
		_corridor_wall_z(center,offset,length,side,variant,min_cut,max_cut)
	_puddle(center+Vector3(-.48,.016,-length*.12),Vector2(.62,minf(2.15,length*.23)),.14*float(variant-1),"243b3a",variant)
	_puddle(center+Vector3(1.08,.014,length*.22),Vector2(.38,minf(.92,length*.11)),-.22,"314744",variant+3)
	_floor_cracks(center+Vector3(.62,.018,-length*.29),false,variant)
	var arch_count := maxi(1,floori(length/7.0))
	for index in arch_count:
		var z := center.z-length*.5+(float(index)+.5)*length/float(arch_count)
		_arch_z(Vector3(center.x,0,z),variant)

func _corridor_x(center: Vector3,length: float,variant: int,open_negative_side := 0,open_positive_side := 0,positive_trim := 0.0) -> void:
	_box(center+Vector3(0,-.12,0),Vector3(length,.20,5.2),"50564e")
	_solid("TunnelFloor",center+Vector3(0,-.20,0),Vector3(length,.22,5.2))
	for side in [-1.0,1.0]:
		var offset: float = float(side)*(2.7+(.22 if variant%2 else 0.0))
		var min_cut := 3.05 if open_negative_side == int(side) else 0.0
		var max_cut := positive_trim + (3.05 if open_positive_side == int(side) else 0.0)
		_corridor_wall_x(center,offset,length,side,variant,min_cut,max_cut,side<0.0)
	_puddle(center+Vector3(-length*.16,.016,-.52),Vector2(minf(2.35,length*.16),.58),.08*float(variant-2),"243b3a",variant+5)
	_puddle(center+Vector3(length*.28,.014,1.08),Vector2(minf(1.06,length*.08),.34),.18,"314744",variant+8)
	_floor_cracks(center+Vector3(length*.08,.018,.62),true,variant)
	var visible_length := length-positive_trim
	var arch_count := maxi(1,floori(visible_length/7.5))
	for index in arch_count:
		var x := center.x-length*.5+(float(index)+.55)*visible_length/float(arch_count)
		_arch_x(Vector3(x,0,center.z),variant)

func _corridor_wall_z(center: Vector3,offset: float,length: float,side: float,variant: int,min_cut: float,max_cut: float) -> void:
	var span := length-min_cut-max_cut
	if span<=.2: return
	var at := center+Vector3(offset,1.65,(min_cut-max_cut)*.5)
	_box(at,Vector3(.46,3.5,span-.08),"454b45")
	_solid("StoneWallZ_%d_%d"%[variant,int(side)],at,Vector3(.48,3.5,span))
	_box(Vector3(center.x+side*2.35,3.42,at.z),Vector3(.72,.36,span-.10),"3d4541",Vector3(0,0,side*.22))
	_masonry_face_z(at,span,side,variant)

func _corridor_wall_x(center: Vector3,offset: float,length: float,side: float,variant: int,min_cut: float,max_cut: float,visible_wall: bool) -> void:
	var span := length-min_cut-max_cut
	if span<=.2: return
	var at := center+Vector3((min_cut-max_cut)*.5,1.65,offset)
	_solid("StoneWallX_%d_%d"%[variant,int(side)],at,Vector3(span,3.5,.48))
	# The +Z wall is closest to the isometric camera: retain collision but use
	# the far wall and partial arches as the cutaway silhouette.
	if not visible_wall: return
	_box(at,Vector3(span-.08,3.5,.46),"454b45")
	_box(Vector3(at.x,3.42,center.z+side*2.35),Vector3(span-.10,.36,.72),"3d4541",Vector3(side*.22,0,0))
	_masonry_face_x(at,span,side,variant)

func _masonry_face_z(at: Vector3,length: float,side: float,variant: int) -> void:
	var palette := ["62685d","596158","4e5750","6b6d60"]
	for course in 6:
		var y := .18+float(course)*.53
		var brick_length := 1.02+.13*float((course+variant)%3)
		var cursor := -length*.5+(.48*brick_length if course%2 else .08)
		var index := 0
		while cursor < length*.5-.12:
			var remaining := length*.5-cursor
			var run := minf(brick_length,remaining)-.055
			if run>.18:
				var depth := .085+.018*float((index+course+variant)%3)
				_box(Vector3(at.x-side*(.245+depth*.5),y,at.z+cursor+run*.5),Vector3(depth,.46,run),palette[(index+course+variant)%palette.size()],Vector3(0,.012*float((index%3)-1),0))
			cursor += brick_length
			index += 1
	# Damp mineral blooms sit on the inner face rather than tinting the room.
	_box(Vector3(at.x-side*.305,.78,at.z-length*.18),Vector3(.025,.82,minf(1.4,length*.26)),"34433b",Vector3(.06,0,.02*side))

func _masonry_face_x(at: Vector3,length: float,side: float,variant: int) -> void:
	var palette := ["62685d","596158","4e5750","6b6d60"]
	for course in 6:
		var y := .18+float(course)*.53
		var brick_length := 1.04+.12*float((course+variant)%3)
		var cursor := -length*.5+(.5*brick_length if course%2 else .08)
		var index := 0
		while cursor < length*.5-.12:
			var remaining := length*.5-cursor
			var run := minf(brick_length,remaining)-.055
			if run>.18:
				var depth := .085+.018*float((index+course+variant)%3)
				_box(Vector3(at.x+cursor+run*.5,y,at.z-side*(.245+depth*.5)),Vector3(run,.46,depth),palette[(index+course+variant)%palette.size()],Vector3(0,.012*float((index%3)-1),0))
			cursor += brick_length
			index += 1
	_box(Vector3(at.x+length*.17,.72,at.z-side*.305),Vector3(minf(1.65,length*.24),.88,.025),"34433b",Vector3(.02,0,.04*side))

func _arch_z(at: Vector3,variant: int) -> void:
	for index in 7:
		var t := (float(index)-3.0)/3.0
		var color := "6b6d60" if (index+variant)%2 else "555e55"
		_box(at+Vector3(t*2.23,2.64+(1.0-absf(t))*.78,0),Vector3(.62,.34,.46),color,Vector3(0,0,-t*.54))

func _arch_x(at: Vector3,variant: int) -> void:
	# Only the far half remains, making the vaulted construction readable while
	# preserving the camera-side cutaway.
	for index in 4:
		var t := -1.0+float(index)/3.0
		var color := "6b6d60" if (index+variant)%2 else "555e55"
		_box(at+Vector3(0,2.64+(1.0-absf(t))*.78,t*2.23),Vector3(.46,.34,.62),color,Vector3(t*.54,0,0))

func _pipe_support(at: Vector3,size: Vector3) -> void:
	_box(at,size,"4a463d")
	_box(at+Vector3(0,-size.y*.44,0),size*Vector3(1.45,.12,1.45),"777063")

func _puddle(at: Vector3,p_scale: Vector2,yaw: float,color: String,variant: int) -> void:
	var surface: SurfaceTool
	if _batches.has(color):
		surface = _batches[color]
	else:
		surface = SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[color] = surface
	var points: Array[Vector3] = []
	for index in 10:
		var angle := TAU*float(index)/10.0
		var irregular := .78+.07*float((index*7+variant*3)%5)
		var local := Vector3(cos(angle)*p_scale.x*irregular,0,sin(angle)*p_scale.y*irregular).rotated(Vector3.UP,yaw)
		points.append(at+local)
	for index in 10:
		for point in [at,points[index],points[(index+1)%10]]:
			surface.set_normal(Vector3.UP)
			surface.add_vertex(point)

func _floor_cracks(at: Vector3,along_x: bool,variant: int) -> void:
	var base_angle := .34 if along_x else -.52
	var main_size := Vector3(.92,.012,.035) if along_x else Vector3(.035,.012,.92)
	_box(at,main_size,"343b37",Vector3(0,base_angle+.04*variant,0))
	var branch_size := Vector3(.42,.011,.028) if along_x else Vector3(.028,.011,.42)
	_box(at+Vector3(.24,0,-.18),branch_size,"343b37",Vector3(0,base_angle-.62,0))

func _build_headquarters() -> void:
	var c := HQ_CENTER
	_box(c+Vector3(0,-.12,0),Vector3(15,.20,15),"4f5550")
	_solid("HeadquartersFloor",c+Vector3(0,-.20,0),Vector3(15,.22,15))
	# The west wall is split around the tunnel mouth. The previous continuous
	# slab at x=50.4 visually and physically cut across the incoming corridor.
	_headquarters_wall_z(c+Vector3(-7.6,2,-5.2),Vector3(.35,4,4.6),-1.0,"WestWallNorth")
	_headquarters_wall_z(c+Vector3(-7.6,2,5.2),Vector3(.35,4,4.6),-1.0,"WestWallSouth")
	_headquarters_wall_z(c+Vector3(7.6,2,0),Vector3(.35,4,15),1.0,"EastWall")
	_headquarters_wall_x(c+Vector3(-5.1,2,-7.6),Vector3(5,4,.35),-1.0,"NorthWallWest")
	_headquarters_wall_x(c+Vector3(5.1,2,-7.6),Vector3(5,4,.35),-1.0,"NorthWallEast")
	for pillar in [
		c+Vector3(-7.22,1.65,-2.72),c+Vector3(-7.22,1.65,2.72),
		c+Vector3(7.22,1.65,-7.15),c+Vector3(-7.22,1.65,-7.15),
	]:
		_box(pillar,Vector3(.62,3.3,.62),"3d4541")
	# Operations table has a readable top and actual legs; its full footprint
	# remains the collision owner so Dante cannot walk through the tabletop.
	_box(c+Vector3(0,.82,1.2),Vector3(3.4,.14,2.1),"796a4e")
	_solid("MapTable",c+Vector3(0,.46,1.2),Vector3(3.4,.92,2.1))
	for x in [-1.42,1.42]:
		for z in [.38,2.02]: _box(c+Vector3(x,.39,z),Vector3(.16,.72,.16),"4a4133")
	_box(c+Vector3(0,.91,1.2),Vector3(3.02,.025,1.72),"b8ad8d")
	# Harbor coastline, main road and drainage branch are geometry, not labels.
	_box(c+Vector3(-1.08,.932,1.22),Vector3(.52,.018,1.58),"526f73",Vector3(0,.08,0))
	_box(c+Vector3(.12,.944,1.28),Vector3(2.34,.022,.10),"5c5850",Vector3(0,-.20,0))
	_box(c+Vector3(.48,.946,.86),Vector3(.10,.023,1.08),"5c5850",Vector3(0,.34,0))
	_box(c+Vector3(.98,.948,1.62),Vector3(.72,.024,.34),"68755d",Vector3(0,-.18,0))
	for marker in [Vector3(-.42,.98,.84),Vector3(.45,.98,1.19),Vector3(1.12,.98,1.65)]:
		_cylinder(c+marker,.07,.10,"9f513f")
	# A real open shelf with uprights, trays and stored field boxes.
	_solid("SupplyShelf",c+Vector3(-5.85,.75,-2.0),Vector3(1.8,1.5,3.8))
	for x in [-6.62,-5.08]:
		for z in [-3.62,-.38]: _box(c+Vector3(x,.86,z),Vector3(.11,1.72,.11),"4c514a")
	for y in [.16,.78,1.46]: _box(c+Vector3(-5.85,y,-2.0),Vector3(1.68,.09,3.55),"697067")
	_box(c+Vector3(-5.86,.47,-2.95),Vector3(1.28,.48,.72),"6b5b43")
	_box(c+Vector3(-5.86,1.06,-1.02),Vector3(1.25,.42,.66),"5b674f")
	for z in [-2.18,-1.94,-1.70,-1.46]: _box(c+Vector3(-5.82,1.15,z),Vector3(1.18,.47,.12),"704f42")
	# Desk and vintage radio retain the route-console footprint.
	_box(c+Vector3(5.7,.78,-2.1),Vector3(2.2,.14,1.1),"675d4b")
	_solid("RadioDesk",c+Vector3(5.7,.68,-2.1),Vector3(2.2,1.36,1.1))
	for x in [4.82,6.58]:
		for z in [-2.48,-1.72]: _box(c+Vector3(x,.4,z),Vector3(.14,.72,.14),"4a4133")
	_build_vintage_radio(c+Vector3(5.7,1.30,-2.1))
	_build_network_console(c)
	_light(c+Vector3(-4.7,3.1,3.8),Color("c6a264"),5.5,.72)
	_light(c+Vector3(4.7,3.1,-4.8),Color("88a291"),5.0,.66)

func _build_network_console(c: Vector3) -> void:
	# Mechanical network console communicates state with lamps, not labels. Built
	# from nodes (not batched) because it lifts away once the sealed sector has power.
	console_node = Node3D.new()
	console_node.name = "NetworkConsoleBoard"
	add_child(console_node)
	_node_box(console_node,c+Vector3(0,1.45,-6.9),Vector3(4.6,2.4,.3),"33403d")
	console_body = _solid("NetworkConsole",c+Vector3(0,1.45,-6.9),Vector3(4.6,2.4,.36))
	for x in [-2.14,2.14]: _node_box(console_node,c+Vector3(x,1.45,-6.70),Vector3(.12,2.18,.08),"777063")
	for y in [.40,2.50]: _node_box(console_node,c+Vector3(0,y,-6.70),Vector3(4.28,.10,.08),"777063")
	for x in [-1.45,-.48,.48,1.45]:
		var color := "6b8f6a" if x<0 else "76564a"
		_node_cylinder(console_node,c+Vector3(x,1.55,-6.67),.16,.08,color,Vector3(PI*.5,0,0))
		_node_box(console_node,c+Vector3(x,1.08,-6.67),Vector3(.22,.08,.07),"b18a4f")
	# Exposed cloth wiring gives the board a mechanical, repaired-by-hand read.
	for wire in [
		[Vector3(-1.46,1.30,-6.60),Vector3(-.55,.70,-6.60),"8d3f35"],
		[Vector3(-.48,1.30,-6.60),Vector3(.40,.82,-6.60),"a68a4c"],
		[Vector3(.48,1.30,-6.60),Vector3(1.45,.72,-6.60),"4d675d"],
	]:
		var from: Vector3 = c+wire[0]
		var to: Vector3 = c+wire[1]
		var rod := _node_cylinder(console_node,(from+to)*.5,.05,from.distance_to(to),wire[2])
		rod.basis = Basis.looking_at((to-from).normalized(),Vector3.UP)*Basis(Vector3.RIGHT,PI*.5)
	for x in [-1.7,-.85,0.0,.85,1.7]: _node_box(console_node,c+Vector3(x,2.18,-6.64),Vector3(.42,.26,.07),"4b5550")

func _node_box(parent: Node3D,at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var display := MeshInstance3D.new()
	display.mesh = mesh
	display.material_override = _material(color)
	display.position = at
	display.rotation = angles
	parent.add_child(display)
	return display

func _node_cylinder(parent: Node3D,at: Vector3,diameter: float,height: float,color: String,angles := Vector3.ZERO,segments := 12) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = diameter*.5
	mesh.bottom_radius = diameter*.5
	mesh.height = height
	mesh.radial_segments = segments
	var display := MeshInstance3D.new()
	display.mesh = mesh
	display.material_override = _material(color)
	display.position = at
	display.rotation = angles
	parent.add_child(display)
	return display

func _headquarters_wall_z(at: Vector3,size: Vector3,side: float,id: String) -> void:
	_box(at,size,"454b48")
	_solid("Headquarters"+id,at,size)
	_masonry_face_z(at,size.z,side,4)

func _headquarters_wall_x(at: Vector3,size: Vector3,side: float,id: String) -> void:
	_box(at,size,"454b48")
	_solid("Headquarters"+id,at,size)
	_masonry_face_x(at,size.x,side,5)

func _build_vintage_radio(at: Vector3) -> void:
	_box(at,Vector3(1.52,.72,.62),"4b4437")
	_box(at+Vector3(-.34,.04,.326),Vector3(.58,.48,.025),"292d2a")
	for x in [-.53,-.41,-.29,-.17,-.05]: _box(at+Vector3(x,.04,.346),Vector3(.026,.42,.018),"777063")
	_box(at+Vector3(.36,.13,.345),Vector3(.40,.12,.02),"b6a36e")
	for x in [.24,.48]: _cylinder(at+Vector3(x,-.13,.36),.09,.07,"777063",Vector3(PI*.5,0,0),12)
	_pipe(at+Vector3(.60,.38,0),at+Vector3(.82,1.16,-.08),.018,"777063")

func _build_sealed_sector() -> void:
	# A damaged containment threshold hints at something older below the city.
	# No readable signage and no creature confirms what happened here.
	var gate := HQ_CENTER+Vector3(0,0,-7.9)
	# Open bars reveal the room beyond. A dedicated full gate collider owns the
	# locked threshold until the sealed sector has power (set_sealed_access).
	gate_body = _solid("SealedGate",gate+Vector3(0,1.65,.02),Vector3(4.2,3.3,.28))
	for x in [-2.04,2.04]: _box(gate+Vector3(x,1.65,.02),Vector3(.24,3.45,.30),"303a39")
	for y in [.08,3.22]: _box(gate+Vector3(0,y,.02),Vector3(4.25,.24,.30),"303a39")
	# As duas folhas de grade deslizam para dentro das paredes laterais.
	for side in [-1.0,1.0]:
		var half := Node3D.new()
		half.name = "SealedGateLeaf"+("West" if side<0 else "East")
		add_child(half)
		gate_halves.append(half)
		for x in [.08,.6,1.12,1.64]: _node_box(half,gate+Vector3(side*x,1.65,.10),Vector3(.095,3.08,.12),"75796e")
		_node_box(half,gate+Vector3(side*.9,1.62,.17),Vector3(1.9,.10,.11),"696d65")
	_node_box(gate_halves[1],gate+Vector3(.25,1.54,.29),Vector3(.28,.38,.16),"8b744a",Vector3(0,0,.12))
	# Piso no mesmo nível do QG, com colisão: antes o setor não tinha chão físico.
	_box(gate+Vector3(0,-.12,-3.5),Vector3(4.2,.20,6.7),"3d4542")
	_solid("SealedFloor",gate+Vector3(0,-.20,-3.1),Vector3(4.2,.22,7.0))
	_build_vault_door(gate)
	for side in [-1.0,1.0]:
		_box(gate+Vector3(side*2.2,1.65,-3.5),Vector3(.35,3.5,7),"414946")
		_solid("SealedWall",gate+Vector3(side*2.2,1.65,-3.5),Vector3(.38,3.5,7))
		_masonry_face_z(gate+Vector3(side*2.2,1.65,-3.5),7,side,6)
	_box(gate+Vector3(0,1.65,-6.92),Vector3(4.7,3.5,.34),"414946")
	_solid("SealedBackWall",gate+Vector3(0,1.65,-6.92),Vector3(4.7,3.5,.38))
	# Broken edge slabs preserve the ceiling volume without hiding the evidence
	# from the elevated cutaway camera.
	for side in [-1.0,1.0]:
		_box(gate+Vector3(side*1.92,3.3,-3.6),Vector3(.72,.32,7.2),"343b39",Vector3(0,0,side*.025))
	_box(gate+Vector3(-1.12,3.28,-6.35),Vector3(1.05,.24,1.22),"3d4541",Vector3(.03,.10,-.02))
	_box(gate+Vector3(1.30,3.26,-5.92),Vector3(.82,.20,.90),"3d4541",Vector3(-.02,-.14,.03))
	# Gurney with frame, mattress, pillow, snapped restraints, legs and wheels.
	var bed := gate+Vector3(-.75,0,-4.5)
	_box(bed+Vector3(0,.66,0),Vector3(1.02,.13,2.20),"65716b",Vector3(0,.12,0))
	_solid("OldGurney",gate+Vector3(-.75,.42,-4.5),Vector3(1.0,.84,2.2))
	for x in [-.46,.46]: _box(bed+Vector3(x,.53,0),Vector3(.07,.08,2.28),"777063",Vector3(0,.12,0))
	for z in [-.88,.88]:
		_box(bed+Vector3(0,.53,z),Vector3(.98,.08,.07),"777063",Vector3(0,.12,0))
		for x in [-.40,.40]:
			_box(bed+Vector3(x,.27,z),Vector3(.07,.52,.07),"696d65")
			_cylinder(bed+Vector3(x,.07,z),.10,.07,"323936",Vector3(0,0,PI*.5),10)
	_box(bed+Vector3(0,.77,-.72),Vector3(.68,.12,.40),"999889",Vector3(0,.12,0))
	for z in [-.30,.38]: _box(bed+Vector3(0,.76,z),Vector3(.94,.055,.09),"584943",Vector3(0,.12,0))
	_rock(gate+Vector3(.72,.12,-2.1),Vector3(.52,.30,.42),.3)
	_rock(gate+Vector3(1.25,.17,-2.55),Vector3(.66,.38,.48),-.45)
	_light(gate+Vector3(0,2.65,-5.0),Color("9a3834"),3.8,.54)

func _build_vault_door(gate: Vector3) -> void:
	# Porta circular de cofre no fundo do setor lacrado (x=1 na parede norte). A folha
	# recua para dentro da parede; o vão revelado é o teletransporte para o forte.
	var center := gate+Vector3(.9,1.5,-6.62)
	var wall_face := gate.z-6.75
	# Moldura fixa (lote estático) e vão escuro/luminoso oculto até a abertura.
	for index in 16:
		var angle := TAU*float(index)/16.0
		_box(Vector3(center.x+cos(angle)*1.0,center.y+sin(angle)*1.0,wall_face+.10),Vector3(.24,.42,.20),"303a39" if index%2 else "696d65",Vector3(0,0,angle))
	vault_portal = Node3D.new()
	vault_portal.name = "VaultPortal"
	vault_portal.visible = false
	add_child(vault_portal)
	_node_cylinder(vault_portal,Vector3(center.x,center.y,wall_face+.05),1.62,.05,"0d1211",Vector3(PI*.5,0,0),24)
	_node_cylinder(vault_portal,Vector3(center.x,center.y,wall_face+.08),1.15,.03,"3f8079",Vector3(PI*.5,0,0),24)
	vault_door = Node3D.new()
	vault_door.name = "VaultDoorLeaf"
	add_child(vault_door)
	_node_cylinder(vault_door,center+Vector3(0,0,.12),1.72,.24,"5b6660",Vector3(PI*.5,0,0),24)
	_node_cylinder(vault_door,center+Vector3(0,0,.26),1.36,.05,"696d65",Vector3(PI*.5,0,0),24)
	for index in 10:
		var angle := TAU*float(index)/10.0
		_node_box(vault_door,center+Vector3(cos(angle)*.74,sin(angle)*.74,.28),Vector3(.16,.16,.09),"303a39",Vector3(0,0,angle))
	# Volante central com raios, faixa de perigo e placa sem texto.
	_node_cylinder(vault_door,center+Vector3(0,0,.34),.34,.1,"777063",Vector3(PI*.5,0,0),14)
	for spoke in 3:
		_node_box(vault_door,center+Vector3(0,0,.40),Vector3(1.0,.09,.06),"777063",Vector3(0,0,PI*float(spoke)/3.0))
	_node_box(vault_door,center+Vector3(0,-.56,.29),Vector3(.9,.10,.03),"8b744a")
	_node_box(vault_door,center+Vector3(0,.56,.29),Vector3(.5,.16,.03),"b8ad8d")
	# Pedestal do teclado diante da porta: visor apagado até o setor ter energia.
	var pedestal := gate+Vector3(.9,0,-5.4)
	_solid("VaultPedestal",pedestal+Vector3(0,.5,0),Vector3(.5,1.0,.4))
	_box(pedestal+Vector3(0,.5,0),Vector3(.5,1.0,.4),"33403d")
	_box(pedestal+Vector3(0,1.03,.03),Vector3(.56,.08,.46),"777063")
	_box(pedestal+Vector3(0,1.1,.06),Vector3(.44,.05,.30),"292d2a",Vector3(-.5,0,0))
	for row in 4:
		for col in 3:
			_box(pedestal+Vector3(-.12+float(col)*.12,1.115+float(row)*.008,.16-float(row)*.055),Vector3(.09,.02,.04),"b8ad8d",Vector3(-.5,0,0))
	_box(pedestal+Vector3(0,1.22,-.1),Vector3(.40,.14,.05),"3d4541")
	_cylinder(pedestal+Vector3(-.15,1.22,-.07),.05,.03,"76564a",Vector3(PI*.5,0,0),8)

func _build_camera() -> void:
	tunnel_camera = Camera3D.new()
	tunnel_camera.name = "SecretTunnelCamera"
	tunnel_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	tunnel_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	tunnel_camera.size = 15.0
	tunnel_camera.far = 90.0
	tunnel_camera.cull_mask = UNDERGROUND_LAYER
	UNDERGROUND_ENVIRONMENT.apply_to(tunnel_camera)
	add_child(tunnel_camera)

func _apply_underground_layer(root: Node) -> void:
	for node in root.find_children("*","GeometryInstance3D",true,false):
		node.layers = UNDERGROUND_LAYER
	for light in root.find_children("*","Light3D",true,false):
		light.layers = UNDERGROUND_LAYER
		light.light_cull_mask = UNDERGROUND_LAYER

func _enable_player_underground_layer() -> void:
	if not is_instance_valid(player): return
	for node in player.find_children("*","GeometryInstance3D",true,false):
		node.layers |= UNDERGROUND_LAYER

func _build_wildlife() -> void:
	var routes: Array[Array] = [
		[Vector3(-1.8,.02,-10),Vector3(6,.02,-11.2),Vector3(12,.02,-10.4)],
		[Vector3(20,.02,-13.5),Vector3(30,.02,-10.2),Vector3(36,.02,-4)],
		[Vector3(48,.02,3.7),Vector3(54,.02,4.2),Vector3(60,.02,5.0)],
	]
	for index in routes.size():
		var rat := RAT.new()
		add_child(rat)
		var global_route: Array[Vector3] = []
		for point in routes[index]: global_route.append(to_global(point))
		rat.global_position = global_route[0]
		rat.configure(global_route,player,index)
		rats.append(rat)

func _light(at: Vector3,color: Color,reach: float,energy: float) -> void:
	# Lights are deliberately few, short-range and shadowless; darkness and
	# flicker sell the space without a large overlapping-light budget.
	var lamp := OmniLight3D.new()
	lamp.position = at
	lamp.light_color = color
	lamp.omni_range = reach
	lamp.light_energy = energy*4.0
	lamp.shadow_enabled = false
	lamp.set_meta("base_energy",energy*4.0)
	add_child(lamp)
	lights.append(lamp)
	# Batched bulkhead housing and guard cage make every real light motivated.
	_box(at+Vector3(0,.15,-.08),Vector3(.44,.30,.12),"303a39")
	_box(at+Vector3(0,.14,.015),Vector3(.25,.13,.10),"7a6a51")
	for x in [-.18,.18]: _box(at+Vector3(x,.14,.03),Vector3(.035,.32,.035),"777063")
	for y in [.01,.27]: _box(at+Vector3(0,y,.035),Vector3(.40,.035,.035),"777063")

func _pipe(a: Vector3,b: Vector3,radius: float,color: String) -> void:
	var midpoint := (a+b)*.5
	var direction := b-a
	if direction.length_squared()<=.000001: return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = direction.length()
	mesh.radial_segments = 8
	var up := Vector3.FORWARD if absf(direction.normalized().dot(Vector3.UP))>.98 else Vector3.UP
	var local_basis := Basis.looking_at(direction.normalized(),up)*Basis(Vector3.RIGHT,PI*.5)
	_batch_mesh(mesh,color,Transform3D(local_basis,midpoint))
	# Slight collars make pipe joins and repaired endpoints visible.
	for point in [a,b]:
		var collar := CylinderMesh.new()
		collar.top_radius=radius*1.34; collar.bottom_radius=radius*1.34
		collar.height=minf(.09,direction.length()*.25); collar.radial_segments=8
		_batch_mesh(collar,color,Transform3D(local_basis,point))

func _cylinder(at: Vector3,radius: float,height: float,color: String,angles := Vector3.ZERO,segments := 8) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius=radius
	mesh.bottom_radius=radius
	mesh.height=height
	mesh.radial_segments=segments
	_batch_mesh(mesh,color,Transform3D(Basis.from_euler(angles),at))

func _rock(at: Vector3,size: Vector3,yaw: float) -> void:
	_box(at,size,"424943",Vector3(.15,yaw,.10))
	_solid("BrokenStone",at,size,Vector3(0,yaw,0))

func _box(at: Vector3,size: Vector3,color: String,angles := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch_mesh(mesh,color,Transform3D(Basis.from_euler(angles),at))

func _batch_mesh(mesh: PrimitiveMesh,color: String,p_transform: Transform3D) -> void:
	var key := color
	if not _batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = surface
	_batches[key].append_from(mesh,0,p_transform)

func _flush() -> void:
	for color in _batches:
		var display := MeshInstance3D.new()
		display.name = "TunnelBatch_"+str(color)
		display.mesh = _batches[color].commit()
		display.material_override = _material(color)
		add_child(display)
	_batches.clear()

func _material(color: String) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(color)
		material.roughness = .91
		if color in ["50564e","4f5550","3d4542"]:
			material.roughness = .72
			material.metallic = 0.0
		if color in ["243b3a","314744"]:
			material.roughness = .22
			material.metallic = .05
		if color in ["34433b","526f73"]:
			material.roughness = .70
			material.metallic = 0.0
		if color in ["777063","696d65","75796e","303a39"]:
			material.roughness=.42
			material.metallic=.38
		if color in ["7a6a51","6b8f6a","76564a","c9a75f","3f8079"]:
			material.emission_enabled = true
			material.emission = Color(color)*1.35
		_materials[color] = material
	return _materials[color]

func _solid(id: String,at: Vector3,size: Vector3,angles := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.rotation = angles
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id","secret_tunnel/"+id)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	solids.append(body)
	return body
