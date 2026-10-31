extends RefCounted
## Pequenas evidências autoradas de trabalho/contrabando. O ornamento de superfície em lote fica
## dentro da área e da altura de topo dos sólidos existentes de móveis/paredes.
const BATCH := preload("res://world/mining/MiningBatch.gd")

static func build(parent: Node3D) -> void:
	var batch := BATCH.new(parent, "CoalGalleryWorkDetails")
	for row in [
		[Vector3(19,.66,3.5),Vector3(2.6,1.32,1.2)],
		[Vector3(24,.64,1),Vector3(3,1.28,1.3)],
		[Vector3(27,.72,7.7),Vector3(2.8,1.44,1.4)],
		[Vector3(.65,.4,-9.4),Vector3(1.2,.8,1.1)]]:
		var at: Vector3 = row[0]
		var size: Vector3 = row[1]
		# Split planks, corner bindings, nailheads and diagonal transport braces.
		for side in [-1.0,1.0]:
			for index in 5:
				var y := -size.y*.5 + (float(index)+.5)*size.y/5.0
				batch.box("CratePlankJoint",at+Vector3(0,y,side*(size.z*.5+.005)),Vector3(size.x-.12,.018,.013),"rubber")
			for x in [-size.x*.5+.09,size.x*.5-.09]:
				batch.box("CrateCornerBinding",at+Vector3(x,0,side*(size.z*.5+.012)),Vector3(.11,size.y,.022),"rust")
				for y in [-size.y*.36,size.y*.36]:
					batch.box("CrateSquareNail",at+Vector3(x,y,side*(size.z*.5+.026)),Vector3(.045,.045,.014),"steel")
		for x in [-size.x*.3,size.x*.3]:
			batch.box("CrateLidGap",at+Vector3(x,size.y*.5+.007,0),Vector3(.018,.014,size.z-.08),"rubber")
	# As fraturas de rocha na parede do fundo são veios de carvão rasos e descontínuos;
	# a orientação varia em vez de produzir um colar de pedras redondas.
	for index in 13:
		var x := -12.2 + float(index)*1.1
		var y := 1.15 + float(index%3)*.28
		batch.box("CoalFaceFracture",Vector3(x,y,-10.994),Vector3(.68,.055,.018),"coal",false,Vector3(0,0,float(index%5-2)*.16))
	# Talas de trilho e pares de grampos explicam como a antiga linha de acesso foi
	# montada. Ficam abaixo da altura do pé e não precisam de obstáculos separados.
	for z in [-8.5,-5.0,-1.5]:
		for x in [-8.14,-6.86]:
			batch.box("RailFishplate",Vector3(x,.09,z),Vector3(.11,.10,.52),"rust")
			for dz in [-.16,.16]:
				batch.box("RailAnchor",Vector3(x,.15,z+dz),Vector3(.15,.04,.08),"steel")
	# The working packing bench: a half-wrapped parcel, folding knife, ledger
	# and tape backing. Blank pages carry no decorative explanatory text.
	batch.box("HalfWrappedParcel",Vector3(25.18,1.06,-4.70),Vector3(1.0,.24,.82),"cream")
	for x in [24.94,25.42]: batch.box("ParcelLooseTape",Vector3(x,1.184,-4.70),Vector3(.09,.009,.83),"rubber")
	batch.box("ParcelPaperFold",Vector3(25.18,1.08,-4.27),Vector3(.82,.10,.045),"white",false,Vector3(.25,0,0))
	batch.box("PackingKnifeGrip",Vector3(24.65,.964,-4.22),Vector3(.18,.035,.065),"rust",false,Vector3(0,.32,0))
	batch.box("PackingKnifeBlade",Vector3(24.80,.964,-4.27),Vector3(.16,.022,.065),"steel",false,Vector3(0,.32,0))
	batch.box("LedgerCover",Vector3(23.60,.963,-4.68),Vector3(.44,.035,.52),"blue",false,Vector3(0,-.17,0))
	batch.box("LedgerPages",Vector3(23.60,.986,-4.68),Vector3(.38,.013,.46),"white",false,Vector3(0,-.17,0))
	# Um rádio portátil e uma caixa de munição aberta pertencem à mesa do dinheiro,
	# abaixo do topo de 1.44 m já reservado, sem ocupar um ladrilho de caminhada.
	batch.box("SmugglerRadio",Vector3(29.55,1.19,-4.55),Vector3(.50,.36,.35),"blue")
	batch.box("RadioGrille",Vector3(29.55,1.19,-4.36),Vector3(.37,.22,.025),"rubber")
	batch.box("RadioAerial",Vector3(29.75,1.34,-4.58),Vector3(.025,.20,.025),"steel")
	batch.box("AmmoTray",Vector3(27.38,1.07,-4.55),Vector3(.63,.14,.64),"steel")
	for index in 5: batch.box("WrappedAmmoRow",Vector3(27.15+float(index)*.11,1.15,-4.55),Vector3(.075,.075,.5),"yellow")
	# Reparos largos de madeira na diagonal são legíveis da câmera do cômodo inteiro.
	# A espessura completa deles fica dentro do volume existente da parede norte.
	for x in [-11.3,-6.0,-.8]:
		batch.beam("GalleryWallDiagonal",Vector3(x-1.5,.35,-11.08),Vector3(x+1.5,2.7,-11.08),.20,"timber")
		batch.beam("GalleryWallCrossBrace",Vector3(x+1.5,.35,-11.13),Vector3(x-1.5,2.7,-11.13),.14,"rust")
	for x in [18.8,24.3,29.2]:
		batch.beam("RaidWallDiagonal",Vector3(x-1.5,.4,-6.13),Vector3(x+1.5,2.8,-6.13),.19,"timber")
	# Cintas largas de metal identificam as caixas de equipamento como carga sem placas.
	for at in [Vector3(19,1.327,3.5),Vector3(24,1.287,1),Vector3(27,1.447,7.7)]:
		for offset in [-.75,.75]: batch.box("CargoLidStrap",at+Vector3(offset,0,0),Vector3(.12,.014,1.15),"steel")
	# Placas de desgaste e reparo no vagão secreto abandonado são filhos só visuais
	# do volume já reservado; a tampa animada continua livre.
	for x in [-8.47,-6.53]:
		for z in [-8.7,-7.9,-7.1]:
			batch.box("WagonPatchPlate",Vector3(x,1.02,z),Vector3(.08,.38,.43),"steel")
			for y in [.9,1.14]: batch.box("WagonPatchBolt",Vector3(x, y,z+.13),Vector3(.09,.055,.055),"rust")
	# Junção elétrica e cabos presos ficam rentes à parede do túnel.
	batch.box("TunnelFuseBox",Vector3(11.005,1.8,-2.0),Vector3(.03,.65,.50),"steel")
	batch.box("FuseBoxLatch",Vector3(10.981,1.8,-1.87),Vector3(.015,.13,.04),"rust")
	for z in [-4,-1,2,5,8,10]:
		batch.box("CableRetainer",Vector3(10.946,2.45,z),Vector3(.055,.14,.06),"rust")
	batch.finish()
