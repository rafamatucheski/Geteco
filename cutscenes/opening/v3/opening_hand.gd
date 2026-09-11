extends Node3D
## Palma arredondada, quatro dedos articulados e polegar oposto no estilo do elenco.
const Model = preload("res://scripts/player/DanteVisualAdapter.gd")
var side := 1.0
var fingers: Array[Node3D] = []
var thumb_segments: Array[MeshInstance3D] = []
var thumb_tip: MeshInstance3D
var contact_local: Vector3

func build(hand_side: float, skin: StandardMaterial3D) -> void:
	side=hand_side
	contact_local=Vector3(side*.021,-.060,-.043)
	var palm:=Model._make_loft([
		Vector4(.014,.020,.011,0), Vector4(-.005,.028,.015,0),
		Vector4(-.025,.032,.014,0), Vector4(-.043,.027,.010,0)],skin,12)
	palm.name="PalmSurface"; add_child(palm)
	for i in 4:
		var root_joint:=Node3D.new(); root_joint.name="Finger%d" % i
		root_joint.position=Vector3((i-1.5)*.016,-.037,.001)
		add_child(root_joint); fingers.append(root_joint)
		var joint:=root_joint
		var length_factor: float=[.84,1.0,.94,.73][i]
		for segment in 3:
			var length: float=[.024,.017,.012][segment]*length_factor
			var radius:=.0073-float(segment)*.0010
			var bone:=CapsuleMesh.new(); bone.radius=radius; bone.height=length+radius*1.3
			bone.radial_segments=8; bone.rings=3
			var mesh:=MeshInstance3D.new(); mesh.mesh=bone; mesh.material_override=skin
			mesh.position.y=-length*.5; joint.add_child(mesh)
			if segment<2:
				var next:=Node3D.new(); next.position.y=-length; joint.add_child(next); joint=next
	for i in 2:
		var bone:=CapsuleMesh.new(); bone.radius=.010-float(i)*.0015; bone.height=.04
		bone.radial_segments=10; bone.rings=3
		var mesh:=MeshInstance3D.new(); mesh.mesh=bone; mesh.material_override=skin
		add_child(mesh); thumb_segments.append(mesh)
	thumb_tip=Model._make_ellipsoid(Vector3(.016,.015,.011),skin,contact_local)
	thumb_tip.name="ThumbContact"; add_child(thumb_tip)
	set_grip(0)

func set_grip(amount: float, phone_grip := false) -> void:
	var grip:=clampf(amount,0,1)
	for i in fingers.size():
		var joint: Node3D=fingers[i]
		joint.rotation=Vector3(lerpf(.13,.20 if phone_grip else .58,grip),0,(float(i)-1.5)*lerpf(.05,.012,grip))
		joint=joint.get_child(1)
		joint.rotation.x=lerpf(.16,.38 if phone_grip else 1.05,grip)
		joint=joint.get_child(1)
		joint.rotation.x=lerpf(.08,.33 if phone_grip else .70,grip)
	var a:=Vector3(side*.026,-.012,0)
	var b:=Vector3(side*lerpf(.047,.034,grip),-.035,lerpf(-.002,-.041,grip))
	if phone_grip:
		# Polegar contorna a lateral; os outros dedos apoiam a traseira.
		b=b.lerp(Vector3(-side*.025,-.030,-.050),grip)
	var c:=Vector3(side*.041,-.061,-.003).lerp(contact_local,grip)
	thumb_tip.position=c
	thumb_tip.scale.z=.011*(1+(.5*grip if phone_grip else 0.0))
	for i in 2:
		var from: Vector3=a if i==0 else b
		var to: Vector3=b if i==0 else c
		var mesh:=thumb_segments[i]
		mesh.position=(from+to)*.5
		mesh.basis=Basis(Quaternion(Vector3.UP,(to-from).normalized()))
		mesh.scale.y=from.distance_to(to)/.04
