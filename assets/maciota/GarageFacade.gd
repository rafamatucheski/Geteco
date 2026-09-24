extends Node3D
## Westgate shell. Footprints are projected from these same structural meshes.
const EXTERIOR_LIFE := preload("res://assets/maciota/MaciotaExteriorLife.gd")
func _ready() -> void:
 # 60% shorter in both plan dimensions. Keep the existing six-metre bay
 # and its street anchor: cars, entrance transitions and saves retain clearance.
 var w := 7.8
 var d := 6.25
 var front := 7.8125
 var center_z := front - d * .5
 box("MainShell",Vector3(-2,2.2,center_z-.5),Vector3(w,4.4,d-1.0),"727c7d")
 box("LeftPier",Vector3(-5.45,2.2,front-.5),Vector3(.9,4.4,1.0),"536368")
 box("RightPier",Vector3(1.45,2.2,front-.5),Vector3(.9,4.4,1.0),"536368")
 box("",Vector3(-2,3.8,front-.5),Vector3(6,1.2,1.0),"536368")
 box("",Vector3(-2,4.45,center_z),Vector3(w+.3,.18,d+.3),"34464e")
 box("",Vector3(-2,2.8,front-.85),Vector3(5.9,.08,.08),"dfb550")
 for x in [-5.45, 1.45]:
  box("",Vector3(x,3.0,front+.06),Vector3(.32,.5,.12),"e6c881")
 # Neighbor shares the existing static viewport; all ground-level volume
 # participates in the same mesh-derived collision projection.
 box("NeighborShell",Vector3(6.1,3.0,center_z),Vector3(5.6,6.0,d),"976b54")
 box("",Vector3(6.1,6.12,center_z),Vector3(5.9,.24,d+.2),"d0b69a")
 box("",Vector3(6.1,6.35,center_z),Vector3(5.35,.24,d-.4),"394649")
 for y in [2.8, 4.8]:
  box("",Vector3(6.1,y-.8,front+.06),Vector3(5.65,.12,.16),"c3a185")
  for x in [4.45, 6.1, 7.75]:
   box("",Vector3(x,y,front+.04),Vector3(1.05,1.3,.12),"d0b69a")
   box("",Vector3(x,y,front+.12),Vector3(.86,1.1,.06),"344f59")
   box("",Vector3(x,y,front+.17),Vector3(.06,1.1,.04),"acb6ac")
   box("",Vector3(x,y-.62,front+.16),Vector3(1.15,.1,.26),"d0b69a")
 box("",Vector3(6.1,1.0,front+.04),Vector3(1.2,2.0,.12),"3d4647")
 box("",Vector3(6.5,1.0,front+.13),Vector3(.06,.3,.05),"c3a185")
 box("",Vector3(8.6,3.0,front+.13),Vector3(.1,5.8,.1),"414f51")
 box("",Vector3(7.4,6.65,center_z-1),Vector3(.8,.8,.8),"735b50")
 EXTERIOR_LIFE.build(self)
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
