extends "res://tools/fleet_fixups/PassengerDesign.gd"
## Rodas de família offline. Reaproveita as superfícies semânticas de roda/pneu e o raio
## de contato/pivôs originais; nenhum nó, material ou luz novo em runtime.
func replace_wheels(target: Node3D, family: String) -> void:
	model=target
	groups.clear()
	materials.clear()
	if family=="work":
		# As rodas utilitárias existentes já compartilham borracha e aço numa só
		# superfície de cor de vértice. Mantém esse orçamento de draw para a família de trabalho.
		var steel_rubber:=material("wheel")
		steel_rubber.metallic=.20
		steel_rubber.roughness=.68
	var wheels := {}
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if not part.has_meta("wheel_center") or part.mesh==null: continue
		var center: Vector3=part.get_meta("wheel_center")
		if not bool(part.get_meta("wheel_spins",true)): continue
		var bounds: AABB=part.transform*part.mesh.get_aabb()
		wheels[center]=bounds if not wheels.has(center) else (wheels[center] as AABB).merge(bounds)
		part.free()
	for center: Vector3 in wheels:
		var bounds: AABB=wheels[center]
		var radius := maxf(bounds.size.y,bounds.size.z)*.5
		var width := clampf(bounds.size.x/1.033,.14,.34)
		wheel(center,radius,width,family)
	finish(wheels)

func wheel(center: Vector3,radius: float,width: float,family: String) -> void:
	active="PassengerWheel_"+str(center)
	var side := signf(center.x)
	var segments := 16 if family in ["popular","work"] else 20
	var section: Array[Vector2]=[Vector2(-.48,.70),Vector2(-.51,.90),Vector2(-.34,1.0),Vector2(.34,1.0),Vector2(.51,.90),Vector2(.515,.70)]
	for j in section.size()-1:
		for i in segments:
			var a:=TAU*i/segments
			var b:=TAU*(i+1)/segments
			var p: Vector2=section[j]
			var q: Vector2=section[j+1]
			color=Color("202528") if j==2 else Color("30373a")
			quad("wheel" if family=="work" else "tire",center+Vector3(side*p.x*width,sin(a)*p.y*radius,cos(a)*p.y*radius),center+Vector3(side*p.x*width,sin(b)*p.y*radius,cos(b)*p.y*radius),center+Vector3(side*q.x*width,sin(b)*q.y*radius,cos(b)*q.y*radius),center+Vector3(side*q.x*width,sin(a)*q.y*radius,cos(a)*q.y*radius),Vector3(side*.3,sin(a),cos(a)))
	var face := center+Vector3(side*width*.515,0,0)
	var n:=Vector3(side,0,0)
	var alloy:=Color("b1b9bb")
	# Fecha o aro interno: o esterçamento expõe a face interna das rodas
	# dianteiras, então o pneu não pode parecer um túnel aberto através do eixo.
	ring("wheel" if family=="work" else "tire",center-Vector3(side*width*.48,0,0),Vector3.UP,Vector3.BACK,radius*.70,0,-n,Color("262d31"),segments)
	ring("wheel",face,Vector3.UP,Vector3.BACK,radius*.71,radius*.63,n,alloy,segments)
	if family in ["popular","work"]:
		var steel:=Color("8d979a") if family=="popular" else Color("6d777b")
		ring("wheel",face-Vector3(side*.006,0,0),Vector3.UP,Vector3.BACK,radius*.64,0,n,steel,segments)
		# Black ventilation pockets in a pressed steel dish; satin centre cap.
		var holes := 8 if family=="popular" else 6
		for i in holes:
			var a:=TAU*i/holes
			ring("wheel",face+Vector3(side*.001,sin(a)*radius*.47,cos(a)*radius*.47),Vector3.UP,Vector3.BACK,radius*.072,0,n,DARK,5)
		ring("wheel",face+Vector3(side*.009,0,0),Vector3.UP,Vector3.BACK,radius*(.27 if family=="popular" else .22),0,n,alloy,12)
	else:
		ring("wheel",face-Vector3(side*.008,0,0),Vector3.UP,Vector3.BACK,radius*.64,0,n,DARK,segments)
		ring("wheel",face-Vector3(side*.004,0,0),Vector3.UP,Vector3.BACK,radius*.54,.19*radius,n,Color("657076"),segments)
		var spokes := 10 if family=="executive" else (5 if family=="traditional" else 6)
		for i in spokes:
			var a:=TAU*i/spokes
			var radial:=Vector3(0,sin(a),cos(a))
			var tangent:=Vector3(0,cos(a),-sin(a))
			var at:=face+Vector3(side*.007,0,0)
			var thickness:=.045 if family=="executive" else .085
			color=alloy
			quad("wheel",at+radial*radius*.15-tangent*radius*thickness,at+radial*radius*.15+tangent*radius*thickness,at+radial*radius*.67+tangent*radius*thickness*.55,at+radial*radius*.67-tangent*radius*thickness*.55,n)
		ring("wheel",face+Vector3(side*.012,0,0),Vector3.UP,Vector3.BACK,radius*.16,0,n,alloy,12)
	color=Color.WHITE
