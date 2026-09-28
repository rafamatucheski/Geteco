extends Node3D
## Shared sculpted meshes and four lightweight two-segment limbs. Contact
## targets are read from the actual moving handlebars and footpegs.
var jersey_color := Color("d5dce1")
var accent_color := Color("dc702b")
var arms: Array = []
var legs: Array = []
var hands: Array[Node3D] = []
var boots: Array[Node3D] = []
var boot_cuffs: Array[Node3D] = []
static var _meshes := {}
static var _materials := {}

func _ready() -> void:
	var jersey := _mat(jersey_color)
	var accent := _mat(accent_color)
	var dark := _mat(Color("26303b"))
	var ivory := _mat(Color("dce2df"))
	# Waist, rib cage and shoulders have distinct sections and a rounded neck.
	_add(_loft("torso",[Vector4(-.04,.15,.115,0),Vector4(.08,.155,.10,0),Vector4(.25,.20,.12,-.008),Vector4(.40,.235,.12,-.025),Vector4(.48,.16,.10,-.025)]),jersey)
	_add(_loft("hips",[Vector4(-.10,.135,.115,.01),Vector4(-.04,.175,.14,0),Vector4(.07,.15,.11,0)]),dark)
	_add(_oval(),accent,Vector3(0,.30,-.135),Vector3(.29,.29,.035))
	_add(_oval(),dark,Vector3(0,.31,.11),Vector3(.30,.29,.045))
	_add(_oval(),ivory,Vector3(0,.44,-.13),Vector3(.30,.06,.025))
	_add(_oval(),dark,Vector3(0,.52,-.02),Vector3(.15,.12,.15))
	# Full-face shell, dark goggle opening, projecting peak and chin guard.
	_add(_loft("helmet",[Vector4(.55,.13,.14,-.04),Vector4(.62,.205,.19,-.045),Vector4(.77,.225,.215,-.05),Vector4(.89,.18,.175,-.03),Vector4(.96,.085,.09,-.015),Vector4(.98,.008,.008,-.015)],16),ivory)
	_add(_oval(),dark,Vector3(0,.757,-.247),Vector3(.365,.16,.045))
	_add(_oval(),_mat(Color("425d69")),Vector3(0,.769,-.268),Vector3(.295,.095,.014))
	_add(_oval(),accent,Vector3(0,.872,-.215),Vector3(.44,.045,.39))
	_add(_oval(),ivory,Vector3(0,.609,-.218),Vector3(.30,.145,.215))
	_add(_oval(),dark,Vector3(0,.613,-.319),Vector3(.18,.065,.015))
	for side in [-1.0,1.0]:
		_add(_oval(),accent,Vector3(side*.207,.74,-.04),Vector3(.018,.10,.20))
		var arm := [_add(_limb_mesh(),jersey),_add(_limb_mesh(),jersey),_add(_oval(),dark)]
		arms.append(arm)
		var hand := Node3D.new()
		hand.name = "LeftGlove" if side<0 else "RightGlove"
		add_child(hand)
		_add(_oval(),ivory,Vector3.ZERO,Vector3(.12,.10,.145),hand)
		_add(_oval(),dark,Vector3(0,.047,.005),Vector3(.095,.022,.10),hand)
		_add(_oval(),ivory,Vector3(-side*.055,-.025,-.015),Vector3(.045,.075,.055),hand)
		hands.append(hand)
		legs.append([_add(_leg_mesh(),dark),_add(_leg_mesh(),dark),_add(_oval(),accent)])
		var boot := Node3D.new()
		boot.name = "LeftBoot" if side<0 else "RightBoot"
		add_child(boot)
		_add(_loft("boot_foot",[Vector4(-.11,.079,.16,-.05),Vector4(-.055,.085,.17,-.05),Vector4(.045,.065,.078,0)]),ivory,Vector3.ZERO,Vector3.ONE,boot)
		_add(_oval(),dark,Vector3(0,-.10,-.05),Vector3(.17,.035,.34),boot)
		boots.append(boot)
		# The foot stays on the peg; the protective shaft follows the shin.
		var cuff := Node3D.new()
		cuff.name = "LeftBootCuff" if side<0 else "RightBootCuff"
		add_child(cuff)
		_add(_loft("boot_cuff",[Vector4(-.015,.063,.073,0),Vector4(.08,.068,.076,0),Vector4(.22,.077,.080,0)]),ivory,Vector3.ZERO,Vector3.ONE,cuff)
		for y in [.045,.115,.185]: _add(_oval(),accent,Vector3(0,y,-.076),Vector3(.125,.026,.022),cuff)
		boot_cuffs.append(cuff)
	# Merge static clothing/helmet/glove detail by material; only limb pieces
	# and their end targets need independent transforms while riding.
	var articulated: Array = []
	for limb in arms+legs: articulated.append_array(limb)
	_merge_static(self,articulated)
	for target in hands+boots+boot_cuffs: _merge_static(target,[])

func pose(bike: Node3D, contact: float, stride: float = 0.0) -> void:
	# Race cleanup can restore the seat after its children leave the scene tree.
	if arms.size()!=2 or not is_inside_tree() or not bike.visual.is_inside_tree() or not bike._front.is_inside_tree(): return
	var inverse := global_transform.affine_inverse()
	var grips: Transform3D = inverse*bike._front.global_transform
	var pedals: Transform3D = inverse*bike.visual.global_transform
	for index in 2:
		var side := -1.0 if index==0 else 1.0
		var shoulder := Vector3(side*.225,.425,-.018)
		var loose_hand := Vector3(side*.28,-.11,-side*stride*.45)
		var grip: Vector3 = grips*Vector3(side*.39,.85,.32)
		var hand := loose_hand.lerp(grip,contact)
		var elbow := _joint(shoulder,hand,.32,.31,Vector3(side,0,.35))
		_segment(arms[index][0],shoulder,elbow,.105,.12)
		_segment(arms[index][1],elbow,hand,.077,.095)
		arms[index][2].position = elbow
		arms[index][2].scale = Vector3(.13,.135,.13)
		hands[index].position = hand
		hands[index].basis = grips.basis if contact>.99 else Basis.IDENTITY
		var hip := Vector3(side*.135,-.04,0)
		var pedal: Vector3 = pedals*Vector3(side*.27,.51,.08)
		var ankle := Vector3(side*.15,-.67,side*stride*.45).lerp(pedal,contact)
		var knee_pole := Vector3(side*.22,0,-1).lerp(pedals.basis*Vector3(side*.22,0,-1),contact)
		var knee := _joint(hip,ankle,.40,.38,knee_pole)
		_segment(legs[index][0],hip,knee,.18,.20)
		_segment(legs[index][1],knee,ankle,.125,.145)
		legs[index][2].position = knee+Vector3(0,0,-.035)
		legs[index][2].scale = Vector3(.16,.19,.10)
		boots[index].position = ankle
		boots[index].basis = pedals.basis if contact>.99 else Basis.IDENTITY
		boot_cuffs[index].position = ankle
		boot_cuffs[index].basis = Basis(Quaternion(Vector3.UP,(knee-ankle).normalized()))

static func _joint(a: Vector3,b: Vector3,upper: float,lower: float,pole: Vector3) -> Vector3:
	var distance := maxf(.001,a.distance_to(b))
	var axis := (b-a)/distance
	var along := clampf((upper*upper-lower*lower+distance*distance)/(2*distance),0,upper)
	var bend := pole.slide(axis).normalized()
	return a+axis*along+bend*sqrt(maxf(.001,upper*upper-along*along))

static func _segment(mesh: MeshInstance3D,a: Vector3,b: Vector3,width: float,depth: float) -> void:
	var length := maxf(.001,a.distance_to(b))
	mesh.transform = Transform3D(Basis(Quaternion(Vector3.UP,(b-a)/length))*Basis.from_scale(Vector3(width,length,depth)),(a+b)*.5)

func _add(mesh: Mesh,material: Material,at := Vector3.ZERO,size := Vector3.ONE,parent: Node3D = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = at
	node.scale = size
	(parent if parent!=null else self).add_child(node)
	return node

static func _mat(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .78
		_materials[color] = material
	return _materials[color]

static func _oval() -> SphereMesh:
	if not _meshes.has("oval"):
		var mesh := SphereMesh.new()
		mesh.radius = .5
		mesh.height = 1
		mesh.radial_segments = 12
		mesh.rings = 6
		_meshes.oval = mesh
	return _meshes.oval

static func _limb_mesh() -> ArrayMesh:
	return _loft("limb",[Vector4(-.5,.28,.30,0),Vector4(-.41,.44,.43,0),Vector4(-.10,.50,.5,0),Vector4(.32,.44,.43,0),Vector4(.5,.31,.32,0)],10)

static func _leg_mesh() -> ArrayMesh:
	return _loft("leg",[Vector4(-.5,.42,.43,0),Vector4(-.35,.48,.47,0),Vector4(.1,.50,.5,0),Vector4(.5,.42,.43,0)],10)

static func _loft(key: String,rings: Array,sides := 12) -> ArrayMesh:
	if _meshes.has(key): return _meshes[key]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in range(rings.size()-1):
		for segment in sides:
			var points: Array[Vector3] = []
			for corner in [Vector2i(row,segment),Vector2i(row,segment+1),Vector2i(row+1,segment),Vector2i(row+1,segment+1)]:
				var r: Vector4 = rings[corner.x]
				var angle := TAU*float(corner.y)/sides
				points.append(Vector3(cos(angle)*r.y,r.x,sin(angle)*r.z+r.w))
			for index in [0,1,2,1,3,2]: surface.add_vertex(points[index])
	for end in [0,rings.size()-1]:
		var ring: Vector4 = rings[end]
		for side in sides:
			var a := TAU*float(side)/sides
			var b := TAU*float(side+1)/sides
			var vertices := [Vector3(0,ring.x,ring.w),Vector3(cos(a)*ring.y,ring.x,sin(a)*ring.z+ring.w),Vector3(cos(b)*ring.y,ring.x,sin(b)*ring.z+ring.w)]
			if end==0: vertices.reverse()
			for vertex in vertices: surface.add_vertex(vertex)
	surface.generate_normals()
	# Every source needs indices before batching with indexed PrimitiveMeshes.
	surface.index()
	_meshes[key] = surface.commit()
	return _meshes[key]

static func _merge_static(parent: Node3D,exclude: Array) -> void:
	var batches := {}
	for child in parent.get_children():
		if not child is MeshInstance3D or child in exclude: continue
		var material: Material = child.material_override
		if not batches.has(material):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[material] = surface
		var mesh: ArrayMesh
		if child.mesh is PrimitiveMesh:
			mesh = ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,child.mesh.get_mesh_arrays())
		else: mesh = child.mesh
		batches[material].append_from(mesh,0,child.transform)
		child.free()
	for material in batches:
		var node := MeshInstance3D.new()
		node.mesh = batches[material].commit()
		node.material_override = material
		parent.add_child(node)
