extends "res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd"
## Ground-supported mountain pad. Markings are single meshes, not overlapping slabs.
func _ready() -> void:
	var concrete := _mat("concrete",Color("59656b"),.95)
	var asphalt := _mat("asphalt",Color("303e46"),.96)
	var white := _mat("white",Color("dce0d8"),.92)
	var amber := _mat("amber",Color("cea94e"),.9)
	var steel := _mat("steel",Color("34434a"),.6,.4)
	var deck := _cylinder("Platform",Vector3(0,-.075,0),3.4,.16,concrete)
	deck.mesh.radial_segments = 32
	deck.set_meta("interior_solid_id",&"HelipadDeck")
	var surface := _cylinder("Tarmac",Vector3(0,.012,0),3.22,.014,asphalt)
	surface.mesh.radial_segments = 32
	for side in [-1,1]:
		_box("HStem",Vector3(side*.63,.026,0),Vector3(.28,.012,2.0),white)
	_box("HBar",Vector3(0,.027,0),Vector3(1.1,.012,.28),white)
	_ring("TouchdownRing",2.43,.065,.029,amber)
	_ring("PerimeterPaint",3.10,.055,.029,white)
	# Inset visual lights: no extra light sources or raised obstacle across the landing area.
	var beacon := _mat("beacon",Color("61b790"),.35,0,.55)
	for i in 8:
		var angle := TAU*i/8.0
		var point := Vector3(sin(angle)*3.30,.018,cos(angle)*3.30)
		_cylinder("InsetLight",point,.065,.024,beacon)
	# Equipment stands beyond the landing disc; a clear southern opening meets the path.
	_cylinder("WindsockMast",Vector3(4.0,1.3,-1.0),.045,2.6,steel).set_meta("interior_solid_id",&"Windsock")
	_cylinder("MastFoot",Vector3(4.0,.08,-1.0),.15,.16,concrete).set_meta("interior_solid_id",&"Windsock")
	for i in 5:
		var cloth := CylinderMesh.new()
		cloth.top_radius = .17-i*.025
		cloth.bottom_radius = .19-i*.025
		cloth.height = .22
		cloth.radial_segments = 10
		var segment := MeshInstance3D.new()
		segment.name = "WindsockBand"
		segment.mesh = cloth
		segment.material_override = amber if i%2==0 else white
		segment.position = Vector3(4.10+i*.20,2.54-i*.035,-1.0)
		segment.rotation.z = -PI*.55
		add_child(segment)

func _ring(id: String,radius: float,width: float,height: float,material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 64:
		var a := TAU*float(i)/64.0
		var b := TAU*float(i+1)/64.0
		var inner_a := Vector3(sin(a)*(radius-width),height,cos(a)*(radius-width))
		var outer_a := Vector3(sin(a)*radius,height,cos(a)*radius)
		var inner_b := Vector3(sin(b)*(radius-width),height,cos(b)*(radius-width))
		var outer_b := Vector3(sin(b)*radius,height,cos(b)*radius)
		surface.set_normal(Vector3.UP)
		for point in [inner_a,outer_b,outer_a,inner_a,inner_b,outer_b]: surface.add_vertex(point)
	var ring := MeshInstance3D.new()
	ring.name = id
	ring.mesh = surface.commit()
	ring.material_override = material
	add_child(ring)
