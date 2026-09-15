extends Node3D
## Westgate shell. Footprints are projected from these same structural meshes.
func _ready() -> void:
 var w := 19.5
 var d := 15.625
 box("MainShell",Vector3(0,2.2,-.5),Vector3(w,4.4,d-1.0),"727c7d")
 box("LeftPier",Vector3(-7.375,2.2,d*.5-.5),Vector3(4.75,4.4,1.0),"536368")
 box("RightPier",Vector3(5.375,2.2,d*.5-.5),Vector3(8.75,4.4,1.0),"536368")
 box("",Vector3(-2,3.8,d*.5-.5),Vector3(6,1.2,1.0),"536368")
 box("",Vector3(0,4.45,0),Vector3(w+.3,.18,d+.3),"34464e")
 for x in [-8.0,4.0,7.0]:
  box("",Vector3(x,2.8,d*.5+.025),Vector3(1.5,.9,.05),"9bbbc2")
 box("",Vector3(-2,2.8,d*.5-.85),Vector3(5.9,.08,.08),"dfb550")
func box(id: String, at: Vector3, size: Vector3, color: String) -> void:
 var part := MeshInstance3D.new()
 var mesh := BoxMesh.new()
 mesh.size = size
 part.mesh = mesh
 part.position = at
 var material := StandardMaterial3D.new()
 material.albedo_color = Color(color)
 material.roughness = .8
 part.material_override = material
 if not id.is_empty(): part.set_meta("interior_solid_id",StringName(id))
 add_child(part)
