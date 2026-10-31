extends RefCounted
## Um contrato autorado em espaço de metros para a torre, a subida helicoidal contínua,
## o poço da escada aberto e a galeria superior. Toda a geometria vai em lote pelo pai.
const BASE_CENTER := Vector3(303,10.2,-198)
const GALLERY_Y := 24.2
const GALLERY_RADIUS := 6.5
const STAIR_RADIUS := 4.25
const STAIR_INNER := 3.25
const STAIR_OUTER := 5.25
const RISE := 14.0
const TURNS := 2.0
const STEPS := 160
const START_ANGLE := PI*.25
const WELL_INNER := 3.05
const WELL_OUTER := 5.48
const WELL_ARC := PI*.80 # Last 144 degrees: >2.5 m clear beneath slab at entry.
const SUMMIT := Vector3(299.2,24.2,-201.8)
var _site

static func _point(angle: float, radius: float, height: float) -> Vector3:
	return Vector3(BASE_CENTER.x+cos(angle)*radius,height,BASE_CENTER.z+sin(angle)*radius)

static func climb_points() -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in STEPS+1:
		var t := float(i)/STEPS
		result.append(_point(START_ANGLE+TAU*TURNS*t,STAIR_RADIUS,BASE_CENTER.y+RISE*t))
	return result

static func gallery_route_points() -> PackedVector3Array:
	var result := PackedVector3Array([_point(START_ANGLE,STAIR_RADIUS,GALLERY_Y)])
	for i in 13:
		var angle := lerpf(PI/3.0,PI*1.25,float(i)/12.0)
		result.append(_point(angle,5.37,GALLERY_Y))
	result.append(SUMMIT)
	return result

static func route_points() -> PackedVector3Array:
	# Entra na tangente antes do primeiro espelho em vez de atravessar o
	# corrimão externo no início SE. Os bancos da praça ficam fora desta aproximação.
	var result := PackedVector3Array([_point(deg_to_rad(25),6.45,BASE_CENTER.y),
		_point(deg_to_rad(34),STAIR_RADIUS,BASE_CENTER.y)])
	result.append_array(climb_points())
	var gallery := gallery_route_points()
	for i in range(1,gallery.size()): result.append(gallery[i])
	return result

func build(site) -> void:
	_site = site
	_materials()
	_tower()
	_staircase()
	_gallery()
	_lantern()

func _materials() -> void:
	_site._material("lighthouse_wall",Color("c4bda9"),"concrete",.32)
	_site._material("lighthouse_weathered",Color("aca994"),"concrete",.37)
	_site._material("lighthouse_stone",Color("938e7c"),"stone",.38)
	_site._material("lighthouse_paving",Color("b8ad96"),"stone",.30)
	_site._material("lighthouse_coping",Color("c5b89a"),"concrete",.32)
	_site._material("lighthouse_bronze",Color("514b40"))
	_site._material("lighthouse_roof",Color("303e42"))
	_site._material("lighthouse_lens",Color("d6bc71"))
	_site._material("lighthouse_lens_edges",Color("e2d8ac"))
	_site._material("lighthouse_glass",Color(.31,.49,.53,.24))
	_site._materials.lighthouse_bronze.metallic = .65
	_site._materials.lighthouse_bronze.roughness = .50
	_site._materials.lighthouse_roof.metallic = .40
	_site._materials.lighthouse_roof.roughness = .62
	_site._materials.lighthouse_lens.emission_enabled = true
	_site._materials.lighthouse_lens.emission = Color("cbbb87")
	_site._materials.lighthouse_lens.emission_energy_multiplier = .75
	_site._materials.lighthouse_glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_site._materials.lighthouse_glass.roughness = .20
	_site._materials.lighthouse_glass.metallic_specular = .30

func _tower() -> void:
	# Foundation, salt-weathered foot and slightly tapered plaster shaft.
	_ring("lighthouse_stone",3.08,3.08,BASE_CENTER.y,BASE_CENTER.y+.42,true)
	_ring("lighthouse_coping",3.16,3.08,BASE_CENTER.y+.42,BASE_CENTER.y+.58,true)
	for band in 10:
		var lower := BASE_CENTER.y+.58+float(band)*1.342
		var upper := lower+1.342
		var r0 := lerpf(2.84,2.40,float(band)/10)
		var r1 := lerpf(2.84,2.40,float(band+1)/10)
		_ring("lighthouse_weathered" if band in [0,1,6] else "lighthouse_wall",r0,r1,lower,upper,true)
	for height in [BASE_CENTER.y+1.15,BASE_CENTER.y+6.6,BASE_CENTER.y+12.0]:
		var radius := lerpf(2.84,2.4,(height-BASE_CENTER.y)/RISE)
		_ring("lighthouse_coping",radius+.12,radius+.12,height,height+.14)
	# Janelas estreitas rebaixadas e emolduradas no fuste. São totalmente fechadas e
	# nunca fingem ser aberturas acessíveis nem alteram a colisão da torre.
	for row in 3:
		var height := BASE_CENTER.y+3.1+float(row)*4.0
		var radius := lerpf(2.84,2.4,(height-BASE_CENTER.y)/RISE)
		for angle in [0.0,PI*.5,PI,PI*1.5]:
			var radial := Vector3(cos(angle),0,sin(angle))
			var tangent := Vector3(-sin(angle),0,cos(angle))
			var basis := Basis(tangent,Vector3.UP,radial)
			var at := Vector3(BASE_CENTER.x,height,BASE_CENTER.z)+radial*(radius+.045)
			_site._box("lighthouse_roof",at,Vector3(.44,1.22,.065),false,basis)
			for x in [-.29,.29]: _site._box("lighthouse_coping",at+tangent*x,Vector3(.12,1.48,.13),false,basis)
			for y in [-.71,.71]: _site._box("lighthouse_coping",at+Vector3.UP*y,Vector3(.70,.13,.18),false,basis)
			_site._box("lighthouse_bronze",at+radial*.04,Vector3(.035,1.18,.03),false,basis)

func _staircase() -> void:
	var path := climb_points()
	for i in STEPS:
		var a := START_ANGLE+TAU*TURNS*float(i)/STEPS
		var b := START_ANGLE+TAU*TURNS*float(i+1)/STEPS
		var h0 := path[i].y
		var h1 := path[i+1].y
		var inner_a := _point(a,STAIR_INNER,h0)
		var outer_a := _point(a,STAIR_OUTER,h0)
		var inner_b := _point(b,STAIR_INNER,h1)
		var outer_b := _point(b,STAIR_OUTER,h1)
		# A física é uma rampa contínua de 15 graus. O piso de pedra tem só 4.4 cm
		# de diferença em cada ponta, então os pés nunca somem em degraus falsos fundos.
		_physical_quad(inner_a,outer_a,outer_b,inner_b)
		var tread_y := (h0+h1)*.5-.018
		var ia := Vector3(inner_a.x,tread_y,inner_a.z)
		var oa := Vector3(outer_a.x,tread_y,outer_a.z)
		var ib := Vector3(inner_b.x,tread_y,inner_b.z)
		var ob := Vector3(outer_b.x,tread_y,outer_b.z)
		_site._quad("lighthouse_paving",ia,oa,ob,ib,Vector3.UP)
		_site._quad("lighthouse_stone",ib,ob,ob-Vector3.UP*(RISE/STEPS),ib-Vector3.UP*(RISE/STEPS),(path[i+1]-path[i]).normalized())
		var inward := Vector3(BASE_CENTER.x,0,BASE_CENTER.z)-Vector3((ia.x+ib.x)*.5,0,(ia.z+ib.z)*.5)
		_site._quad("lighthouse_stone",inner_a,inner_b,inner_b-Vector3.UP*.20,inner_a-Vector3.UP*.20,inward,true)
		_site._quad("lighthouse_stone",outer_a,outer_b,outer_b-Vector3.UP*.20,outer_a-Vector3.UP*.20,-inward,true)
		_site._quad("lighthouse_stone",inner_a-Vector3.UP*.20,outer_a-Vector3.UP*.20,outer_b-Vector3.UP*.20,inner_b-Vector3.UP*.20,Vector3.DOWN,true)
		_site._guard(inner_a,inner_b,"lighthouse_")
		_site._guard(outer_a,outer_b,"lighthouse_")
		if i%10==0:
			var support := _point(a,2.72,h0-.78)
			_site._beam("lighthouse_bronze",support,_point(a,STAIR_OUTER-.08,h0-.22),.085,.10)
	# Um patamar sólido rente no início; sem soleira de primeiro degrau nem corrimão
	# atravessando a boca. A borda final fica exatamente na altitude do piso da galeria.

func _physical_quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	# Match Godot clockwise front faces; kept separate from shallow tread art.
	for triangle in [[a,b,c],[a,c,d]]:
		var normal: Vector3 = (triangle[2]-triangle[0]).cross(triangle[1]-triangle[0])
		if normal.y<0:
			_site._collision.append_array(PackedVector3Array([triangle[0],triangle[2],triangle[1]]))
		else: _site._collision.append_array(PackedVector3Array(triangle))

func _gallery() -> void:
	# Um anel, não um disco sobre os últimos metros de subida. O poço da escada fica aberto
	# por 144 graus com folga >=2.5 m onde a laje volta por cima.
	var count := 80
	for i in count:
		var a := START_ANGLE+TAU*float(i)/count
		var b := START_ANGLE+TAU*float(i+1)/count
		var in_well := TAU*float(i+.5)/count>TAU-WELL_ARC
		if in_well:
			_gallery_sector(a,b,2.38,WELL_INNER)
			_gallery_sector(a,b,WELL_OUTER,GALLERY_RADIUS)
			_site._guard(_point(a,WELL_INNER,GALLERY_Y),_point(b,WELL_INNER,GALLERY_Y),"lighthouse_")
			_site._guard(_point(a,WELL_OUTER,GALLERY_Y),_point(b,WELL_OUTER,GALLERY_Y),"lighthouse_")
		else: _gallery_sector(a,b,2.38,GALLERY_RADIUS)
		_site._guard(_point(a,GALLERY_RADIUS,GALLERY_Y),_point(b,GALLERY_RADIUS,GALLERY_Y),"lighthouse_")
	# Fecha só a ponta baixa do poço da escada. A ponta alta continua caminhável.
	var start := START_ANGLE+TAU-WELL_ARC
	_site._guard(_point(start,WELL_INNER,GALLERY_Y),_point(start,WELL_OUTER,GALLERY_Y),"lighthouse_")
	# O anel de cachorros e os suportes individuais explicam a sacada em balanço.
	_ring("lighthouse_coping",2.42,3.15,GALLERY_Y-1.0,GALLERY_Y-.30)
	for i in 16:
		var angle := TAU*i/16.0
		# Evita um suporte cruzando o setor aberto da subida final.
		if fposmod(angle-START_ANGLE,TAU)>TAU-WELL_ARC: continue
		_site._beam("lighthouse_bronze",_point(angle,2.5,GALLERY_Y-1.3),_point(angle,6.05,GALLERY_Y-.30),.14,.18)

func _gallery_sector(a: float,b: float,inner: float,outer: float) -> void:
	var ia := _point(a,inner,GALLERY_Y)
	var oa := _point(a,outer,GALLERY_Y)
	var ib := _point(b,inner,GALLERY_Y)
	var ob := _point(b,outer,GALLERY_Y)
	_site._quad("lighthouse_paving",ia,oa,ob,ib,Vector3.UP,true)
	_site._quad("lighthouse_stone",ia-Vector3.UP*.24,oa-Vector3.UP*.24,ob-Vector3.UP*.24,ib-Vector3.UP*.24,Vector3.DOWN,true)
	_site._quad("lighthouse_coping",oa,ob,ob-Vector3.UP*.24,oa-Vector3.UP*.24,Vector3(cos((a+b)*.5),0,sin((a+b)*.5)),true)

func _lantern() -> void:
	_ring("lighthouse_coping",2.63,2.63,GALLERY_Y,GALLERY_Y+.36,true)
	_ring("lighthouse_roof",2.72,2.72,GALLERY_Y+.36,GALLERY_Y+.52,true)
	var panels := 12
	for i in panels:
		var a := TAU*i/panels
		var b := TAU*(i+1)/panels
		var low_a := _point(a,2.55,GALLERY_Y+.50)
		var low_b := _point(b,2.55,GALLERY_Y+.50)
		_site._quad("lighthouse_glass",low_a,low_b,low_b+Vector3.UP*2.45,low_a+Vector3.UP*2.45,Vector3(cos(a),0,sin(a)),true)
		_site._beam("lighthouse_roof",low_a,low_a+Vector3.UP*2.55,.095,.095)
		_site._beam("lighthouse_bronze",low_a+Vector3.UP*1.15,low_b+Vector3.UP*1.15,.045,.05)
	_ring("lighthouse_roof",2.77,2.77,GALLERY_Y+2.91,GALLERY_Y+3.09)
	_ring("lighthouse_roof",2.90,2.82,GALLERY_Y+3.10,GALLERY_Y+3.28)
	# Cúpula curva cinza-cobre feita de anéis de raios desiguais em vez de um cone.
	var profile := [Vector2(2.82,3.28),Vector2(2.73,3.61),Vector2(2.35,4.07),Vector2(1.74,4.50),Vector2(.92,4.83),Vector2(.16,5.00)]
	for i in range(profile.size()-1):
		_ring("lighthouse_roof",profile[i].x,profile[i+1].x,GALLERY_Y+profile[i].y,GALLERY_Y+profile[i+1].y)
	for i in 12:
		var angle := TAU*i/12.0
		for j in range(profile.size()-1):
			_site._beam("lighthouse_bronze",_point(angle,profile[j].x+.015,GALLERY_Y+profile[j].y),_point(angle,profile[j+1].x+.015,GALLERY_Y+profile[j+1].y),.035,.035)
	_site._cylinder("lighthouse_roof",Vector3(BASE_CENTER.x,GALLERY_Y+5.35,BASE_CENTER.z),.075,.80)
	# Conjunto Fresnel parado e uma lâmpada de manutenção contida. Não há
	# feixe girando, movimento de luz por quadro nem mudanças de luz global.
	_site._cylinder("lighthouse_bronze",Vector3(BASE_CENTER.x,GALLERY_Y+.67,BASE_CENTER.z),.42,.35)
	_site._cylinder("lighthouse_bronze",Vector3(BASE_CENTER.x,GALLERY_Y+1.08,BASE_CENTER.z),.18,.66)
	_site._cylinder("lighthouse_lens",Vector3(BASE_CENTER.x,GALLERY_Y+1.78,BASE_CENTER.z),.74,1.35)
	for i in 9:
		_ring("lighthouse_lens_edges",.78,.78,GALLERY_Y+1.13+i*.155,GALLERY_Y+1.15+i*.155)
	_site._cylinder("lighthouse_bronze",Vector3(BASE_CENTER.x,GALLERY_Y+2.5,BASE_CENTER.z),.82,.09)
	var lamp := OmniLight3D.new()
	lamp.name = "LighthouseLanternLight"
	# O Fresnel de vidro e as vidraças deixam passar esta luz (sem sombra opaca);
	# a torre, a galeria, os corrimãos e o telhado mantêm as sombras físicas inteiras.
	lamp.position = Vector3(BASE_CENTER.x,26.0,BASE_CENTER.z)
	lamp.light_color = Color("ffe0a6")
	lamp.light_energy = 1.65
	lamp.omni_range = 6.5
	lamp.omni_attenuation = 1.15
	lamp.light_specular = .35
	lamp.shadow_enabled = true
	lamp.distance_fade_enabled = false
	_site.add_child(lamp)

func _ring(material: String,r0: float,r1: float,y0: float,y1: float,solid := false) -> void:
	for i in 64:
		var a := TAU*i/64.0
		var b := TAU*(i+1)/64.0
		_site._quad(material,_point(a,r0,y0),_point(b,r0,y0),_point(b,r1,y1),_point(a,r1,y1),Vector3(cos((a+b)*.5),0,sin((a+b)*.5)),solid)
	# Anéis de fechamento planos precisam de tampas reais para não se verem cornijas ocas.
	if absf(y1-y0)<.45:
		for i in 64:
			var a := TAU*i/64.0
			var b := TAU*(i+1)/64.0
			_site._triangle(material,Vector3(BASE_CENTER.x,y1,BASE_CENTER.z),_point(a,r1,y1),_point(b,r1,y1),Vector3.UP,solid)
