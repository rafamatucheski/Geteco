extends "res://world/harbor/PortBossGarageArt.gd"

func _ready() -> void:
 # Closed east-facing garage volume; entry happens through its recessed gate.
 box("MainShell",Vector3(-1,1.6,0),Vector3(15,3.2,6),"777c72")
 box("",Vector3(-1,3.25,0),Vector3(15.3,.16,6.3),"45565c")
 box("",Vector3(7.4,-.04,0),Vector3(1.8,.08,5.7),"3c4445")
 for side in [-1.0,1.0]:
  box("Side%s" % side,Vector3(7.4,1.6,side*2.9),Vector3(1.8,3.2,.3),"777c72")
  box("DoorPost%s" % side,Vector3(8.3,1.25,side*2.45),Vector3(.45,2.5,.5),"94958a")
  box("",Vector3(9,.02,side*2.1),Vector3(2.7,.025,.13),"cfb850")
 box("",Vector3(8.3,2.8,0),Vector3(.6,.6,5.4),"777e75")
 gate=box("Shutter",Vector3(8.3,1.15,0),Vector3(.16,2.3,4.4),"3a484a")
 for i in 11:
  var rib:=box("",Vector3(8.40,.10+i*.20,0),Vector3(.035,.025,4.4),"85918d")
  rib.reparent(gate,true)
 box("",Vector3(9.3,-.02,0),Vector3(3.3,.04,4.5),"68706c")
