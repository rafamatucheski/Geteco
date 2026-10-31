extends RefCounted
## Os visitantes pertencem ao encontro aberto, nunca à progressão da campanha/ranking.
const MESH_ARRAYS := preload("res://world/chunk_bake/MeshArrayCache.gd")
const IDS := ["open_bruno", "open_celia", "open_ivo", "open_mara", "open_denis", "open_luna"]
const CARS := {
	"open_bruno":{"name":"Bruno","car":"desert_faisca","distance":800.0,"reaction":.25,"mistake":.06,"number":41},
	"open_celia":{"name":"Célia","car":"desert_siroco","distance":800.0,"reaction":.21,"mistake":.04,"number":58},
	"open_ivo":{"name":"Ivo","car":"desert_coyote","distance":800.0,"reaction":.19,"mistake":.05,"number":63},
	"open_mara":{"name":"Mara","car":"desert_mirage","distance":800.0,"reaction":.23,"mistake":.04,"number":76},
	"open_denis":{"name":"Denis","car":"ranch_pickup","distance":800.0,"reaction":.24,"mistake":.05,"number":83},
	"open_luna":{"name":"Luna","car":"monaliza","distance":800.0,"reaction":.22,"mistake":.05,"number":92},
}

static func attach_number(car: Node3D, number: int) -> void:
	if car.has_node("DragEntryNumber"): return
	var holder := Node3D.new()
	holder.name = "DragEntryNumber"
	car.add_child(holder)
	# Segue a inclinação do vidro traseiro, por fora do vidro, sem texto de billboard.
	var cabin: Dictionary = preload("res://gameplay/VehicleInterior.gd").spec(car)
	var bottom := Vector3(0,float(cabin.belt),float(cabin.rear))
	var top := Vector3(0,float(cabin.roof),float(cabin.rear_top))
	var along := (top-bottom).normalized()
	var outward := Vector3.RIGHT.cross(along).normalized()
	var label := Label3D.new()
	label.name = "RearWindowNumber"
	label.text = "%02d"%number
	label.font_size = 64
	label.pixel_size = .005
	label.outline_size = 4
	label.modulate = Color("fff4dc")
	label.position = bottom.lerp(top,.48)+outward*.025+Vector3.RIGHT*float(cabin.hw)*.36
	label.basis = Basis(Vector3.RIGHT,along,outward)
	# As dimensões da cabine descrevem o interior, não o vidro externo curvo.
	# Monta no triângulo real do vidro traseiro nesta altura.
	var hit_z := -INF
	var ray_origin := Vector3(label.position.x,label.position.y,10)
	var interior = preload("res://gameplay/VehicleInterior.gd")
	for part: MeshInstance3D in car.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null: continue
		var local := car.global_transform.affine_inverse()*part.global_transform
		for surface in part.mesh.get_surface_count():
			if not interior._is_glass(part,surface,part.get_active_material(surface)): continue
			var arrays := MESH_ARRAYS.arrays_of(part.mesh, surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0,count-2,3):
				var a: Vector3 = local*vertices[indices[i] if not indices.is_empty() else i]
				var b: Vector3 = local*vertices[indices[i+1] if not indices.is_empty() else i+1]
				var c: Vector3 = local*vertices[indices[i+2] if not indices.is_empty() else i+2]
				var normal := (b-a).cross(c-a).normalized()
				if normal.z<0: normal = -normal
				if normal.z<.25: continue
				var hit = Geometry3D.ray_intersects_triangle(ray_origin,Vector3.FORWARD,a,b,c)
				if hit == null or hit.z<=hit_z: continue
				hit_z = hit.z
				var right := Vector3.UP.cross(normal).normalized()
				label.position = hit+normal*.012
				label.basis = Basis(right,normal.cross(right),normal)
	holder.add_child(label)
	car.set_meta("drag_entry_number",number)
