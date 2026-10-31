extends "res://world/places/upside_world/UpsideGeometry.gd"
## Um palco de alucinação finito e remoto. O runtime é dono do teleporte, da câmera em
## primeira pessoa, da duração e da recuperação; este nó só é dono do cenário e das aparições.
const APPARITION := preload("res://world/places/upside_world/Apparition.gd")
const SPAWN := Vector3(0,.08,7)
const METEOR_COUNT := 22
const RAIN_COUNT := 112
const FLOATING_COUNT := 16
var spawn_local := SPAWN
var visitor_local := SPAWN
var elapsed := 0.0
var active := true
var monsters: Array[CharacterBody3D] = []
var local_lights: Array[OmniLight3D] = []
var floating: Array[MeshInstance3D] = []
var floating_homes: Array[Vector3] = []
var meteor_batch: MultiMesh
var trail_batch: MultiMesh
var rain_batch: MultiMesh
var wind: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _meteor_seeds: Array[Vector3] = []
var _rain_seeds: Array[Vector3] = []

func _ready() -> void:
	name = "UpsideWorld"
	set_meta("illusion_only",true)
	_rng.seed = 6100713
	_ground()
	_borders()
	_ruins()
	_broken_furniture()
	_roots_and_rifts()
	_floating_debris()
	_lighting()
	flush_batches()
	_weather()
	_ambience()
	_residents()
	var spawn := Marker3D.new()
	spawn.name = "SafeArrival"
	spawn.position = spawn_local
	add_child(spawn)
	update_effect(0.0)

func set_visitor(point: Vector3) -> void:
	visitor_local = point
	for monster in monsters: monster.visitor_local = point

func set_active(value: bool) -> void:
	active = value
	visible = value
	process_mode = Node.PROCESS_MODE_INHERIT if value else Node.PROCESS_MODE_DISABLED
	if is_instance_valid(wind): wind.stream_paused = not value

func _process(delta: float) -> void:
	if active: update_effect(delta)

func _ground() -> void:
	box("UnbrokenFloor",Vector3(0,-.15,0),Vector3(28,.30,28),"312c3a",true)
	for row in 14:
		for col in 14:
			var shade: String = ["383041","3c3348","332d3c"][(row*7+col)%3]
			piece("box",Vector3(-13+col*2,.010,-13+row*2),Vector3(1.98,.019,1.98),shade)
	# Marcas de aparência quebrada ficam no piso físico contínuo; o jogador
	# nunca cai numa rachadura cosmética nem aparece acima de destroços flutuando.
	for side in [-1,1]:
		for segment in 10:
			piece("box",Vector3(side*2.45,.023,-10+segment*2.1),Vector3(.055,.013,1.28),"807384","metal",Vector3(0,sin(segment)*.10,0))
	for i in 20:
		var x := _rng.randf_range(-12.7,12.7)
		var z := _rng.randf_range(-12.7,12.7)
		piece("box",Vector3(x,.022,z),Vector3(.05,.013,.35+fmod(i*.7,1.2)),"161321", "metal",Vector3(0,i*1.7,0))

func _borders() -> void:
	# A arena caminhável termina em alvenaria real, nunca numa barreira invisível
	# sem marca. Silhuetas externas repetidas fazem um skyline em ruínas maior.
	for side in [-1,1]:
		box("EastWestBoundary%d"%side,Vector3(side*13.85,1.65,0),Vector3(.30,3.3,28),"393043",true)
		box("NorthSouthBoundary%d"%side,Vector3(0,1.65,side*13.85),Vector3(27.4,3.3,.30),"3f3248",true)
		for index in 8:
			var z := -12+index*3.4
			var height := 4.0+fmod(index*1.7,4.8)
			piece("box",Vector3(side*15.5,height*.5,z),Vector3(2.6,height,2.6),"302635", "stone",Vector3(0,.05*side,.10*side))
			for story in 3:
				piece("box",Vector3(side*13.96,1.5+story*1.5,z),Vector3(.035,.62,.5),"9864b4","glow")
		for index in 7:
			var x := -12+index*4.0
			var height := 5.3+fmod(index*2.3,4.5)
			piece("box",Vector3(x,height*.5,side*15.8),Vector3(3.2,height,2.9),"382b40","stone",Vector3(side*.12,0,.05*sin(index)))
			for story in 4:
				for window in 2: piece("box",Vector3(x-.65+window*1.25,1.4+story*1.55,side*14.28),Vector3(.5,.64,.025),"655175","metal")

func _ruins() -> void:
	for side in [-1,1]:
		for index in 2:
			var x: float = side*10.15
			var z := -6.4+index*11.2
			var label := "Ruin%d_%d"%[side,index]
			box(label+"Foundation",Vector3(x,.27,z),Vector3(4.0,.54,4.6),"554759",true)
			box(label+"RearWall",Vector3(x,2.65,z-2.15),Vector3(4.0,5.3,.32),"615268",true)
			box(label+"OuterWall",Vector3(x+side*1.83,2.3,z),Vector3(.34,4.6,4.3),"4b3f54",true)
			for edge in [-1,1]:
				box(label+"Pillar%d"%edge,Vector3(x+edge*1.65,2.30,z+1.7),Vector3(.38,4.6,.4),"6a586e",true)
				piece("box",Vector3(x+edge*.87,3.2,z-1.97),Vector3(.8,1.6,.035),"201b2b","metal")
				piece("box",Vector3(x+edge*.87,3.2,z-1.94),Vector3(.055,1.6,.045),"978b95","metal")
			# A saliência inclinada fica acima de uma cápsula humana e tem o próprio sólido
			# real girado; não projeta uma parede invisível até o piso.
			box(label+"BrokenLintel",Vector3(x,4.2,z+1.7),Vector3(3.85,.5,.5),"877286",true,"stone",Vector3(0,0,side*.13))
			piece("box",Vector3(x,5.25,z-.40),Vector3(3.7,.21,3.7),"473549","stone",Vector3(.20,0,side*.15))
			for beam in 3: piece("box",Vector3(x-1.2+beam*1.2,4.90,z),Vector3(.12,.20,3.9),"776776","metal",Vector3(.13,0,side*.06))
			for rubble in 6:
				var at := Vector3(x-1.45+(rubble%3)*1.12,.3,z-1.4+floorf(rubble/3.0)*1.8)
				piece("rock",at,Vector3(.65,.5,.55),"746176","stone",Vector3(.2*rubble,.6*rubble,.3))
	# Uma porta alta quebrada leva o olhar em primeira pessoa ao centro distante.
	for side in [-1,1]:
		box("PortalPier%d"%side,Vector3(side*2.65,2.7,-11.3),Vector3(1.25,5.4,1.0),"6c5675",true)
		piece("box",Vector3(side*2.65,2.7,-10.78),Vector3(.09,4.9,.03),"9b4ecc","glow")
		piece("taper",Vector3(side*2.65,5.7,-11.3),Vector3(.85,1.15,.95),"94799e")
	box("PortalBrokenArch",Vector3(0,5.15,-11.3),Vector3(4.1,.75,1.0),"7c6185",true,"stone",Vector3(0,0,-.08))
	for band in 3: piece("box",Vector3(0,4.97+band*.17,-10.76),Vector3(3.85,.035,.04),"ae76d5","glow",Vector3(0,0,-.08))

func _broken_furniture() -> void:
	# Áreas inteiras cobrem o tampo e as tábuas caídas. Tudo fica fora
	# do corredor central de chegada e das cápsulas iniciais dos monstros.
	box("OverturnedDesk",Vector3(-5.2,.45,.4),Vector3(1.7,.90,1.15),"55404a",true,"wood",Vector3(0,.20,0))
	for side in [-1,1]: piece("box",Vector3(-5.2+side*.7,1.02,.4),Vector3(.08,.5,1.05),"7c5b64","wood",Vector3(.14,0,side*.1))
	box("BrokenBench",Vector3(5.65,.43,-.75),Vector3(2.4,.86,.80),"5c4c60",true,"wood",Vector3(0,-.28,0))
	box("FallenCabinet",Vector3(-5.5,.45,-6.8),Vector3(2.0,.9,1.1),"4d3b50",true,"wood",Vector3(0,.25,0))
	for plank in 4: piece("box",Vector3(-5.5,.92,-7.22+plank*.27),Vector3(1.83,.04,.18),"8b687d","wood",Vector3(0,.25,0))
	box("BrokenPlanter",Vector3(5.25,.41,9.85),Vector3(1.15,.82,1.05),"6c596b",true)
	for stem in 6:
		piece("taper",Vector3(5.1+sin(stem)*.28,1.4+stem*.07,9.85+cos(stem)*.2),Vector3(.09,1.6,.08),"2c2134","wood",Vector3(.20*sin(stem),0,.25*cos(stem)))
	box("StreetLampBase",Vector3(-5.3,.24,9.6),Vector3(.62,.48,.62),"4e4258",true,"metal")
	box("StreetLampShaft",Vector3(-5.3,2.0,9.6),Vector3(.13,3.5,.13),"5c4f62",true,"metal",Vector3(.08,0,-.13))
	piece("box",Vector3(-5.05,3.80,9.5),Vector3(.48,.4,.44),"b371d0","glow")

func _roots_and_rifts() -> void:
	for side in [-1,1]:
		for index in 8:
			var x: float = side*(3.0+index*.55)
			var z := -10.0+index*2.7
			for segment in 3:
				piece("box",Vector3(x+sin(index+segment)*.25,.024,z+segment*.29),Vector3(.08,.022,.57),"a35aca","glow",Vector3(0,sin(index*.5+segment)*.8,0))
		for branch in 7:
			var z := -10.0+branch*3.2
			blocking_box("BoundaryRoots%d_%d"%[side,branch],Vector3(side*13.35,.95,z+.2),Vector3(.65,1.9,.6))
			piece("round",Vector3(side*13.53,.32,z),Vector3(.21,.95,.26),"201d2b","wood",Vector3(PI*.5,.4,0))
			piece("taper",Vector3(side*13.4,1.23,z+.2),Vector3(.19,2.3,.17),"34243d","wood",Vector3(.2,0,side*.21))
			piece("taper",Vector3(side*13.1,2.0,z+.15),Vector3(.09,1.4,.09),"5d396c","wood",Vector3(.10,0,side*.65))

func _floating_debris() -> void:
	for index in FLOATING_COUNT:
		var angle := index*TAU/FLOATING_COUNT
		var at := Vector3(cos(angle)*(8.0+index%3),4.0+(index%4)*1.5,sin(angle)*(8.0+index%3)-1.2)
		var shard := box("FloatingMasonry%d"%index,at,Vector3(.65+index%3*.3,.32,.8),"6e5579",false,"stone",Vector3(.13*index,.37*index,.17*index))
		shard.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		floating.append(shard)
		floating_homes.append(at)
	# A fractured dark moon, made from a few distant fixed pieces.
	for index in 7:
		piece("rock",Vector3(-3+index*.8,17.5+sin(index)*1.5,-24),Vector3(3.2,2.7,2.0),"70507d","stone",Vector3(index*.4,0,index*.6))
		piece("box",Vector3(-3+index*.8,17.5+sin(index)*1.5,-22.94),Vector3(.055,2.1,.03),"c270de","glow",Vector3(0,0,index*.6))

func _lighting() -> void:
	for data in [[Vector3(0,3.8,-10.5),Color("a36fe4"),1.9,18.0],[Vector3(-5.05,3.45,9.5),Color("9f67bc"),1.3,15.0]]:
		var light := OmniLight3D.new()
		light.name = "StableRiftLight"
		light.position = data[0]
		light.light_color = data[1]
		light.light_energy = data[2]
		light.omni_range = data[3]
		light.shadow_enabled = false
		add_child(light)
		local_lights.append(light)

func make_environment(source: Environment = null) -> Environment:
	var result: Environment = source.duplicate(true) if source != null else Environment.new()
	result.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color("14091f")
	material.sky_horizon_color = Color("543362")
	material.ground_horizon_color = Color("543362")
	material.ground_bottom_color = Color("130d1d")
	material.sky_curve = .22
	material.ground_curve = .22
	sky.sky_material = material
	result.sky = sky
	result.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	result.ambient_light_color = Color("9b80b1")
	result.ambient_light_energy = .44
	# A exposição local à câmera também impede que um sol diurno do Harbor desbote
	# o pesadelo violeta. A iluminação do mundo compartilhado nunca muda.
	result.tonemap_exposure = .32
	result.fog_enabled = true
	result.fog_light_color = Color("56336d")
	result.fog_light_energy = .75
	result.fog_density = .035
	result.fog_sky_affect = .72
	return result

func _dynamic_batch(label: String, count: int, shape: String, color: String, kind: String) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = primitive(shape)
	multi.instance_count = count
	var node := MultiMeshInstance3D.new()
	# Estas trajetórias cosméticas avançam a cada quadro renderizado, não a cada tick.
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.name = label
	node.multimesh = multi
	node.material_override = surface(color,kind)
	node.custom_aabb = AABB(Vector3(-45,-2,-45),Vector3(90,50,90))
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return multi

func _weather() -> void:
	meteor_batch = _dynamic_batch("MeteorCores",METEOR_COUNT,"rock","dda6ed","glow")
	trail_batch = _dynamic_batch("MeteorTrails",METEOR_COUNT,"taper","8756ab","glow")
	rain_batch = _dynamic_batch("VioletRain",RAIN_COUNT,"box","877097","metal")
	for index in METEOR_COUNT: _meteor_seeds.append(Vector3(_rng.randf_range(-28,28),_rng.randf_range(0,1),_rng.randf_range(-30,12)))
	for index in RAIN_COUNT: _rain_seeds.append(Vector3(_rng.randf_range(-13,13),_rng.randf_range(0,1),_rng.randf_range(-13,13)))

func _ambience() -> void:
	wind = AudioStreamPlayer.new()
	wind.name = "IllusionWind"
	var stream: AudioStreamOggVorbis = preload("res://audio/regional/wind_0.ogg").duplicate()
	stream.loop = true
	wind.stream = stream
	wind.volume_db = -22.0
	wind.pitch_scale = .82
	wind.bus = &"Ambient" if AudioServer.get_bus_index(&"Ambient") >= 0 else &"Master"
	add_child(wind)
	wind.play()

func _residents() -> void:
	var points := [Vector3(-3.2,.1,-4),Vector3(3.2,.1,-5),Vector3(-7.0,.1,4.2),Vector3(7.0,.1,6.2)]
	for index in 4:
		var monster := APPARITION.new()
		monster.appearance_index = index
		monster.variant = [0,2,1,0][index]
		monster.position = points[index]
		monster.visitor_local = visitor_local
		add_child(monster)
		monsters.append(monster)

func update_effect(delta: float) -> void:
	elapsed += maxf(0.0,delta)
	for index in floating.size():
		floating[index].position = floating_homes[index]+Vector3(sin(elapsed*.4+index)*.14,sin(elapsed*.7+index*.8)*.25,cos(elapsed*.3+index)*.12)
		floating[index].rotation.y += delta*(.05 if index%2 == 0 else -.06)
	if meteor_batch == null: return
	var meteor_basis := Basis.from_euler(Vector3(0,0,-.50))
	for index in METEOR_COUNT:
		var seed_point: Vector3 = _meteor_seeds[index]
		var phase := fposmod(elapsed/(4.8+(index%4)*.7)+seed_point.y,1.0)
		var point := Vector3(seed_point.x-9*phase,29-25*phase,seed_point.z)
		var envelope := maxf(.001,smoothstep(0.0,.1,phase)*(1.0-smoothstep(.82,1.0,phase)))
		meteor_batch.set_instance_transform(index,Transform3D(Basis.from_scale(Vector3(.26,.40,.26)*envelope),point))
		trail_batch.set_instance_transform(index,Transform3D(meteor_basis.scaled(Vector3(.18,4.5,.18)*envelope),point+Vector3(.94,2.0,0)))
	for index in RAIN_COUNT:
		var seed_point: Vector3 = _rain_seeds[index]
		var phase := fposmod(elapsed*.85+seed_point.y,1.0)
		var at := Vector3(seed_point.x-1.4*phase,10.5-10.1*phase,seed_point.z)
		rain_batch.set_instance_transform(index,Transform3D(Basis.from_euler(Vector3(0,0,-.10)).scaled(Vector3(.012,.32,.012)),at))

func is_floor_clear(point: Vector3, radius := .35) -> bool:
	if absf(point.x)+radius > 13.6 or absf(point.z)+radius > 13.6: return false
	for bounds in solid_bounds:
		if bounds.position.y >= point.y+1.8 or bounds.end.y < point.y+.05: continue
		if Rect2(bounds.position.x,bounds.position.z,bounds.size.x,bounds.size.z).grow(radius).has_point(Vector2(point.x,point.z)): return false
	return true

func get_stats() -> Dictionary:
	var paths := []
	for monster in monsters:
		paths.append({"id":monster.appearance_index,"variant":monster.variant,"position":monster.position,"distance":monster.traveled,"blocked_frames":monster.blocked_frames})
	return {"elapsed":elapsed,"active":active,"solids":solid_bodies.size(),"static_detail_instances":detail_instances,"static_batches":static_draw_batches,"meteors":METEOR_COUNT,"rain":RAIN_COUNT,"floating":floating.size(),"lights":local_lights.size(),"monsters":paths,"spawn_clear":is_floor_clear(spawn_local)}
