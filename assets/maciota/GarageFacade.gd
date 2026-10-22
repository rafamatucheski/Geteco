extends Node3D
## Independent industrial workshop: a low parts annex and a west service court.
## Ground-level footprints are projected from these same structural meshes.
const EXTERIOR_LIFE := preload("res://assets/maciota/MaciotaExteriorLife.gd")
func _ready() -> void:
 # Preserve the six-metre access and human proportions of the existing workshop.
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
 # Recessed open gate, metal jambs and a flush threshold make the access legible.
 box("",Vector3(-2,1.55,front-.48),Vector3(5.95,3.1,.035),"172226")
 for x in [-4.98,.98]:
  box("",Vector3(x,1.55,front+.015),Vector3(.10,3.1,.10),"d6b361")
 box("",Vector3(-2,.015,front+.08),Vector3(5.9,.03,.28),"b9b4a1")
 for x in [-5.45, 1.45]:
  box("",Vector3(x,3.0,front+.06),Vector3(.32,.5,.12),"e6c881")
 # A matching low annex replaces the tall residential neighbour. It belongs
 # to Maciota and keeps the same independent, fully solid footprint.
 box("NeighborShell",Vector3(6.1,1.9,center_z),Vector3(5.6,3.8,d),"536368")
 box("",Vector3(6.1,3.92,center_z),Vector3(5.9,.24,d+.2),"a7a895")
 box("",Vector3(6.1,4.10,center_z),Vector3(5.35,.12,d-.4),"394649")
 for y in [2.8]:
  box("",Vector3(6.1,y-.8,front+.06),Vector3(5.65,.12,.16),"c3a185")
  for x in [4.45, 6.1, 7.75]:
   box("",Vector3(x,y,front+.04),Vector3(1.05,1.3,.12),"d0b69a")
   box("",Vector3(x,y,front+.12),Vector3(.86,1.1,.06),"344f59")
   box("",Vector3(x,y,front+.17),Vector3(.06,1.1,.04),"acb6ac")
   box("",Vector3(x,y-.62,front+.16),Vector3(1.15,.1,.26),"d0b69a")
 box("",Vector3(6.1,1.0,front+.04),Vector3(1.2,2.0,.12),"3d4647")
 box("",Vector3(6.5,1.0,front+.13),Vector3(.06,.3,.05),"c3a185")
 box("",Vector3(8.6,1.9,front+.13),Vector3(.1,3.6,.1),"414f51")
 box("",Vector3(7.4,4.40,center_z-1),Vector3(.8,.6,.8),"735b50")
 EXTERIOR_LIFE.build(self)
 preload("res://assets/maciota/GarageWallDetails.gd").build(self)
 var painted_skin := preload("res://assets/maciota/GaragePaintedSkin.gd")
 if painted_skin.enabled(): painted_skin.apply(self,center_z)
 # Build after the painted skin: it deliberately hides all earlier facade meshes.
 _build_entry_frame(front)
 var backyard := preload("res://assets/maciota/GarageBackyard.gd").new()
 # The old project car stays east of FreightOffice's full footprint.
 backyard.position.x = 3.5
 add_child(backyard)
 add_child(preload("res://assets/maciota/WorkshopCourt.gd").new())
func _build_entry_frame(front: float) -> void:
 var entry := Node3D.new()
 entry.name = "OpenGarageEntrance"
 add_child(entry)
 var details := preload("res://assets/maciota/WorkshopDetails.gd")
 var amber := details.material("e4b94c",.7,.2)
 var dark := details.material("23373e",.8,.3)
 var metal := details.material("c2c8bf",.5,.55)
 # Deep side reveals frame a six-metre open portal; the raised shutter is above it.
 for x in [-5.1,1.1]:
  details.box(entry,"PortalSide",Vector3(x,1.65,front+.13),Vector3(.24,3.3,.48),amber)
  details.box(entry,"PortalTrack",Vector3(x,1.65,front+.40),Vector3(.09,3.3,.12),metal)
  for y in [.25,.75,1.25,1.75,2.25,2.75]:
   var stripe := details.box(entry,"PortalHazardStripe",Vector3(x,y,front+.385),Vector3(.245,.16,.015),dark)
   stripe.rotation.z = -.45
 details.box(entry,"PortalHeader",Vector3(-2,3.4,front+.14),Vector3(6.44,.28,.5),amber)
 # Recognisable rolled steel door rather than a flat dark patch on the facade.
 for y in [3.58,3.70,3.82]:
  details.box(entry,"RaisedShutterSlat",Vector3(-2,y,front+.12),Vector3(5.92,.10,.24),metal)
 details.box(entry,"OpenPortalRecess",Vector3(-2,1.6,front-.22),Vector3(5.96,3.2,.02),dark)
 details.box(entry,"EntryApron",Vector3(-2,.014,front+.55),Vector3(5.96,.028,1.22),details.material("bebba6",.92))
 details.box(entry,"ThresholdChannel",Vector3(-2,.032,front+.17),Vector3(5.96,.018,.11),metal)
 # Unbroken light floor leads toward the opening, with dark edges outside walking space.
 for x in [-4.93,.93]:
  details.box(entry,"ApronEdge",Vector3(x,.034,front+.58),Vector3(.10,.014,1.15),amber)

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
