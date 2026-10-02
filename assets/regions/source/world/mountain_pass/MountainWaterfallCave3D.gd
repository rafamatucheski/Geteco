extends Node3D

const ROCK := preload("res://assets/regions/source/world/mountain_pass/CaveRockGeometry.gd")
const DETAIL := preload("res://assets/regions/source/world/mountain_pass/CaveDetailGeometry.gd")
var spray: MultiMeshInstance3D
var clock := 0.0

func _ready() -> void:
	_build_cliff()
	_build_water()
	_build_approach()

func _build_cliff() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 428
	for side in [-1.0, 1.0]:
		for column in 4:
			var x: float = side*(2.1+column*1.22)
			var height := 5.9 - column*0.6
			for tier in 2:
				var rock := ROCK.rock(self,Vector3(x+rng.randf_range(-0.22,0.22),height*(tier+0.5)*0.5,-1.15+rng.randf_range(-0.2,0.3)),Vector3(2.0,height*0.63,3.0),column*7+tier,Color("52605a") if tier else Color("3f504b"))
				rock.rotation.z = side*rng.randf_range(0.05,0.24)
				if tier == 0: rock.set_meta("interior_solid_id",StringName("CliffLeft" if side<0 else "CliffRight"))
	# Three overlapping rock arches form a tunnel, instead of a black quad.
	for depth in 3:
		for i in 9:
			var a := PI*float(i)/8.0
			var point := Vector3(cos(a)*1.8,0.3+sin(a)*3.3,-float(depth)*1.15)
			var rock := ROCK.rock(self,point,Vector3(1.1,1.55,1.55),110+depth*11+i,Color("44534d").darkened(depth*0.16))
			rock.name = "TunnelArch_%d_%d" % [depth,i]
			if i in [0,8]: rock.set_meta("interior_solid_id",StringName("CliffLeft" if i==8 else "CliffRight"))
	var floor_mat := DETAIL.material(Color("34443e"))
	DETAIL.floor_patch(self,"TunnelFloor",PackedVector2Array([Vector2(-1.7,2.4),Vector2(1.7,2.4),Vector2(1.4,-4),Vector2(-1.4,-4)]),0.025,floor_mat)
	for i in 4:
		ROCK.rock(self,Vector3(-0.95+i*0.65,1.15,-3.4),Vector3(1.15,2.8,1.2),170+i,Color("243932")).set_meta("interior_solid_id",&"TunnelBack")
	for i in 9:
		var point := Vector3(-4.6+float(i)*1.0,4.4-absf(float(i)-4.0)*0.24,-0.7)
		ROCK.rock(self,point,Vector3(1.6,0.48,2.0),190+i,Color("647564"))
	for side in [-1.0,1.0]:
		for i in 9:
			# Whole-number grouping/index; preserve integer truncation and precision.
			@warning_ignore("integer_division")
			var p := Vector3(side*(2.5+float(i%3)*1.08),0.2+float(i/3)*1.35,0.38)
			var moss := ROCK.rock(self,p,Vector3(0.90,0.14,0.50),210+i,Color("576a46"))
			moss.name = "MossLedge"

func _build_water() -> void:
	for i in 3:
		var water := MeshInstance3D.new()
		water.name = "CascadeRibbon%d" % i
		var ribbon := PlaneMesh.new()
		ribbon.size = Vector2(1.12,4.9)
		ribbon.subdivide_width = 5
		ribbon.subdivide_depth = 18
		water.mesh = ribbon
		water.rotation.x = PI*0.5
		water.position = Vector3(-1.75+i*0.57,2.6,0.9+float(i)*0.07)
		var branch_mat := ShaderMaterial.new()
		branch_mat.shader = preload("res://assets/regions/source/world/mountain_pass/MountainCascade.gdshader")
		branch_mat.set_shader_parameter("phase",float(i)*0.31)
		water.material_override = branch_mat
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)
	var pool := MeshInstance3D.new()
	pool.name = "CascadePool"
	var surface := PlaneMesh.new()
	surface.size = Vector2(7.2,4.25)
	surface.subdivide_width = 12
	surface.subdivide_depth = 12
	pool.mesh = surface
	pool.position = Vector3(-1.5,0.06,2.15)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/regions/source/world/mountain_pass/MountainCascade.gdshader")
	mat.set_shader_parameter("pool",true)
	pool.material_override = mat
	pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pool)
	# All splash droplets share a single draw.
	spray = MultiMeshInstance3D.new()
	spray.name = "CascadeSpray"
	spray.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	spray.multimesh = MultiMesh.new()
	spray.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var droplet := SphereMesh.new()
	droplet.radius = 0.045
	droplet.height = 0.09
	droplet.radial_segments = 6
	droplet.rings = 3
	spray.multimesh.mesh = droplet
	spray.multimesh.instance_count = 28
	spray.material_override = DETAIL.material(Color("b2d5cd"),0.5)
	spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(spray)
	_process(0.0)

func _build_approach() -> void:
	for i in 18:
		var a := float(i)*TAU/18.0
		ROCK.rock(self,Vector3(-1.5+cos(a)*3.45,0.12,sin(a)*2.05+2.15),Vector3(0.85,0.38,0.62),300+i,Color("526157"))
	for i in 5:
		ROCK.rock(self,Vector3(0.42-float(i)*0.10,0.13,3.65-float(i)*0.65),Vector3(0.94,0.22,0.56),360+i,Color("879086"))

func _process(delta: float) -> void:
	if not is_instance_valid(spray): return
	clock += delta
	for i in spray.multimesh.instance_count:
		var t := fposmod(clock*0.85+float(i)*0.137,1.0)
		var a := float(i)*2.399
		var point := Vector3(-1.1+sin(a)*(0.35+t*1.4),0.12+sin(t*PI)*0.65,1.25+cos(a)*t*1.1)
		spray.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*(0.7+t)),point))
