extends Node3D
## Cobre: side vault, angled customer circulation and a rear teller gallery.
const G := preload("res://world/desert/DesertGeometry.gd")
var variant := 0
func _ready() -> void:
	G.room_box(self,"Terrazzo",Vector3(0,-.035,0),Vector3(20,.05,14),Color("b9aa8a"),false)
	G.room_box(self,"RearWall",Vector3(0,1.8,-6.9),Vector3(20,3.6,.22),Color("c6af8a"))
	G.room_box(self,"LeftWall",Vector3(-9.9,1.8,0),Vector3(.22,3.6,14),Color("c6af8a"))
	G.room_box(self,"RightWall",Vector3(9.9,1.8,0),Vector3(.22,3.6,14),Color("c6af8a"))
	for side in [-1.0,1.0]: G.room_box(self,"FrontWall%s"%side,Vector3(side*5.65,1.8,6.9),Vector3(8.5,3.6,.22),Color("c6af8a"))
	# Three stations, connected counter physically covers the entire furniture footprint.
	G.room_box(self,"TellerCounter",Vector3(1.9,.57,-2.6),Vector3(10.4,1.14,.85),Color("796149"))
	G.room_box(self,"CounterTop",Vector3(1.9,1.16,-2.6),Vector3(10.7,.12,1),Color("d0b892"))
	for i in 3:
		var x := -1.5+float(i)*3.4
		G.room_box(self,"Terminal%d"%i,Vector3(x,1.48,-2.64),Vector3(.52,.52,.35),Color("3d4945"))
		G.room_box(self,"ClerkChair%d"%i,Vector3(x,.48,-4.25),Vector3(.7,.96,.7),Color("596451"))
		G.room_box(self,"BrassDivider%d"%i,Vector3(x+1.5,1.75,-2.6),Vector3(.06,1.2,.12),Color("b2975d"))
	# Vault occupies left rear, lobby retains a 3m corridor along its east side.
	G.room_box(self,"VaultNorth",Vector3(-7,1.8,-5.9),Vector3(5,3.6,.45),Color("888575"))
	G.room_box(self,"VaultEast",Vector3(-4.65,1.8,-4.45),Vector3(.4,3.6,3.4),Color("888575"))
	G.room_box(self,"VaultFrontLeft",Vector3(-8.6,1.8,-2.95),Vector3(1.6,3.6,.4),Color("888575"))
	G.room_box(self,"VaultFrontRight",Vector3(-5.45,1.8,-2.95),Vector3(1.25,3.6,.4),Color("888575"))
	G.room_box(self,"VaultDoor",Vector3(-7.1,1.2,-2.72),Vector3(1.8,2.4,.32),Color("697168"))
	var wheel := G.cylinder(self,"VaultWheel",Vector3(-7.1,1.22,-2.49),.36,.09,Color("b0ada0"))
	wheel.rotation.x=PI*.5
	for z in [0.5,2.1]:
		G.room_box(self,"WaitingBench%s"%z,Vector3(-7.2,.46,z),Vector3(3.5,.92,.82),Color("756f50"))
	G.room_box(self,"DepositDesk",Vector3(6.7,.62,1.2),Vector3(2.8,1.24,1.3),Color("967952"))
	G.room_box(self,"DepositPaper",Vector3(6.7,1.26,1.2),Vector3(.55,.02,.4),Color("ded4b7"),false)
	G.room_box(self,"Rug",Vector3(0,.003,4.7),Vector3(3,.012,2),Color("77513f"),false)
	for x in [-6.5,0.0,6.5]:
		G.room_box(self,"CeilingBeam",Vector3(x,3.5,0),Vector3(.18,.22,13),Color("826647"),false)
		var lamp := OmniLight3D.new()
		lamp.position=Vector3(x,2.8,0)
		lamp.light_color=Color("ffdab0")
		lamp.light_energy=.7
		lamp.omni_range=7
		lamp.shadow_enabled=false
		add_child(lamp)
	preload("res://world/desert/DesertInteriorFinish.gd").apply(self,true)
