extends Node3D
## Refúgio da Serra (26/10, carta do mundo 2.0): abrigo de toras aberto na frente, com catre,
## fogueira e lenha, a leste da largada da Pista da Sombra e a ~80 m da largada da Descida da
## Meia-Noite. Dormir no catre leva às 7h, cura e salva, de graça (RestUntil, o mesmo descanso do
## Motel Oásis). Ponto achado por tests/tools/sweep_mountain_site.gd. Sem interior nem morador.
## Origem do nó = CENTER, girado por YAW: o alpendre (+Z local) olha para o oeste, de onde a trilha
## chega. GETECO_MOUNTAIN_REFUGE=0 tira o abrigo e o catre (a fogueira é da lista de calor).
const GEO := preload("res://world/mountain_detail/forge/ForgeGeometry.gd")
const REST := preload("res://runtime/RestUntil.gd")
const CENTER := Vector3(766,0,-502)
const YAW := -PI*.5
const FOOTPRINT := Rect2(752,-516,28,28)
## Fogueira em frente ao abrigo, local: é a fonte de calor `mountain_refuge` (OriginalHeatSources).
const FIRE := Vector3(2.6,0,3.4)
## Catre dentro do abrigo, local; o jogador dorme de pé ao lado dele.
const COT := Vector3(-1.2,0,-1.4)
const COT_REACH := 1.8
var session
static var _enabled := -1

static func enabled() -> bool:
	if _enabled < 0: _enabled = 0 if OS.get_environment("GETECO_MOUNTAIN_REFUGE") == "0" else 1
	return _enabled == 1

static func world_point(local: Vector3) -> Vector3:
	return CENTER + Basis(Vector3.UP, YAW) * local

## Trilha curta da largada da Pista da Sombra até o alpendre; o terreno se aplana em volta dela.
static func approach() -> Dictionary:
	return {"id":"mountain_refuge_trail","width":1.8,"points":PackedVector3Array([Vector3(734,0,-498),Vector3(743,0,-500),Vector3(751,0,-501),Vector3(757,0,-502)])}

## Chão pisado do pátio, desenhado pelo próprio terreno como trilha de terra (lama, cascalho e neve
## amontoada na borda irregular). Antes era uma placa verde-oliva de 17 m pousada sobre a neve,
## sem ligação com o chão (pedido de 27/10). Só entra na máscara do terreno, não no mapa.
static func yard_trails() -> Array[Dictionary]:
	if not enabled(): return []
	return GEO.yard_trails("mountain_refuge_yard", [
		[Vector3(0,0,9), Vector3(1.2,0,5.2), 2.4],     # da trilha de acesso até a roda da fogueira
		[Vector3(.6,0,3.6), Vector3(4.4,0,3.6), 4.6],  # roda dos troncos-banco
		[Vector3(1.2,0,2.6), Vector3(-1.0,0,.9), 3.4], # da fogueira até a frente do abrigo
		[Vector3(2.8,0,1.4), Vector3(2.6,0,-2.4), 1.6], # até a lenha
	], CENTER, YAW)

func _ready() -> void:
	name = "MountainRefuge"
	rotation.y = YAW
	add_to_group("mountain_refuge_site")
	var g := GEO.new()
	_shelter(g)
	_yard(g)
	g.flush(self)

func _shelter(g: RefCounted) -> void:
	# Abrigo de toras 5 × 4 m: fundo e lados fechados sobre soleira de pedra, frente aberta para o
	# fogo, telhado de uma água descendo para trás, coberto de neve. O piso é um assoalho rente ao
	# chão (6 cm): o bloco de pedra de 30 cm de antes engolia o catre e os pés de quem entrava.
	var c := Vector3(-1.0,0,-1.8)
	g.part("box", c+Vector3(0,.15,-2.0), Vector3(5.7,.3,.55), "6f6f65")
	for side in [-1.0,1.0]:
		g.part("box", c+Vector3(side*2.5,.15,-.2), Vector3(.55,.3,3.9), "6f6f65")
		# Pedras soltas na quina da soleira quebram a aresta reta.
		g.part("round", c+Vector3(side*2.85,.12,1.45), Vector3(.5,.28,.45), "77776c")
	for row in 10:
		var z := -1.72+float(row)*.4
		g.part("box", c+Vector3(0,.03,z), Vector3(4.5,.06,.38), "7a5a3a" if row%3 else "6b4f33")
	# Viga de borda na frente do assoalho e pedra chata de degrau até o chão pisado.
	g.part("pole", c+Vector3(0,.09,2.2), Vector3(.2,4.9,.2), "5f432b", Vector3(0,0,PI*.5))
	g.part("round", c+Vector3(.3,.06,2.95), Vector3(1.3,.16,.8), "8d8c84")
	# Neve acumulada contra o fundo e as quinas de trás.
	g.part("round", c+Vector3(0,.12,-2.6), Vector3(5.8,.45,.9), "e8ecef")
	for side in [-1.0,1.0]:
		g.part("round", c+Vector3(side*3.0,.16,-2.5), Vector3(1.1,.5,1.0), "e8ecef")
	for row in 6:
		var y := .45+float(row)*.38
		g.part("pole", c+Vector3(0,y,-2.0), Vector3(.38,5.4,.38), "6a4b30" if row%2==0 else "5f432b", Vector3(0,0,PI*.5))
		for side in [-1.0,1.0]:
			g.part("pole", c+Vector3(side*2.5,y+.19,-.2), Vector3(.38,3.8,.38), "5f432b" if row%2==0 else "6a4b30", Vector3(PI*.5,0,0))
	GEO.solid(self, "RefugeBackWall", c+Vector3(0,1.3,-2.0), Vector3(5.4,2.6,.4))
	for side in [-1.0,1.0]:
		GEO.solid(self, "RefugeSideWall", c+Vector3(side*2.5,1.3,-.2), Vector3(.4,2.6,3.8))
		g.part("pole", c+Vector3(side*2.5,1.55,2.0), Vector3(.3,3.1,.3), "5f432b")
	# Rotação negativa em X levanta a frente (+Z): a água desce para o fundo.
	g.part("box", c+Vector3(0,3.15,0), Vector3(6.0,.2,5.0), "4d4038", Vector3(-.22,0,0))
	g.part("box", c+Vector3(0,3.28,0), Vector3(6.1,.08,5.05), "e8ecef", Vector3(-.22,0,0))
	# Catre de tábuas com cobertor e travesseiro; lampião apagado num caixote ao lado.
	g.part("box", COT+Vector3(0,.42,0), Vector3(.9,.1,2.0), "806044")
	for x in [-.38,.38]:
		for z in [-.9,.9]: g.part("box", COT+Vector3(x,.2,z), Vector3(.08,.4,.08), "5f432b")
	g.part("box", COT+Vector3(0,.52,.15), Vector3(.86,.1,1.5), "7a3b2e")
	g.part("box", COT+Vector3(0,.55,-.75), Vector3(.6,.12,.32), "cfc4a8")
	GEO.solid(self, "RefugeCot", COT+Vector3(0,.25,0), Vector3(.95,.5,2.05))
	var crate := COT+Vector3(1.1,0,-.6)
	g.part("box", crate+Vector3(0,.3,0), Vector3(.6,.6,.6), "8a6d4a")
	g.part("pole", crate+Vector3(0,.72,0), Vector3(.16,.24,.16), "3d3129")
	g.part("box", crate+Vector3(0,.72,0), Vector3(.12,.16,.12), "d9a35a")
	# Dois pares de esquis e bastões encostados por dentro do lado esquerdo.
	for k in 2:
		var at := c+Vector3(-2.15,0,.4+float(k)*.5)
		g.part("box", at+Vector3(0,.95,0), Vector3(.08,1.9,.1), "b8322a" if k==0 else "2f4f6e", Vector3(.12,0,-.1))
		g.part("box", at+Vector3(.12,.95,0), Vector3(.08,1.9,.1), "b8322a" if k==0 else "2f4f6e", Vector3(.12,0,-.1))

func _yard(g: RefCounted) -> void:
	# Troncos-banco em volta da fogueira (a fogueira em si vem da fonte de calor).
	for at in [FIRE+Vector3(1.8,0,.3), FIRE+Vector3(-.3,0,1.9), FIRE+Vector3(-1.9,0,-.1)]:
		g.part("pole", at+Vector3(0,.22,0), Vector3(.42,1.3,.42), "6a4b30", Vector3(0,0,PI*.5))
		GEO.solid(self, "LogSeat", at+Vector3(0,.22,0), Vector3(1.3,.44,.45))
	# Lenha empilhada contra o lado de fora e um trenó velho apoiado nela.
	for row in 2:
		for i in 4-row:
			g.part("pole", Vector3(2.4,.18+row*.32,-3.6+float(i)*.36+row*.18), Vector3(.32,1.6,.32), "7a5a3a", Vector3(0,0,PI*.5))
	GEO.solid(self, "RefugeWoodpile", Vector3(2.4,.4,-3.1), Vector3(1.7,.8,1.6))
	g.part("box", Vector3(3.6,.35,-2.8), Vector3(.6,.08,1.4), "806044", Vector3(.5,0,0))
	for x in [3.35,3.85]: g.part("box", Vector3(x,.2,-2.8), Vector3(.05,.08,1.5), "3a3634", Vector3(.5,0,0))
	# Pedras da clareira com neve em cima, soltas em volta (o anel de bolas verdes lia como cerca
	# de arbusto); nenhuma no rumo da trilha de acesso (+Z local).
	for i in 8:
		var angle := float(i)/8.0*TAU+sin(i*2.3)*.3
		if absf(wrapf(angle-PI*.5, -PI, PI)) < .55: continue
		var reach := 10.5+sin(i*1.7)*1.6
		var at := Vector3(cos(angle)*reach, 0, sin(angle)*reach)
		var size := Vector3(1.3,.8,1.0)*(.8+.3*sin(i*3.1))
		g.part("round", at+Vector3(0,.25,0), size, "6e716c" if i%3 else "77776c")
		g.part("round", at+Vector3(0,.25+size.y*.3,0), Vector3(size.x*.85,size.y*.4,size.z*.85), "e8ecef")

## Catre: dormir até as 7h (curado e salvo), a pé, fora do carro.
func nearest_action() -> Dictionary:
	if not _session_ready() or not session.ready_for_play or session.modal or not session.state.place_id.is_empty(): return {}
	if session.world.driving.occupied or session.world.gameplay.health <= 0: return {}
	var player: Vector3 = session.world.player.global_position
	var cot := to_global(COT)
	if Vector2(player.x-cot.x,player.z-cot.z).length() > COT_REACH or absf(player.y-cot.y) > 2.0: return {}
	return {"id":"mountain_refuge", "target":"rest", "label":"Dormir no catre até as 7h", "provider":self}

func perform(action: Dictionary) -> bool:
	if str(action.get("target","")) != "rest" or nearest_action().is_empty(): return false
	if REST.blocked(session):
		session.show_message("Encerre a atividade e despiste a polícia antes de descansar.")
		return true
	REST.until(session, 7.0, true)
	session.show_message("Você dorme no refúgio, ao lado do fogo, e acorda às 7h descansado.")
	return true

func _session_ready() -> bool:
	if session == null or not is_instance_valid(session):
		session = null
		var ancestor := get_parent()
		while ancestor != null:
			if ancestor.get("session") != null:
				session = ancestor.session
				break
			ancestor = ancestor.get_parent()
	return session != null
