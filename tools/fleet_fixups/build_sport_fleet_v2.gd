extends "res://tools/fleet_fixups/build_sport_coupe_gt.gd"
## Esportivos 2.0 (27/10). Geração offline e determinística; no jogo só a cena assada é lida.
## A carroceria é um loft: seções transversais suaves (largura, cintura e coroa vêm de curvas
## cúbicas monótonas, sem ondular) costuradas ao longo do comprimento, com caixa de roda
## recortada na própria seção. Faróis, entradas de ar e frisos são remendos amostrados na
## mesma superfície e afastados pela normal: encaixam na curva em vez de boiar como caixas.
## As portas são folhas completas (lataria, vidro, cartão, espelho), como na frota civil nova.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tools/fleet_fixups/build_sport_fleet_v2.gd -- [--id=raijin_gt]
const CATALOG := preload("res://runtime/SportFleet.gd")
const COUNTS := preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const REPORT := "res://evidence/sport-fleet-v2-20261027/geometry.json"
## Linhas da lateral (fração entre soleira e cintura) e colunas do capô (fração da meia largura).
const SIDE_T := [0.0, .17, .35, .52, .68, .82, .93, 1.0]
const OUT_U := [0.0, .18, .44, .72, 1.0]
const IN_U := [0.0, .12, .28, .48, .72, 1.0]
## Estufa: frisos da cintura e da calha são as linhas extremas; o vidro fica entre elas.
const GS_T := [0.0, .09, .50, .91, 1.0]
const GT_U := [0.0, .07, .20, .40, .62, .82, 1.0]
const INTERIOR := Color("2a2d30")
const RUBBER := Color("1a1d20")
const CHROME := Color("c3ccd1")
const AMBER := Color("d98a2b")
const PLATE := Color("e6e4da")

var car_id := ""
var D := {}
var door := {}
var paint_color := Color.WHITE
var zf := 0.0
var zr := 0.0
var stations: Array[float] = []
var roof_keys: Array = []

const DESIGNS := {
	"raijin_gt": {"front":-2.355, "rear":2.355, "zf":-1.30, "zr":1.48, "wheel_r":.345, "track":.80, "wheel_w":.27, "rim":.70,
		"rim_style":"multi", "rim_color":"3b4045", "caliper":"d8732c", "tire":"sport", "arch":.385,
		"sill":[[-2.355,.31],[-2.05,.25],[2.0,.25],[2.355,.31]],
		"hw":[[-2.355,.70],[-2.27,.80],[-2.10,.86],[-1.70,.885],[0.0,.90],[1.80,.90],[2.18,.865],[2.355,.79]],
		"flare":.045, "flare_len":.62,
		"belt":[[-2.355,.66],[-2.22,.75],[-1.95,.84],[-1.30,.905],[-.70,.91],[.40,.92],[1.40,.97],[2.00,.98],[2.355,.95]],
		"crown":[[-2.355,0.0],[-2.10,.03],[-1.60,.06],[-.90,.05],[0.0,.04],[1.70,.03],[2.355,.012]],
		"edge":4.5, "tuck":.08, "tumble":.07, "hm":.48, "crease":[.70,.006], "inset":.07,
		"gh":{"zA":-.78, "zH":-.08, "zR":.80, "zC":1.66, "roof":[[-.42,1.16],[-.08,1.33],[.35,1.36],[.80,1.335],[1.25,1.13]],
			"tumble":.42, "rc":.045, "edge":3.5, "bow":.05, "side":[[-.70,.38],[.46,1.04]]}},
	"tauro_v10": {"front":-2.28, "rear":2.28, "zf":-1.25, "zr":1.37, "wheel_r":.35, "track":.84, "wheel_w":.29, "rim":.72,
		"rim_style":"y_spoke", "rim_color":"2a2d31", "caliper":"e8c228", "tire":"sport", "arch":.40,
		"sill":[[-2.28,.23],[-1.95,.17],[1.95,.17],[2.28,.25]],
		"hw":[[-2.28,.64],[-2.19,.79],[-1.97,.875],[-1.40,.895],[0.0,.88],[.80,.90],[1.50,.93],[2.10,.90],[2.28,.82]],
		"flare":.05, "flare_len":.60,
		"belt":[[-2.28,.50],[-2.12,.62],[-1.72,.76],[-1.25,.83],[-.70,.80],[.20,.79],[.90,.84],[1.37,.89],[1.90,.87],[2.28,.82]],
		"crown":[[-2.28,-.01],[-1.90,-.05],[-1.30,-.07],[-.95,-.05],[0.0,0.0],[1.00,-.02],[1.70,-.01],[2.28,0.0]],
		"edge":6.0, "tuck":.10, "tumble":.09, "hm":.45, "crease":[.58,.012], "inset":.10, "plate_y":.60,
		"gh":{"zA":-.98, "zH":-.20, "zR":.30, "zC":1.85, "roof":[[-.58,.99],[-.20,1.135],[.05,1.165],[.30,1.155],[.90,1.06],[1.42,.95]],
			"tumble":.62, "rc":.03, "edge":3.0, "bow":.02, "side":[[-.90,.30],[.37,.62]], "glass_end":.88}},
	"kite_type_s": {"front":-2.20, "rear":2.20, "zf":-1.33, "zr":1.24, "wheel_r":.30, "track":.73, "wheel_w":.21, "rim":.64,
		"rim_style":"five", "rim_color":"e9e9e4", "caliper":"c23030", "tire":"sport", "arch":.345,
		"sill":[[-2.20,.31],[-1.95,.27],[1.95,.27],[2.20,.31]],
		"hw":[[-2.20,.66],[-2.11,.76],[-1.92,.81],[-1.30,.835],[0.0,.84],[1.30,.84],[1.95,.82],[2.20,.76]],
		"flare":.015, "flare_len":.50,
		"belt":[[-2.20,.61],[-2.03,.71],[-1.33,.79],[-.90,.81],[0.0,.83],[1.20,.88],[1.80,.91],[2.20,.89]],
		"crown":[[-2.20,0.0],[-1.90,.03],[-1.30,.05],[-.80,.045],[0.0,.04],[1.50,.03],[2.20,.01]],
		"edge":4.0, "tuck":.07, "tumble":.08, "hm":.55, "crease":[.68,.006], "inset":.065,
		"gh":{"zA":-.80, "zH":-.04, "zR":.55, "zC":1.70, "roof":[[-.46,1.11],[-.04,1.29],[.25,1.31],[.55,1.29],[1.10,1.10]],
			"tumble":.45, "rc":.04, "edge":3.5, "bow":.05, "side":[[-.72,.40],[.48,1.04]]}},
	"lince_rs": {"front":-2.19, "rear":1.99, "zf":-1.40, "zr":1.27, "wheel_r":.33, "track":.80, "wheel_w":.24, "rim":.68,
		"rim_style":"multi", "rim_color":"1d2024", "caliper":"e8c228", "tire":"sport", "arch":.375,
		"sill":[[-2.19,.31],[-1.95,.26],[1.75,.26],[1.99,.33]],
		"hw":[[-2.19,.70],[-2.09,.80],[-1.86,.86],[-1.40,.87],[0.0,.88],[1.27,.88],[1.80,.86],[1.99,.80]],
		"flare":.05, "flare_len":.55,
		"belt":[[-2.19,.65],[-2.01,.74],[-1.60,.82],[-1.00,.87],[0.0,.90],[1.20,.95],[1.70,.975],[1.99,.955]],
		"crown":[[-2.19,0.0],[-1.90,.03],[-1.40,.05],[-.90,.045],[0.0,.03],[1.99,.01]],
		"edge":4.0, "tuck":.07, "tumble":.08, "hm":.52, "crease":[.66,.007], "inset":.07,
		"gh":{"zA":-.88, "zH":-.06, "zR":1.15, "zC":1.84, "roof":[[-.50,1.20],[-.06,1.39],[.50,1.43],[1.00,1.41],[1.15,1.39],[1.55,1.21]],
			"tumble":.40, "rc":.05, "edge":3.5, "bow":.05, "side":[[-.80,.28],[.37,1.08]]}},
	"brisa_s": {"front":-1.99, "rear":1.99, "zf":-1.06, "zr":1.25, "wheel_r":.31, "track":.74, "wheel_w":.21, "rim":.66,
		"rim_style":"six", "rim_color":"c9ced2", "caliper":"9aa3aa", "tire":"sport", "arch":.355,
		"sill":[[-1.99,.28],[-1.75,.22],[1.75,.22],[1.99,.28]],
		"hw":[[-1.99,.62],[-1.89,.74],[-1.66,.81],[-1.06,.85],[0.0,.83],[1.25,.86],[1.75,.82],[1.99,.74]],
		"flare":.03, "flare_len":.50,
		"belt":[[-1.99,.58],[-1.80,.67],[-1.40,.76],[-1.06,.79],[0.0,.77],[1.25,.83],[1.70,.83],[1.99,.79]],
		"crown":[[-1.99,-.01],[-1.60,-.03],[-1.10,-.04],[-.60,-.02],[.60,-.01],[1.99,0.0]],
		"edge":3.2, "tuck":.08, "tumble":.10, "hm":.50, "crease":[], "inset":.10, "roadster":true,
		"gh":{"zA":-.56, "zH":-.17, "zC":.68, "roof":[[-.17,1.10]], "tumble":.30, "rc":.03, "edge":3.0, "bow":0.0, "side":[]}},
	"sakura_s15": {"front":-2.23, "rear":2.23, "zf":-1.30, "zr":1.225, "wheel_r":.32, "track":.76, "wheel_w":.23, "rim":.66,
		"rim_style":"dish", "rim_color":"b58a52", "caliper":"c23030", "tire":"sport", "arch":.36,
		"sill":[[-2.23,.31],[-1.95,.26],[1.95,.26],[2.23,.31]],
		"hw":[[-2.23,.64],[-2.12,.76],[-1.90,.81],[-1.30,.825],[0.0,.82],[1.22,.83],[1.95,.81],[2.23,.76]],
		"flare":.03, "flare_len":.55,
		"belt":[[-2.23,.61],[-2.05,.70],[-1.60,.77],[-1.30,.80],[-1.00,.81],[0.0,.83],[1.20,.88],[1.90,.90],[2.23,.88]],
		"crown":[[-2.23,0.0],[-1.95,.03],[-1.40,.045],[-.80,.035],[1.60,.03],[2.23,.02]],
		"edge":4.5, "tuck":.07, "tumble":.07, "hm":.52, "crease":[.64,.006], "inset":.065,
		"gh":{"zA":-.74, "zH":-.02, "zR":.52, "zC":1.48, "roof":[[-.40,1.10],[-.02,1.27],[.25,1.285],[.52,1.27],[1.05,1.07]],
			"tumble":.42, "rc":.04, "edge":3.5, "bow":.05, "side":[[-.66,.36],[.44,.92]]}},
	"rapina_r": {"front":-2.76, "rear":2.76, "zf":-1.62, "zr":1.78, "wheel_r":.43, "track":.92, "wheel_w":.32, "rim":.52,
		"rim_style":"beadlock", "rim_color":"1b1e22", "caliper":"1b1e22", "tire":"offroad", "arch":.50, "arch_lift":.04,
		"sill":[[-2.76,.68],[-2.30,.55],[2.30,.55],[2.76,.70]],
		"hw":[[-2.76,.86],[-2.63,.94],[-2.30,.97],[0.0,.99],[2.60,.99],[2.76,.97]],
		"flare":.02, "flare_len":.70, "flare_band":.10, "cladding":.22,
		"belt":[[-2.76,1.08],[-2.50,1.16],[-1.70,1.23],[0.0,1.27],[.62,1.28],[2.76,1.29]],
		"crown":[[-2.76,.03],[-2.30,.07],[-1.40,.08],[-.90,.06],[0.0,.02]],
		"edge":9.0, "tuck":.03, "tumble":.04, "hm":.50, "crease":[.62,.008], "inset":.06, "pickup":true, "bed_floor":.98,
		"gh":{"zA":-.98, "zH":-.42, "zR":.52, "zC":.66, "roof":[[-.76,1.62],[-.42,1.95],[0.0,1.99],[.52,1.97],[.62,1.80]],
			"tumble":.12, "rc":.025, "edge":6.0, "bow":.02, "side":[[-.90,-.08],[.02,.50]]}},
	"bastiao_63": {"front":-2.46, "rear":2.46, "zf":-1.42, "zr":1.47, "wheel_r":.40, "track":.86, "wheel_w":.29, "rim":.60,
		"rim_style":"twin_five", "rim_color":"1b1e22", "caliper":"c23030", "tire":"allterrain", "arch":.46,
		"sill":[[-2.46,.56],[-2.20,.46],[2.20,.46],[2.46,.56]],
		"hw":[[-2.46,.88],[-2.40,.93],[-2.20,.94],[2.30,.94],[2.40,.93],[2.46,.89]],
		"flare":.035, "flare_len":.62,
		"belt":[[-2.46,1.00],[-2.30,1.05],[-1.50,1.08],[0.0,1.10],[2.46,1.10]],
		"crown":[[-2.46,.01],[-1.60,.02],[-1.00,.02],[2.46,0.0]],
		"edge":14.0, "tuck":.015, "tumble":.015, "hm":.50, "crease":[.74,.012], "inset":.05,
		"gh":{"zA":-.74, "zH":-.50, "zR":2.28, "zC":2.40, "roof":[[-.68,1.40],[-.50,1.93],[0.0,1.97],[2.0,1.97],[2.28,1.95],[2.36,1.55]],
			"tumble":.07, "rc":.012, "edge":8.0, "bow":0.0, "side":[[-.68,.02],[.10,1.30],[1.38,2.22]], "black_pillars":false}},
}

func _initialize() -> void: run.call_deferred()

## Contagem de triângulos por etapa do desenho (só para o relatório).
var phase := ""
var phase_tris := {}
func triangle(key: String, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	phase_tris[phase] = int(phase_tris.get(phase,0))+1
	super.triangle(key,a,b,c,outward)

# ---------------------------------------------------------------- curvas

func _secant(keys: Array, i: int) -> float:
	return (float(keys[i+1][1])-float(keys[i][1]))/maxf(float(keys[i+1][0])-float(keys[i][0]),.00001)

func _tangent(keys: Array, i: int) -> float:
	var n := keys.size()
	if i == 0: return _secant(keys,0)
	if i == n-1: return _secant(keys,n-2)
	var a := _secant(keys,i-1)
	var b := _secant(keys,i)
	if a*b <= 0.0: return 0.0
	var h0 := float(keys[i][0])-float(keys[i-1][0])
	var h1 := float(keys[i+1][0])-float(keys[i][0])
	return 3.0*(h0+h1)/((2.0*h1+h0)/a+(h1+2.0*h0)/b)

## Interpolação cúbica monótona (Fritsch–Carlson): passa pelos pontos sem criar calombo entre eles.
func cv(keys: Array, z: float) -> float:
	var n := keys.size()
	if n == 1 or z <= float(keys[0][0]): return float(keys[0][1])
	if z >= float(keys[n-1][0]): return float(keys[n-1][1])
	var i := 0
	while z > float(keys[i+1][0]): i += 1
	var h := float(keys[i+1][0])-float(keys[i][0])
	var t := (z-float(keys[i][0]))/h
	var m0 := _tangent(keys,i)*h
	var m1 := _tangent(keys,i+1)*h
	var t2 := t*t
	var t3 := t2*t
	return (2*t3-3*t2+1)*float(keys[i][1])+(t3-2*t2+t)*m0+(-2*t3+3*t2)*float(keys[i+1][1])+(t3-t2)*m1

# ---------------------------------------------------------------- superfície

func hw(z: float) -> float:
	var w := cv(D.hw,z)
	for a in [zf,zr]: w += float(D.flare)*exp(-pow((z-a)/float(D.flare_len),4))
	return w

func belt_y(z: float) -> float: return cv(D.belt,z)
func crown(z: float) -> float: return cv(D.crown,z)
func sill_y(z: float) -> float: return cv(D.sill,z)
func wheel_y() -> float: return float(D.wheel_r)
func arch_center_y() -> float: return wheel_y()+float(D.get("arch_lift",.02))

## Borda de baixo da lateral: soleira, ou o arco da caixa de roda.
func skirt_y(z: float) -> float:
	var y := sill_y(z)
	var r := float(D.arch)
	for a in [zf,zr]:
		var dz := absf(z-a)
		if dz < r: y = maxf(y, arch_center_y()+sqrt(r*r-dz*dz))
	return minf(y, sill_y(z)+(belt_y(z)-sill_y(z))*.86)

func side_x(z: float, h: float) -> float:
	var hm := float(D.hm)
	var f := 1.0
	if h < hm: f -= float(D.tuck)*pow((hm-h)/hm,2)
	else: f -= float(D.tumble)*pow((h-hm)/(1.0-hm),2)
	var x := hw(z)*f
	var c: Array = D.crease
	if not c.is_empty(): x -= float(c[1])*smoothstep(float(c[0])-.012,float(c[0])+.012,h)
	return x

func side_pt(z: float, h: float, s: float) -> Vector3:
	return Vector3(s*side_x(z,h), sill_y(z)+h*(belt_y(z)-sill_y(z)), z)

func top_y(z: float, u: float) -> float:
	var e := float(D.edge)
	return belt_y(z)+crown(z)*pow(maxf(0.0,1.0-pow(1.0-clampf(u,0.0,1.0),e)),1.0/e)

func top_pt(z: float, u: float, s: float) -> Vector3:
	return Vector3(s*side_x(z,1.0)*(1.0-u), top_y(z,u), z)

func ub(z: float) -> float: return float(D.inset)/side_x(z,1.0)
func u_at_x(z: float, x: float) -> float: return clampf(1.0-absf(x)/side_x(z,1.0),0.0,1.0)

func gh_base(z: float) -> Vector2: return Vector2(side_x(z,1.0)-float(D.inset), top_y(z,ub(z)))
func gh_edge(z: float) -> float: return cv(roof_keys,z)
func gh_xr(z: float) -> float:
	var b := gh_base(z)
	return maxf(.22, b.x-(gh_edge(z)-b.y)*tan(float(D.gh.tumble)))

## Estufa: w de 0 a 1 sobe a lateral (cintura → calha); de 1 a 2 atravessa o teto até o centro.
## Perto da base do para-brisa a seção copia a curva do capô, então o vidro nasce em cima dele.
func gh_pt(z: float, w: float, s: float) -> Vector3:
	var b := gh_base(z)
	var ye := gh_edge(z)
	var xr := gh_xr(z)
	if w <= 1.0:
		var x := lerpf(b.x,xr,w)+float(D.gh.bow)*sin(PI*w)*(ye-b.y)
		return Vector3(s*x, lerpf(b.y,ye,w), z)
	var u := w-1.0
	var x2 := xr*(1.0-u)
	var eg := float(D.gh.edge)
	var roof := ye+float(D.gh.rc)*pow(maxf(0.0,1.0-pow(1.0-u,eg)),1.0/eg)
	var hood := top_y(z,u_at_x(z,x2))+(ye-b.y)
	return Vector3(s*x2, lerpf(hood,roof,clampf((ye-b.y)/.14,0.0,1.0)), z)

func normal_at(surf: Callable, z: float, p: float, s: float) -> Vector3:
	var e := .004
	var dz: Vector3 = surf.call(z+e,p,s)-surf.call(z-e,p,s)
	var dp: Vector3 = surf.call(z,p+e,s)-surf.call(z,p-e,s)
	var n := dz.cross(dp).normalized()
	var at: Vector3 = surf.call(z,p,s)
	var radial := at-Vector3(0,(sill_y(z)+belt_y(z))*.5-.15,z)
	if n.dot(radial) < 0: n = -n
	return n

func on(surf: Callable, z: float, p: float, s: float, lift: float) -> Vector3:
	return surf.call(z,p,s)+normal_at(surf,z,p,s)*lift

## Remendo amostrado na superfície (lente, entrada de ar, friso): p0/p1 dão a faixa em cada t.
func patch(key: String, color: Color, s: float, surf: Callable, z0: float, z1: float, p0: Callable, p1: Callable, nz: int, np: int, lift: float) -> void:
	tint = color
	var grid := []
	for i in nz+1:
		var t := float(i)/nz
		var z := lerpf(z0,z1,t)
		var row := []
		for j in np+1:
			row.append(on(surf,z,lerpf(float(p0.call(t)),float(p1.call(t)),float(j)/np),s,lift))
		grid.append(row)
	for i in nz:
		var zc := lerpf(z0,z1,(i+.5)/nz)
		for j in np:
			var pc := lerpf(float(p0.call((i+.5)/nz)),float(p1.call((i+.5)/nz)),(j+.5)/np)
			quad(key,grid[i][j],grid[i+1][j],grid[i+1][j+1],grid[i][j+1],normal_at(surf,zc,pc,s))
	tint = Color.WHITE

func const_fn(v: float) -> Callable: return func(_t: float) -> float: return v
func lerp_fn(a: float, b: float) -> Callable: return func(t: float) -> float: return lerpf(a,b,t)
func arc_fn(a: float, b: float, bulge: float) -> Callable: return func(t: float) -> float: return lerpf(a,b,t)+bulge*sin(PI*t)

# ---------------------------------------------------------------- montagem

func material(key: String) -> StandardMaterial3D:
	if materials.has(key): return materials[key]
	var m := super.material(key)
	m.vertex_color_is_srgb = true
	if key == "paint": m.albedo_color = paint_color
	if key == "glass":
		m.albedo_color = Color("27404c")
		m.roughness = .16
	return m

func gh_on() -> bool: return D.has("gh")
func zA() -> float: return float(D.gh.zA)
func zH() -> float: return float(D.gh.zH)
func zC() -> float: return float(D.gh.zC)
func zR() -> float: return float(D.gh.get("zR",D.gh.zH))
func roadster() -> bool: return bool(D.get("roadster",false))
func pickup() -> bool: return bool(D.get("pickup",false))
func gh_end() -> float: return zH() if roadster() else zC()

func setup(id: String) -> void:
	car_id = id
	groups = {}
	materials = {}
	D = DESIGNS[id]
	door = CATALOG.door_spec(id)
	paint_color = Color.html(str(CATALOG.spec(id).colors[0]))
	zf = float(D.zf)
	zr = float(D.zr)
	roof_keys = [[zA(), gh_base(zA()).y]]
	roof_keys.append_array(D.gh.roof)
	if not roadster(): roof_keys.append([zC(), gh_base(zC()).y])
	var marks: Array[float] = [float(D.front), float(D.rear), float(door.zf), float(door.zr), zA(), zH(), zC(), zR(),
		zA()+.04, zA()+.05, zH()-.05, zR()+.05, zC()-.04, zC()-.05]
	for span: Array in D.gh.side:
		marks.append(float(span[0]))
		marks.append(float(span[1]))
	if D.gh.has("glass_end"):
		marks.append(float(D.gh.glass_end))
		marks.append(float(D.gh.glass_end)-.05)
	var zs: Array[float] = []
	var step := .085
	var count := int(ceil((float(D.rear)-float(D.front))/step))
	for i in count+1: zs.append(lerpf(float(D.front),float(D.rear),float(i)/count))
	for a in [zf,zr]:
		for k in 15: zs.append(a+float(D.arch)*cos(PI*k/14.0))
	# Pontas: estações extras onde a largura e a cintura viram o bico.
	for k in 6:
		zs.append(float(D.front)+.012*k*k)
		zs.append(float(D.rear)-.012*k*k)
	zs.sort()
	stations.clear()
	# Estações a pelo menos 3 cm umas das outras e das marcas (porta, para-brisa, colunas):
	# o arco e a grade uniforme se sobrepunham e dobravam a malha sem ganho de curva.
	for z in zs:
		if z < float(D.front)-.0001 or z > float(D.rear)+.0001: continue
		var keep := true
		for m in marks:
			if absf(z-m) < .03: keep = false
		if keep and (stations.is_empty() or z-stations[-1] > .03 or z < float(D.front)+.2 or z > float(D.rear)-.2): stations.append(z)
	for m in marks:
		if m < float(D.front)-.0001 or m > float(D.rear)+.0001: continue
		var found := false
		for z in stations:
			if absf(z-m) < .00001: found = true
		if not found: stations.append(m)
	stations.sort()
	model = Node3D.new()
	model.name = id.to_pascal_case()
	model.set_meta("fleet_finish",true)
	model.set_meta("fleet_redesign_version",2)
	model.set_meta("sport_fleet_version",2)
	# As correções de apply_fleet_fixups são para as cenas exportadas da V1 (lanterna descolada,
	# piloto de moto); aqui a lanterna já é amostrada na lataria, então nada a corrigir.
	model.set_meta("fleet_fixups",1)

func door_label(za: float, zb: float, s: float) -> String:
	if za >= float(door.zf)-.0001 and zb <= float(door.zr)+.0001: return "DoorL" if s < 0 else "DoorR"
	return "Body"

func has_inner(za: float, zb: float) -> bool:
	if zb <= zA()+.04+.0001: return true
	if pickup(): return false
	return za >= zC()-.04-.0001

func lower_section(z: float, s: float, inner: bool) -> Array:
	var pts := []
	var y0 := skirt_y(z)
	var h0 := (y0-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01)
	for t in SIDE_T: pts.append(side_pt(z,lerpf(h0,1.0,t),s))
	var b := ub(z)
	for k in range(1,OUT_U.size()): pts.append(top_pt(z,b*float(OUT_U[k]),s))
	if inner:
		for k in range(1,IN_U.size()): pts.append(top_pt(z,lerpf(b,1.0,float(IN_U[k])),s))
	return pts

func row_key(k: int, z: float) -> String:
	var clad := float(D.get("cladding",0.0))
	if clad > 0.0 and k < SIDE_T.size()-1:
		var h0 := (skirt_y(z)-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01)
		if lerpf(h0,1.0,float(SIDE_T[k+1])) <= clad+.001: return "clad"
	return "paint"

func lower_body() -> void:
	for s in [-1.0,1.0]:
		for i in stations.size()-1:
			var za := stations[i]
			var zb := stations[i+1]
			var inner := has_inner(za,zb)
			var a := lower_section(za,s,inner)
			var b := lower_section(zb,s,inner)
			active = door_label(za,zb,s)
			for k in a.size()-1:
				var key := row_key(k,za)
				var c: Vector3 = (a[k]+b[k+1])*.5
				var hint := c-Vector3(0,(sill_y(c.z)+belt_y(c.z))*.5-.15,c.z)
				if key == "clad":
					tint = RUBBER
					quad("detail",a[k],b[k],b[k+1],a[k+1],hint)
					tint = Color.WHITE
				else: quad("paint",a[k],b[k],b[k+1],a[k+1],hint)
	active = "Body"
	for end in [float(D.front),float(D.rear)]:
		var loop := []
		var inner := has_inner(end-.001,end+.001) if end < 0 else has_inner(end-.001,end)
		var right := lower_section(end,1.0,inner)
		var left := lower_section(end,-1.0,inner)
		loop.append_array(right)
		var back := left.duplicate()
		back.reverse()
		if inner: back.remove_at(0)
		loop.append_array(back)
		var center := Vector3.ZERO
		for p: Vector3 in loop: center += p
		center /= loop.size()
		var n := Vector3.FORWARD if end < 0 else Vector3.BACK
		for k in loop.size():
			triangle("paint",center,loop[k],loop[(k+1)%loop.size()],n)
	# Assoalho escuro: ninguém enxerga a cabine pelo vão de baixo.
	box("detail",Vector3(0,sill_y(0)+.03,0),Vector3(hw(0)*1.7,.03,float(D.rear)-float(D.front)-.30),RUBBER)

## Estufa: a classificação por faixa (friso, vidro, coluna) segue a grade, então as molduras ficam retas.
func greenhouse() -> void:
	var gz: Array[float] = []
	for z in stations:
		if z >= zA()-.0001 and z <= gh_end()+.0001: gz.append(z)
	var black_pillars := bool(D.gh.get("black_pillars",true))
	for s in [-1.0,1.0]:
		for i in gz.size()-1:
			var za := gz[i]
			var zb := gz[i+1]
			var zm := (za+zb)*.5
			var label := door_label(za,zb,s)
			# Lateral
			for k in GS_T.size()-1:
				var p := [gh_pt(za,GS_T[k],s),gh_pt(zb,GS_T[k],s),gh_pt(zb,GS_T[k+1],s),gh_pt(za,GS_T[k+1],s)]
				var hint := Vector3(s,.25,0)
				active = label
				if roadster():
					tint = RUBBER
					quad("detail",p[0],p[1],p[2],p[3],hint)
					continue
				var glass := false
				for span: Array in D.gh.side:
					if za >= float(span[0])-.0001 and zb <= float(span[1])+.0001: glass = true
				if k == 0 or not glass and black_pillars and k < GS_T.size()-2:
					tint = RUBBER
					quad("detail",p[0],p[1],p[2],p[3],hint)
				elif glass and k < GS_T.size()-2: quad("glass",p[0],p[1],p[2],p[3],hint)
				else: quad("paint",p[0],p[1],p[2],p[3],hint)
			tint = Color.WHITE
			active = "Body"
			# Teto, para-brisa e vigia
			for j in GT_U.size()-1:
				var q := [gh_pt(za,1.0+GT_U[j],s),gh_pt(zb,1.0+GT_U[j],s),gh_pt(zb,1.0+GT_U[j+1],s),gh_pt(za,1.0+GT_U[j+1],s)]
				var hint := Vector3(s*.3,1,0)
				var screen := zm < zH() or (zm > zR() and zm < float(D.gh.get("glass_end",99.0)))
				if roadster() and zm >= zH(): continue
				if not screen: quad("paint",q[0],q[1],q[2],q[3],hint)
				elif j == 0:
					if black_pillars:
						tint = RUBBER
						quad("detail",q[0],q[1],q[2],q[3],hint)
						tint = Color.WHITE
					else: quad("paint",q[0],q[1],q[2],q[3],hint)
				elif zm < zA()+.05 or (zm > zH()-.05 and zm < zH()) or (zm > zR() and zm < zR()+.05) or zm > minf(zC(),float(D.gh.get("glass_end",99.0)))-.05:
					tint = RUBBER
					quad("detail",q[0],q[1],q[2],q[3],hint)
					tint = Color.WHITE
				else: quad("glass",q[0],q[1],q[2],q[3],hint)
	if roadster():
		# Arco superior do para-brisa aberto: a moldura fecha a borda do vidro.
		for s in [-1.0,1.0]:
			for j in GT_U.size()-1:
				beam("detail",gh_pt(zH(),1.0+GT_U[j],s),gh_pt(zH(),1.0+GT_U[j+1],s),.035,RUBBER)
			beam("detail",gh_pt(zH(),1.0,s),gh_pt(zH(),0.0,s),.035,RUBBER)

func arches() -> void:
	var r := float(D.arch)
	var cy := arch_center_y()
	for s in [-1.0,1.0]:
		for a in [zf,zr]:
			var inner_x := float(D.track)-float(D.wheel_w)*.5-.05
			var pts_out := []
			var pts_in := []
			for j in 17:
				var th := PI*j/16.0
				var z: float = a+cos(th)*r
				var y := cy+sin(th)*r
				if y < sill_y(z)-.02: y = sill_y(z)-.02
				var h := (y-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01)
				pts_out.append(Vector3(s*(side_x(z,clampf(h,0,1))-.004),y,z))
				pts_in.append(Vector3(s*inner_x,y-.01,z))
			active = "Body"
			tint = RUBBER
			for j in 16: quad("detail",pts_out[j],pts_out[j+1],pts_in[j+1],pts_in[j],Vector3(0,-1,0))
			# Parede interna da caixa: o olhar pelo arco encontra plástico escuro, não a cabine.
			var c := Vector3(s*inner_x,cy,a)
			for j in 16: triangle("detail",c,pts_in[j],pts_in[j+1],Vector3(s,0,0))
			quad("detail",Vector3(s*inner_x,cy,a-r),Vector3(s*inner_x,cy,a+r),Vector3(s*inner_x,sill_y(a)-.05,a+r),Vector3(s*inner_x,sill_y(a)-.05,a-r),Vector3(s,0,0))
			# Friso do arco (ou alargador de plástico na picape) acompanha a lateral.
			var band := float(D.get("flare_band",0.0))
			for j in 16:
				var z0: float = pts_out[j].z
				var z1: float = pts_out[j+1].z
				active = door_label(minf(z0,z1),maxf(z0,z1),s)
				if band > 0.0:
					var th0 := PI*j/16.0
					var th1 := PI*(j+1)/16.0
					var o0 := arch_band_pt(a,th0,r+band,s,.022)
					var o1 := arch_band_pt(a,th1,r+band,s,.022)
					var i0 := arch_band_pt(a,th0,r,s,.03)
					var i1 := arch_band_pt(a,th1,r,s,.03)
					quad("detail",i0,i1,o1,o0,Vector3(s,0,0))
					quad("detail",pts_out[j],pts_out[j+1],i1,i0,Vector3(s,-.5,0))
				else:
					beam("detail",pts_out[j]+Vector3(s*.004,0,0),pts_out[j+1]+Vector3(s*.004,0,0),.014,RUBBER)
			tint = Color.WHITE
	active = "Body"

func arch_band_pt(a: float, th: float, rr: float, s: float, lift: float) -> Vector3:
	var z := a+cos(th)*rr
	var y := maxf(arch_center_y()+sin(th)*rr, sill_y(z)-.02)
	var h := clampf((y-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01),0.0,1.0)
	var p := side_pt(z,h,s)
	return Vector3(p.x+s*lift,y,z)

## Folha da porta: cartão interno, espessura nas bordas, frestas e batentes do vão.
func doors() -> void:
	var z0 := float(door.zf)
	var z1 := float(door.zr)
	var inner := minf(side_x(z0,.5),side_x(z1,.5))-.075
	for s in [-1.0,1.0]:
		active = "DoorL" if s < 0 else "DoorR"
		var ylo := maxf(skirt_y(z0),skirt_y(z1))+.04
		var yhi := minf(belt_y(z0),belt_y(z1))-.025
		tint = INTERIOR
		quad("detail",Vector3(s*inner,ylo,z0+.02),Vector3(s*inner,ylo,z1-.02),Vector3(s*inner,yhi,z1-.02),Vector3(s*inner,yhi,z0+.02),Vector3(-s,0,0))
		box("detail",Vector3(s*(inner-.03),lerpf(ylo,yhi,.62),lerpf(z0,z1,.42)),Vector3(.05,.05,.32),Color("3b3f43"))
		box("detail",Vector3(s*(inner-.012),lerpf(ylo,yhi,.30),lerpf(z0,z1,.35)),Vector3(.02,.16,.30),Color("232628"))
		for z in [z0,z1]:
			# box() devolve a cor a branco: as bordas reafirmam a cor escura.
			tint = Color("232628")
			for k in range(1,SIDE_T.size()):
				var h := float(SIDE_T[k])
				var cur := side_pt(z,lerpf((skirt_y(z)-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01),1.0,h),s)
				var p0 := side_pt(z,lerpf((skirt_y(z)-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01),1.0,float(SIDE_T[k-1])),s)
				quad("detail",p0,cur,Vector3(s*inner,cur.y,z),Vector3(s*inner,p0.y,z),Vector3.FORWARD if z == z0 else Vector3.BACK)
		# Topo da porta na cintura, entre a lataria e o cartão.
		var top_a := gh_pt(z0+.02,0.0,s) if not roadster() else top_pt(z0+.02,ub(z0+.02),s)
		var top_b := gh_pt(z1-.02,0.0,s) if not roadster() else top_pt(z1-.02,ub(z1-.02),s)
		tint = INTERIOR
		quad("detail",top_a,top_b,Vector3(s*inner,top_b.y-.01,z1-.02),Vector3(s*inner,top_a.y-.01,z0+.02),Vector3.UP)
		tint = Color.WHITE
		# Frestas: linhas escuras finas presas à folha.
		for z in [z0+.004,z1-.004]:
			var h0 := (skirt_y(z)-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01)
			for k in 8:
				var a := on(side_pt,z,lerpf(h0,1.0,k/8.0),s,.002)
				var b := on(side_pt,z,lerpf(h0,1.0,(k+1)/8.0),s,.002)
				beam("detail",a,b,.007,RUBBER)
		# Maçaneta embutida e espelho.
		var hz := lerpf(z0,z1,.80)
		patch("detail",CHROME,s,side_pt,hz-.07,hz+.07,const_fn(.80),const_fn(.86),2,1,.006)
		patch("detail",RUBBER,s,side_pt,hz-.06,hz+.06,const_fn(.81),const_fn(.85),2,1,.008)
		mirror(s)
		active = "Body"
		# Batentes do vão, um pouco para dentro da folha para não brigar com ela fechada.
		tint = RUBBER
		for jamb in [[z0-.012,Vector3.BACK],[z1+.012,Vector3.FORWARD]]:
			var z: float = jamb[0]
			quad("detail",Vector3(s*(side_x(z,.5)-.012),skirt_y(z),z),Vector3(s*(side_x(z,.5)-.012),belt_y(z),z),Vector3(s*(inner-.05),belt_y(z),z),Vector3(s*(inner-.05),skirt_y(z),z),jamb[1])
		box("detail",Vector3(s*(inner-.02),sill_y(0)+.10,(z0+z1)*.5),Vector3(.10,.14,z1-z0-.04),Color("1f2224"))
		tint = Color.WHITE
	active = "Body"

func mirror(s: float) -> void:
	var z := float(door.zf)+.16
	var base := gh_pt(z,.12,s) if not roadster() else top_pt(z,ub(z)*.5,s)
	var big := pickup() or car_id == "bastiao_63"
	var size := Vector3(.10,.15,.20) if big else Vector3(.085,.095,.17)
	var reach := .16 if big else .12
	var c := base+Vector3(s*reach,.06,.02)
	beam("detail",base+Vector3(s*.01,.0,.03),c-Vector3(s*size.x*.4,.0,-.02),.03,RUBBER)
	box("paint",c,size)
	box("detail",c+Vector3(s*.004,0,size.z*.5+.002),Vector3(size.x*.8,size.y*.8,.006),Color("8ea0a8"))
	box("detail",c+Vector3(s*size.x*.45,-size.y*.28,-.02),Vector3(.012,.018,size.z*.6),AMBER)

func underbody_and_plates() -> void:
	active = "Body"
	var f := float(D.front)
	var r := float(D.rear)
	box("detail",Vector3(0,sill_y(f)+.10,f-.006),Vector3(.52,.11,.012),PLATE)
	box("detail",Vector3(0,sill_y(f)+.10,f-.009),Vector3(.48,.08,.006),Color("5a6066"))
	var rear_plate_y := float(D.get("plate_y",lerpf(sill_y(r),belt_y(r),.42)))
	box("detail",Vector3(0,rear_plate_y,r+.006),Vector3(.52,.11,.012),PLATE)
	box("detail",Vector3(0,rear_plate_y,r+.009),Vector3(.48,.08,.006),Color("5a6066"))
	box("detail",Vector3(0,rear_plate_y+.075,r+.012),Vector3(.12,.012,.02),CHROME)

func wipers() -> void:
	if roadster(): return
	active = "Body"
	var z := zA()+.07
	for x in [-.38,.18]:
		var a := gh_pt(z,1.0+u_of(z,absf(x)),signf(x) if x != 0 else 1.0)
		var b := gh_pt(z+.04,1.0+u_of(z+.04,absf(x+.42)),signf(x+.42))
		beam("detail",a+Vector3(0,.012,0),b+Vector3(0,.012,0),.012,RUBBER)

func u_of(z: float, x: float) -> float: return clampf(1.0-x/gh_xr(z),0.0,1.0)

# ---------------------------------------------------------------- rodas

func wheels_v2() -> void:
	var R := float(D.wheel_r)
	var W := float(D.wheel_w)*.5
	var rim := R*float(D.rim)
	var rim_color := Color.html(str(D.rim_color))
	var style := str(D.rim_style)
	var tire := str(D.tire)
	for s in [-1.0,1.0]:
		for a in [zf,zr]:
			active = "Wheel_%s_%s" % ["L" if s < 0 else "R","F" if a < 0 else "R"]
			var c := Vector3(s*float(D.track),R,a)
			# Perfil do pneu: talão, flanco arredondado, ombro e banda de rodagem.
			var bulge := .015 if tire == "sport" else .03
			var profile := [Vector2(-W*.90,rim),Vector2(-W-bulge,rim+(R-rim)*.50),Vector2(-W*.96,R-.022),Vector2(-W*.78,R),
				Vector2(W*.78,R),Vector2(W*.96,R-.022),Vector2(W+bulge,rim+(R-rim)*.50),Vector2(W*.90,rim)]
			var segs := 28
			for j in profile.size()-1:
				for i in segs:
					var t0 := TAU*i/segs
					var t1 := TAU*(i+1)/segs
					var pa: Vector2 = profile[j]
					var pb: Vector2 = profile[j+1]
					tint = Color("202427") if j == 3 else Color("2a2f33")
					if j == 3 and tire != "sport" and i % 2 == 0: tint = Color("16191b")
					quad("wheel",c+Vector3(s*pa.x,sin(t0)*pa.y,cos(t0)*pa.y),c+Vector3(s*pa.x,sin(t1)*pa.y,cos(t1)*pa.y),
						c+Vector3(s*pb.x,sin(t1)*pb.y,cos(t1)*pb.y),c+Vector3(s*pb.x,sin(t0)*pb.y,cos(t0)*pb.y),Vector3(s*(pa.x+pb.x),sin(t0+.1),cos(t0+.1)))
			# Garras do pneu de terra: blocos alternados na banda.
			if tire != "sport":
				var lugs := 24
				for i in lugs:
					var t := TAU*i/lugs
					var side := W*.44*(1.0 if i % 2 == 0 else -1.0)
					var radial := Vector3(0,sin(t),cos(t))
					var tangent := Vector3(0,cos(t),-sin(t))
					box_oriented("wheel",c+Vector3(s*side,0,0)+radial*(R-.007),radial,tangent,Vector3(W*.66,.014,.055),Color("1c1f22"))
			# Fundo do aro escuro, disco de freio e a face com o desenho do aro.
			var face := c+Vector3(s*W*.84,0,0)
			ellipse("wheel",c+Vector3(s*W*.15,0,0),Vector3.UP,Vector3.BACK,rim*.98,0,Vector3(s,0,0),Color("15181a"),20)
			ellipse("wheel",c+Vector3(s*W*.42,0,0),Vector3.UP,Vector3.BACK,rim*.80,rim*.30,Vector3(s,0,0),Color("7d8489"),24)
			for i in 12:
				var t := TAU*i/12.0
				ellipse("wheel",c+Vector3(s*W*.425,sin(t)*rim*.55,cos(t)*rim*.55),Vector3.UP,Vector3.BACK,.010,0,Vector3(s,0,0),Color("3a3f43"),5)
			ellipse("wheel",face,Vector3.UP,Vector3.BACK,rim*1.03,rim*.93,Vector3(s,0,0),rim_color.lightened(.12),28)
			ellipse("wheel",face-Vector3(s*.012,0,0),Vector3.UP,Vector3.BACK,rim*.94,rim*.90,Vector3(s,0,0),rim_color.darkened(.25),28)
			rim_face(style,face,s,rim,rim_color)
			tint = Color.WHITE
			# Pinça fixa na carroceria: não gira com a roda.
			active = "Body"
			box("detail",c+Vector3(-s*W*.05,rim*.48,(.11 if a < 0 else -.11)),Vector3(.05,rim*.38,rim*.32),Color.html(str(D.caliper)))
	active = "Body"

func box_oriented(key: String, at: Vector3, up: Vector3, along: Vector3, size: Vector3, color: Color) -> void:
	tint = color
	var x := Vector3.RIGHT*size.x*.5
	var y := up.normalized()*size.y*.5
	var z := along.normalized()*size.z*.5
	var p := [at-x-y-z,at+x-y-z,at+x+y-z,at-x+y-z,at-x-y+z,at+x-y+z,at+x+y+z,at-x+y+z]
	quad(key,p[0],p[1],p[2],p[3],-z)
	quad(key,p[4],p[5],p[6],p[7],z)
	quad(key,p[3],p[2],p[6],p[7],y)
	quad(key,p[0],p[1],p[5],p[4],-y)
	quad(key,p[0],p[3],p[7],p[4],-x)
	quad(key,p[1],p[2],p[6],p[5],x)
	tint = Color.WHITE

## Raio com espessura: face afinando do cubo para o aro e duas paredes laterais.
func spoke(face: Vector3, s: float, ang: float, r0: float, r1: float, w0: float, w1: float, depth: float, color: Color, dish := 0.0) -> void:
	var radial := Vector3(0,sin(ang),cos(ang))
	var tangent := Vector3(0,cos(ang),-sin(ang))
	var out := Vector3(s,0,0)
	var a0 := face+radial*r0-tangent*w0*.5+out*.010
	var b0 := face+radial*r0+tangent*w0*.5+out*.010
	var a1 := face+radial*r1-tangent*w1*.5-out*dish
	var b1 := face+radial*r1+tangent*w1*.5-out*dish
	tint = color
	quad("wheel",a0,b0,b1,a1,out)
	tint = color.darkened(.35)
	quad("wheel",a0,a1,a1-out*depth,a0-out*depth,-tangent)
	quad("wheel",b0,b1,b1-out*depth,b0-out*depth,tangent)

func rim_face(style: String, face: Vector3, s: float, rim: float, color: Color) -> void:
	var hub := rim*.24
	match style:
		"five":
			for j in 5: spoke(face,s,TAU*j/5.0+.3,hub,rim*.92,.075,.055,.035,color,.012)
		"six":
			for j in 6: spoke(face,s,TAU*j/6.0,hub,rim*.92,.058,.05,.035,color,.008)
		"multi":
			for j in 10: spoke(face,s,TAU*j/10.0,hub,rim*.93,.030,.036,.03,color,.015)
		"y_spoke":
			for j in 5:
				var ang := TAU*j/5.0
				spoke(face,s,ang,hub,rim*.55,.05,.042,.035,color,.006)
				for k in [-1.0,1.0]:
					var mid := face+Vector3(0,sin(ang),cos(ang))*rim*.52
					spoke(mid,s,ang+k*.32,0.0,rim*.43,.034,.026,.03,color,.01)
		"dish":
			# Prato fundo: raios recuados e uma aba larga polida.
			ellipse("wheel",face+Vector3(s*.004,0,0),Vector3.UP,Vector3.BACK,rim*.93,rim*.74,Vector3(s,0,0),CHROME,28)
			for j in 5: spoke(face-Vector3(s*.03,0,0),s,TAU*j/5.0+.2,hub,rim*.75,.07,.06,.03,color,0.0)
		"beadlock":
			ellipse("wheel",face+Vector3(s*.006,0,0),Vector3.UP,Vector3.BACK,rim*1.04,rim*.86,Vector3(s,0,0),color.lightened(.2),28)
			for j in 16:
				var t := TAU*j/16.0
				ellipse("wheel",face+Vector3(s*.012,sin(t)*rim*.95,cos(t)*rim*.95),Vector3.UP,Vector3.BACK,.011,0,Vector3(s,0,0),CHROME,6)
			for j in 6: spoke(face,s,TAU*j/6.0,hub,rim*.86,.10,.12,.04,color,.02)
		"twin_five":
			for j in 5:
				for k in [-1.0,1.0]: spoke(face,s,TAU*j/5.0+k*.11,hub,rim*.92,.034,.032,.035,color,.012)
	ellipse("wheel",face+Vector3(s*.013,0,0),Vector3.UP,Vector3.BACK,hub*1.15,0,Vector3(s,0,0),color.darkened(.2),16)
	for j in 5:
		var t := TAU*j/5.0
		ellipse("wheel",face+Vector3(s*.016,sin(t)*hub*.62,cos(t)*hub*.62),Vector3.UP,Vector3.BACK,.009,0,Vector3(s,0,0),CHROME,6)
	ellipse("wheel",face+Vector3(s*.018,0,0),Vector3.UP,Vector3.BACK,hub*.42,0,Vector3(s,0,0),Color("2a2e31"),12)

# ---------------------------------------------------------------- luzes e frente

func lens(label: String, key: String, s: float, surf: Callable, z0: float, z1: float, p0: Callable, p1: Callable, nz: int, np: int, bezel := RUBBER, glow := Color.WHITE) -> void:
	active = "Body"
	var grow := func(f: Callable, d: float) -> Callable: return func(t: float) -> float: return float(f.call(t))+d
	patch("detail",bezel,s,surf,z0-.012,z1+.012,grow.call(p0,-.012),grow.call(p1,.012),nz,np,.004)
	active = label
	patch(key,glow,s,surf,z0,z1,p0,p1,nz,np,.008)
	active = "Body"

func head_label(s: float) -> String: return "HeadlightL" if s < 0 else "HeadlightR"

## Plano da frente (z constante): peças apoiadas no para-choque.
func front_plate(key: String, x: float, y: float, w: float, h: float, color: Color, depth := .02, label := "Body") -> void:
	active = label
	box(key,Vector3(x,y,float(D.front)-depth*.5),Vector3(w,h,depth),color)
	active = "Body"

func rear_plate(key: String, x: float, y: float, w: float, h: float, color: Color, depth := .02, label := "Body") -> void:
	active = label
	box(key,Vector3(x,y,float(D.rear)+depth*.5),Vector3(w,h,depth),color)
	active = "Body"

func front_ring(key: String, x: float, y: float, r: float, inner: float, color: Color, lift := .012, label := "Body") -> void:
	active = label
	ellipse(key,Vector3(x,y,float(D.front)-lift),Vector3.RIGHT,Vector3.UP,r,inner,Vector3.FORWARD,color,24)
	active = "Body"

func rear_ring(key: String, x: float, y: float, r: float, inner: float, color: Color, lift := .012, label := "Body") -> void:
	active = label
	ellipse(key,Vector3(x,y,float(D.rear)+lift),Vector3.RIGHT,Vector3.UP,r,inner,Vector3.BACK,color,24)
	active = "Body"

func slats_front(x: float, y: float, w: float, h: float, count: int, color: Color) -> void:
	front_plate("detail",x,y,w,h,Color("121416"),.012)
	for i in count:
		front_plate("detail",x,y-h*.5+h*(i+.5)/count,w*.98,h*.28/count,color,.024)

func exhaust(x: float, y: float, r: float, shape := "round") -> void:
	active = "Body"
	var z := float(D.rear)+.035
	if shape == "hex":
		ellipse("detail",Vector3(x,y,z),Vector3.RIGHT,Vector3.UP,r,r*.78,Vector3.BACK,CHROME,6)
		ellipse("detail",Vector3(x,y,z-.02),Vector3.RIGHT,Vector3.UP,r*.78,0,Vector3.BACK,Color("0d0f10"),6)
	elif shape == "oval":
		ellipse("detail",Vector3(x,y,z),Vector3.RIGHT*1.4,Vector3.UP,r,r*.80,Vector3.BACK,CHROME,20)
		ellipse("detail",Vector3(x,y,z-.02),Vector3.RIGHT*1.4,Vector3.UP,r*.80,0,Vector3.BACK,Color("0d0f10"),20)
	else:
		ellipse("detail",Vector3(x,y,z),Vector3.RIGHT,Vector3.UP,r,r*.80,Vector3.BACK,CHROME,20)
		ellipse("detail",Vector3(x,y,z-.02),Vector3.RIGHT,Vector3.UP,r*.80,0,Vector3.BACK,Color("0d0f10"),20)
	tint = CHROME
	for i in 12:
		var t0 := TAU*i/12.0
		var t1 := TAU*(i+1)/12.0
		var k := 1.4 if shape == "oval" else 1.0
		quad("detail",Vector3(x+cos(t0)*r*k,y+sin(t0)*r,z),Vector3(x+cos(t1)*r*k,y+sin(t1)*r,z),Vector3(x+cos(t1)*r*k,y+sin(t1)*r,z-.06),Vector3(x+cos(t0)*r*k,y+sin(t0)*r,z-.06),Vector3(cos(t0),sin(t0),0))
	tint = Color.WHITE

func diffuser(width: float, fins: int, height := .10) -> void:
	var r := float(D.rear)
	var y := sill_y(r)+.02
	active = "Body"
	box("detail",Vector3(0,y+height*.5,r-.02),Vector3(width,height,.06),Color("15181a"))
	for i in fins:
		var x := lerpf(-width*.42,width*.42,float(i)/maxf(fins-1,1))
		box("detail",Vector3(x,y+height*.5,r-.07),Vector3(.012,height*1.05,.22),Color("202427"))

func splitter(width: float, depth := .10, color := RUBBER) -> void:
	var f := float(D.front)
	active = "Body"
	box("detail",Vector3(0,sill_y(f)-.005,f+depth*.3),Vector3(width,.022,depth),color)

func side_skirt(color := RUBBER) -> void:
	active = "Body"
	for s in [-1.0,1.0]:
		var a := zf+float(D.arch)+.03
		var b := zr-float(D.arch)-.03
		patch("detail",color,s,side_pt,a,b,const_fn(0.0),const_fn(.08),10,1,.012)

func hood_line(u: float, z0: float, z1: float) -> void:
	active = "Body"
	for s in [-1.0,1.0]:
		for k in 10:
			var za := lerpf(z0,z1,k/10.0)
			var zb := lerpf(z0,z1,(k+1)/10.0)
			beam("detail",on(top_pt,za,u,s,.003),on(top_pt,zb,u,s,.003),.006,RUBBER)

func cross_line(z: float, u0: float) -> void:
	active = "Body"
	for s in [-1.0,1.0]:
		for k in 10:
			beam("detail",on(top_pt,z,lerpf(u0,1.0,k/10.0),s,.003),on(top_pt,z,lerpf(u0,1.0,(k+1)/10.0),s,.003),.006,RUBBER)

# ---------------------------------------------------------------- desenho de cada carro

func features() -> void:
	call("features_"+car_id)

func features_raijin_gt() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	for s in [-1.0,1.0]:
		# Farol bumerangue varrido para trás sobre o para-lama.
		lens(head_label(s),"headlight",s,top_pt,f+.03,f+.46,lerp_fn(.05,.03),arc_fn(.36,.13,.05),7,3)
		active = "Body"
		patch("detail",Color("eef4f6"),s,top_pt,f+.05,f+.40,lerp_fn(.065,.04),lerp_fn(.09,.055),6,1,.011)
		patch("detail",AMBER,s,top_pt,f+.38,f+.46,const_fn(.035),const_fn(.11),1,1,.011)
		# Saída de ar no para-lama, acima e atrás da roda dianteira (antes da porta).
		patch("detail",Color("121416"),s,side_pt,zf+.27,zf+.43,lerp_fn(.62,.70),lerp_fn(.90,.88),3,2,.004)
		for k in 3: patch("detail",CHROME,s,side_pt,zf+.29+k*.05,zf+.30+k*.05,lerp_fn(.66,.70),const_fn(.87),1,1,.007)
	# Grade trapezoidal grande, entradas laterais e lábio.
	slats_front(0,sill_y(f)+.24,.70,.20,6,Color("3a3f44"))
	front_plate("detail",0,sill_y(f)+.355,.74,.018,CHROME,.03)
	for x in [-.52,.52]:
		front_plate("detail",x,sill_y(f)+.15,.26,.13,Color("121416"),.012)
		front_plate("detail",x,sill_y(f)+.15,.22,.02,Color("3a3f44"),.02)
	splitter(1.50,.12)
	hood_line(.28,f+.08,zA()-.05)
	cross_line(zA()-.06,.28)
	# Dois respiros no capô.
	for s in [-1.0,1.0]:
		patch("detail",Color("121416"),s,top_pt,-1.55,-1.35,const_fn(.50),const_fn(.70),3,2,.004)
	# Quatro lanternas redondas — a assinatura do GT.
	for s in [-1.0,1.0]:
		for x in [.36,.62]:
			rear_ring("detail",s*x,belt_y(r)-.11,.09,.075,RUBBER,.010)
			rear_ring("tail",s*x,belt_y(r)-.11,.075,.042,Color.WHITE,.016,"Tail")
			rear_ring("detail",s*x,belt_y(r)-.11,.042,0.0,Color("3a1214"),.014)
	diffuser(1.20,7,.12)
	for s in [-1.0,1.0]:
		for x in [.40,.56]: exhaust(s*x,sill_y(r)+.12,.045)
	# Asa alta em dois pedestais.
	active = "Body"
	for s in [-1.0,1.0]:
		beam("detail",top_pt(2.06,.30,s)+Vector3(0,-.01,0),Vector3(s*.58,1.10,2.16),.045,RUBBER)
	box("paint",Vector3(0,1.115,2.17),Vector3(1.62,.028,.24))
	for s in [-1.0,1.0]: box("detail",Vector3(s*.82,1.10,2.17),Vector3(.012,.10,.28),RUBBER)
	side_skirt()

func features_tauro_v10() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	for s in [-1.0,1.0]:
		# Farol fino em cunha com a assinatura em Y.
		lens(head_label(s),"headlight",s,top_pt,f+.05,f+.34,lerp_fn(.10,.05),lerp_fn(.24,.15),5,2)
		active = "Body"
		patch("detail",Color("eef4f6"),s,top_pt,f+.08,f+.30,lerp_fn(.13,.09),lerp_fn(.145,.10),4,1,.011)
		patch("detail",Color("eef4f6"),s,top_pt,f+.16,f+.20,const_fn(.10),const_fn(.22),1,2,.011)
		# Entrada lateral enorme na frente da roda traseira, com aletas.
		# Tomada de ar do motor: triângulo que sobe em direção à roda traseira, com uma lâmina.
		patch("detail",Color("101214"),s,side_pt,.48,.98,const_fn(.30),lerp_fn(.42,.86),6,3,.004)
		patch("detail",Color("2f3337"),s,side_pt,.62,.97,const_fn(.52),const_fn(.57),4,1,.008)
		# Lâmina na soleira.
		patch("detail",Color("1b1e22"),s,side_pt,zf+.45,zr-.45,const_fn(0.0),lerp_fn(.10,.14),10,1,.012)
	# Boca hexagonal e duas tomadas grandes.
	front_plate("detail",0,sill_y(f)+.13,.62,.10,Color("101214"),.012)
	for x in [-.48,.48]:
		front_plate("detail",x,sill_y(f)+.14,.34,.16,Color("101214"),.012)
		for i in 3: front_plate("detail",x,sill_y(f)+.08+i*.055,.30,.012,Color("2a2d31"),.022)
	splitter(1.60,.14)
	hood_line(.30,f+.10,zA()-.05)
	# Tampa do motor com venezianas, na própria superfície da estufa atrás da vigia.
	active = "Body"
	for k in 7:
		var z := .98+k*.115
		for s in [-1.0,1.0]: patch("detail",Color("101214"),s,gh_pt,z,z+.055,const_fn(1.30),const_fn(2.0),1,3,.004)
	# Lanterna fina atravessada e hexágonos nas pontas.
	rear_plate("detail",0,belt_y(r)-.06,1.40,.07,RUBBER,.012)
	rear_plate("tail",0,belt_y(r)-.06,1.32,.028,Color.WHITE,.02,"Tail")
	for s in [-1.0,1.0]:
		rear_ring("tail",s*.60,belt_y(r)-.06,.08,.05,Color.WHITE,.022,"Tail")
	diffuser(1.40,9,.16)
	exhaust(-.16,sill_y(r)+.11,.065,"hex")
	exhaust(.16,sill_y(r)+.11,.065,"hex")
	# Lábio da tampa traseira.
	active = "Body"
	box("paint",Vector3(0,belt_y(r)+.025,r-.04),Vector3(1.50,.03,.10))

func features_kite_type_s() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var y := belt_y(f)-.08
	# Quatro faróis redondos numa faixa escura — o "quatro olhos".
	front_plate("detail",0,y,1.20,.13,Color("121416"),.012)
	for s in [-1.0,1.0]:
		for x in [.36,.52]:
			front_ring("detail",s*x,y,.065,.055,CHROME,.016)
			front_ring("headlight",s*x,y,.055,0.0,Color.WHITE,.020,head_label(s))
		front_plate("detail",s*.20,y-.005,.12,.05,AMBER,.022)
	front_plate("detail",0,y+.002,.18,.05,Color("2a2d31"),.024)
	front_plate("detail",0,y+.002,.05,.035,Color("c23030"),.03)
	# Boca inferior e lábio.
	front_plate("detail",0,sill_y(f)+.12,.90,.13,Color("121416"),.012)
	for i in 3: front_plate("detail",0,sill_y(f)+.07+i*.045,.84,.010,Color("2a2d31"),.022)
	splitter(1.30,.08)
	hood_line(.24,f+.06,zA()-.05)
	cross_line(zA()-.06,.24)
	# Faixa vermelha atravessada na traseira com a placa no meio.
	rear_plate("detail",0,belt_y(r)-.10,1.46,.13,RUBBER,.012)
	for s in [-1.0,1.0]:
		rear_plate("tail",s*.47,belt_y(r)-.10,.50,.10,Color.WHITE,.02,"Tail")
		rear_plate("detail",s*.47,belt_y(r)-.125,.48,.012,Color("e9e9e4"),.026)
	rear_plate("detail",0,belt_y(r)-.10,.36,.10,Color("8a1f24"),.02)
	exhaust(.48,sill_y(r)+.06,.045)
	# Asa alta na tampa.
	active = "Body"
	for s in [-1.0,1.0]: beam("detail",top_pt(2.0,.42,s),Vector3(s*.56,1.06,2.06),.035,RUBBER)
	box("paint",Vector3(0,1.075,2.08),Vector3(1.44,.025,.20))
	for s in [-1.0,1.0]: box("paint",Vector3(s*.72,1.055,2.08),Vector3(.012,.07,.22))
	side_skirt()

func features_lince_rs() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	for s in [-1.0,1.0]:
		# Farol anguloso com o "C" de LED.
		lens(head_label(s),"headlight",s,top_pt,f+.03,f+.30,lerp_fn(.04,.03),arc_fn(.36,.20,.03),5,3)
		active = "Body"
		patch("detail",Color("eef4f6"),s,top_pt,f+.05,f+.08,const_fn(.06),const_fn(.30),1,2,.011)
		patch("detail",Color("eef4f6"),s,top_pt,f+.05,f+.26,const_fn(.05),const_fn(.07),3,1,.011)
		# Lanterna bumerangue na quina da tampa.
		lens("Tail","tail",s,side_pt,r-.24,r-.02,lerp_fn(.78,.70),lerp_fn(.92,.96),4,2,RUBBER,Color.WHITE)
	# Grade em colmeia larga, faróis de neblina e lábio.
	front_plate("detail",0,sill_y(f)+.20,1.10,.24,Color("101214"),.012)
	for i in 5:
		for j in 9:
			front_plate("detail",-.44+j*.11+(.055 if i % 2 == 1 else 0.0),sill_y(f)+.11+i*.045,.05,.022,Color("33383c"),.022)
	for x in [-.66,.66]:
		front_ring("detail",x,sill_y(f)+.12,.045,0.0,Color("eef4f6"),.016)
	splitter(1.40,.10,Color("e8c228"))
	hood_line(.26,f+.06,zA()-.05)
	# Aerofólio de teto sobre a vigia.
	active = "Body"
	var zs := zR()-.02
	box("paint",Vector3(0,gh_edge(zs)+.045,zs+.14),Vector3(1.24,.03,.26))
	for s in [-1.0,1.0]: box("paint",Vector3(s*.61,gh_edge(zs)+.02,zs+.14),Vector3(.03,.07,.26))
	diffuser(1.10,5,.12)
	exhaust(-.08,sill_y(r)+.10,.05)
	exhaust(.08,sill_y(r)+.10,.05)
	side_skirt()

func features_brisa_s() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	for s in [-1.0,1.0]:
		# Faróis ovais sobre as quinas do capô.
		lens(head_label(s),"headlight",s,top_pt,f+.04,f+.30,arc_fn(.09,.12,-.02),arc_fn(.26,.20,.04),6,3)
		active = "Body"
		patch("detail",AMBER,s,top_pt,f+.05,f+.10,const_fn(.20),const_fn(.25),1,1,.011)
		lens("Tail","tail",s,side_pt,r-.20,r-.03,lerp_fn(.66,.64),lerp_fn(.86,.90),4,2,RUBBER,Color.WHITE)
		# Guelras atrás da roda dianteira.
		for k in 2: patch("detail",Color("121416"),s,side_pt,zf+.40+k*.05,zf+.42+k*.05,const_fn(.48),const_fn(.70),1,1,.004)
	# Boca oval larga.
	active = "Body"
	ellipse("detail",Vector3(0,sill_y(f)+.15,f-.012),Vector3.RIGHT*.46,Vector3.UP*.11,1.0,0.0,Vector3.FORWARD,Color("101214"),24)
	for i in 3: front_plate("detail",0,sill_y(f)+.10+i*.05,.78,.010,Color("2a2d31"),.022)
	splitter(1.10,.06)
	diffuser(1.10,5,.09)
	rear_plate("detail",0,belt_y(r)-.07,.70,.025,CHROME,.014)
	exhaust(-.30,sill_y(r)+.08,.04)
	exhaust(.30,sill_y(r)+.08,.04)
	cockpit()

## Roadster aberto: banco, painel, volante, laterais e arcos de proteção ficam à vista.
func cockpit() -> void:
	active = "Body"
	var z0 := zA()+.02
	var z1 := zC()-.04
	var floor_y := sill_y(0)+.07
	var wall := gh_base(0).x-.015
	# Laterais internas da cabine (na porta, o cartão já é a parede).
	tint = INTERIOR
	for s in [-1.0,1.0]:
		for span in [[z0,float(door.zf)-.02],[float(door.zr)+.02,z1]]:
			quad("detail",Vector3(s*wall,floor_y,span[0]),Vector3(s*wall,floor_y,span[1]),Vector3(s*wall,belt_y(span[1])-.01,span[1]),Vector3(s*wall,belt_y(span[0])-.01,span[0]),Vector3(-s,0,0))
	quad("detail",Vector3(-wall,floor_y,z1),Vector3(wall,floor_y,z1),Vector3(wall,top_y(z1,1.0),z1),Vector3(-wall,top_y(z1,1.0),z1),Vector3.FORWARD)
	tint = Color.WHITE
	box("detail",Vector3(0,floor_y,(z0+z1)*.5),Vector3(wall*2,.02,z1-z0),Color("1d1f21"))
	# Painel e capuz dos instrumentos.
	box("detail",Vector3(0,belt_y(z0)-.05,z0+.10),Vector3(wall*2-.02,.16,.22),INTERIOR)
	box("detail",Vector3(-.36,belt_y(z0)+.06,z0+.13),Vector3(.30,.06,.14),Color("1d1f21"))
	box("detail",Vector3(0,floor_y+.18,z0+.45),Vector3(.20,.24,.60),Color("232628"))
	# Volante do lado do motorista (x negativo).
	var hub := Vector3(-.36,belt_y(z0)+.02,z0+.34)
	ellipse("detail",hub,Vector3.RIGHT,Vector3(0,.82,.57),.18,.155,Vector3(0,-.57,.82),Color("1b1d1f"),24)
	for k in 3:
		var t := PI*.5+TAU*k/3.0
		beam("detail",hub,hub+Vector3(cos(t)*.155,sin(t)*.155*.82,sin(t)*.155*.57),.022,Color("2c2f32"))
	# Bancos.
	var seat := Color("6b4a35")
	for x in [-.36,.36]:
		box("detail",Vector3(x,floor_y+.11,.06),Vector3(.44,.12,.46),seat)
		box_oriented("detail",Vector3(x,floor_y+.40,.34),Vector3(0,.96,.28),Vector3(0,-.28,.96),Vector3(.44,.56,.11),seat)
		box("detail",Vector3(x,floor_y+.71,.42),Vector3(.24,.16,.08),seat.darkened(.15))
		# Arco de proteção atrás de cada banco.
		var base := Vector3(x,top_y(z1+.08,.8),z1+.10)
		for k in 8:
			var a := PI*k/8.0
			var b := PI*(k+1)/8.0
			beam("detail",base+Vector3(cos(a)*.20,sin(a)*.32,0),base+Vector3(cos(b)*.20,sin(b)*.32,0),.035,CHROME)

func features_sakura_s15() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	for s in [-1.0,1.0]:
		# Farol estreito puxado para trás.
		lens(head_label(s),"headlight",s,top_pt,f+.02,f+.40,lerp_fn(.05,.05),arc_fn(.36,.13,.02),6,2)
		active = "Body"
		patch("detail",AMBER,s,top_pt,f+.03,f+.08,const_fn(.06),const_fn(.18),1,1,.011)
		patch("detail",Color("3a3f44"),s,top_pt,f+.10,f+.32,lerp_fn(.13,.10),lerp_fn(.22,.14),3,1,.011)
	# Boca larga embaixo e fenda fina em cima.
	front_plate("detail",0,sill_y(f)+.13,1.06,.14,Color("101214"),.012)
	for i in 2: front_plate("detail",0,sill_y(f)+.10+i*.06,1.0,.012,Color("2a2d31"),.022)
	front_plate("detail",0,belt_y(f)-.05,.46,.035,Color("101214"),.012)
	splitter(1.32,.09)
	hood_line(.25,f+.06,zA()-.05)
	cross_line(zA()-.06,.25)
	# Lanternas finas e o friso atravessando a tampa.
	rear_plate("detail",0,belt_y(r)-.08,1.50,.10,RUBBER,.012)
	for s in [-1.0,1.0]:
		rear_plate("tail",s*.54,belt_y(r)-.08,.38,.075,Color.WHITE,.02,"Tail")
		rear_plate("detail",s*.54,belt_y(r)-.08,.36,.010,Color("e9e9e4"),.026)
	rear_plate("detail",0,belt_y(r)-.08,.66,.075,Color("5a1418"),.02)
	exhaust(.50,sill_y(r)+.08,.055,"oval")
	# Rabo de pato.
	active = "Body"
	box("paint",Vector3(0,top_y(r-.05,1.0)+.03,r-.07),Vector3(1.38,.035,.12))
	side_skirt()

func features_rapina_r() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := sill_y(f)+.30
	# Grade enorme com barra e "letras" em bloco (só geometria).
	front_plate("detail",0,gy,1.52,.36,Color("101214"),.014)
	front_plate("detail",0,gy+.02,1.30,.055,Color("2a2d31"),.026)
	for i in 6: front_plate("detail",-.45+i*.18,gy+.02,.11,.075,Color("3a3f44"),.034)
	for s in [-1.0,1.0]:
		# Farol em C nas pontas da grade.
		front_plate("detail",s*.70,gy+.06,.26,.22,RUBBER,.018)
		front_plate("headlight",s*.70,gy+.06,.20,.15,Color.WHITE,.026,head_label(s))
		front_plate("detail",s*.70,gy-.045,.22,.02,AMBER,.032)
		front_plate("detail",s*.58,gy+.06,.02,.17,Color("eef4f6"),.032)
	# Três marcadores âmbar na grade e três no teto.
	for x in [-.12,0.0,.12]:
		front_plate("detail",x,gy+.15,.07,.025,AMBER,.03)
		active = "Body"
		box("detail",Vector3(x,gh_pt(zH()+.08,2.0,1.0).y+.012,zH()+.08),Vector3(.07,.025,.04),AMBER)
	# Para-choque de aço, protetor e ganchos vermelhos.
	front_plate("detail",0,sill_y(f)+.06,1.70,.14,Color("2a2d31"),.05)
	for x in [-.52,.52]: front_plate("detail",x,sill_y(f)+.06,.06,.10,Color("b8282e"),.08)
	splitter(1.10,.30,Color("4a5056"))
	# Dois respiros no capô.
	for s in [-1.0,1.0]:
		patch("detail",Color("101214"),s,top_pt,-2.20,-1.85,const_fn(.42),const_fn(.62),3,2,.004)
	hood_line(.22,f+.08,zA()-.05)
	# Caçamba: assoalho, paredes internas, frente e tampa.
	active = "Body"
	var z0 := zC()
	var bed_floor := float(D.bed_floor)
	tint = Color("1d2022")
	for s in [-1.0,1.0]:
		var xs := []
		for k in 13:
			var z := lerpf(z0,r-.06,k/12.0)
			xs.append(Vector3(s*gh_base(z).x,top_y(z,ub(z)),z))
		tint = Color("1d2022")
		for k in 12:
			quad("detail",xs[k],xs[k+1],Vector3(xs[k+1].x,bed_floor,xs[k+1].z),Vector3(xs[k].x,bed_floor,xs[k].z),Vector3(-s,0,0))
		# Caixa da roda dentro da caçamba.
		box("detail",Vector3(s*(gh_base(zr).x-.14),bed_floor+.13,zr),Vector3(.28,.26,.95),Color("26292c"))
	var w := gh_base(z0).x
	tint = Color("1d2022")
	quad("detail",Vector3(-w,bed_floor,z0),Vector3(w,bed_floor,z0),Vector3(w,top_y(z0,ub(z0)),z0),Vector3(-w,top_y(z0,ub(z0)),z0),Vector3.BACK)
	var wr := gh_base(r-.06).x
	quad("detail",Vector3(-wr,bed_floor,r-.06),Vector3(wr,bed_floor,r-.06),Vector3(wr,top_y(r-.06,ub(r-.06)),r-.06),Vector3(-wr,top_y(r-.06,ub(r-.06)),r-.06),Vector3.FORWARD)
	box("detail",Vector3(0,bed_floor,(z0+r)*.5),Vector3(w*2,.02,r-z0-.06),Color("1d2022"))
	for k in 7: box("detail",Vector3(-w+.12+k*(w*2-.24)/6.0,bed_floor+.012,(z0+r)*.5),Vector3(.03,.012,r-z0-.12),Color("2c3033"))
	tint = Color.WHITE
	# Frisos da porta traseira (cabine dupla) presos à carroceria.
	for s in [-1.0,1.0]:
		for z in [float(door.zr)+.004,zC()-.06]:
			var h0 := (skirt_y(z)-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01)
			for k in 8: beam("detail",on(side_pt,z,lerpf(h0,1.0,k/8.0),s,.002),on(side_pt,z,lerpf(h0,1.0,(k+1)/8.0),s,.002),.007,RUBBER)
		patch("detail",CHROME,s,side_pt,zC()-.22,zC()-.10,const_fn(.80),const_fn(.86),2,1,.006)
		# Estribo tubular.
		box("detail",Vector3(s*(hw(0)-.02),sill_y(0)-.06,(float(door.zf)+zC())*.5),Vector3(.12,.04,zC()-float(door.zf)+.10),Color("2a2d31"))
	# Lanternas verticais altas, para-choque traseiro e maçaneta da tampa.
	for s in [-1.0,1.0]:
		rear_plate("detail",s*.86,belt_y(r)-.20,.16,.40,RUBBER,.012)
		rear_plate("tail",s*.86,belt_y(r)-.20,.12,.34,Color.WHITE,.02,"Tail")
	rear_plate("detail",0,belt_y(r)-.08,.22,.06,Color("2a2d31"),.03)
	rear_plate("detail",0,sill_y(r)+.06,1.86,.16,Color("2a2d31"),.06)
	exhaust(.62,sill_y(r)+.02,.05)

func features_bastiao_63() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var ly := belt_y(f)-.16
	for s in [-1.0,1.0]:
		# Farol redondo com anel de LED, e a seta em cima do para-lama.
		front_ring("detail",s*.64,ly,.125,.105,CHROME,.014)
		front_ring("headlight",s*.64,ly,.105,0.0,Color.WHITE,.020,head_label(s))
		front_ring("detail",s*.64,ly,.07,.06,Color("eef4f6"),.026)
		active = "Body"
		var pod := top_pt(f+.10,.10,s)
		box("detail",pod+Vector3(0,.035,0),Vector3(.11,.07,.16),Color("1b1e22"))
		box("detail",pod+Vector3(0,.05,-.07),Vector3(.09,.05,.025),AMBER)
	# Grade de três lâminas.
	front_plate("detail",0,ly,.82,.30,Color("101214"),.012)
	for i in 3: front_plate("paint",0,ly-.10+i*.10,.80,.035,Color.WHITE,.026)
	front_plate("detail",0,ly,.82,.30,CHROME,.006)
	# Para-choque saliente com neblina.
	front_plate("detail",0,sill_y(f)+.12,1.80,.20,Color("1b1e22"),.10)
	for x in [-.62,.62]: front_ring("detail",x,sill_y(f)+.12,.05,0.0,Color("eef4f6"),.105)
	hood_line(.06,f+.03,zA()-.03)
	# Bagageiro no teto.
	active = "Body"
	for s in [-1.0,1.0]:
		box("detail",Vector3(s*(gh_xr(.8)-.06),gh_edge(.8)+.04,.8),Vector3(.04,.04,2.6),Color("1b1e22"))
		for z in [-.30,.8,1.9]: box("detail",Vector3(s*(gh_xr(z)-.06),gh_edge(z)+.02,z),Vector3(.05,.04,.06),Color("1b1e22"))
	# Escapes laterais antes da roda traseira.
	for s in [-1.0,1.0]:
		for k in 2:
			var c := Vector3(s*(hw(zr-.62)+.02),sill_y(0)+.02,zr-.66+k*.09)
			ellipse("detail",c,Vector3.FORWARD,Vector3.UP,.04,.03,Vector3(s,0,0),CHROME,16)
			ellipse("detail",c+Vector3(s*.002,0,0),Vector3.FORWARD,Vector3.UP,.03,0,Vector3(s,0,0),Color("0d0f10"),16)
		# Dobradiças externas da porta e friso da porta traseira.
		for y in [.62,.94]: box("detail",Vector3(s*(side_x(float(door.zf),.5)+.012),y,float(door.zf)+.04),Vector3(.03,.07,.07),Color("1b1e22"))
		for z in [float(door.zr)+.004,1.30]:
			var h0 := (skirt_y(z)-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01)
			for k in 8: beam("detail",on(side_pt,z,lerpf(h0,1.0,k/8.0),s,.002),on(side_pt,z,lerpf(h0,1.0,(k+1)/8.0),s,.002),.007,RUBBER)
		patch("detail",CHROME,s,side_pt,1.10,1.22,const_fn(.80),const_fn(.86),2,1,.006)
	# Lanternas verticais e estepe na porta traseira.
	for s in [-1.0,1.0]:
		rear_plate("detail",s*.80,belt_y(r)-.22,.14,.30,RUBBER,.012)
		rear_plate("tail",s*.80,belt_y(r)-.22,.10,.26,Color.WHITE,.02,"Tail")
	active = "Body"
	var sc := Vector3(0,belt_y(r)+.05,r+.13)
	box("detail",sc-Vector3(0,0,.07),Vector3(.18,.18,.10),Color("1b1e22"))
	tint = Color.WHITE
	for i in 24:
		var t0 := TAU*i/24.0
		var t1 := TAU*(i+1)/24.0
		quad("paint",sc+Vector3(cos(t0),sin(t0),0)*.36,sc+Vector3(cos(t1),sin(t1),0)*.36,sc+Vector3(cos(t1),sin(t1),0)*.36-Vector3(0,0,.22),sc+Vector3(cos(t0),sin(t0),0)*.36-Vector3(0,0,.22),Vector3(cos(t0),sin(t0),0))
	ellipse("paint",sc,Vector3.RIGHT,Vector3.UP,.36,0.0,Vector3.BACK,Color.WHITE,24)
	ellipse("detail",sc+Vector3(0,0,.004),Vector3.RIGHT,Vector3.UP,.30,.27,Vector3.BACK,CHROME,24)
	rear_plate("detail",0,sill_y(r)+.10,1.80,.18,Color("1b1e22"),.08)

# ---------------------------------------------------------------- assar

func cabin_meta() -> Dictionary:
	var floor_y := sill_y(0)+.07
	var seat := float(door.seat_z)
	var kind := "pickup" if pickup() else ("suv" if car_id == "bastiao_63" else "sport")
	var spec := {"kind":kind, "floor":floor_y, "belt":float(door.belt), "roof":gh_edge(0.0) if not roadster() else float(door.top),
		"hw":gh_base(0.0).x-.06, "wz0":zA(), "wz1":zH(), "rear":gh_end(), "rear_top":zR() if not roadster() else zH(), "sx":-.36, "sz":seat}
	if roadster(): spec.merge({"open_top":true, "cush":floor_y+.17, "roof":1.20},true)
	return spec

func bake() -> Dictionary:
	var nodes := {}
	for bucket: String in groups:
		var parts := bucket.split("/")
		var label := parts[0]
		var key := parts[1]
		if not nodes.has(label):
			var n := MeshInstance3D.new()
			n.name = label
			n.mesh = ArrayMesh.new()
			model.add_child(n)
			n.owner = model
			nodes[label] = n
		var node: MeshInstance3D = nodes[label]
		var st: SurfaceTool = groups[bucket]
		st.index()
		# Roda também: com normal por face a banda do pneu acendia em blocos e parecia quebrada.
		if key in ["paint","glass","wheel"]: st = soften(st)
		st.set_material(material(key))
		st.commit(node.mesh)
		var roles: Array = node.get_meta("sport_surface_material_keys",[])
		roles.append(key)
		node.set_meta("sport_surface_material_keys",roles)
	for s in [-1,1]:
		var leaf: MeshInstance3D = nodes["DoorL" if s < 0 else "DoorR"]
		leaf.set_meta("new_civilian_door_side",s)
		leaf.set_meta("new_civilian_door_hinge",Vector3(s*side_x(float(door.zf),.5),0,float(door.zf)))
	for s in [-1.0,1.0]:
		for a in [zf,zr]:
			var n: MeshInstance3D = nodes["Wheel_%s_%s" % ["L" if s < 0 else "R","F" if a < 0 else "R"]]
			n.set_meta("wheel_center",Vector3(s*float(D.track),float(D.wheel_r),a))
			n.set_meta("wheel_spins",true)
	model.set_meta("vehicle_interior_spec",cabin_meta())
	var bounds := AABB()
	var first := true
	for n: MeshInstance3D in nodes.values():
		var b := n.mesh.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	var path := "res://assets/fleet/redesigned/"+car_id+".scn"
	var packed := PackedScene.new()
	packed.pack(model)
	var err := ResourceSaver.save(packed,path,ResourceSaver.FLAG_BUNDLE_RESOURCES)
	var result := COUNTS.counts(model)
	var per_node := {}
	for n: MeshInstance3D in nodes.values(): per_node[n.name] = n.mesh.get_faces().size()/3
	result["nodes"] = per_node
	result["path"] = path
	result["save_error"] = err
	result["bounds_size"] = [snappedf(bounds.size.x,.01),snappedf(bounds.size.y,.01),snappedf(bounds.size.z,.01)]
	result["bounds_min_y"] = snappedf(bounds.position.y,.001)
	result["door_suggestion"] = {"zf":door.zf,"zr":door.zr,"belt":snappedf(minf(belt_y(float(door.zf)),belt_y(float(door.zr))),.01),
		"top":snappedf(gh_edge((float(door.zf)+float(door.zr))*.5) if not roadster() else 1.10,.01),"x":snappedf(side_x((float(door.zf)+float(door.zr))*.5,.5),.01)}
	result["interior"] = cabin_meta()
	model.free()
	return result

func run() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--id="): only = arg.trim_prefix("--id=")
	var metrics := {}
	if FileAccess.file_exists(REPORT): metrics = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	for id: String in CATALOG.IDS:
		if not only.is_empty() and id != only: continue
		setup(id)
		phase_tris = {}
		for step in ["lower_body","greenhouse","arches","doors","underbody_and_plates","wipers","features","wheels_v2"]:
			phase = step
			call(step)
		metrics[id] = bake()
		metrics[id]["phases"] = phase_tris.duplicate()
		metrics[id]["stations"] = stations.size()
		print("SPORT_V2_BAKED ",id," ",JSON.stringify(metrics[id]))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT.get_base_dir()))
	FileAccess.open(REPORT,FileAccess.WRITE).store_string(JSON.stringify(metrics,"\t"))
	quit()
