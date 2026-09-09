extends "res://prototypes/living_cast/CivilianDriverModel.gd"
const DETAIL=preload("res://world/shared/pedestrians/CitizenDetails.gd")
func _ready() -> void:
	super._ready()
	var suit=Color("293443")
	for item in find_children("*","MeshInstance3D",true,false):
		if item.material_override.albedo_color.is_equal_approx(coat_color): item.material_override.albedo_color=suit
		if item.get_parent()!=self and item.position.y<-.6: item.material_override.albedo_color=Color("202125")
		if item.get_parent()!=self and item.position.y==-.32: item.material_override.albedo_color=suit
	DETAIL.piece(self,Vector3(.15,.28,.025),Vector3(0,1.31,.167),Color("e6e6de"))
	DETAIL.piece(self,Vector3(.045,.21,.025),Vector3(0,1.29,.188),Color("773e40"))
	DETAIL.piece(self,Vector3(.055,.045,.025),Vector3(0,1.42,.188),Color("773e40"))
	for side in [-1,1]:
		var lapel=DETAIL.piece(self,Vector3(.065,.26,.04),Vector3(side*.10,1.30,.177),suit.lightened(.08))
		lapel.rotation.z=side*.27
func part(parent: Node3D, point: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	if parent==self and point.y>1.5 and point.y<1.85:
		return super.part(parent,point,size,color)
	var item=DETAIL.piece(parent,size,point,color)
	if size.y>.30:
		var surface=SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		var profile=[Vector2(-.36,-.5),Vector2(.36,-.5),Vector2(.5,-.32),Vector2(.5,.32),Vector2(.36,.5),Vector2(-.36,.5),Vector2(-.5,.32),Vector2(-.5,-.32)]
		var rings=[]
		for level in 3:
			var ring=[]
			var width=[.84,1.0,.92][level]
			for point2 in profile: ring.append(Vector3(point2.x*size.x*width,(level*.5-.5)*size.y,point2.y*size.z))
			rings.append(ring)
		for level in 2:
			for i in 8:
				var j=(i+1)%8
				for vertex in [rings[level][i],rings[level+1][i],rings[level+1][j],rings[level][i],rings[level+1][j],rings[level][j]]: surface.add_vertex(vertex)
		for i in range(1,7):
			for vertex in [rings[0][0],rings[0][i+1],rings[0][i],rings[2][0],rings[2][i],rings[2][i+1]]: surface.add_vertex(vertex)
		surface.generate_normals()
		item.mesh=surface.commit()
	return item

func set_behind_counter(behind: bool) -> void:
	for index in [0,2]:
		if limbs.size()>index: limbs[index].visible=not behind
	for item in get_children():
		if item is MeshInstance3D and item.position.y<1.0: item.visible=not behind
