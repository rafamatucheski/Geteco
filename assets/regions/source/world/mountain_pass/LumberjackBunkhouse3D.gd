extends Node3D
## Workers' bunkhouse, deliberately distinct from the hunting chalet.
func mat(color: String, metal := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(color)
	material.roughness = 0.85
	material.metallic = metal
	return material
func box(parent: Node3D, pos: Vector3,size: Vector3, material: Material, label := "") -> MeshInstance3D:
	var part := MeshInstance3D.new()
	if not label.is_empty(): part.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = pos
	part.material_override = material
	parent.add_child(part)
	return part
func cylinder(parent: Node3D,pos: Vector3,radius: float,height: float,material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	part.mesh = mesh
	part.position = pos
	part.material_override = material
	parent.add_child(part)
	return part
func _ready() -> void:
	var timber := mat("61442f")
	var pale := mat("987955")
	var dark := mat("2d241d")
	var steel := mat("363d3e",0.65)
	var silver := mat("9badae",0.70)
	var cream := mat("d3c7ae")
	var floor := mat("665441")
	var warm_glow := mat("ffd2a0")
	warm_glow.emission_enabled = true
	warm_glow.emission = Color("ffad61")
	warm_glow.emission_energy_multiplier = 1.5
	box(self,Vector3(0,0.04,0),Vector3(10,0.08,9.4),floor,"BunkhouseFloor")
	for i in 21:
		box(self,Vector3(-5+i*0.5,0.09,0),Vector3(0.018,0.015,9.35),dark)
	for i in 13:
		var y := 0.2+i*0.22
		box(self,Vector3(0,y,-4.7),Vector3(10,0.20,0.20),timber)
		for side in [-1.0,1.0]: box(self,Vector3(side*4.95,y,0),Vector3(0.20,0.20,9.4),timber)
	for side in [-1.0,1.0]: box(self,Vector3(side*2.9,0.4,4.65),Vector3(4.1,0.8,0.18),timber)
	# Heavy ceiling beams and two practical lamps give the long room a readable
	# depth rhythm without adding more shadow maps.
	for z in [-3.2, 0.0, 3.2]:
		box(self, Vector3(0, 3.0, z), Vector3(10.0, 0.18, 0.22), dark)
	for x in [-2.2, 2.2]:
		cylinder(self, Vector3(x, 2.72, 0.0), 0.035, 0.55, steel)
		cylinder(self, Vector3(x, 2.40, 0.0), 0.16, 0.20, warm_glow)
	# Rear windows break up the uninterrupted log wall and add a cold exterior
	# counterpoint to the stove lighting.
	var glass := mat("8ba7b4")
	glass.metallic = 0.15
	glass.roughness = 0.18
	for x in [-3.1, 3.1]:
		box(self, Vector3(x, 1.65, -4.56), Vector3(1.35, 1.20, 0.08), pale)
		box(self, Vector3(x, 1.65, -4.50), Vector3(1.14, 0.98, 0.035), glass)
		box(self, Vector3(x, 1.65, -4.47), Vector3(0.055, 1.0, 0.03), dark)
		box(self, Vector3(x, 1.65, -4.47), Vector3(1.16, 0.055, 0.03), dark)
	# Four iron bunks, eight individual mattresses, personal blankets and ladders.
	for side in [-1.0,1.0]:
		for row in 2:
			var bunk := Node3D.new()
			bunk.name = "WorkerBunk_%s_%d" % [str(side),row]
			bunk.position = Vector3(side*3.75,0,-2.5+row*2.8)
			add_child(bunk)
			var blanket := mat("4b655b" if row==0 else "6e4950")
			for x in [-0.55,0.55]:
				for z in [-1.12,1.12]: box(bunk,Vector3(x,1.15,z),Vector3(0.065,2.3,0.065),steel)
			for level in [0.5,1.75]:
				box(bunk,Vector3(0,level-0.12,0),Vector3(1.13,0.12,2.18),steel)
				box(bunk,Vector3(0,level,0),Vector3(1.05,0.16,2.1),cream)
				box(bunk,Vector3(0,level+0.10,0.30),Vector3(1.03,0.05,1.40),blanket)
				box(bunk,Vector3(0,level+0.14,-0.78),Vector3(0.80,0.17,0.40),cream)
				for z in [-1.12,1.12]: box(bunk,Vector3(0,level+0.25,z),Vector3(1.15,0.05,0.05),steel)
			for rung in 6: box(bunk,Vector3(-side*0.64,0.23+rung*0.29,0.72),Vector3(0.06,0.04,0.62),silver)
	# Repair bench: a crosscut saw, two axes, gloves, tool board and oil cans.
	box(self,Vector3(0,0.84,-3.55),Vector3(3.6,0.16,1.05),pale,"LoggingWorkbench")
	for x in [-1.5,1.5]: box(self,Vector3(x,0.42,-3.55),Vector3(0.14,0.84,0.80),timber)
	box(self,Vector3(0,1.9,-4.54),Vector3(3.7,1.05,0.08),dark)
	var saw := box(self,Vector3(-0.45,0.95,-3.48),Vector3(1.70,0.035,0.20),silver,"CrosscutSaw")
	for i in 16: box(saw,Vector3(-0.78+i*0.10,-0.012,0.12),Vector3(0.055,0.025,0.055),silver).rotation.y = PI/4
	for x in [-1.35,0.45]: box(self,Vector3(x,0.98,-3.48),Vector3(0.11,0.12,0.45),timber)
	for x in [-1.1,0.9]:
		box(self,Vector3(x,1.8,-4.4),Vector3(0.055,0.95,0.055),pale)
		box(self,Vector3(x+0.12,2.16,-4.37),Vector3(0.32,0.18,0.075),silver)
	for x in [0.9,1.3]: cylinder(self,Vector3(x,1.08,-3.7),0.11,0.28,mat("a17c32"))
	# Central communal table, benches, enamel mugs, a thermos and a trail chart.
	box(self,Vector3(0,0.80,0.35),Vector3(2.35,0.13,1.20),pale,"CommunalTable")
	for x in [-0.9,0.9]:
		for z in [-0.1,0.8]: box(self,Vector3(x,0.40,z),Vector3(0.09,0.8,0.09),timber)
	for z in [-0.6,1.3]:
		box(self,Vector3(0,0.45,z),Vector3(2.2,0.12,0.32),timber)
		for x in [-0.9,0.9]: box(self,Vector3(x,0.22,z),Vector3(0.12,0.45,0.25),dark)
	box(self,Vector3(0.2,0.885,0.3),Vector3(0.80,0.015,0.60),cream)
	for i in 4: box(self,Vector3(0.2,0.90,0.1+i*0.10),Vector3(0.64,0.01,0.012),mat("6b8674"))
	for x in [-0.72,0.75]: cylinder(self,Vector3(x,0.96,0.65),0.07,0.15,mat("b1c4b8"))
	cylinder(self,Vector3(-0.7,1.1,0.12),0.09,0.40,steel)
	# Cast-iron stove with open fire window, copper kettle, small smoke wisps.
	var stove := Vector3(-3.75,0,3.0)
	box(self,stove+Vector3(0,0.1,0),Vector3(1.2,0.08,1.3),mat("74706a"),"StoveHearth")
	for x in [-0.4,0.4]: box(self,stove+Vector3(x,0.52,0),Vector3(0.09,0.75,0.75),steel)
	box(self,stove+Vector3(0,0.9,0),Vector3(0.9,0.09,0.85),steel)
	box(self,stove+Vector3(0,0.5,-0.36),Vector3(0.9,0.8,0.07),steel)
	cylinder(self,stove+Vector3(0.2,1.95,-0.20),0.09,2.1,steel)
	cylinder(self,stove+Vector3(-0.18,1.07,0.08),0.18,0.26,mat("aa754d",0.5))
	var fire := preload("res://assets/regions/source/world/mountain_pass/MountainHearthEffects3D.gd").new()
	fire.position = stove+Vector3(0,0.3,0.15)
	fire.smoke_height = 0.25
	fire.warmth = 0.5
	add_child(fire)
	var steam := preload("res://assets/regions/source/world/mountain_pass/MountainHearthEffects3D.gd").new()
	steam.position = stove+Vector3(-0.18,1.25,0.08)
	steam.show_flames = false
	steam.smoke_height = 0.35
	steam.warmth = 0.08
	add_child(steam)
	for row in 3:
		for column in 4:
			var log := cylinder(self,Vector3(3.25+column*0.22,0.25+row*0.20,3.2),0.11,1.15,timber)
			log.rotation.x = PI/2
	# Work coats and heavy boots drying near the entrance.
	box(self,Vector3(2.5,1.9,4.45),Vector3(2.8,0.12,0.12),pale)
	for i in 3:
		var coat := mat(["bc813e","4c6b70","8f433e"][i])
		box(self,Vector3(1.6+i*0.8,1.45,4.3),Vector3(0.5,0.75,0.15),coat)
		for side in [-1.0,1.0]:
			box(self,Vector3(1.6+i*0.8+side*0.34,1.50,4.28),Vector3(0.18,0.58,0.14),coat).rotation.z = side*0.15
			box(self,Vector3(1.6+i*0.8+side*0.13,0.17,4.2),Vector3(0.20,0.30,0.35),dark)
