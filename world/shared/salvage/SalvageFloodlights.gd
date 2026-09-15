extends Node2D
## Two tall twin-head industrial masts, with light in both presentation worlds.
const POLES := [Vector3(-14.6,0,9.4),Vector3(14.4,0,-9.4)]
const TARGETS := [Vector3(-4,0,3),Vector3(5,0,-1)]
const LIGHT_COLOR := Color("e9f2ff")
var art: Node2D
var is_lit := false
var _spots: Array[SpotLight3D]=[]
var _pools: Array[PointLight2D]=[]
var _glows: Array[Sprite2D]=[]
var _lenses: Array[StandardMaterial3D]=[]

func _ready() -> void:
	for i in POLES.size(): _build_mast(i)
	set_lit(false)
	_bind_weather.call_deferred()

func _build_mast(index: int) -> void:
	var pole:=Node3D.new()
	pole.name="FloodlightMast%d" % (index+1)
	pole.position=POLES[index]
	art.stage.add_child(pole)
	art.box(pole,Vector3(0,.16,0),Vector3(.8,.32,.8),"9b9d91")
	art.box(pole,Vector3(0,.35,0),Vector3(.48,.10,.48),"3c4950")
	for x in [-.18,.18]:
		for z in [-.18,.18]: art.cylinder(pole,Vector3(x,.43,z),.045,.08,"b9c4c8")
	art.cylinder(pole,Vector3(0,4.4,0),.12,8.0,"73848b")
	art.box(pole,Vector3(0,1.1,.15),Vector3(.29,.50,.16),"45565d")
	art.box(pole,Vector3(0,8.35,0),Vector3(2.7,.16,.20),"64757d")
	for side in [-1,1]:
		var head:=Node3D.new()
		head.position=Vector3(side*1.05,8.3,0)
		pole.add_child(head)
		head.look_at(TARGETS[index]+Vector3(side*2,0,0))
		art.box(head,Vector3.ZERO,Vector3(1.05,.65,.30),"35464e")
		# Raised cooling fins, deep metal rim and a broad LED reflector.
		for rib in 5:
			art.box(head,Vector3(-.4+rib*.2,0,.19),Vector3(.06,.57,.12),"7e8c90")
		var lens: MeshInstance3D=art.box(head,Vector3(0,0,-.17),Vector3(.9,.51,.05),"d2dbe0")
		var material:=StandardMaterial3D.new()
		material.albedo_color=Color("d2dbe0")
		material.emission=LIGHT_COLOR
		material.emission_energy_multiplier=2.0
		lens.material_override=material
		_lenses.append(material)
		var glow:=Sprite2D.new()
		glow.texture=_gradient(64)
		glow.position=art.projected(head.global_position)
		glow.scale=Vector2.ONE*.75
		glow.modulate=Color(.82,.91,1,.8)
		glow.z_as_relative=false
		glow.z_index=25
		var additive:=CanvasItemMaterial.new()
		additive.light_mode=CanvasItemMaterial.LIGHT_MODE_UNSHADED
		additive.blend_mode=CanvasItemMaterial.BLEND_MODE_ADD
		glow.material=additive
		add_child(glow)
		_glows.append(glow)
	# The same projected steel/concrete geometry blocks vehicles and pedestrians.
	art._solid_group(pole.name,[pole])
	art._overhead_layer(pole)
	var spot:=SpotLight3D.new()
	spot.name="YardFlood%d" % (index+1)
	spot.position=POLES[index]+Vector3(0,8.15,0)
	spot.layers=3
	spot.light_color=LIGHT_COLOR
	spot.light_energy=1.4
	spot.spot_range=32
	spot.spot_angle=65
	spot.spot_attenuation=.6
	spot.shadow_enabled=true
	art.stage.add_child(spot)
	spot.look_at(TARGETS[index])
	_spots.append(spot)
	# Canvas light also illuminates the real player/car outside the 3D viewport.
	var pool:=PointLight2D.new()
	pool.name="GroundFlood%d" % (index+1)
	pool.position=art.projected(TARGETS[index])
	pool.texture=_gradient(512)
	pool.texture_scale=1.55
	pool.color=LIGHT_COLOR
	pool.energy=1.25
	pool.height=80
	add_child(pool)
	_pools.append(pool)

func _gradient(size: int) -> GradientTexture2D:
	var gradient:=Gradient.new()
	gradient.offsets=PackedFloat32Array([0,.18,.55,1])
	gradient.colors=PackedColorArray([Color(1,1,1,.95),Color(1,1,1,.78),Color(1,1,1,.28),Color(1,1,1,0)])
	var texture:=GradientTexture2D.new()
	texture.width=size
	texture.height=size
	texture.gradient=gradient
	texture.fill=GradientTexture2D.FILL_RADIAL
	texture.fill_from=Vector2(.5,.5)
	texture.fill_to=Vector2(1,.5)
	return texture

func _bind_weather() -> void:
	var weather:=get_tree().get_first_node_in_group("day_night_manager")
	if weather==null: return
	weather.time_changed.connect(set_lit)
	set_lit(weather.is_dark)

func set_lit(lit: bool) -> void:
	is_lit=lit
	for spot in _spots: spot.visible=lit
	for pool in _pools: pool.visible=lit
	for glow in _glows: glow.visible=lit
	for lens in _lenses: lens.emission_enabled=lit
	if not art.animating:
		art.viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
		art.overhead_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE
