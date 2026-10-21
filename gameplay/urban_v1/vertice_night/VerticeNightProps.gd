extends RefCounted
## Peças da M06-C montadas uma vez, sob a cortina, junto com a Vértice, e estacionadas:
## arquivo de aço e livro, cofre, bueiro, van de reforço, giroflex do alarme e fita da polícia.
## Tudo usa o cache de materiais da Vértice (cor lisa ou as lâmpadas que as empilhadeiras já
## usam): nenhum shader novo para compilar no meio do jogo e nenhuma luz nova.
const BOOK_POINT := Vector3(40.75,0,4.5)
const SAFE_POINT := Vector3(40.75,0,11.2)
const SEWER_POINT := Vector3(-22,0,84)
const GATE_POINT := Vector3(0,0,81.5)
const VAN_FROM := Vector3(0,0,98)
const VAN_TO := Vector3(0,0,64)

static func build(company: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "VerticeNightShift"
	company.add_child(root)
	var parts := {"root":root, "beacons":[]}
	# Arquivo de aço do escritório, gaveta por ano, encostado na parede leste.
	company.box("ArchiveCabinet",Vector3(41.42,.7,4.5),Vector3(.8,1.4,2.0),"6f7a7c",true,root)
	for row in 4:
		for side in [-1,1]:
			var at := Vector3(41.0,.22+row*.33,4.5+side*.48)
			company.box("ArchiveDrawer",at,Vector3(.03,.29,.9),"5d686a",false,root)
			company.box("ArchiveHandle",at+Vector3(-.03,.06,0),Vector3(.03,.03,.22),"c8cdcd",false,root)
	parts.book = company.box("DispatchBook",Vector3(41.25,1.44,4.25),Vector3(.3,.06,.24),"6b2f2a",false,root)
	# Cofre baixo do escritório; a porta gira quando é aberto.
	company.box("OfficeSafe",Vector3(41.42,.5,11.2),Vector3(.8,1.0,.8),"3b4245",true,root)
	var hinge := Node3D.new()
	hinge.name = "SafeDoorHinge"
	hinge.position = Vector3(41.0,.5,11.5)
	root.add_child(hinge)
	company.box("SafeDoor",Vector3(0,0,-.3),Vector3(.04,.82,.6),"2c3233",false,hinge)
	company.box("SafeDial",Vector3(-.03,.12,-.3),Vector3(.03,.12,.12),"c8cdcd",false,hinge)
	parts.safe_door = hinge
	# Bueiro da calçada: liga ao porão (VerticeUndercroft), que sobe pelo alçapão do galpão.
	var sewer := Node3D.new()
	sewer.name = "StreetSewerGrate"
	sewer.position = SEWER_POINT
	root.add_child(sewer)
	company.box("SewerFrame",Vector3(0,.03,0),Vector3(1.2,.04,1.2),"343d3d",false,sewer)
	for i in 5: company.box("SewerBar",Vector3(-.4+i*.2,.055,0),Vector3(.06,.03,1.0),"252f30",false,sewer)
	parts.sewer = sewer
	# Giroflex vermelho nos postes do portão e nos cantos do galpão, apagado até o alarme.
	for at in [Vector3(-7.4,3.35,78),Vector3(7.4,3.35,78),Vector3(-27.6,6.2,18),Vector3(28.1,6.2,18),Vector3(14,3.15,73)]:
		var beacon: Node3D = company.box("AlarmBeacon",at,Vector3(.32,.3,.32),"lamp_red",false,root)
		beacon.visible = false
		parts.beacons.append(beacon)
	# Fita da polícia nos dias em que a Vértice fica fechada.
	var tape := Node3D.new()
	tape.name = "PoliceTape"
	root.add_child(tape)
	for y in [.95,1.35]: company.box("TapeBand",Vector3(0,y,78.55),Vector3(14.6,.07,.02),"e8c22a",false,tape)
	company.box("TapeNotice",Vector3(3.2,1.15,78.6),Vector3(.6,.42,.02),"f1ead2",false,tape)
	tape.visible = false
	parts.tape = tape
	parts.van = _van(company,root)
	return parts

## Van dos Cobras: só visual enquanto anda; a colisão liga quando estaciona no pátio.
static func _van(company: Node3D, root: Node3D) -> Dictionary:
	var van := Node3D.new()
	van.name = "ReinforcementVan"
	van.position = VAN_FROM
	root.add_child(van)
	company.box("VanBody",Vector3(0,1.25,.2),Vector3(2.0,1.9,4.4),"202d26",false,van)
	company.box("VanHood",Vector3(0,.85,-2.35),Vector3(1.96,.9,.9),"202d26",false,van)
	company.box("VanWindshield",Vector3(0,1.75,-2.05),Vector3(1.8,.7,.05),"glass",false,van)
	company.box("VanBumper",Vector3(0,.42,-2.82),Vector3(2.0,.22,.12),"2c3233",false,van)
	for x in [-.7,.7]: company.box("VanHeadlight",Vector3(x,.85,-2.81),Vector3(.32,.16,.03),"lamp_white",false,van)
	for x in [-.95,.95]:
		for z in [-1.7,1.5]: company.box("VanWheel",Vector3(x,.36,z),Vector3(.26,.72,.72),"1b1f20",false,van)
	var body := StaticBody3D.new()
	body.name = "VanSolid"
	body.collision_layer = 0
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var volume := BoxShape3D.new()
	volume.size = Vector3(2.0,2.2,5.4)
	shape.shape = volume
	shape.position = Vector3(0,1.1,-.2)
	body.add_child(shape)
	van.add_child(body)
	van.visible = false
	return {"node":van, "body":body}
