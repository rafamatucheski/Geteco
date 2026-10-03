extends RefCounted
## Trajeto autorado sobre as faixas reais: Cobras → Eastgate → docas.
const VERSION := 2
const TIME_LIMIT := 180.0
const OFFROAD_GRACE := 20.0
const HALF_GATE := 5.0
const GATE_INDICES := [22, 47, 72, 90]
const GRID_X := 438.0
const GRID_Z := 106.16
const POINTS := [
	Vector3(460.0041, 0, 104.9280),
	Vector3(455.0041, 0, 104.9089),
	Vector3(450.0041, 0, 104.8898),
	Vector3(445.0042, 0, 104.8708),
	Vector3(440.0042, 0, 104.8517),
	Vector3(435.0042, 0, 104.8326),
	Vector3(430.0043, 0, 104.8136),
	Vector3(425.0043, 0, 104.7945),
	Vector3(420.0044, 0, 104.7755),
	Vector3(415.0044, 0, 104.7564),
	Vector3(410.0044, 0, 104.7373),
	Vector3(405.0045, 0, 104.7176),
	Vector3(403.6801, 0, 100.6954),
	Vector3(403.8174, 0, 95.6973),
	Vector3(403.9546, 0, 90.6991),
	Vector3(404.0917, 0, 85.7010),
	Vector3(404.1222, 0, 80.7060),
	Vector3(401.3109, 0, 76.7748),
	Vector3(396.4187, 0, 76.1100),
	Vector3(391.4187, 0, 76.1106),
	Vector3(386.4187, 0, 76.1113),
	Vector3(381.4187, 0, 76.1119),
	Vector3(376.4187, 0, 76.1125),
	Vector3(371.4187, 0, 76.1131),
	Vector3(366.4187, 0, 76.1138),
	Vector3(361.4187, 0, 76.1144),
	Vector3(356.4187, 0, 76.1150),
	Vector3(351.4187, 0, 76.1146),
	Vector3(348.8703, 0, 72.8256),
	Vector3(348.8699, 0, 67.8256),
	Vector3(348.8696, 0, 62.8256),
	Vector3(348.8693, 0, 57.8256),
	Vector3(348.8688, 0, 52.8256),
	Vector3(348.8685, 0, 47.8256),
	Vector3(348.8682, 0, 42.8255),
	Vector3(348.8678, 0, 37.8256),
	Vector3(348.8675, 0, 32.8255),
	Vector3(348.7778, 0, 27.8305),
	Vector3(345.9106, 0, 23.9407),
	Vector3(341.0189, 0, 23.2702),
	Vector3(336.0189, 0, 23.2699),
	Vector3(331.0189, 0, 23.2695),
	Vector3(326.0189, 0, 23.2692),
	Vector3(321.0189, 0, 23.2689),
	Vector3(316.0189, 0, 23.2686),
	Vector3(311.0189, 0, 23.2683),
	Vector3(306.0189, 0, 23.2679),
	Vector3(301.0189, 0, 23.2676),
	Vector3(296.0189, 0, 23.2673),
	Vector3(291.0189, 0, 23.2670),
	Vector3(286.0189, 0, 23.2667),
	Vector3(281.0189, 0, 23.2664),
	Vector3(276.0189, 0, 23.2660),
	Vector3(271.0189, 0, 23.2657),
	Vector3(266.0189, 0, 23.2654),
	Vector3(261.0189, 0, 23.2651),
	Vector3(256.0189, 0, 23.2648),
	Vector3(251.0189, 0, 23.2644),
	Vector3(246.0189, 0, 23.2641),
	Vector3(241.0188, 0, 23.2638),
	Vector3(236.0188, 0, 23.2635),
	Vector3(231.0188, 0, 23.2632),
	Vector3(226.0188, 0, 23.2628),
	Vector3(221.0188, 0, 23.2625),
	Vector3(216.0187, 0, 23.2622),
	Vector3(211.0187, 0, 23.2619),
	Vector3(206.0187, 0, 23.2616),
	Vector3(201.0188, 0, 23.2612),
	Vector3(196.0188, 0, 23.2608),
	Vector3(191.1566, 0, 24.1606),
	Vector3(187.5195, 0, 27.4943),
	Vector3(186.2494, 0, 32.2616),
	Vector3(186.2500, 0, 37.2616),
	Vector3(186.2500, 0, 42.2615),
	Vector3(186.2500, 0, 47.2616),
	Vector3(186.2500, 0, 52.2616),
	Vector3(186.2500, 0, 57.2616),
	Vector3(186.2500, 0, 62.2616),
	Vector3(186.2500, 0, 67.2616),
	Vector3(186.2500, 0, 72.2615),
	Vector3(186.2500, 0, 77.2616),
	Vector3(186.2500, 0, 82.2616),
	Vector3(186.2500, 0, 87.2616),
	Vector3(186.2500, 0, 92.2616),
	Vector3(186.2500, 0, 97.2616),
	Vector3(186.2500, 0, 102.2616),
	Vector3(186.2500, 0, 107.2616),
	Vector3(186.2500, 0, 112.2616),
	Vector3(186.2500, 0, 117.2617),
	Vector3(186.2500, 0, 122.2617),
	Vector3(186.2500, 0, 127.2618),
	Vector3(186.5729, 0, 132.2178),
 ]
static var _curve: Curve3D
static func curve() -> Curve3D:
	if _curve == null:
		_curve = Curve3D.new()
		_curve.bake_interval = .4
		for point in POINTS: _curve.add_point(point)
	return _curve
static func gate(index: int) -> Vector3: return POINTS[GATE_INDICES[clampi(index,0,3)]]
static func forward(index: int) -> Vector3:
	var at: int = GATE_INDICES[clampi(index,0,3)]
	return POINTS[at-1].direction_to(POINTS[at+1])
static func grid(index: int) -> Vector3:
	return Vector3(GRID_X + floori(index/2.0)*8.0, .10, GRID_Z + (-1.22 if index%2==0 else 1.22))
static func passing_lanes(offset: float) -> Array[float]:
	# Larguras do grafo: acesso Cobra 5,25 m; Eastgate/Market/Union 7,5 m;
	# Foundry e Quay 14 m (quatro faixas). A curva usa uma faixa interior.
	if offset<60: return [-2.35,0.0]
	if offset<190: return [-3.75,0.0]
	return [3.5,-3.5,0.0]
static func offset(point: Vector3, checkpoint: int) -> float:
	var measured := curve().get_closest_offset(point)
	var upper := curve().get_closest_offset(gate(mini(checkpoint,3)))
	return minf(measured,upper) if checkpoint<4 else curve().get_baked_length()
