extends Node3D
## Bancos de névoa rasteira que andam com o vento do clima (WindField). Três planos
## horizontais baixos seguem o foco; o desenho fica preso ao mundo e é arrastado pelo
## vento, então a névoa passa pela rua em vez de andar junto com quem joga.
## A antiga névoa de partículas em volta do foco (WeatherSurfaceEffects) segue desligada.
## GETECO_FOG_BANKS=0 desliga (A/B): Weather nem cria o nó.
const SHADER := preload("res://runtime/atmosphere/fog_banks.gdshader")
static var enabled := OS.get_environment("GETECO_FOG_BANKS") != "0"
## Período do ruído do shader (CELL*PERIOD): o arrasto volta a zero nele sem costura.
const WRAP_METRES := 18.0*64.0
const RADIUS := 70.0
## Altura sobre o pé do foco e opacidade máxima de cada camada. Juntas chegam a ~65%
## só onde os três bancos se somam (com ~45% a névoa sumia na cor do ar: 3/255 na captura); paredes cortam cada uma num ponto diferente.
## Pedido do jogador (29/10): névoa 30% mais fraca. Mesmo fator da névoa de profundidade
## (RegionalAtmosphere3D.HARBOR_FOG_SCALE); multiplica só a opacidade, não a cobertura.
const OPACITY_SCALE := .7
const LAYERS := [Vector2(.45,.34),Vector2(1.5,.28),Vector2(2.9,.22)]
## A névoa é ar parado sendo levado: anda um pouco mais devagar que a rajada.
const DRIFT := .75
const AMOUNT_SECONDS := 8.0
const HEIGHT_SECONDS := 1.5
var material: ShaderMaterial
var planes: Array[MeshInstance3D] = []
var amount := 0.0
var target := 0.0
## Pré-aquecimento (RainPrewarm) desenha a névoa inteira sob a cortina. Ao soltar, a próxima
## condição do clima vale na hora: a névoa forçada não fica esvaindo depois da cortina.
var force := false:
	set(value):
		force = value
		if not value: _snap = true
var drift := Vector2.ZERO
var _hidden := true
var _height := 0.0
var _height_ready := false
var _coverage := -1.0
## Carregar o jogo de madrugada já mostra a névoa; não espera os 8 s de subida.
var _snap := true

func _ready() -> void:
	name = "FogBanks"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("radius",RADIUS)
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE*RADIUS*2.0
	mesh.material = material
	for i in LAYERS.size():
		var plane := MeshInstance3D.new()
		plane.name = "Layer%d" % i
		plane.mesh = mesh
		plane.position.y = LAYERS[i].x
		plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		plane.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		plane.set_instance_shader_parameter("layer",float(i))
		plane.set_instance_shader_parameter("opacity",0.0)
		add_child(plane)
		planes.append(plane)
	visible = false

## Umidade de 0 a 1 que vira névoa no chão. Litoral: bruma da madrugada, garoa e
## tempestade, céu fechado fraco. Serra: madrugada e frente fria. Deserto fica de fora
## (a poeira é outro efeito), porque `coast` e `mountain` já chegam a zero lá.
static func amount_for(hour: float, rain_level: float, clouds: float, coast: float, mountain: float, front: float) -> float:
	var h := fposmod(hour,1.0)
	# Nasce antes do sol e queima até o meio da manhã.
	var dawn := smoothstep(.17,.23,h)*(1.0-smoothstep(.31,.40,h))
	var wet := smoothstep(.05,.55,rain_level)
	var coastal := maxf(dawn*.85,maxf(wet*.8,smoothstep(.45,.80,clouds)*.35))
	var serra := maxf(dawn*.9,clampf(front,0,1)*.8)
	return clampf(coast*coastal+mountain*serra,0.0,1.0)

## Chamado pelo Weather a cada atualização do clima (5 Hz).
func set_conditions(next_amount: float, color: Color, hidden: bool) -> void:
	target = clampf(next_amount,0.0,1.0)
	if _snap and not force:
		amount = target
		_snap = false
	_hidden = hidden
	# Cor do ar da paleta, mais clara: na cor exata o banco some no véu de profundidade.
	material.set_shader_parameter("tint",color.lerp(Color.WHITE,.3))

## Todo quadro: suaviza a quantidade, arrasta o desenho e segue o pé do foco.
func advance(delta: float, wind: Vector3, focus: Vector3) -> void:
	amount = 1.0 if force else lerpf(amount,target,1.0-exp(-maxf(delta,0.0)/AMOUNT_SECONDS))
	var shown := force or (not _hidden and amount > .005)
	if visible != shown: visible = shown
	if not shown: return
	# O desenho em `p` mostra o mundo em `p - v t`: o banco anda a favor do vento.
	drift = Vector2(fposmod(drift.x-wind.x*DRIFT*delta,WRAP_METRES),fposmod(drift.y-wind.z*DRIFT*delta,WRAP_METRES))
	# Pulo, rampa e escada não sacodem a névoa; teleporte reposiciona na hora.
	if not _height_ready or absf(focus.y-_height) > 12.0: _height = focus.y
	else: _height = lerpf(_height,focus.y,1.0-exp(-maxf(delta,0.0)/HEIGHT_SECONDS))
	_height_ready = true
	global_position = Vector3(focus.x,_height,focus.z)
	material.set_shader_parameter("drift",drift)
	material.set_shader_parameter("center",Vector2(focus.x,focus.z))
	if absf(amount-_coverage) > .01:
		_coverage = amount
		material.set_shader_parameter("coverage",amount)
		var fade := smoothstep(0.0,.35,amount)
		for i in planes.size():
			planes[i].set_instance_shader_parameter("opacity",LAYERS[i].y*fade*OPACITY_SCALE)
