extends RefCounted
## Acabamento localizado dos dois encontros mostrados no acesso à Vértice.
## Mantém malha, cota e colisão; compartilha as texturas já usadas no trecho.
const HINTS := [Vector2(-290,26)]
var ends: Array[Dictionary] = []
var materials: Dictionary = {}

func configure(roads: Array[Dictionary]) -> void:
	ends.clear()
	materials.clear()
	for road in roads:
		if road.id!="vertice_rural_access": continue
		var points: PackedVector2Array=road.points
		var outward:=points[-3].direction_to(points[-2])
		ends.append({"point":points[-2]+outward*float(road.width)*.5,"axis":outward,"width":float(road.width)*.55+.7})
	for hint in HINTS:
		var best := 25.0
		var chosen: Dictionary = {}
		for road in roads:
			var points: PackedVector2Array = road.points
			for index in [0,points.size()-1]:
				var distance := points[index].distance_squared_to(hint)
				if distance>best: continue
				var neighbor := 1 if index==0 else points.size()-2
				chosen={"point":points[index],"axis":points[neighbor].direction_to(points[index]),"width":float(road.width)*.5+.125}
				best=distance
		if not chosen.is_empty(): ends.append(chosen)

func affects(bounds: Rect2) -> bool:
	for end in ends:
		if bounds.intersects(Rect2(end.point-Vector2(8,8),Vector2(16,16)),true): return true
	return false

func material(base: Material) -> Material:
	if ends.is_empty(): return base
	var key:=base.get_instance_id()
	if materials.has(key): return materials[key]
	var result:=ShaderMaterial.new()
	result.shader=preload("res://world/urban_detail/rural_road_end.gdshader")
	if base is StandardMaterial3D:
		result.set_shader_parameter("base_texture",base.albedo_texture)
		result.set_shader_parameter("textured",base.albedo_texture!=null)
		result.set_shader_parameter("roughness_texture",base.roughness_texture)
		result.set_shader_parameter("mapped_roughness",base.roughness_texture!=null)
	else:
		result.set_shader_parameter("coastal_asphalt",true)
		result.set_shader_parameter("textured",true)
		result.set_shader_parameter("mapped_roughness",true)
	result.set_shader_parameter("earth_texture",preload("res://world/urban_detail/RuralGroundMaterial.gd").material().get_shader_parameter("earth_texture"))
	for i in 2:
		var end: Dictionary=ends[mini(i,ends.size()-1)]
		result.set_shader_parameter("mouth_%d"%i,Vector4(end.point.x,end.point.y,end.axis.x,end.axis.y))
		result.set_shader_parameter("width_%d"%i,end.width)
	materials[key]=result
	sync_material(base)
	return result

func sync_material(base: Material) -> void:
	# The blend is a cached shader copy, so changing the shared asphalt alone
	# left dry, bright rectangles at rural mouths after rain or save restore.
	var key := base.get_instance_id()
	if not materials.has(key): return
	var result: ShaderMaterial = materials[key]
	if base is StandardMaterial3D:
		result.set_shader_parameter("base_color",base.albedo_color)
		result.set_shader_parameter("roughness",base.roughness)
		result.set_shader_parameter("specular",base.metallic_specular)
	elif base is ShaderMaterial:
		for parameter in ["base_texture","roughness_texture","wetness","urban_wear","reflection_texture","reflection_projection","reflection_enabled","reflection_strength","reflection_texel_size","reflection_flip_y"]:
			result.set_shader_parameter(parameter,base.get_shader_parameter(parameter))
