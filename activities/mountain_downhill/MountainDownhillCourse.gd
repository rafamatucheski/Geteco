extends RefCounted
## Passo exato da produção, invertido do cume para a base. O NativeRegion mantém o corredor
## da estrada plano; preserva o Y escrito em vez de supor que todo terreno é plano.
const LAYOUT := preload("res://world/mountain_detail/MountainRouteLayout.gd")
const TIME_LIMIT := 240.0
const HALF_GATE := 4.2
const ROAD_HALF_WIDTH := 4.375
const COUNTDOWN := 3.0
const OFFROAD_GRACE := 7.0
const RACER_COUNT := 7
const PLAYER_INDEX := 6
var route := Curve3D.new()
var length := 0.0
var gate_offsets: Array[float] = []
var turns: Array[Dictionary] = []

func _init() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://world/regions/OriginalWorldData.json"))
	var points := LAYOUT.main_route(source.mountain_control_points)
	points.reverse()
	route.bake_interval = .5
	for p in points: route.add_point(p)
	length = route.get_baked_length()
	var offset := 52.0
	while offset < length - 95.0:
		gate_offsets.append(offset)
		offset += 32.0
	gate_offsets.append(length - 75.0)
	for at in range(8, int(length)-8, 4):
		var angle := direction(float(at)-6.0).angle_to(direction(float(at)+6.0))
		if angle > .12:
			turns.append({"offset":float(at),"speed":clampf(sqrt(3.6*12.0/angle),5.5,25.0)})

func point(offset: float) -> Vector3:
	return route.sample_baked(clampf(offset,0.0,length),false)

func direction(offset: float) -> Vector3:
	return point(maxf(0.0,offset-.5)).direction_to(point(minf(length,offset+.5)))

## shift anda a vaga pela pista e spread abre a faixa para fora: vagas alternativas quando
## dois carros largos não cabem lado a lado na mesma fila.
func grid(index: int, shift := 0.0, spread := 0.0) -> Transform3D:
	# Grade na reta de 28–52 m (portão 0 em 52). Antes ia de 34 a 10 m e a terceira fila caía no
	# grampo de 14–26 m: os carros lado a lado giravam ~80° e se cruzavam ("largada ocupada").
	var offset := 49.0-floori(float(index)/2.0)*7.0+shift
	var grid_forward := direction(offset)
	var right := grid_forward.cross(Vector3.UP).normalized()
	var lane := (-1.8-spread) if index%2 == 0 else (1.8+spread)
	return Transform3D(Basis(Vector3.UP,atan2(-grid_forward.x,-grid_forward.z)),point(offset)+right*lane+Vector3.UP*.08)

func gate(index: int) -> Vector3:
	return point(gate_offsets[clampi(index,0,gate_offsets.size()-1)])

func forward(index: int) -> Vector3:
	return direction(gate_offsets[clampi(index,0,gate_offsets.size()-1)])

func start_position() -> Vector3:
	return grid(PLAYER_INDEX).origin

func nearest_offset(position: Vector3) -> float:
	return route.get_closest_offset(position)

func speed_at(offset: float, cap: float) -> float:
	var desired := cap
	for turn in turns:
		var gap: float = float(turn.offset)-offset
		if gap < -5.0 or gap > 85.0: continue
		# v²=u²+2as: tira o pé/freia antes das curvas sem derrapar no freio de mão.
		desired = minf(desired,sqrt(float(turn.speed)*float(turn.speed)+8.0*maxf(0.0,gap-6.0)))
	return minf(desired,sqrt(maxf(0.0,8.0*(length-offset-4.0))))
