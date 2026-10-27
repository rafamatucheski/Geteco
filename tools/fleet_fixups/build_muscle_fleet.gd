extends "res://tools/fleet_fixups/build_sport_fleet_v2.gd"
## Muscle cars e lowriders (27/10). Mesmo loft do gerador dos esportivos 2.0; aqui entram as peças
## que a escola americana pede: para-choque cromado que contorna a ponta, faixas sobre capô e teto,
## tomadas no capô, teto de vinil, saias de para-lama, estepe "continental", rodas raiadas cromadas
## com pneu de faixa branca e cabine de banco inteiriço nos lowriders.
## Os lowriders saem assados na altura mais baixa; a hidráulica levanta a carroceria em jogo
## (gameplay/lowrider/LowriderHydraulics.gd), por isso a pinça de freio fica fora (clássicos têm
## tambor) e nada da carroceria entra na malha das rodas.
## Uso: tools/run_godot_locked.sh --headless --path . --script res://tools/fleet_fixups/build_muscle_fleet.gd -- [--id=potro_68]
const MUSCLE := preload("res://runtime/MuscleFleet.gd")
const MUSCLE_REPORT := "res://evidence/muscle-lowrider-20261027/geometry.json"
const WHITEWALL := Color("e8e6dc")
const BLACK := Color("101214")
const VINYL := Color("1f1d1c")

const MUSCLE_DESIGNS := {
	"potro_68": {"front":-2.35, "rear":2.35, "zf":-1.31, "zr":1.43, "wheel_r":.335, "track":.76, "wheel_w":.24, "rim":.62,
		"rim_style":"slot", "rim_color":"c3ccd1", "caliper":"", "tire":"sport", "arch":.375,
		"sill":[[-2.35,.32],[-2.05,.25],[2.05,.25],[2.35,.33]],
		"hw":[[-2.35,.72],[-2.28,.83],[-2.10,.875],[-1.30,.885],[0.0,.89],[1.43,.90],[2.10,.875],[2.35,.80]],
		"flare":.012, "flare_len":.55,
		"belt":[[-2.35,.68],[-2.24,.78],[-2.0,.83],[-1.3,.86],[-.82,.875],[0.0,.88],[.9,.90],[1.6,.92],[2.15,.93],[2.35,.90]],
		"crown":[[-2.35,0.0],[-2.10,.02],[-1.40,.035],[-.85,.03],[0.0,.02],[1.5,.015],[2.35,.01]],
		"edge":5.0, "tuck":.07, "tumble":.06, "hm":.55, "crease":[.70,.006], "inset":.08,
		"fplate":[.40,.065], "rplate":[.42,0.0],
		"gh":{"zA":-.80, "zH":-.12, "zR":.32, "zC":1.95, "roof":[[-.46,1.10],[-.12,1.29],[.15,1.31],[.32,1.30],[.80,1.19],[1.30,1.06],[1.70,.98]],
			"tumble":.40, "rc":.04, "edge":3.5, "bow":.04, "side":[[-.70,.28]], "glass_end":1.20, "black_pillars":false}},
	"jararaca_v10": {"front":-2.245, "rear":2.245, "zf":-1.17, "zr":1.27, "wheel_r":.345, "track":.82, "wheel_w":.29, "rim":.70,
		"rim_style":"five", "rim_color":"c9ced2", "caliper":"c23030", "tire":"sport", "arch":.39,
		"sill":[[-2.245,.26],[-1.95,.20],[1.95,.20],[2.245,.27]],
		"hw":[[-2.245,.60],[-2.17,.74],[-2.0,.84],[-1.5,.92],[-1.17,.94],[-.6,.915],[0.0,.90],[.7,.925],[1.27,.95],[1.9,.925],[2.245,.84]],
		"flare":.025, "flare_len":.60,
		"belt":[[-2.245,.52],[-2.12,.63],[-1.85,.72],[-1.2,.80],[-.65,.84],[0.0,.82],[.6,.83],[1.27,.88],[1.9,.90],[2.245,.86]],
		"crown":[[-2.245,0.0],[-1.90,.03],[-1.30,.07],[-.75,.06],[0.0,.02],[1.2,.01],[2.245,0.0]],
		"edge":3.0, "tuck":.10, "tumble":.12, "hm":.45, "crease":[], "inset":.12,
		"gh":{"zA":-.62, "zH":-.02, "zR":.40, "zC":1.45, "roof":[[-.36,1.02],[-.02,1.19],[.20,1.205],[.40,1.19],[.85,1.06],[1.15,.98]],
			"tumble":.55, "rc":.05, "edge":2.8, "bow":.03, "side":[[-.48,.38]], "glass_end":1.0}},
	"carcara_ss": {"front":-2.36, "rear":2.36, "zf":-1.30, "zr":1.44, "wheel_r":.34, "track":.78, "wheel_w":.25, "rim":.63,
		"rim_style":"rally", "rim_color":"3b4045", "caliper":"", "tire":"sport", "arch":.38,
		"sill":[[-2.36,.31],[-2.05,.25],[2.05,.25],[2.36,.31]],
		"hw":[[-2.36,.76],[-2.28,.86],[-2.10,.90],[-1.30,.92],[-.40,.915],[0.0,.91],[.8,.925],[1.44,.94],[2.10,.91],[2.36,.84]],
		"flare":.02, "flare_len":.55,
		"belt":[[-2.36,.70],[-2.24,.78],[-2.0,.82],[-1.3,.85],[-.80,.86],[0.0,.87],[1.0,.88],[1.8,.89],[2.36,.87]],
		"crown":[[-2.36,0.0],[-2.10,.015],[-1.30,.03],[-.85,.03],[0.0,.02],[1.2,.02],[2.36,.01]],
		"edge":6.0, "tuck":.06, "tumble":.07, "hm":.52, "crease":[.66,.008], "inset":.09,
		"fplate":[.40,.055], "rplate":[.40,0.0],
		"gh":{"zA":-.78, "zH":-.10, "zR":.55, "zC":1.45, "roof":[[-.44,1.10],[-.10,1.285],[.20,1.305],[.55,1.29],[1.05,1.10],[1.30,1.0]],
			"tumble":.40, "rc":.04, "edge":3.5, "bow":.04, "side":[[-.68,.40],[.48,.88]], "black_pillars":false}},
	"trovao_440": {"front":-2.64, "rear":2.64, "zf":-1.47, "zr":1.55, "wheel_r":.345, "track":.80, "wheel_w":.25, "rim":.62,
		"rim_style":"torq", "rim_color":"c3ccd1", "caliper":"", "tire":"sport", "arch":.385,
		"sill":[[-2.64,.31],[-2.30,.25],[2.30,.25],[2.64,.31]],
		"hw":[[-2.64,.80],[-2.58,.88],[-2.40,.93],[-1.47,.955],[-.60,.935],[0.0,.93],[.70,.945],[1.55,.975],[2.30,.955],[2.64,.90]],
		"flare":0.0, "flare_len":.55,
		"belt":[[-2.64,.74],[-2.52,.80],[-2.25,.84],[-1.47,.87],[-.80,.88],[0.0,.89],[1.0,.90],[1.9,.91],[2.64,.90]],
		"crown":[[-2.64,0.0],[-2.30,.01],[-1.50,.025],[-.95,.02],[0.0,.02],[1.6,.01],[2.64,0.0]],
		"edge":7.0, "tuck":.07, "tumble":.06, "hm":.55, "crease":[.62,.006], "inset":.10,
		"fplate":[.41,.065], "rplate":[.40,0.0],
		"gh":{"zA":-.90, "zH":-.20, "zR":.50, "zC":1.95, "roof":[[-.55,1.12],[-.20,1.32],[.10,1.345],[.50,1.335],[1.00,1.20],[1.50,1.06],[1.80,.97]],
			"tumble":.38, "rc":.04, "edge":3.8, "bow":.04, "side":[[-.80,.42]], "glass_end":1.25, "black_pillars":false}},
	"caiman_454": {"front":-2.50, "rear":2.50, "zf":-1.36, "zr":1.48, "wheel_r":.34, "track":.79, "wheel_w":.25, "rim":.62,
		"rim_style":"rally", "rim_color":"8f979c", "caliper":"", "tire":"sport", "arch":.38,
		"sill":[[-2.50,.32],[-2.20,.26],[2.20,.26],[2.50,.33]],
		"hw":[[-2.50,.82],[-2.44,.90],[-2.25,.935],[-1.36,.945],[0.0,.94],[1.48,.955],[2.25,.94],[2.50,.88]],
		"flare":.01, "flare_len":.55,
		"belt":[[-2.50,.76],[-2.40,.81],[-2.15,.85],[-1.36,.87],[-.80,.88],[0.0,.89],[1.2,.91],[2.0,.92],[2.50,.91]],
		"crown":[[-2.50,0.0],[-2.25,.01],[-1.40,.02],[-.95,.02],[0.0,.02],[1.5,.015],[2.50,.01]],
		"edge":9.0, "tuck":.05, "tumble":.05, "hm":.60, "crease":[.74,.008], "inset":.10,
		"fplate":[.41,.07], "rplate":[.66,0.0],
		"gh":{"zA":-.92, "zH":-.22, "zR":.42, "zC":1.72, "roof":[[-.56,1.13],[-.22,1.33],[.10,1.35],[.42,1.335],[.95,1.17],[1.40,1.03]],
			"tumble":.38, "rc":.03, "edge":4.5, "bow":.03, "side":[[-.80,.38],[.46,.95]], "black_pillars":false}},
	"brasa_hc": {"front":-2.515, "rear":2.515, "zf":-1.44, "zr":1.51, "wheel_r":.36, "track":.86, "wheel_w":.30, "rim":.72,
		"rim_style":"y_spoke", "rim_color":"1d2024", "caliper":"e2672c", "tire":"sport", "arch":.40,
		"sill":[[-2.515,.30],[-2.25,.24],[2.25,.24],[2.515,.31]],
		"hw":[[-2.515,.80],[-2.45,.90],[-2.25,.955],[-1.44,.975],[0.0,.96],[1.51,.985],[2.25,.97],[2.515,.92]],
		"flare":.03, "flare_len":.65,
		"belt":[[-2.515,.74],[-2.40,.82],[-2.15,.86],[-1.44,.90],[-.80,.92],[0.0,.93],[1.2,.95],[2.0,.97],[2.515,.96]],
		"crown":[[-2.515,0.0],[-2.20,.01],[-1.50,.02],[-.95,.02],[0.0,.02],[1.6,.015],[2.515,.01]],
		"edge":9.0, "tuck":.06, "tumble":.05, "hm":.58, "crease":[.70,.01], "inset":.11,
		"gh":{"zA":-.80, "zH":-.12, "zR":.55, "zC":1.70, "roof":[[-.47,1.20],[-.12,1.42],[.20,1.45],[.55,1.44],[1.05,1.27],[1.45,1.10]],
			"tumble":.45, "rc":.04, "edge":4.0, "bow":.04, "side":[[-.70,.48],[.56,1.05]]}},
	"imperador_64": {"front":-2.68, "rear":2.68, "zf":-1.42, "zr":1.58, "wheel_r":.295, "track":.80, "wheel_w":.17, "rim":.55,
		"rim_style":"wire", "rim_color":"c3ccd1", "caliper":"", "tire":"whitewall", "arch":.37, "arch_lift":-.03,
		"sill":[[-2.68,.22],[-2.40,.17],[2.40,.17],[2.68,.22]],
		"hw":[[-2.68,.86],[-2.62,.93],[-2.45,.97],[-1.42,.985],[0.0,.98],[1.58,.99],[2.45,.975],[2.68,.93]],
		"flare":0.0, "flare_len":.55,
		"belt":[[-2.68,.66],[-2.58,.70],[-2.35,.73],[-1.42,.75],[-.85,.76],[0.0,.765],[1.4,.78],[2.30,.79],[2.68,.78]],
		"crown":[[-2.68,0.0],[-2.40,.01],[-1.50,.02],[-1.0,.015],[0.0,.015],[1.6,.01],[2.68,0.0]],
		"edge":8.0, "tuck":.08, "tumble":.04, "hm":.62, "crease":[.84,.006], "inset":.12,
		"fplate":[.32,.085], "rplate":[.50,0.0],
		"gh":{"zA":-.98, "zH":-.30, "zR":.52, "zC":1.72, "roof":[[-.64,1.04],[-.30,1.24],[0.0,1.26],[.52,1.25],[1.05,1.10],[1.45,.96]],
			"tumble":.30, "rc":.025, "edge":4.5, "bow":.02, "side":[[-.88,.45],[.53,1.05]], "black_pillars":false}},
	"imperador_64_conv": {"front":-2.68, "rear":2.68, "zf":-1.42, "zr":1.58, "wheel_r":.295, "track":.80, "wheel_w":.17, "rim":.55,
		"rim_style":"wire", "rim_color":"c9a24a", "caliper":"", "tire":"whitewall", "arch":.37, "arch_lift":-.03,
		"sill":[[-2.68,.22],[-2.40,.17],[2.40,.17],[2.68,.22]],
		"hw":[[-2.68,.86],[-2.62,.93],[-2.45,.97],[-1.42,.985],[0.0,.98],[1.58,.99],[2.45,.975],[2.68,.93]],
		"flare":0.0, "flare_len":.55,
		"belt":[[-2.68,.66],[-2.58,.70],[-2.35,.73],[-1.42,.75],[-.85,.76],[0.0,.765],[1.4,.78],[2.30,.79],[2.68,.78]],
		"crown":[[-2.68,0.0],[-2.40,.01],[-1.50,.02],[-1.0,.015],[0.0,.015],[1.6,.01],[2.68,0.0]],
		"edge":8.0, "tuck":.08, "tumble":.04, "hm":.62, "crease":[.84,.006], "inset":.12, "roadster":true,
		"fplate":[.32,.085], "rplate":[.50,0.0],
		"gh":{"zA":-.98, "zH":-.40, "zC":1.10, "roof":[[-.40,1.08]], "tumble":.30, "rc":.02, "edge":3.0, "bow":0.0, "side":[]}},
	"monte_rei_84": {"front":-2.55, "rear":2.55, "zf":-1.40, "zr":1.48, "wheel_r":.30, "track":.76, "wheel_w":.17, "rim":.55,
		"rim_style":"wire", "rim_color":"c9a24a", "caliper":"", "tire":"whitewall", "arch":.37, "arch_lift":-.03,
		"sill":[[-2.55,.22],[-2.30,.17],[2.30,.17],[2.55,.22]],
		"hw":[[-2.55,.84],[-2.50,.89],[-2.35,.91],[0.0,.92],[2.35,.915],[2.55,.88]],
		"flare":0.0, "flare_len":.55,
		"belt":[[-2.55,.68],[-2.45,.72],[-2.20,.74],[-1.40,.75],[0.0,.76],[1.50,.78],[2.30,.79],[2.55,.78]],
		"crown":[[-2.55,0.0],[-2.30,.01],[-1.50,.02],[-1.0,.02],[0.0,.01],[2.55,0.0]],
		"edge":12.0, "tuck":.03, "tumble":.03, "hm":.60, "crease":[.80,.008], "inset":.10,
		"fplate":[.34,.10], "rplate":[.56,0.0],
		"gh":{"zA":-.98, "zH":-.32, "zR":.62, "zC":1.62, "roof":[[-.66,1.04],[-.32,1.25],[0.0,1.27],[.62,1.265],[1.0,1.15],[1.36,1.02]],
			"tumble":.22, "rc":.02, "edge":6.0, "bow":.01, "side":[[-.90,.36]], "black_pillars":false}},
	"duque_76": {"front":-2.85, "rear":2.85, "zf":-1.53, "zr":1.70, "wheel_r":.31, "track":.82, "wheel_w":.18, "rim":.55,
		"rim_style":"wire", "rim_color":"c3ccd1", "caliper":"", "tire":"whitewall", "arch":.38, "arch_lift":-.02,
		"sill":[[-2.85,.24],[-2.55,.19],[2.55,.19],[2.85,.24]],
		"hw":[[-2.85,.90],[-2.80,.96],[-2.60,.99],[0.0,1.0],[2.60,.995],[2.85,.96]],
		"flare":0.0, "flare_len":.55,
		"belt":[[-2.85,.74],[-2.75,.78],[-2.45,.80],[-1.50,.81],[0.0,.82],[1.80,.83],[2.60,.83],[2.85,.82]],
		"crown":[[-2.85,0.0],[-2.60,.01],[-1.60,.02],[-1.10,.02],[0.0,.01],[2.85,.01]],
		"edge":14.0, "tuck":.03, "tumble":.02, "hm":.60, "crease":[.82,.008], "inset":.11,
		"fplate":[.36,.12], "rplate":[.58,0.0],
		"gh":{"zA":-1.05, "zH":-.40, "zR":1.10, "zC":1.85, "roof":[[-.72,1.10],[-.40,1.36],[0.0,1.38],[1.10,1.37],[1.45,1.20],[1.70,1.06]],
			"tumble":.18, "rc":.02, "edge":6.0, "bow":.01, "side":[[-.95,.15],[.25,.95]], "black_pillars":false}},
}

func catalog() -> GDScript: return MUSCLE
func designs() -> Dictionary: return MUSCLE_DESIGNS
func report_path() -> String: return MUSCLE_REPORT
func lowrider() -> bool: return MUSCLE.is_lowrider(car_id)

func setup(id: String) -> void:
	super.setup(id)
	model.set_meta("muscle_fleet_version",1)
	if lowrider(): model.set_meta("lowrider",true)

# ---------------------------------------------------------------- peças comuns

## Faixa extrudada ao longo de uma linha (para-choque, friso grosso): face externa, topo e base.
func strip(key: String, pts: Array, normals: Array, h: float, depth: float, color: Color, scales: Array = []) -> void:
	tint = color
	var up := Vector3(0,h*.5,0)
	var d := func(i: int) -> float: return depth*(float(scales[i]) if i < scales.size() else 1.0)
	for i in pts.size()-1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i+1]
		var ao: Vector3 = a+normals[i]*float(d.call(i))
		var bo: Vector3 = b+normals[i+1]*float(d.call(i+1))
		var n: Vector3 = (normals[i]+normals[i+1]).normalized()
		quad(key,ao-up,bo-up,bo+up,ao+up,n)
		quad(key,a+up,b+up,bo+up,ao+up,Vector3.UP)
		quad(key,a-up,b-up,bo-up,ao-up,Vector3.DOWN)
	for end in [0,pts.size()-1]:
		var p: Vector3 = pts[end]
		var o: Vector3 = p+normals[end]*float(d.call(end))
		var along: Vector3 = (pts[1]-pts[0]) if end == 0 else (pts[end]-pts[end-1])
		quad(key,p-up,p+up,o+up,o-up,-along if end == 0 else along)
	tint = Color.WHITE

## Para-choque que contorna a ponta: sai da lateral `wrap` metros atrás da ponta e atravessa a frente.
func bumper(front: bool, y: float, h: float, depth: float, wrap: float, color := CHROME) -> void:
	active = "Body"
	var e := float(D.front) if front else float(D.rear)
	var inward := 1.0 if front else -1.0
	var pts := []
	var side := []
	var scales := []
	for k in 7:
		var z := e+inward*wrap*(1.0-k/6.0)
		if k == 6: z = e+inward*.015
		var hh := clampf((y-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01),0.0,1.0)
		side.append(Vector3(side_x(z,hh)-.004,y,z))
	# Na lateral o para-choque afina até a ponta de trás: largura de colisão quase não muda.
	for k in 7:
		pts.append(Vector3(-side[k].x,side[k].y,side[k].z))
		scales.append(lerpf(.30,1.0,k/6.0))
	var xe: float = side[6].x-.02
	for k in 5:
		pts.append(Vector3(lerpf(-xe,xe,k/4.0),y,e-inward*.002))
		scales.append(1.0)
	for k in range(6,-1,-1):
		pts.append(side[k])
		scales.append(lerpf(.30,1.0,k/6.0))
	var center := Vector3(0,y,e+inward*3.0)
	var normals := []
	for i in pts.size():
		var t: Vector3 = pts[mini(i+1,pts.size()-1)]-pts[maxi(i-1,0)]
		var n := t.cross(Vector3.UP).normalized()
		if n.dot(pts[i]-center) < 0: n = -n
		normals.append(n)
	strip("detail",pts,normals,h,depth,color,scales)

## Faixa pintada sobre capô ou tampa, entre as distâncias x0 e x1 da linha de centro.
func stripe_top(x0: float, x1: float, z0: float, z1: float, color: Color, nz := 8) -> void:
	active = "Body"
	for s in [-1.0,1.0]:
		var p0 := func(t: float) -> float: return u_at_x(lerpf(z0,z1,t),x1)
		var p1 := func(t: float) -> float: return u_at_x(lerpf(z0,z1,t),x0)
		patch("detail",color,s,top_pt,z0,z1,p0,p1,nz,1,.004)

## A mesma faixa sobre o teto (superfície da estufa).
func stripe_roof(x0: float, x1: float, z0: float, z1: float, color: Color, nz := 6) -> void:
	active = "Body"
	for s in [-1.0,1.0]:
		var p0 := func(t: float) -> float: return 2.0-x1/gh_xr(lerpf(z0,z1,t))
		var p1 := func(t: float) -> float: return 2.0-x0/gh_xr(lerpf(z0,z1,t))
		patch("detail",color,s,gh_pt,z0,z1,p0,p1,nz,1,.005)

## Teto de vinil: cobre o teto inteiro ou só a parte de trás (landau), sem tocar no vidro.
func vinyl_top(z0: float, z1: float, color := VINYL) -> void:
	active = "Body"
	for s in [-1.0,1.0]:
		patch("detail",color,s,gh_pt,z0,z1,const_fn(1.02),const_fn(1.99),8,4,.004)

## Friso cromado fino ao longo da lateral, na altura h (fração entre soleira e cintura).
func side_trim(h0: float, h1: float, z0: float, z1: float, color := CHROME, nz := 14) -> void:
	for s in [-1.0,1.0]:
		var a := z0
		var segments: Array = [[z0,z1]]
		# A faixa pula as caixas de roda: o friso da soleira não atravessa o arco.
		if h0 < .5:
			segments = []
			var cuts: Array = [[zf-float(D.arch)-.02,zf+float(D.arch)+.02],[zr-float(D.arch)-.02,zr+float(D.arch)+.02]]
			for cut: Array in cuts:
				if float(cut[1]) <= a or float(cut[0]) >= z1: continue
				if float(cut[0]) > a: segments.append([a,float(cut[0])])
				a = maxf(a,float(cut[1]))
			if a < z1: segments.append([a,z1])
		for seg: Array in segments:
			var za: float = seg[0]
			var zb: float = seg[1]
			if zb-za < .05: continue
			active = "Body"
			var n := maxi(2,int(nz*(zb-za)/maxf(z1-z0,.01)))
			# Na folha da porta o friso vai junto com ela.
			var dz0 := float(door.zf)
			var dz1 := float(door.zr)
			if za < dz0 and zb > dz0:
				patch("detail",color,s,side_pt,za,dz0-.004,const_fn(h0),const_fn(h1),maxi(2,int(n*.5)),1,.006)
				za = dz0+.004
			if za < dz1 and zb > dz1:
				active = "DoorL" if s < 0 else "DoorR"
				patch("detail",color,s,side_pt,za,dz1-.004,const_fn(h0),const_fn(h1),maxi(2,int(n*.5)),1,.006)
				za = dz1+.004
				active = "Body"
			if za >= dz0-.0001 and zb <= dz1+.0001: active = "DoorL" if s < 0 else "DoorR"
			patch("detail",color,s,side_pt,za,zb,const_fn(h0),const_fn(h1),maxi(2,int(n*.5)),1,.006)
			active = "Body"

## Saia do para-lama traseiro: tampa o arco com lataria pintada e um friso cromado embaixo.
func fender_skirt() -> void:
	active = "Body"
	var r := float(D.arch)
	for s in [-1.0,1.0]:
		var top := func(t: float) -> float:
			var z := lerpf(zr-r+.01,zr+r-.01,t)
			return clampf((skirt_y(z)-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01)+.03,0.0,1.0)
		# Fica 2 cm para fora: cobre o friso de borracha do arco que o gerador desenha.
		patch("paint",Color.WHITE,s,side_pt,zr-r+.01,zr+r-.01,const_fn(0.0),top,12,3,.02)
		patch("detail",CHROME,s,side_pt,zr-r+.02,zr+r-.02,const_fn(.0),const_fn(.05),8,1,.026)

## Estepe "continental": roda coberta presa ao para-choque traseiro, de pé.
func continental_kit(color := Color.WHITE) -> void:
	active = "Body"
	var r := float(D.rear)
	var c := Vector3(0,sill_y(r)+.30,r+.17)
	box("detail",Vector3(0,sill_y(r)+.10,r+.08),Vector3(.62,.07,.20),CHROME)
	tint = color
	# Capa: disco pintado com aro cromado, encostado num tambor curto.
	for i in 24:
		var t0 := TAU*i/24.0
		var t1 := TAU*(i+1)/24.0
		var ra := Vector3(cos(t0),sin(t0),0)
		var rb := Vector3(cos(t1),sin(t1),0)
		quad("paint",c+ra*.30-Vector3(0,0,.09),c+rb*.30-Vector3(0,0,.09),c+rb*.30+Vector3(0,0,.07),c+ra*.30+Vector3(0,0,.07),ra)
	ellipse("paint",c+Vector3(0,0,.07),Vector3.RIGHT,Vector3.UP,.30,0.0,Vector3.BACK,Color.WHITE,24)
	ellipse("detail",c+Vector3(0,0,.074),Vector3.RIGHT,Vector3.UP,.30,.26,Vector3.BACK,CHROME,24)
	ellipse("detail",c+Vector3(0,0,.076),Vector3.RIGHT,Vector3.UP,.07,0.0,Vector3.BACK,CHROME,16)
	tint = Color.WHITE

## Tomada de ar elevada no capô (pintada), com a boca escura na frente.
func hood_scoop(z0: float, z1: float, width: float, height: float, mouth := true) -> void:
	active = "Body"
	var zc := (z0+z1)*.5
	var y := top_y(zc,1.0)
	box("paint",Vector3(0,y+height*.5-.01,zc),Vector3(width,height,z1-z0))
	if mouth: box("detail",Vector3(0,y+height*.55-.01,z0-.004),Vector3(width*.82,height*.62,.012),BLACK)

## Costura da porta traseira (sedã de quatro portas): frestas e maçaneta presas à carroceria.
func rear_door_seams(z0: float, z1: float) -> void:
	active = "Body"
	for s in [-1.0,1.0]:
		for z in [z0,z1]:
			var h0 := (skirt_y(z)-sill_y(z))/maxf(belt_y(z)-sill_y(z),.01)
			for k in 8: beam("detail",on(side_pt,z,lerpf(h0,1.0,k/8.0),s,.002),on(side_pt,z,lerpf(h0,1.0,(k+1)/8.0),s,.002),.007,RUBBER)
		patch("detail",CHROME,s,side_pt,z1-.20,z1-.08,const_fn(.80),const_fn(.86),2,1,.006)

## Ornamento cromado de capô.
func hood_ornament(z: float) -> void:
	active = "Body"
	var y := top_y(z,1.0)
	ellipse("detail",Vector3(0,y+.004,z),Vector3.RIGHT,Vector3.BACK,.035,0.0,Vector3.UP,CHROME,12)
	beam("detail",Vector3(0,y,z),Vector3(0,y+.07,z+.015),.012,CHROME)
	ellipse("detail",Vector3(0,y+.075,z+.016),Vector3.UP,Vector3.BACK,.03,.022,Vector3.RIGHT,CHROME,14)

# ---------------------------------------------------------------- placas, rodas e cabine

func underbody_and_plates() -> void:
	active = "Body"
	var f := float(D.front)
	var r := float(D.rear)
	var fp: Array = D.get("fplate",[sill_y(f)+.10,0.0])
	var rp: Array = D.get("rplate",[lerpf(sill_y(r),belt_y(r),.42),0.0])
	box("detail",Vector3(0,fp[0],f-.006-float(fp[1])),Vector3(.52,.11,.012),PLATE)
	box("detail",Vector3(0,fp[0],f-.009-float(fp[1])),Vector3(.48,.08,.006),Color("5a6066"))
	box("detail",Vector3(0,rp[0],r+.006+float(rp[1])),Vector3(.52,.11,.012),PLATE)
	box("detail",Vector3(0,rp[0],r+.009+float(rp[1])),Vector3(.48,.08,.006),Color("5a6066"))
	box("detail",Vector3(0,float(rp[0])+.075,r+.012+float(rp[1])),Vector3(.12,.012,.02),CHROME)

## Igual às rodas do gerador 2.0, com o pneu de faixa branca dos lowriders e sem pinça nos clássicos.
func wheels_v2() -> void:
	var R := float(D.wheel_r)
	var W := float(D.wheel_w)*.5
	var rim := R*float(D.rim)
	var rim_color := Color.html(str(D.rim_color))
	var style := str(D.rim_style)
	var tire := str(D.tire)
	var smooth := tire in ["sport","whitewall"]
	for s in [-1.0,1.0]:
		for a in [zf,zr]:
			active = "Wheel_%s_%s" % ["L" if s < 0 else "R","F" if a < 0 else "R"]
			var c := Vector3(s*float(D.track),R,a)
			var bulge := .015 if tire == "sport" else .03
			var profile := [Vector2(-W*.90,rim),Vector2(-W-bulge,rim+(R-rim)*.50),Vector2(-W*.96,R-.022),Vector2(-W*.78,R),
				Vector2(W*.78,R),Vector2(W*.96,R-.022),Vector2(W+bulge,rim+(R-rim)*.50),Vector2(W*.90,rim)]
			var segs := 28
			var middle := Vector2(0.0,(R+rim)*.5)
			for j in profile.size()-1:
				for i in segs:
					var t0 := TAU*i/segs
					var t1 := TAU*(i+1)/segs
					var pa: Vector2 = profile[j]
					var pb: Vector2 = profile[j+1]
					# Normal do trecho do perfil, para fora da seção do pneu. A dica antiga (soma dos x
					# mais a radial) virava o flanco de fora para dentro e o corte de faces o escondia.
					var n2 := Vector2(pb.y-pa.y,-(pb.x-pa.x))
					if n2.dot((pa+pb)*.5-middle) < 0.0: n2 = -n2
					var tm := (t0+t1)*.5
					tint = Color("202427") if j == 3 else Color("2a2f33")
					# Faixa branca só no flanco de fora, do meio do flanco até o aro.
					if tire == "whitewall" and j == 6: tint = WHITEWALL
					quad("wheel",c+Vector3(s*pa.x,sin(t0)*pa.y,cos(t0)*pa.y),c+Vector3(s*pa.x,sin(t1)*pa.y,cos(t1)*pa.y),
						c+Vector3(s*pb.x,sin(t1)*pb.y,cos(t1)*pb.y),c+Vector3(s*pb.x,sin(t0)*pb.y,cos(t0)*pb.y),Vector3(s*n2.x,sin(tm)*n2.y,cos(tm)*n2.y))
			if not smooth:
				for i in 24:
					var t := TAU*i/24.0
					var radial := Vector3(0,sin(t),cos(t))
					box_oriented("wheel",c+Vector3(s*W*.44*(1.0 if i % 2 == 0 else -1.0),0,0)+radial*(R-.007),radial,Vector3(0,cos(t),-sin(t)),Vector3(W*.66,.014,.055),Color("1c1f22"))
			var face := c+Vector3(s*W*.84,0,0)
			ellipse("wheel",c+Vector3(s*W*.15,0,0),Vector3.UP,Vector3.BACK,rim*.98,0,Vector3(s,0,0),Color("15181a"),20)
			ellipse("wheel",face,Vector3.UP,Vector3.BACK,rim*1.03,rim*.93,Vector3(s,0,0),rim_color.lightened(.12),28)
			ellipse("wheel",face-Vector3(s*.012,0,0),Vector3.UP,Vector3.BACK,rim*.94,rim*.90,Vector3(s,0,0),rim_color.darkened(.25),28)
			rim_face(style,face,s,rim,rim_color)
			tint = Color.WHITE
			if str(D.caliper) != "":
				ellipse("wheel",c+Vector3(s*W*.42,0,0),Vector3.UP,Vector3.BACK,rim*.80,rim*.30,Vector3(s,0,0),Color("7d8489"),24)
				active = "Body"
				box("detail",c+Vector3(-s*W*.05,rim*.48,(.11 if a < 0 else -.11)),Vector3(.05,rim*.38,rim*.32),Color.html(str(D.caliper)))
	active = "Body"

func rim_face(style: String, face: Vector3, s: float, rim: float, color: Color) -> void:
	var out := Vector3(s,0,0)
	var hub := rim*.24
	match style:
		"wire":
			# Raiada cromada: prato fundo, 36 raios cruzados em três camadas e borboleta de duas pás.
			ellipse("wheel",face-out*.04,Vector3.UP,Vector3.BACK,rim*.92,0,out,color.darkened(.30),28)
			ellipse("wheel",face-out*.004,Vector3.UP,Vector3.BACK,rim*.93,rim*.84,out,color.lightened(.15),28)
			var hr := rim*.30
			for i in 36:
				var a := TAU*i/36.0
				var lace := .55 if i % 2 == 0 else -.55
				var layer: float = [.004,-.010,-.022][i % 3]
				var p0 := face+out*layer+Vector3(0,sin(a),cos(a))*hr*.92
				var p1 := face-out*.03+Vector3(0,sin(a+lace),cos(a+lace))*rim*.86
				beam("wheel",p0,p1,.0065,color)
			ellipse("wheel",face+out*.010,Vector3.UP,Vector3.BACK,hr,0,out,color,20)
			ellipse("wheel",face+out*.018,Vector3.UP,Vector3.BACK,hr*.55,0,out,color.lightened(.25),16)
			for k in [-1.0,1.0]:
				beam("wheel",face+out*.026,face+out*.026+Vector3(0,k*hr*1.25,k*.012),.024,color.lightened(.2))
			return
		"slot":
			ellipse("wheel",face+out*.002,Vector3.UP,Vector3.BACK,rim*.93,hub*.95,out,color,28)
			for j in 5: spoke(face+out*.004,s,TAU*j/5.0+.3,rim*.40,rim*.80,.07,.10,.006,Color("15181a"),0.0)
		"rally":
			ellipse("wheel",face+out*.002,Vector3.UP,Vector3.BACK,rim*.93,hub*.95,out,color,28)
			ellipse("wheel",face+out*.006,Vector3.UP,Vector3.BACK,rim*.94,rim*.80,out,CHROME,28)
			for j in 6:
				var t := TAU*j/6.0
				ellipse("wheel",face+out*.006+Vector3(0,sin(t),cos(t))*rim*.56,Vector3.UP,Vector3.BACK,rim*.075,0,out,Color("15181a"),8)
			ellipse("wheel",face+out*.014,Vector3.UP,Vector3.BACK,hub*1.35,0,out,CHROME,18)
			ellipse("wheel",face+out*.018,Vector3.UP,Vector3.BACK,hub*.6,0,out,Color("8a1f24"),12)
			return
		"torq":
			ellipse("wheel",face-out*.02,Vector3.UP,Vector3.BACK,rim*.92,0,out,Color("2a2e31"),24)
			for j in 5: spoke(face,s,TAU*j/5.0+.3,hub,rim*.92,.11,.06,.035,color,.015)
			ellipse("wheel",face+out*.004,Vector3.UP,Vector3.BACK,rim*.95,rim*.86,out,CHROME,28)
	super.rim_face(style,face,s,rim,color)

func cabin_meta() -> Dictionary:
	var spec := super.cabin_meta()
	# Lowrider é carro de banco inteiriço e cabine alta; o "sport" baixava demais o Dante.
	if lowrider(): spec.kind = "car"
	return spec

## Conversível lowrider: banco inteiriço na frente e atrás, volante de corrente e capota recolhida.
func lowrider_cockpit() -> void:
	active = "Body"
	var z0 := zA()+.02
	var z1 := zC()-.04
	var floor_y := sill_y(0)+.07
	var wall := gh_base(0).x-.015
	tint = INTERIOR
	for s in [-1.0,1.0]:
		for span in [[z0,float(door.zf)-.02],[float(door.zr)+.02,z1]]:
			quad("detail",Vector3(s*wall,floor_y,span[0]),Vector3(s*wall,floor_y,span[1]),Vector3(s*wall,belt_y(span[1])-.01,span[1]),Vector3(s*wall,belt_y(span[0])-.01,span[0]),Vector3(-s,0,0))
	quad("detail",Vector3(-wall,floor_y,z1),Vector3(wall,floor_y,z1),Vector3(wall,top_y(z1,1.0),z1),Vector3(-wall,top_y(z1,1.0),z1),Vector3.FORWARD)
	tint = Color.WHITE
	box("detail",Vector3(0,floor_y,(z0+z1)*.5),Vector3(wall*2,.02,z1-z0),Color("2a1d22"))
	box("detail",Vector3(0,belt_y(z0)-.05,z0+.10),Vector3(wall*2-.02,.16,.22),INTERIOR)
	box("detail",Vector3(0,belt_y(z0)+.02,z0+.06),Vector3(wall*2-.06,.03,.10),CHROME)
	# Volante pequeno de corrente (o clássico dos lowriders).
	var hub := Vector3(-.36,belt_y(z0)+.02,z0+.34)
	ellipse("detail",hub,Vector3.RIGHT,Vector3(0,.82,.57),.15,.13,Vector3(0,-.57,.82),CHROME,24)
	ellipse("detail",hub,Vector3.RIGHT,Vector3(0,.82,.57),.04,0.0,Vector3(0,-.57,.82),CHROME,12)
	# Bancos inteiriços em capitonê vinho (dianteiro e traseiro).
	var seat := Color("6e1f2c")
	for row in [[float(door.seat_z)+.02,1.0],[float(door.zr)+.32,.92]]:
		var z: float = row[0]
		box("detail",Vector3(0,floor_y+.12,z),Vector3(wall*2-.10,.13,.50),seat)
		box_oriented("detail",Vector3(0,floor_y+.42,z+.28),Vector3(0,.96,.28),Vector3(0,-.28,.96),Vector3(wall*2-.10,.56*float(row[1]),.11),seat)
		for k in 6: box("detail",Vector3(-wall+.18+k*(wall*2-.36)/5.0,floor_y+.43,z+.21),Vector3(.012,.42*float(row[1]),.012),seat.darkened(.3))
	# Capota recolhida atrás do banco de trás.
	box("detail",Vector3(0,belt_y(z1)+.06,z1-.12),Vector3(wall*2-.04,.14,.30),Color("e6e1d4"))

func bake() -> Dictionary:
	# O emblema da gangue (CobraAppearance) assenta aqui sem medir a malha em jogo.
	var z := lerpf(float(D.front),zA(),.42)
	model.set_meta("hood_badge",Vector3(0,top_y(z,1.0)+.012,z))
	return super.bake()

# ---------------------------------------------------------------- desenho de cada carro

func features_potro_68() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := .56
	# Boca da grade funda com farol redondo em cada ponta e o emblema no meio.
	front_plate("detail",0,gy,1.22,.20,BLACK,.012)
	for y in [gy+.105,gy-.105]: front_plate("detail",0,y,1.26,.018,CHROME,.02)
	for s in [-1.0,1.0]:
		front_plate("detail",s*.62,gy,.018,.21,CHROME,.02)
		front_ring("detail",s*.50,gy,.092,.078,CHROME,.016)
		front_ring("headlight",s*.50,gy,.078,0.0,Color.WHITE,.020,head_label(s))
		front_plate("detail",s*.40,.345,.13,.045,AMBER,.02)
	front_ring("detail",0,gy,.07,.056,CHROME,.02)
	front_plate("detail",0,gy,.09,.016,CHROME,.024)
	for k in 5: front_plate("detail",0,gy-.08+k*.04,.62,.006,Color("2a2d31"),.016)
	bumper(true,.415,.055,.06,.24)
	# Duas tomadas no capô e a do para-lama traseiro.
	for s in [-1.0,1.0]:
		patch("detail",BLACK,s,top_pt,-2.02,-1.84,const_fn(.30),const_fn(.42),2,1,.010)
		patch("detail",BLACK,s,side_pt,zr-.86,zr-.47,lerp_fn(.40,.48),lerp_fn(.80,.70),3,2,.004)
		patch("detail",CHROME,s,side_pt,zr-.88,zr-.85,lerp_fn(.40,.40),lerp_fn(.80,.80),1,1,.008)
	# Grelha de ventilação na coluna do fastback.
	for k in 4:
		var z := .52+k*.09
		for s in [-1.0,1.0]: patch("detail",BLACK,s,gh_pt,z,z+.045,const_fn(.20),const_fn(.78),1,2,.004)
	# Faixa GT baixa na lateral.
	side_trim(.17,.23,zf+.42,zr-.42,Color("e9e6dc"))
	# Traseira: painel escuro com três barras verticais de cada lado e a tampa do tanque.
	var ty := belt_y(r)-.14
	rear_plate("detail",0,ty,1.52,.19,BLACK,.012)
	rear_plate("detail",0,ty+.10,1.56,.016,CHROME,.02)
	for s in [-1.0,1.0]:
		for k in 3: rear_plate("tail",s*(.40+k*.12),ty,.075,.14,Color.WHITE,.02,"Tail")
	rear_ring("detail",0,ty,.065,0.0,CHROME,.02)
	rear_ring("detail",0,ty,.045,0.0,Color("2a2d31"),.024)
	bumper(false,.52,.055,.06,.22)
	exhaust(-.40,.36,.035)
	exhaust(.40,.36,.035)
	active = "Body"
	box("paint",Vector3(0,top_y(r-.06,1.0)+.018,r-.06),Vector3(1.30,.03,.10))

func features_jararaca_v10() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	for s in [-1.0,1.0]:
		# Farol em gota deitado sobre o para-lama.
		lens(head_label(s),"headlight",s,top_pt,f+.10,f+.48,lerp_fn(.05,.10),arc_fn(.28,.22,.05),6,3)
		active = "Body"
		patch("detail",AMBER,s,top_pt,f+.12,f+.18,const_fn(.08),const_fn(.20),1,1,.011)
		# Três guelras grandes no para-lama, atrás da roda dianteira.
		for k in 3:
			var z := zf+float(D.arch)+.03+k*.07
			patch("detail",BLACK,s,side_pt,z,z+.04,lerp_fn(.38,.46),lerp_fn(.86,.90),2,2,.004)
		# Escapamento lateral sob a porta, com o protetor de calor cromado.
		box("detail",Vector3(s*(hw(-.15)+.01),sill_y(0)+.07,-.12),Vector3(.075,.085,.86),CHROME)
		for k in 8: box("detail",Vector3(s*(hw(-.15)+.05),sill_y(0)+.07,-.48+k*.105),Vector3(.006,.05,.05),Color("2a2d31"))
	# Boca oval larga e a barra cromada no meio.
	active = "Body"
	ellipse("detail",Vector3(0,sill_y(f)+.11,f-.012),Vector3.RIGHT*.42,Vector3.UP*.075,1.0,0.0,Vector3.FORWARD,BLACK,24)
	front_plate("detail",0,sill_y(f)+.11,.62,.012,Color("3a3f44"),.024)
	splitter(1.20,.08)
	# Respiros grandes no capô, de cada lado do calombo do meio.
	for s in [-1.0,1.0]:
		patch("detail",BLACK,s,top_pt,-1.58,-1.18,const_fn(.42),const_fn(.62),3,2,.004)
		for k in 4: patch("detail",Color("3a3f44"),s,top_pt,-1.56+k*.10,-1.53+k*.10,const_fn(.43),const_fn(.61),1,1,.008)
	# Faixas duplas: capô, teto e tampa.
	for x in [[.07,.17]]:
		stripe_top(x[0],x[1],f+.04,zA()-.03,Color("e9e6dc"),10)
		stripe_roof(x[0],x[1],zH()+.03,zR()-.02,Color("e9e6dc"))
		stripe_top(x[0],x[1],zC()+.04,r-.03,Color("e9e6dc"),4)
	# Lanternas ovais deitadas e o rabinho de pato.
	for s in [-1.0,1.0]:
		active = "Body"
		ellipse("detail",Vector3(s*.56,belt_y(r)-.13,r+.010),Vector3.RIGHT*1.8,Vector3.UP,.075,0.0,Vector3.BACK,RUBBER,20)
		active = "Tail"
		ellipse("tail",Vector3(s*.56,belt_y(r)-.13,r+.016),Vector3.RIGHT*1.8,Vector3.UP,.062,0.0,Vector3.BACK,Color.WHITE,20)
	active = "Body"
	box("paint",Vector3(0,top_y(r-.07,1.0)+.02,r-.07),Vector3(1.40,.035,.12))
	diffuser(1.0,5,.09)

func features_carcara_ss() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := .565
	# Grade colmeia de ponta a ponta com os faróis redondos dentro dela.
	front_plate("detail",0,gy,1.44,.23,BLACK,.012)
	for y in [gy+.12,gy-.12]: front_plate("detail",0,y,1.48,.02,CHROME,.022)
	for k in 9: front_plate("detail",-.36+k*.09,gy,.008,.20,Color("4a5056"),.018)
	front_plate("detail",0,gy,.80,.008,Color("4a5056"),.018)
	for s in [-1.0,1.0]:
		front_plate("detail",s*.735,gy,.02,.25,CHROME,.022)
		front_ring("detail",s*.58,gy,.09,.077,CHROME,.016)
		front_ring("headlight",s*.58,gy,.077,0.0,Color.WHITE,.020,head_label(s))
		front_plate("detail",s*.42,.35,.14,.04,AMBER,.02)
	front_ring("detail",0,gy,.05,0.0,Color("8a1f24"),.022)
	bumper(true,.405,.05,.055,.26)
	# Faixa "abelha" atravessando o bico, capô com a tomada no pé do para-brisa.
	active = "Body"
	for s in [-1.0,1.0]:
		patch("detail",Color("e9e6dc"),s,top_pt,f+.28,f+.40,const_fn(0.0),const_fn(1.0),2,6,.004)
		patch("detail",Color("e9e6dc"),s,side_pt,f+.28,f+.40,const_fn(.55),const_fn(1.0),2,3,.004)
		# Guelras na frente da roda traseira.
		for k in 3: patch("detail",BLACK,s,side_pt,zr-.66+k*.06,zr-.63+k*.06,const_fn(.52),const_fn(.80),1,2,.004)
	hood_scoop(zA()-.48,zA()-.05,.50,.045)
	stripe_top(.08,.20,f+.42,zA()-.03,Color("e9e6dc"),8)
	stripe_top(.08,.20,zC()+.04,r-.03,Color("e9e6dc"),4)
	# Lanternas largas de três gomos e o rabo de pato.
	var ty := belt_y(r)-.13
	for s in [-1.0,1.0]:
		rear_plate("detail",s*.46,ty,.52,.14,CHROME,.012)
		rear_plate("tail",s*.46,ty,.48,.11,Color.WHITE,.02,"Tail")
		for k in 2: rear_plate("detail",s*(.30+k*.16),ty,.012,.12,CHROME,.026)
	rear_plate("detail",0,ty,.36,.12,BLACK,.016)
	rear_ring("detail",0,ty,.045,0.0,CHROME,.02)
	bumper(false,.50,.055,.06,.24)
	exhaust(-.42,.36,.036)
	exhaust(.42,.36,.036)
	active = "Body"
	box("paint",Vector3(0,top_y(r-.06,1.0)+.02,r-.06),Vector3(1.36,.035,.11))

func features_trovao_440() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := .58
	# Grade escura inteira (faróis escondidos com as tampas abertas), moldura cromada e divisória.
	front_plate("detail",0,gy,1.62,.27,BLACK,.014)
	for y in [gy+.14,gy-.14]: front_plate("detail",0,y,1.66,.02,CHROME,.022)
	for k in 12: front_plate("detail",-.66+k*.12,gy,.006,.24,Color("24282b"),.018)
	front_plate("detail",0,gy,.03,.27,CHROME,.024)
	for s in [-1.0,1.0]:
		front_plate("detail",s*.82,gy,.02,.29,CHROME,.022)
		front_ring("detail",s*.62,gy,.095,.08,Color("2a2d31"),.02)
		front_ring("headlight",s*.62,gy,.08,0.0,Color.WHITE,.024,head_label(s))
		front_plate("detail",s*.36,.355,.18,.04,AMBER,.02)
	bumper(true,.42,.06,.065,.26)
	# Dois respiros no capô.
	for s in [-1.0,1.0]: patch("detail",BLACK,s,top_pt,-2.22,-2.02,const_fn(.36),const_fn(.46),2,1,.010)
	# Teto de vinil preto e a faixa "abelha" que dá a volta na tampa.
	vinyl_top(zH()+.05,zR()-.02)
	for s in [-1.0,1.0]:
		patch("detail",Color("e9e6dc"),s,top_pt,r-.58,r-.44,const_fn(0.0),const_fn(1.0),2,6,.004)
		patch("detail",Color("e9e6dc"),s,side_pt,r-.58,r-.44,const_fn(.50),const_fn(1.0),2,3,.004)
		# Marcadores laterais redondos.
		patch("detail",AMBER,s,side_pt,f+.22,f+.30,const_fn(.40),const_fn(.52),1,1,.006)
		patch("detail",Color("a82425"),s,side_pt,r-.30,r-.22,const_fn(.48),const_fn(.60),1,1,.006)
	# Duas lanternas redondas de cada lado num painel escuro.
	var ty := belt_y(r)-.15
	rear_plate("detail",0,ty,1.64,.20,BLACK,.012)
	rear_plate("detail",0,ty+.105,1.68,.016,CHROME,.02)
	for s in [-1.0,1.0]:
		for x in [.42,.68]:
			rear_ring("detail",s*x,ty,.085,.072,CHROME,.016)
			rear_ring("tail",s*x,ty,.072,0.0,Color.WHITE,.020,"Tail")
	bumper(false,.53,.06,.065,.26)
	exhaust(-.46,.36,.04)
	exhaust(.46,.36,.04)

func features_caiman_454() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := .59
	# Grade inteira com barra cromada no meio e dois faróis redondos de cada lado.
	front_plate("detail",0,gy,1.68,.25,BLACK,.014)
	for y in [gy+.13,gy-.13]: front_plate("detail",0,y,1.72,.02,CHROME,.022)
	front_plate("detail",0,gy,1.70,.03,CHROME,.026)
	for k in 10: front_plate("detail",-.27+k*.06,gy,.006,.22,Color("2a2d31"),.018)
	for s in [-1.0,1.0]:
		for x in [.56,.75]:
			front_ring("detail",s*x,gy,.08,.067,CHROME,.03)
			front_ring("headlight",s*x,gy,.067,0.0,Color.WHITE,.034,head_label(s))
		front_plate("detail",s*.45,.35,.14,.04,AMBER,.02)
	front_ring("detail",0,gy,.055,0.0,Color("c3ccd1"),.03)
	bumper(true,.41,.065,.07,.26)
	# Capô com a tomada que abre no pé do para-brisa e duas faixas largas.
	hood_scoop(zA()-.58,zA()-.04,.56,.05)
	stripe_top(.06,.22,f+.06,zA()-.62,BLACK,10)
	stripe_top(.06,.22,zC()+.04,r-.03,BLACK,5)
	stripe_roof(.06,.22,zH()+.03,zR()-.02,BLACK)
	side_trim(.03,.08,zf+.42,zr-.42)
	# Para-choque traseiro alto com as lanternas embutidas.
	bumper(false,.50,.12,.07,.24)
	for s in [-1.0,1.0]:
		rear_plate("detail",s*.55,.50,.36,.085,RUBBER,.075)
		rear_plate("tail",s*.55,.50,.32,.065,Color.WHITE,.085,"Tail")
	rear_plate("detail",0,belt_y(r)-.06,1.66,.016,CHROME,.02)
	exhaust(-.42,.33,.038)
	exhaust(.42,.33,.038)

func features_brasa_hc() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := .58
	# Grade funda com dois faróis redondos de cada lado (o de fora maior) e anéis de LED.
	front_plate("detail",0,gy,1.54,.25,BLACK,.016)
	for i in 4:
		for j in 14: front_plate("detail",-.50+j*.077,gy-.075+i*.05,.04,.018,Color("2c3034"),.024)
	for s in [-1.0,1.0]:
		front_ring("detail",s*.64,gy,.10,.088,Color("2a2d31"),.02)
		front_ring("headlight",s*.64,gy,.088,0.0,Color.WHITE,.024,head_label(s))
		front_ring("detail",s*.64,gy,.075,.066,Color("eef4f6"),.03)
		front_ring("detail",s*.43,gy,.078,.068,Color("2a2d31"),.02)
		front_ring("headlight",s*.43,gy,.068,0.0,Color.WHITE,.024,head_label(s))
		front_ring("detail",s*.43,gy,.058,.050,Color("eef4f6"),.03)
	# Entrada baixa larga, lábio e o capô com a tomada do compressor e dois extratores.
	front_plate("detail",0,.39,1.36,.12,BLACK,.014)
	for k in 3: front_plate("detail",0,.35+k*.04,1.30,.008,Color("2c3034"),.024)
	splitter(1.70,.10)
	hood_scoop(zA()-.95,zA()-.30,.42,.06)
	for s in [-1.0,1.0]:
		patch("detail",BLACK,s,top_pt,-1.75,-1.35,const_fn(.28),const_fn(.42),3,2,.004)
		for k in 4: patch("detail",Color("3a3f44"),s,top_pt,-1.73+k*.10,-1.70+k*.10,const_fn(.29),const_fn(.41),1,1,.008)
	side_skirt()
	# Lanterna de ponta a ponta, aerofólio na tampa e escapes ovais nos cantos.
	var ty := belt_y(r)-.12
	rear_plate("detail",0,ty,1.74,.13,RUBBER,.012)
	rear_plate("tail",0,ty,1.66,.06,Color.WHITE,.02,"Tail")
	rear_plate("detail",0,ty,.40,.07,Color("2a2d31"),.026)
	active = "Body"
	box("paint",Vector3(0,top_y(r-.07,1.0)+.025,r-.07),Vector3(1.56,.04,.12))
	diffuser(1.30,5,.10)
	exhaust(-.62,.36,.055,"oval")
	exhaust(.62,.36,.055,"oval")

## Frente e traseira do Imperador (teto rígido e conversível).
func imperador_ends() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := .50
	# Grade larga de frisos horizontais e quatro faróis redondos.
	front_plate("detail",0,gy,1.66,.20,BLACK,.014)
	for k in 5: front_plate("detail",0,gy-.08+k*.04,1.62,.012,CHROME,.022)
	for y in [gy+.11,gy-.11]: front_plate("detail",0,y,1.70,.022,CHROME,.026)
	for s in [-1.0,1.0]:
		for x in [.56,.74]:
			front_ring("detail",s*x,gy,.078,.064,CHROME,.03)
			front_ring("headlight",s*x,gy,.064,0.0,Color.WHITE,.034,head_label(s))
	front_ring("detail",0,gy,.05,0.0,Color("8a1f24"),.034)
	bumper(true,.32,.085,.08,.30)
	# Lança cromada na lateral e friso da soleira.
	side_trim(.80,.83,f+.25,r-.25)
	side_trim(.02,.07,zf+.40,zr-.40)
	# Traseira: painel com três lanternas redondas de cada lado.
	var ty := belt_y(r)-.13
	rear_plate("detail",0,ty,1.70,.15,BLACK,.012)
	for y in [ty+.08,ty-.08]: rear_plate("detail",0,y,1.74,.016,CHROME,.02)
	for s in [-1.0,1.0]:
		for x in [.36,.54,.72]:
			rear_ring("detail",s*x,ty,.062,.052,CHROME,.016)
			rear_ring("tail",s*x,ty,.052,0.0,Color.WHITE,.020,"Tail")
	bumper(false,.36,.08,.075,.30)
	exhaust(-.50,.20,.032)
	exhaust(.50,.20,.032)

func features_imperador_64() -> void:
	imperador_ends()

func features_imperador_64_conv() -> void:
	imperador_ends()
	lowrider_cockpit()
	continental_kit()

func features_monte_rei_84() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := .52
	# Grade quadrada no meio, dois faróis retangulares de cada lado.
	front_plate("detail",0,gy,.56,.23,CHROME,.016)
	front_plate("detail",0,gy,.50,.18,BLACK,.02)
	for i in 3:
		for j in 6: front_plate("detail",-.20+j*.08,gy-.06+i*.06,.06,.04,Color("4a5056"),.026)
	for s in [-1.0,1.0]:
		front_plate("detail",s*.55,gy,.48,.15,CHROME,.014)
		for x in [.43,.66]:
			front_plate("detail",s*x,gy,.20,.11,RUBBER,.018)
			front_plate("headlight",s*x,gy,.18,.09,Color.WHITE,.024,head_label(s))
	bumper(true,.34,.10,.09,.28)
	bumper(true,.34,.025,.10,.28,RUBBER)
	for s in [-1.0,1.0]: front_plate("detail",s*.58,.34,.16,.04,AMBER,.11)
	# Calombo do capô e o teto landau de vinil na metade de trás.
	hood_scoop(-2.10,-1.40,.46,.03,false)
	vinyl_top(.05,zR()-.03)
	side_trim(.02,.06,zf+.40,zr-.40)
	side_trim(.46,.50,f+.20,r-.20,RUBBER)
	# Lanternas retangulares largas e o aerofólio pequeno da tampa.
	var ty := belt_y(r)-.18
	for s in [-1.0,1.0]:
		rear_plate("detail",s*.52,ty,.58,.17,CHROME,.012)
		rear_plate("tail",s*.52,ty,.54,.14,Color.WHITE,.02,"Tail")
		rear_plate("detail",s*.52,ty,.012,.15,CHROME,.026)
	bumper(false,.34,.10,.09,.28)
	bumper(false,.34,.025,.10,.28,RUBBER)
	active = "Body"
	box("paint",Vector3(0,top_y(r-.10,1.0)+.025,r-.10),Vector3(1.40,.03,.14))
	exhaust(.55,.20,.032)

func features_duque_76() -> void:
	var f := float(D.front)
	var r := float(D.rear)
	var gy := .55
	# Grade de pé cromada (frisos verticais) e quatro faróis retangulares.
	front_plate("detail",0,gy,.68,.32,CHROME,.03)
	front_plate("detail",0,gy,.62,.27,BLACK,.034)
	for k in 13: front_plate("detail",-.288+k*.048,gy,.014,.26,CHROME,.04)
	front_plate("detail",0,gy+.17,.70,.03,CHROME,.05)
	for s in [-1.0,1.0]:
		for x in [.50,.72]:
			front_plate("detail",s*x,gy+.02,.20,.12,CHROME,.016)
			front_plate("headlight",s*x,gy+.02,.17,.095,Color.WHITE,.024,head_label(s))
		front_plate("detail",s*.61,gy-.09,.40,.03,AMBER,.02)
	bumper(true,.36,.12,.10,.32)
	for s in [-1.0,1.0]: front_plate("detail",s*.34,.36,.10,.14,RUBBER,.12)
	hood_ornament(f+.20)
	# Teto de vinil branco, quatro portas, saias e frisos.
	vinyl_top(zH()+.04,zR()-.02,Color("2a2224"))
	rear_door_seams(float(door.zr)+.004,1.12)
	fender_skirt()
	side_trim(.60,.63,f+.25,r-.25)
	side_trim(.02,.07,zf+.40,zr-.40)
	# Lanternas verticais nas quinas e para-choque maciço.
	for s in [-1.0,1.0]:
		rear_plate("detail",s*.84,.56,.13,.36,CHROME,.012)
		rear_plate("tail",s*.84,.56,.10,.32,Color.WHITE,.02,"Tail")
	rear_plate("detail",0,belt_y(r)-.04,1.50,.02,CHROME,.02)
	bumper(false,.36,.12,.10,.32)
	for s in [-1.0,1.0]: rear_plate("detail",s*.34,.36,.10,.14,RUBBER,.12)
	exhaust(-.55,.18,.034)
	exhaust(.55,.18,.034)
