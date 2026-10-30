extends "res://tools/fleet_fixups/build_sport_coupe_gt.gd"
## Offline authored utility collection. Geometry is baked; no per-frame work or extra lights.
const IDS := preload("res://tools/fleet_fixups/utility_inventory.gd").IDS
const FOLDER := "res://evidence/fleet-redesign-20261011/utility"
var car_id := ""
var data := {}
var door := {}
var family := ""
var front := -2.3
var rear := 2.3
var skin := .97
var belt_y := 1.0
var roof_y := 1.6
var sill_y := .35
var windshield_z := -.9
var roof_front := -.6
var roof_back := .8
var cabin_back := 1.1
var axles: Array[Vector3] = []
var paint_color := Color.WHITE
var accent := Color("b8b2a0")

func material(key: String) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m := super.material(key)
	m.vertex_color_is_srgb = true
	if key == "paint":
		m.albedo_color = paint_color
		m.metallic = .26
		m.roughness = .43
	elif key == "glass":
		m.albedo_color = Color("294857")
		m.metallic = .36
		m.roughness = .19
	return m

func setup(id: String, row: Dictionary) -> void:
	car_id = id
	data = row
	door = row.door
	if id in ["beach_buggy","dune_buggy"]: family="buggy"
	elif id in ["courier_van","polar_van","dock_delivery_van","nimbus_minivan"]: family="van"
	elif "pickup" in id or id in ["ranch_single","bravio_crew"]: family="pickup"
	else: family="suv"
	axles.clear()
	for c in row.wheels: axles.append(Vector3(c[0],c[1],c[2]))
	front=float(row.spec.bounds_center[2])-float(row.spec.bounds_size[2])*.5+.085
	rear=float(row.spec.bounds_center[2])+float(row.spec.bounds_size[2])*.5-.085
	skin=float(door.get("x",.78))
	belt_y=float(door.get("belt",.67))
	roof_y=float(door.get("top",1.25))-.015
	sill_y=float(door.get("sill",.30))-.10
	windshield_z=float(door.get("zf",-.48))-.09
	roof_front=windshield_z+(.13 if "jeep" in id else .31)
	if family=="pickup":
		cabin_back=.29 if id in ["ranch_pickup","ranch_single","lumber_pickup_4x4"] else .90
		roof_back=cabin_back-.14
	elif family=="suv":
		cabin_back=rear-.36
		roof_back=cabin_back-.20
	else:
		cabin_back=rear-.16
		roof_back=cabin_back-.10
	paint_color=Color.html(row.spec.colors[0])
	accent=Color("b5a57d") if id in ["desert_jeep_4x4","sertao_trail_pickup","lumber_pickup_4x4","dune_buggy"] else Color("b7c2c7")
	groups={}; materials={}
	model=Node3D.new()
	model.name=id.to_pascal_case()+"Redesign"
	model.set_meta("fleet_finish",true)
	model.set_meta("fleet_redesign_version",1)
	model.set_meta("fleet_redesign_family",family)
	# These bodies already have an authored open bed. The legacy usage adapter
	# removes a cap from a one-surface export and must not slice this batched body.
	if preload("res://runtime/VehicleUsage.gd").BEDS.has(id): model.set_meta("usage_open_bed",true)
	active="Body"

func arch_bottom(z: float) -> float:
	var y := sill_y
	for c in axles:
		if c.x > 0: continue
		var radius := c.y+.055
		var dz := absf(z-c.z)
		if dz < radius: y=maxf(y,c.y+sqrt(radius*radius-dz*dz))
	return y

func side_x(z: float) -> float:
	var flare := 0.0
	for c in axles:
		if c.x > 0: continue
		flare=maxf(flare,.065*exp(-pow((z-c.z)/.49,4)))
	if not door.is_empty() and z>float(door.zf) and z<float(door.zr): flare=0.0
	var taper := .10*maxf(clampf((front+.25-z)/.25,0,1),clampf((z-rear+.24)/.24,0,1))
	return skin+flare-taper

func chassis_stations() -> Array[float]:
	var stations: Array[float] = [front,front+.22,windshield_z,rear-.20,rear]
	if not door.is_empty(): stations.append_array([float(door.zf),float(door.zr)])
	for c in axles:
		if c.x>0: continue
		for j in 17: stations.append(c.z+(c.y+.055)*cos(PI*float(j)/16.0))
	stations.sort()
	return stations

func chassis() -> void:
	active="Body"
	var stations := chassis_stations()
	for s in [-1.0,1.0]:
		for i in stations.size()-1:
			var za:=stations[i]
			var zb:=stations[i+1]
			if za<front or zb>rear or zb-za<.00001: continue
			var ya:=arch_bottom(za)
			var yb:=arch_bottom(zb)
			var shoulder:=belt_y-.085
			quad("paint",Vector3(s*side_x(za),ya,za),Vector3(s*side_x(zb),yb,zb),Vector3(s*side_x(zb),maxf(shoulder,yb),zb),Vector3(s*side_x(za),maxf(shoulder,ya),za),Vector3(s,0,0))
			quad("paint",Vector3(s*side_x(za),maxf(shoulder,ya),za),Vector3(s*side_x(zb),maxf(shoulder,yb),zb),Vector3(s*(side_x(zb)-.065),maxf(belt_y,yb),zb),Vector3(s*(side_x(za)-.065),maxf(belt_y,ya),za),Vector3(s,1,0))
			# Inner return at the open wheel wells; no body plane across the tyres.
			tint=DARK
			quad("detail",Vector3(s*side_x(za),ya,za),Vector3(s*side_x(zb),yb,zb),Vector3(s*(side_x(zb)-.13),yb+.018,zb),Vector3(s*(side_x(za)-.13),ya+.018,za),Vector3(0,-1,0))
			tint=Color.WHITE
		# Sculpted arch flares follow each axle; single material batch for all trim.
		for c in axles:
			if c.x>0: continue
			var rr:=c.y+.061
			for j in 16:
				var a:=PI*j/16.0
				var b:=PI*(j+1)/16.0
				var za:=c.z+cos(a)*rr
				var zb:=c.z+cos(b)*rr
				beam("detail",Vector3(s*(side_x(za)+.005),c.y+sin(a)*rr,za),Vector3(s*(side_x(zb)+.005),c.y+sin(b)*rr,zb),.040 if family=="suv" else .023,DARK)
			# Calipers are stationary, separate from wheel rotation but in body batch.
			box("detail",Vector3(s*(absf(c.x)+.095),c.y+.05,c.z+.14),Vector3(.025,.15,.075),Color("a96038"))
		var rocker_front := maxf(float(door.get("zf",-.4)),axles[0].z+axles[0].y+.07)
		var rocker_rear := minf(float(door.get("zr",.5)),axles[1].z-axles[1].y-.07)
		var middle_z := (rocker_front+rocker_rear)*.5
		var length := rocker_rear-rocker_front
		if length>.12:
			box("detail",Vector3(s*(skin-.04),sill_y+.035,middle_z),Vector3(.07,.075,length),DARK)
			box("detail",Vector3(s*(skin+.012),sill_y+.045,middle_z),Vector3(.02,.022,length-.10),accent)
	# The underbody stays inside the wells. Front/rear faces include bevelled paint.
	box("detail",Vector3(0,sill_y+.025,(front+rear)*.5),Vector3(skin*1.53,.06,rear-front-.1),DARK)
	for z in [front,rear]:
		var n:=Vector3.FORWARD if z==front else Vector3.BACK
		quad("paint",Vector3(-side_x(z),sill_y,z),Vector3(side_x(z),sill_y,z),Vector3(side_x(z)-.065,belt_y,z),Vector3(-side_x(z)+.065,belt_y,z),n)
	# Shallow three-strip hood has real chamfered shoulders.
	var hood_z: Array[float]=[front,front+.18,windshield_z]
	for j in hood_z.size()-1:
		for i in 6:
			var xa:=lerpf(-1,1,float(i)/6)
			var xb:=lerpf(-1,1,float(i+1)/6)
			quad("paint",hood_point(xa,hood_z[j]),hood_point(xb,hood_z[j]),hood_point(xb,hood_z[j+1]),hood_point(xa,hood_z[j+1]),Vector3.UP)
	for s in [-1.0,1.0]:
		beam("detail",hood_point(s*.71,front+.15)+Vector3.UP*.006,hood_point(s*.71,windshield_z-.04)+Vector3.UP*.006,.009,DARK)

func hood_point(x: float,z: float) -> Vector3:
	return Vector3(x*(side_x(z)-.065),belt_y+.025*(1-x*x)-.04*clampf((front+.15-z)/.15,0,1),z)

func cabin() -> void:
	var lower_x:=skin-.075
	var upper_x:=skin-(.16 if family=="van" else .19)
	active="Body"
	glazing([Vector3(-lower_x,belt_y,windshield_z),Vector3(lower_x,belt_y,windshield_z),Vector3(upper_x,roof_y,roof_front),Vector3(-upper_x,roof_y,roof_front)],Vector3(0,1,-1))
	# Visually connected wipers sit on the glazing instead of floating trim.
	for s in [-1.0,1.0]:
		beam("detail",Vector3(s*.10,belt_y+.045,windshield_z+.012),Vector3(s*.55,belt_y+.13,windshield_z+.065),.013,DARK)
	var cuts: Array[float] = [windshield_z,float(door.zr),cabin_back]
	if family=="suv" and not "jeep" in car_id: cuts.insert(2,minf(cabin_back-.25,float(door.zr)+.85))
	if family=="van" and car_id=="nimbus_minivan": cuts.insert(2,.65)
	for s in [-1.0,1.0]:
		for i in cuts.size()-1:
			var za:=cuts[i]
			var zb:=cuts[i+1]
			var ta:=roof_front if i==0 else za
			var tb:=roof_back if i==cuts.size()-2 else zb
			var corners: Array=[Vector3(s*lower_x,belt_y,za),Vector3(s*lower_x,belt_y,zb),Vector3(s*upper_x,roof_y,tb),Vector3(s*upper_x,roof_y,ta)]
			var cargo_panel:=family=="van" and car_id!="nimbus_minivan" and i>0
			if cargo_panel:
				quad("paint",corners[0],corners[1],corners[2],corners[3],Vector3(s,0,0))
				# Recessed pressed cargo panel, sliding rail and rear door hardware.
				tint=Color(.81,.83,.84)
				var pressed:Array=[]
				for corner:Vector3 in corners: pressed.append(corner+Vector3(s*.006,0,0))
				panel("paint",pressed,.055,.945,.16,.80,Vector3(s,0,0))
				tint=Color.WHITE
				beam("detail",Vector3(s*(lower_x+.01),belt_y+.21,za+.12),Vector3(s*(lower_x+.01),belt_y+.21,zb-.12),.015,DARK)
			else: glazing(corners,Vector3(s,0,0))
		# Door seams, handle and mirror sit on the same measured side as old doors.
		for z in [float(door.zf),float(door.zr)]: beam("detail",Vector3(s*(skin+.005),sill_y+.05,z),Vector3(s*(skin+.005),belt_y-.10,z),.009,DARK)
		active="DoorTrimL" if s<0 else "DoorTrimR"
		box("detail",Vector3(s*(skin+.014),belt_y-.17,float(door.zr)-.15),Vector3(.024,.046,.19),DARK)
		box("detail",Vector3(s*(skin+.029),belt_y-.16,float(door.zr)-.15),Vector3(.022,.020,.145),accent)
		active="Body"
		if family=="pickup" and cabin_back>.5:
			beam("detail",Vector3(s*(skin+.005),sill_y+.05,cabin_back-.1),Vector3(s*(skin+.005),belt_y-.10,cabin_back-.1),.009,DARK)
			box("detail",Vector3(s*(skin+.022),belt_y-.17,cabin_back-.26),Vector3(.03,.032,.15),accent)
		active="DoorTrimL" if s<0 else "DoorTrimR"
		var mirror_z:float=float(door.zf)+.14
		var mirror_x:=minf(skin+.15,float(data.spec.bounds_size[0])*.5-.075)
		beam("detail",Vector3(s*(lower_x+.015),belt_y+.14,mirror_z),Vector3(s*(mirror_x-.01),belt_y+.17,mirror_z),.032,DARK)
		box("detail",Vector3(s*mirror_x,belt_y+.21,mirror_z),Vector3(.14,.13,.23),DARK)
		box("detail",Vector3(s*mirror_x,belt_y+.21,mirror_z+.119),Vector3(.11,.10,.008),METAL)
		active="Body"
	# Arched roof, bevel lip, rear glazing; no solid block inside the cabin.
	for i in 8:
		var xa:=lerpf(-upper_x,upper_x,i/8.0)
		var xb:=lerpf(-upper_x,upper_x,(i+1)/8.0)
		var ya:=roof_y+.035*(1-pow(xa/upper_x,2))
		var yb:=roof_y+.035*(1-pow(xb/upper_x,2))
		quad("paint",Vector3(xa,ya,roof_front),Vector3(xb,yb,roof_front),Vector3(xb,yb,roof_back),Vector3(xa,ya,roof_back),Vector3.UP)
		quad("paint",Vector3(xa,roof_y,roof_front),Vector3(xb,roof_y,roof_front),Vector3(xb,yb,roof_front),Vector3(xa,ya,roof_front),Vector3.FORWARD)
		quad("paint",Vector3(xa,roof_y,roof_back),Vector3(xb,roof_y,roof_back),Vector3(xb,yb,roof_back),Vector3(xa,ya,roof_back),Vector3.BACK)
	var back_corners: Array=[Vector3(-lower_x,belt_y,cabin_back),Vector3(lower_x,belt_y,cabin_back),Vector3(upper_x,roof_y,roof_back),Vector3(-upper_x,roof_y,roof_back)]
	if family=="van" and car_id!="nimbus_minivan":
		quad("paint",back_corners[0],back_corners[1],back_corners[2],back_corners[3],Vector3.BACK)
		beam("detail",Vector3(0,belt_y+.01,cabin_back+.005),Vector3(0,roof_y-.055,roof_back+.005),.015,DARK)
		for s in [-1.,1.]:
			box("detail",Vector3(s*.08,belt_y+.3,cabin_back-.023),Vector3(.024,.19,.038),METAL)
			for yy in [belt_y+.2,roof_y-.2]: box("detail",Vector3(s*(lower_x-.08),yy,cabin_back-.03),Vector3(.08,.042,.052),accent)
	else: glazing(back_corners,Vector3(0,1,1))
	if family!="pickup":
		quad("paint",Vector3(-lower_x,belt_y,cabin_back),Vector3(lower_x,belt_y,cabin_back),Vector3(side_x(rear)-.065,belt_y,rear),Vector3(-side_x(rear)+.065,belt_y,rear),Vector3.UP)
		box("detail",Vector3(0,belt_y-.18,rear+.011),Vector3(.25,.035,.018),accent)
	if family=="suv" or car_id=="nimbus_minivan": roof_rails(upper_x)
	if car_id=="polar_van":
		# Compact cold-region roof vent seated on a base, no powered light or effect.
		box("detail",Vector3(0,roof_y+.08,.30),Vector3(.65,.12,.54),Color("d0d5d3"))
		for j in 5: box("detail",Vector3(0,roof_y+.095,.07+j*.10),Vector3(.54,.035,.026),DARK)
	if car_id in ["winter_suv_heavy","arctic_jeep"]:
		for s in [-1.,1.]:
			box("detail",Vector3(s*(skin+.004),sill_y+.11,(float(door.zf)+float(door.zr))*.5),Vector3(.027,.15,float(door.zr)-float(door.zf)-.06),DARK)

func roof_rails(rx: float) -> void:
	for s in [-1.,1.]:
		for z in [roof_front+.12,roof_back-.12]: box("detail",Vector3(s*(rx-.045),roof_y+.055,z),Vector3(.055,.11,.09),DARK)
		beam("detail",Vector3(s*(rx-.045),roof_y+.115,roof_front+.12),Vector3(s*(rx-.045),roof_y+.115,roof_back-.12),.032,accent)
	if car_id in ["arctic_jeep","winter_suv_heavy"]:
		for z in [roof_front+.24,roof_back-.24]: beam("detail",Vector3(-rx+.04,roof_y+.115,z),Vector3(rx-.04,roof_y+.115,z),.031,DARK)
		# Compact expedition rack, six broad slats baked into Body.
		for j in 6: box("detail",Vector3(lerpf(-rx+.13,rx-.13,j/5.0),roof_y+.137,(roof_front+roof_back)*.5),Vector3(.042,.026,roof_back-roof_front-.40),DARK)

func pickup_bed() -> void:
	active="Body"
	var bed_front:=cabin_back+.10
	var bed_rear:=rear-.13
	var floor_y:=sill_y+.23
	var load_beds:Dictionary=preload("res://runtime/VehicleUsage.gd").BEDS
	# Cargo rests on the liner ribs, whose tops sit .0475 above the floor center.
	if load_beds.has(car_id): floor_y=float(load_beds[car_id][0])-.0475
	# Actual open bed: four thin walls, recessed floor, inner wheel housings and ribs.
	box("detail",Vector3(0,floor_y,(bed_front+bed_rear)*.5),Vector3((skin-.105)*2,.055,bed_rear-bed_front),Color("303638"))
	for s in [-1.,1.]:
		quad("paint",Vector3(s*(skin-.065),belt_y,bed_front),Vector3(s*(skin-.065),belt_y,bed_rear),Vector3(s*(skin-.12),belt_y-.035,bed_rear),Vector3(s*(skin-.12),belt_y-.035,bed_front),Vector3.UP)
		quad("paint",Vector3(s*(skin-.12),floor_y,bed_front),Vector3(s*(skin-.12),floor_y,bed_rear),Vector3(s*(skin-.12),belt_y-.035,bed_rear),Vector3(s*(skin-.12),belt_y-.035,bed_front),Vector3(-s,0,0))
		box("detail",Vector3(s*(skin-.09),belt_y+.009,(bed_front+bed_rear)*.5),Vector3(.085,.035,bed_rear-bed_front),DARK)
		box("detail",Vector3(s*(skin-.20),floor_y+.13,axles[1].z),Vector3(.30,.27,.83),Color("303638"))
	for z in [bed_front,bed_rear]:
		quad("paint",Vector3(-skin+.12,floor_y,z),Vector3(skin-.12,floor_y,z),Vector3(skin-.12,belt_y-.03,z),Vector3(-skin+.12,belt_y-.03,z),Vector3.FORWARD if z==bed_rear else Vector3.BACK)
	for j in 9: box("detail",Vector3(lerpf(-skin+.18,skin-.18,j/8.0),floor_y+.035,(bed_front+bed_rear)*.5),Vector3(.026,.025,bed_rear-bed_front-.14),Color("454d4f"))
	box("detail",Vector3(0,belt_y-.15,rear+.012),Vector3(.30,.045,.024),DARK)
	for s in [-1.,1.]:
		beam("detail",Vector3(s*(skin-.06),sill_y+.05,rear+.008),Vector3(s*(skin-.06),belt_y-.08,rear+.008),.012,DARK)
	if car_id in ["lumber_pickup_4x4","sertao_trail_pickup","bravio_crew"]:
		for s in [-1.,1.]:
			beam("detail",Vector3(s*(skin-.18),belt_y+.02,bed_front+.20),Vector3(s*(skin-.28),roof_y-.10,bed_front+.24),.064,DARK)
			beam("detail",Vector3(s*(skin-.28),roof_y-.10,bed_front+.24),Vector3(s*(skin-.18),belt_y+.02,bed_front+.64),.056,DARK)
		beam("detail",Vector3(-skin+.28,roof_y-.10,bed_front+.24),Vector3(skin-.28,roof_y-.10,bed_front+.24),.064,DARK)
	if car_id=="ranch_pickup":
		# Warm timber strips distinguish the rural classic without new materials.
		for s in [-1.,1.]:
			for span:Vector2 in [Vector2(bed_front+.08,axles[1].z-axles[1].y-.07),Vector2(axles[1].z+axles[1].y+.07,bed_rear-.08)]:
				if span.y>span.x: box("detail",Vector3(s*(skin+.01),belt_y-.20,(span.x+span.y)*.5),Vector3(.025,.14,span.y-span.x),Color("886443"))

## Borda interna do ombro (topo da lataria, na cintura), linear entre as estações do chassis
## exatamente como os quads de chassis() a desenham, para a emenda não deixar fresta.
func shoulder_inner(z: float) -> float:
	var stations := chassis_stations()
	for i in stations.size()-1:
		var za:=stations[i]
		var zb:=stations[i+1]
		if z<za or z>zb: continue
		var t:=0.0 if zb-za<.00001 else (z-za)/(zb-za)
		return lerpf(side_x(za),side_x(zb),t)-.065
	return side_x(z)-.065

## Borda externa do que já cobre o topo por dentro do ombro (capô, vidro lateral, deck
## traseiro ou trilho da caçamba). Valor negativo = nada ali (tampa traseira da picape).
func top_inner(z: float) -> float:
	var hood_z:=front+.18
	if z<windshield_z: return lerpf(side_x(hood_z),side_x(windshield_z),clampf((z-hood_z)/(windshield_z-hood_z),0,1))-.065
	if z<=cabin_back: return skin-.075
	if family!="pickup": return lerpf(skin-.075,side_x(rear)-.065,(z-cabin_back)/(rear-cabin_back))
	# Entre a cabine e a frente da caçamba só a linha da parede interna (skin-.12) tem cobertura.
	if z<=cabin_back+.10: return skin-.12
	if z<=rear-.13: return skin-.065
	return -1.0

## Fechamento do topo (29/10, relato do jogador "as laterais não são grudadas no carro"):
## o alargamento dos para-lamas (side_x) empurra o ombro para fora perto dos eixos, mas o capô
## (só 3 estações) e o vidro lateral seguem em linha reta. Medido de cima (raster de 5 mm): fresta
## de até 8,5 cm na cintura do desert_jeep_4x4 e 5,5 cm nas ranch, por onde se via o oco da
## carroceria (fundo em y≈0,4–0,8), e o para-lama parecia peça solta. Na picape, a tampa traseira
## (parede interna de face única em rear-.13, face externa em rear) não tinha topo: de trás a
## parede interna some (culling) e via-se o assoalho através da tampa. Faixas na altura da
## cintura, na tinta, fecham os dois vãos (aplicado nas cenas instaladas por fit_top_gaps_20261029).
func top_gap_fill() -> void:
	active="Body"
	var stations: Array[float]=[]
	for z in chassis_stations():
		if z>=front+.18-.00001: stations.append(z)
	for z in [front+.18,windshield_z,cabin_back,cabin_back+.10,rear-.13]:
		if z>front+.17 and z<rear and not stations.has(z): stations.append(z)
	stations.sort()
	var tailgate:=family=="pickup"
	for s in [-1.,1.]:
		for i in stations.size()-1:
			var za:=stations[i]
			var zb:=stations[i+1]
			if zb-za<.0005: continue
			var mid:=(za+zb)*.5
			# Borda interna lida um fio para dentro do trecho: a estação que divide duas regiões
			# (para-brisa, fundo da cabine, tampa) fica com o valor do próprio lado.
			var ia:=top_inner(za+.0001)
			var ib:=top_inner(zb-.0001)
			var oa:=shoulder_inner(za)
			var ob:=shoulder_inner(zb)
			if top_inner(mid)<0:
				if not tailgate: continue
				# Tampa da picape: um topo só, de ombro a ombro.
				if s>0: quad("paint",Vector3(-oa,belt_y,za),Vector3(oa,belt_y,za),Vector3(ob,belt_y,zb),Vector3(-ob,belt_y,zb),Vector3.UP)
				continue
			if oa<=ia+.001 and ob<=ib+.001: continue
			quad("paint",Vector3(s*ia,belt_y,za),Vector3(s*ib,belt_y,zb),Vector3(s*maxf(ob,ib),belt_y,zb),Vector3(s*maxf(oa,ia),belt_y,za),Vector3.UP)
	if tailgate:
		# A parede interna da tampa para .03 abaixo da cintura; a borda sobe até o topo novo.
		var z:=rear-.13
		quad("paint",Vector3(-skin+.12,belt_y-.03,z),Vector3(skin-.12,belt_y-.03,z),Vector3(skin-.12,belt_y,z),Vector3(-skin+.12,belt_y,z),Vector3.FORWARD)

func fascia() -> void:
	active="Body"
	var front_z:=front-.012
	var lamp_y:=belt_y-.15
	var grille_w:=skin*.91
	box("detail",Vector3(0,belt_y-.19,front_z),Vector3(grille_w,.30,.045),DARK)
	var jeep:=car_id in ["arctic_jeep","desert_jeep_4x4"]
	var modern:=car_id in ["bravio_crew","atlas_crew_pickup","sertao_trail_pickup","nimbus_minivan","winter_suv_heavy"]
	if jeep:
		for j in 7: box("detail",Vector3(lerpf(-grille_w*.43,grille_w*.43,j/6.0),belt_y-.19,front_z-.028),Vector3(.028,.26,.020),accent)
	else:
		var bars:=4 if car_id in ["bravio_crew","atlas_crew_pickup","ranch_single"] else 3
		for j in bars: box("detail",Vector3(0,belt_y-.30+j*.073,front_z-.028),Vector3(grille_w-.045,.019,.02),accent)
		for j in 7: box("detail",Vector3(lerpf(-grille_w*.45,grille_w*.45,j/6.0),belt_y-.19,front_z-.032),Vector3(.012,.25,.012),Color("485155"))
		if modern:
			box("detail",Vector3(0,belt_y-.385,front_z-.029),Vector3(grille_w*.86,.055,.02),DARK)
			box("detail",Vector3(0,belt_y-.015,front_z-.016),Vector3(grille_w+.055,.032,.029),accent)
	for s in [-1.,1.]:
		var lamp_x:float=s*skin*.73
		active="Body"
		if jeep:
			ellipse("detail",Vector3(lamp_x,lamp_y,front_z-.022),Vector3.RIGHT,Vector3.UP,.158,.120,Vector3.FORWARD,accent,20)
			active="HeadlightL" if s<0 else "HeadlightR"
			ellipse("headlight",Vector3(lamp_x,lamp_y,front_z-.025),Vector3.RIGHT,Vector3.UP,.120,0,Vector3.FORWARD,Color.WHITE,20)
		else:
			box("detail",Vector3(lamp_x,lamp_y,front_z-.012),Vector3(skin*.41,.19,.041),DARK)
			active="HeadlightL" if s<0 else "HeadlightR"
			if modern:
				box("headlight",Vector3(lamp_x,lamp_y+.058,front_z-.038),Vector3(skin*.34,.024,.014))
				box("headlight",Vector3(lamp_x+s*skin*.157,lamp_y,front_z-.038),Vector3(.025,.115,.014))
				for xx in [-.065,.04]: ellipse("headlight",Vector3(lamp_x+xx,lamp_y-.011,front_z-.04),Vector3.RIGHT,Vector3.UP,.038,0,Vector3.FORWARD,Color.WHITE,12)
			else: box("headlight",Vector3(lamp_x,lamp_y,front_z-.038),Vector3(skin*.34,.105,.014))
		active="Body"
		box("detail",Vector3(lamp_x,lamp_y-.111,front_z-.029),Vector3(skin*.30,.027,.018),Color("c58336"))
		box("detail",Vector3(s*skin*.78,sill_y+.12,front_z-.034),Vector3(.18,.055,.025),METAL)
	# Bumpers have stepped corners and a central skid insert instead of a thick block.
	for z in [front-.025,rear+.025]:
		box("detail",Vector3(0,sill_y+.065,z),Vector3(skin*1.76,.15,.105),DARK)
		box("detail",Vector3(0,sill_y+.035,z+(-.06 if z<0 else .06)),Vector3(skin*.93,.075,.025),accent)
		for s in [-1.,1.]: box("detail",Vector3(s*skin*.79,sill_y+.086,z),Vector3(.20,.18,.13),DARK)
	box("detail",Vector3(0,sill_y+.22,rear+.018),Vector3(.34,.10,.015),Color("b5bdb7"))
	for s in [-1.,1.]:
		var vertical:=family=="van" or family=="pickup"
		active="Body"
		box("detail",Vector3(s*(skin-.14),belt_y-.22,rear+.004),Vector3(.145,.32,.026) if vertical else Vector3(.345,.14,.026),DARK)
		active="Tail"
		box("tail",Vector3(s*(skin-.14),belt_y-.22,rear+.013),Vector3(.12,.29,.024) if vertical else Vector3(.33,.11,.024))
	active="Body"
	for s in [-1.,1.]:
		box("detail",Vector3(s*(skin-.14),belt_y-.25,rear+.028),Vector3(.124,.021,.012) if family in ["van","pickup"] else Vector3(.33,.014,.012),METAL)
		box("detail",Vector3(s*.63,sill_y-.032,rear-.025),Vector3(.12,.065,.21),Color("41494d"))
	if car_id in ["arctic_jeep","desert_jeep_4x4"]:
		var at:=Vector3(0,belt_y+.12,rear+.058)
		box("detail",at+Vector3(0,-.11,-.11),Vector3(.14,.34,.15),DARK)
		for j in 20:
			var a:=TAU*j/20.0
			var b:=TAU*(j+1)/20.0
			var pa:=Vector3(cos(a),sin(a),0)*.315
			var pb:=Vector3(cos(b),sin(b),0)*.315
			tint=DARK
			quad("detail",at+pa,at+pb,at+pb+Vector3.FORWARD*.14,at+pa+Vector3.FORWARD*.14,Vector3(cos(a),sin(a),0))
			triangle("detail",at+Vector3.FORWARD*.14,at+pb+Vector3.FORWARD*.14,at+pa+Vector3.FORWARD*.14,Vector3.FORWARD)
		ellipse("detail",at,Vector3.RIGHT,Vector3.UP,.315,.20,Vector3.BACK,DARK,20)
		ellipse("detail",at+Vector3.BACK*.005,Vector3.RIGHT,Vector3.UP,.20,.075,Vector3.BACK,accent,20)
		ellipse("detail",at+Vector3.BACK*.007,Vector3.RIGHT,Vector3.UP,.075,0,Vector3.BACK,DARK,12)
	if car_id in ["desert_jeep_4x4","lumber_pickup_4x4"]:
		for s in [-1.,1.]: beam("detail",Vector3(s*.53,sill_y+.06,front-.085),Vector3(s*.53,belt_y-.04,front-.085),.045,DARK)
		beam("detail",Vector3(-.53,belt_y-.04,front-.085),Vector3(.53,belt_y-.04,front-.085),.045,DARK)

func utility_wheels() -> void:
	for c in axles:
		var s:=signf(c.x)
		active="Wheel_%s_%s" % ["L" if s<0 else "R","F" if c.z<0 else "R"]
		var r:=c.y-.025
		var rw:=.115 if family!="buggy" else .13
		var profile: Array[Vector2]=[Vector2(-rw,r*.68),Vector2(-rw,r*.90),Vector2(-rw*.7,r),Vector2(rw*.7,r),Vector2(rw,r*.90),Vector2(rw+.003,r*.62)]
		for j in profile.size()-1:
			for i in 20:
				var a:=TAU*i/20.0
				var b:=TAU*(i+1)/20.0
				var pa:=profile[j]
				var pb:=profile[j+1]
				tint=Color("20272c") if j==2 else Color("2b3236")
				quad("wheel",c+Vector3(s*pa.x,sin(a)*pa.y,cos(a)*pa.y),c+Vector3(s*pa.x,sin(b)*pa.y,cos(b)*pa.y),c+Vector3(s*pb.x,sin(b)*pb.y,cos(b)*pb.y),c+Vector3(s*pb.x,sin(a)*pb.y,cos(a)*pb.y),Vector3(s*.25,sin(a),cos(a)))
		var face:=c+Vector3(s*(rw+.007),0,0)
		ellipse("wheel",face,Vector3.UP,Vector3.BACK,r*.67,r*.57,Vector3(s,0,0),accent,20)
		ellipse("wheel",face-Vector3(s*.010,0,0),Vector3.UP,Vector3.BACK,r*.57,0,Vector3(s,0,0),DARK,20)
		ellipse("wheel",face+Vector3(s*.002,0,0),Vector3.UP,Vector3.BACK,r*.50,.05,Vector3(s,0,0),Color("505a5f"),20)
		var spokes:=6 if family in ["pickup","suv"] else 5
		for j in spokes:
			var a:=TAU*j/spokes+.14
			var radial:=Vector3(0,sin(a),cos(a))
			var tangent:=Vector3(0,cos(a),-sin(a))
			var at:=face+Vector3(s*.009,0,0)
			tint=accent
			quad("wheel",at+radial*.050-tangent*.035,at+radial*.050+tangent*.035,at+radial*r*.61+tangent*.025,at+radial*r*.61-tangent*.025,Vector3(s,0,0))
			ellipse("wheel",at+radial*.045+Vector3(s*.003,0,0),Vector3.UP,Vector3.BACK,.010,0,Vector3(s,0,0),DARK,5)
		ellipse("wheel",face+Vector3(s*.021,0,0),Vector3.UP,Vector3.BACK,.046,0,Vector3(s,0,0),accent,12)
		# Broad tread blocks add depth without dense smooth tyre cylinders.
		if car_id not in ["nimbus_minivan","courier_van","dock_delivery_van","polar_van"]:
			for j in 16:
				var a:=TAU*j/16.0
				var radial:=Vector3(0,sin(a),cos(a))
				var tangent:=Vector3(0,cos(a),-sin(a))*.015
				tint=Color("353c3f")
				quad("wheel",c+radial*(r+.002)-Vector3(rw*.61,0,0)-tangent,c+radial*(r+.002)+Vector3(rw*.61,0,0)-tangent,c+radial*(r+.002)+Vector3(rw*.61,0,0)+tangent,c+radial*(r+.002)-Vector3(rw*.61,0,0)+tangent,radial)
			tint=Color.WHITE

func buggy() -> void:
	active="Body"
	skin=.75 if car_id=="beach_buggy" else .69
	belt_y=.62 if car_id=="beach_buggy" else .68
	sill_y=.29
	var c_front:=axles[0].z
	var c_rear:=axles[1].z
	# Open fiberglass tub and tapered boat-tail, deliberately different from an SUV.
	var nose: Array=[Vector3(-skin*.58,.52,front+.09),Vector3(skin*.58,.52,front+.09),Vector3(skin*.92,.75,-.58),Vector3(-skin*.92,.75,-.58)]
	quad("paint",nose[0],nose[1],nose[2],nose[3],Vector3.UP)
	quad("paint",Vector3(-skin*.58,.34,front+.09),Vector3(skin*.58,.34,front+.09),nose[1],nose[0],Vector3.FORWARD)
	box("detail",Vector3(0,.33,.10),Vector3(skin*1.70,.09,1.58),DARK)
	for s in [-1.,1.]:
		quad("paint",Vector3(s*skin*.58,.34,front+.09),Vector3(s*skin,.33,-.5),Vector3(s*skin*.92,.75,-.58),Vector3(s*skin*.58,.52,front+.09),Vector3(s,0,0))
		quad("paint",Vector3(s*skin,.33,-.50),Vector3(s*skin,.33,.65),Vector3(s*skin,.51,.65),Vector3(s*skin,.49,-.50),Vector3(s,0,0))
		beam("detail",Vector3(s*(skin-.005),.515,-.5),Vector3(s*(skin-.005),.515,.65),.035,DARK)
		for z in [c_front,c_rear]:
			for j in 12:
				var a:=PI*j/12
				var b:=PI*(j+1)/12
				var radius:=axles[0].y+.07
				var ya:=axles[0].y+sin(a)*radius
				var yb:=axles[0].y+sin(b)*radius
				quad("paint",Vector3(s*.61,ya,z+cos(a)*radius),Vector3(s*.97,ya,z+cos(a)*radius),Vector3(s*.97,yb,z+cos(b)*radius),Vector3(s*.61,yb,z+cos(b)*radius),Vector3.UP)
			# Visible wishbone suspension under exposed wheels.
			beam("detail",Vector3(s*.39,.30,z-.20),Vector3(s*.79,.36,z),.028,METAL)
			beam("detail",Vector3(s*.39,.30,z+.20),Vector3(s*.79,.36,z),.028,METAL)
		# The low roll hoop fits the original height envelope and remains open.
		var roof:=1.26 if car_id=="beach_buggy" else 1.34
		beam("detail",Vector3(s*.64,.40,.48),Vector3(s*.59,roof,.42),.058,DARK)
		beam("detail",Vector3(s*.59,roof,.42),Vector3(s*.52,roof,-.28),.058,DARK)
		beam("detail",Vector3(s*.52,roof,-.28),Vector3(s*.63,.69,-.58),.052,DARK)
		beam("detail",Vector3(s*.59,roof,.42),Vector3(s*.65,.56,1.0),.050,DARK)
		box("detail",Vector3(s*.34,.49,.02),Vector3(.43,.14,.50),Color("313941"))
		box("detail",Vector3(s*.34,.72,.30),Vector3(.43,.45,.12),Color("39434b"))
		box("detail",Vector3(s*.34,.74,.231),Vector3(.33,.34,.016),Color("967b57") if car_id=="beach_buggy" else Color("6d5240"))
		box("detail",Vector3(s*.34,1.02,.30),Vector3(.25,.13,.12),DARK)
		active="HeadlightL" if s<0 else "HeadlightR"
		ellipse("headlight",Vector3(s*.54,.69,front+.20),Vector3.RIGHT,Vector3.UP,.105,0,Vector3.FORWARD,Color.WHITE,16)
		active="Body"
		ellipse("detail",Vector3(s*.54,.69,front+.201),Vector3.RIGHT,Vector3.UP,.131,.105,Vector3.FORWARD,accent,16)
		# Closed lamp bucket and bracket, visible from the rear of the open buggy.
		var lamp_at:Vector3=Vector3(s*.54,.69,front+.207)
		for j in 16:
			var a:=TAU*j/16
			var b:=TAU*(j+1)/16
			var pa:=Vector3(cos(a),sin(a),0)*.131
			var pb:=Vector3(cos(b),sin(b),0)*.131
			tint=DARK
			quad("detail",lamp_at+pa,lamp_at+pb,lamp_at+pb*.78+Vector3.BACK*.10,lamp_at+pa*.78+Vector3.BACK*.10,Vector3(cos(a),sin(a),0))
		ellipse("detail",lamp_at+Vector3.BACK*.102,Vector3.RIGHT,Vector3.UP,.105,0,Vector3.BACK,DARK,16)
		beam("detail",lamp_at+Vector3(0,-.09,.05),lamp_at+Vector3(0,-.20,.05),.038,DARK)
		box("detail",Vector3(s*.66,.71,-.54),Vector3(.10,.08,.13),DARK)
	var top:=1.26 if car_id=="beach_buggy" else 1.34
	beam("detail",Vector3(-.59,top,.42),Vector3(.59,top,.42),.058,DARK)
	beam("detail",Vector3(-.52,top,-.28),Vector3(.52,top,-.28),.052,DARK)
	glazing([Vector3(-.63,.69,-.58),Vector3(.63,.69,-.58),Vector3(.52,top,-.28),Vector3(-.52,top,-.28)],Vector3(0,1,-1))
	box("detail",Vector3(0,.62,-.43),Vector3(1.10,.14,.16),DARK)
	quad("paint",Vector3(-skin,.55,.66),Vector3(skin,.55,.66),Vector3(skin*.63,.53,rear),Vector3(-skin*.63,.53,rear),Vector3.UP)
	quad("paint",Vector3(-skin*.63,.34,rear),Vector3(skin*.63,.34,rear),Vector3(skin*.63,.53,rear),Vector3(-skin*.63,.53,rear),Vector3.BACK)
	for s in [-1.,1.]: quad("paint",Vector3(s*skin,.34,.66),Vector3(s*skin*.63,.34,rear),Vector3(s*skin*.63,.53,rear),Vector3(s*skin,.55,.66),Vector3(s,0,0))
	for j in 5: box("detail",Vector3(0,.56,.76+j*.095),Vector3(.65,.018,.025),DARK)
	for z in [front+.01,rear+.012]: beam("detail",Vector3(-.55,.38,z),Vector3(.55,.38,z),.045,accent)
	active="Tail"
	for s in [-1.,1.]: box("tail",Vector3(s*.39,.47,rear+.008),Vector3(.15,.07,.015))
	active="Body"
	for s in [-1.,1.]: box("detail",Vector3(s*.28,.35,rear-.015),Vector3(.10,.055,.15),METAL)

func save_model() -> Dictionary:
	var nodes := {}
	for bucket: String in groups:
		var parts:=bucket.split("/")
		var label:=parts[0]
		var key:=parts[1]
		if not nodes.has(label):
			var part:=MeshInstance3D.new()
			part.name=label
			part.mesh=ArrayMesh.new()
			model.add_child(part)
			part.owner=model
			nodes[label]=part
		var node:MeshInstance3D=nodes[label]
		var tool:SurfaceTool=groups[bucket]
		tool.index()
		if key=="paint": tool=soften(tool)
		tool.set_material(material(key))
		tool.commit(node.mesh)
		var roles:Array=node.get_meta("utility_surface_material_keys",[])
		roles.append(key)
		node.set_meta("utility_surface_material_keys",roles)
	for c in axles:
		var label:="Wheel_%s_%s" % ["L" if c.x<0 else "R","F" if c.z<0 else "R"]
		var node:MeshInstance3D=nodes[label]
		node.set_meta("wheel_center",c)
		node.set_meta("wheel_spins",true)
	var pack:=PackedScene.new()
	pack.pack(model)
	var path:="res://assets/fleet/redesigned/"+car_id+".scn"
	var result:=ResourceSaver.save(pack,path,ResourceSaver.FLAG_BUNDLE_RESOURCES)
	var metrics:={"path":path,"meshes":nodes.size(),"surfaces":0,"triangles":0,"save_error":result,"baseline_meshes":data.meshes,"baseline_triangles":data.triangles,"wheels":data.wheels,"family":family}
	for node:MeshInstance3D in nodes.values():
		metrics.surfaces+=node.mesh.get_surface_count()
		metrics.triangles+=node.mesh.get_faces().size()/3
	model.free()
	return metrics

func run() -> void:
	var baseline:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(FOLDER.path_join("baseline.json")))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/fleet/redesigned"))
	var selected:Array[String]=[]
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--ids="): selected.assign(argument.trim_prefix("--ids=").split(","))
	var output:Dictionary={}
	if not selected.is_empty() and FileAccess.file_exists(FOLDER.path_join("after.json")):
		output=JSON.parse_string(FileAccess.get_file_as_string(FOLDER.path_join("after.json")))
	for id in IDS:
		if not selected.is_empty() and id not in selected: continue
		setup(id,baseline[id])
		if family=="buggy": buggy()
		else:
			chassis()
			cabin()
			if family=="pickup": pickup_bed()
			top_gap_fill()
			fascia()
		utility_wheels()
		output[id]=save_model()
		print("UTILITY_BAKED ",id," ",JSON.stringify(output[id]))
	FileAccess.open(FOLDER.path_join("after.json"),FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))
	quit()
