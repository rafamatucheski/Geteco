extends RefCounted
## Visitantes escritos usam a faixa da direita da estrada de acesso. A geometria é montada
## uma vez por admissão; o motorista físico de trânsito consome estes mesmos pontos.
const ENTRY_DISTANCE := 100.0
const MITER_LIMIT := 1.5

static func build(road: Dictionary, start_distance := ENTRY_DISTANCE) -> Array[Vector3]:
	var source: PackedVector3Array = road.get("points",PackedVector3Array())
	var center: Array[Vector3] = []
	var remaining := maxf(0.0,start_distance)
	for index in range(1,source.size()):
		var a := source[index-1]
		var b := source[index]
		var length := a.distance_to(b)
		if length<.0001: continue
		if remaining>length:
			remaining-=length
			continue
		if center.is_empty(): center.append(a.lerp(b,remaining/length))
		if center[-1].distance_squared_to(b)>.000001: center.append(b)
		remaining=0.0
	var result: Array[Vector3] = []
	if center.size()<2: return result
	# O NativeTrafficRoutes usa width/4 para a única faixa em cada sentido.
	var lane := maxf(0.0,float(road.get("width",8.0)))*.25
	for index in center.size():
		var before := center[index]-center[maxi(0,index-1)]
		var after := center[mini(center.size()-1,index+1)]-center[index]
		before.y=0.0; after.y=0.0
		if before.length_squared()<.000001: before=after
		if after.length_squared()<.000001: after=before
		var incoming := before.normalized().cross(Vector3.UP)
		var outgoing := after.normalized().cross(Vector3.UP)
		# Mantém a picape de tamanho cheio dentro da pista nas curvas R12
		# amostradas. Senão o canto externo passa do pavimento em uns 8 cm.
		# Faixas opostas retas mantêm a separação comum de quatro metros.
		var bend := 1.0-clampf(before.normalized().dot(after.normalized()),-1.0,1.0)
		var curve_lane := lane*lerpf(1.0,.9,clampf(bend/.02,0.0,1.0))
		var miter := incoming+outgoing
		var denominator := miter.dot(outgoing)
		var offset := outgoing*curve_lane
		if denominator>.0001: offset=miter*(curve_lane/denominator)
		if offset.length()>curve_lane*MITER_LIMIT: offset=offset.normalized()*curve_lane*MITER_LIMIT
		result.append(center[index]+offset+Vector3.UP*.08)
	return result
