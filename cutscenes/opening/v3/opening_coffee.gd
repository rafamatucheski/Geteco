extends RefCounted
## Bico físico e queda balística: a origem do líquido é a boca do bico.
var stage: Node3D
var tip: Marker3D
var segments: Array[MeshInstance3D]=[]
var stream_points: PackedVector3Array=[]

func _init(s: Node3D) -> void:
	stage=s
	var metal: StandardMaterial3D=s.mat("757477",.28,.8)
	s.cylinder(s.pot,Vector3.ZERO,.063,.145,metal,.048)
	s.cylinder(s.pot,Vector3(0,.075,0),.050,.009,metal)
	s.sphere(s.pot,Vector3(0,.086,0),Vector3(.020,.014,.020),s._dark)
	# Alça em C aberta: os dedos não precisam entrar no corpo do bule.
	for pair in [[Vector3(.05,.045,0),Vector3(.098,.045,0)],[Vector3(.098,.045,0),Vector3(.098,-.043,0)],[Vector3(.098,-.043,0),Vector3(.058,-.043,0)]]:
		var limb: MeshInstance3D=s.cylinder(s.pot,Vector3.ZERO,.010,1,s._dark)
		span(limb,pair[0],pair[1])
	var points: Array[Vector3]=[Vector3(-.045,.012,0),Vector3(-.072,.037,0),Vector3(-.091,.049,0),Vector3(-.110,.050,0)]
	for i in 3:
		var piece: MeshInstance3D=s.cylinder(s.pot,Vector3.ZERO,.012-i*.002,1,metal,.010-i*.002)
		span(piece,points[i],points[i+1])
	tip=Marker3D.new(); tip.name="SpoutOutlet"; tip.position=points[-1]; s.pot.add_child(tip)
	var opening: MeshInstance3D=s.cylinder(s.pot,Vector3.ZERO,.0057,.001,s.mat("17100c"))
	opening.position=points[-1]; opening.basis=Basis(Quaternion(Vector3.UP,(points[-1]-points[-2]).normalized()))
	s.pour=Node3D.new(); s.room.add_child(s.pour)
	for i in 24:
		segments.append(s.cylinder(s.pour,Vector3.ZERO,.0019,1,s.mat("49311d",.22)))

func span(mesh: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	mesh.position=(a+b)*.5
	mesh.basis=Basis(Quaternion(Vector3.UP,(b-a).normalized()))
	mesh.scale.y=maxf(.00001,a.distance_to(b))

func apply(t: float) -> void:
	var lift:=smoothstep(.5,1.3,t)*(1-smoothstep(3.5,4.2,t))
	stage.pot.position=Vector3(.27,.731,-.30).lerp(Vector3(.31,.98,-.35),lift)
	stage.pot.rotation.z=.65*lift
	stage.pour.visible=t>=1.3 and t<3.5
	var from: Vector3=tip.global_position
	var to: Vector3=stage.mug.position+Vector3(0,.118,0)
	var height:=maxf(.001,from.y-to.y)
	var flight: float=(sqrt(.04*.04+2*9.81*height)-.04)/9.81
	stream_points.clear()
	for i in 25:
		var u:=float(i)/24
		var time:=u*flight
		var point:=from.lerp(to,u)
		point.y=from.y-.04*time-.5*9.81*time*time
		stream_points.append(point)
	for i in 24:
		var segment:=segments[i]
		span(segment,stream_points[i],stream_points[i+1])
		var u:=float(i)/24
		var radius:=lerpf(1.05,.65,u)*(1+.045*sin(t*31-i*.8))
		segment.scale.x=radius; segment.scale.z=radius
		segment.visible=u<smoothstep(1.3,1.48,t) and u>=smoothstep(3.30,3.5,t)
