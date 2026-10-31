extends RefCounted
## Observações limitadas do movimento real das rodas; nunca dirige nem pontua um carro.
const SPLITS := [60.0,201.0,402.0,800.0]
var launch := ""
var launch_score := 0.0
var shifts: Array[Dictionary] = []
var good_shifts := 0
var bad_shifts := 0
var limiter_seconds := 0.0
var wheelspin_seconds := 0.0
var nitro_seconds := 0.0
var top_kmh := 0.0
var splits: Dictionary = {}
var _serial := 0
var _finished := false

func observe(drive: RefCounted, before: float, after: float, elapsed_before: float, delta: float, finish_distance: float) -> void:
	if _finished or delta<=0.0: return
	launch=str(drive.launch_quality)
	launch_score=float(drive.launch_score)
	var fraction := clampf((finish_distance-before)/maxf(.000001,after-before),0.0,1.0) if after>=finish_distance else 1.0
	var dt := delta*fraction
	if int(drive.shift_serial)>_serial:
		_serial=int(drive.shift_serial)
		var quality := str(drive.last_shift)
		if quality in ["TROCA IDEAL","BOA TROCA"]: good_shifts+=1
		else: bad_shifts+=1
		if shifts.size()<8: shifts.append({"at":elapsed_before,"quality":quality,"gear":int(drive.gear)})
	if drive.limiter: limiter_seconds+=dt
	if float(drive.wheelspin)>.25: wheelspin_seconds+=dt
	if drive.nitro_active: nitro_seconds+=dt
	top_kmh=maxf(top_kmh,float(drive.speed_mps)*3.6)
	for metres in SPLITS:
		var key := str(int(metres))
		if metres<=finish_distance and before<metres and after>=metres and not splits.has(key):
			splits[key]=elapsed_before+delta*clampf((metres-before)/maxf(.000001,after-before),0.0,1.0)
	_finished=after>=finish_distance

func snapshot() -> Dictionary:
	var advice := "Compare as parciais com outra passada usando o mesmo acerto."
	if launch=="GIRO BAIXO": advice="Prepare mais giro antes do verde."
	elif launch=="PATINOU": advice="Solte um pouco o acelerador antes do verde."
	elif bad_shifts>0: advice="Troque dentro da faixa âmbar para manter o motor cheio."
	elif limiter_seconds>.35: advice="Antecipe a próxima marcha antes de segurar o limitador."
	elif wheelspin_seconds>1.0: advice="Experimente mais aderência para aproveitar a força na saída."
	return {"launch":launch,"launch_score":launch_score,"shifts":shifts.duplicate(true),"good_shifts":good_shifts,
		"bad_shifts":bad_shifts,"limiter_seconds":limiter_seconds,"wheelspin_seconds":wheelspin_seconds,
		"nitro_seconds":nitro_seconds,"top_kmh":top_kmh,"splits":splits.duplicate(true),"advice":advice}
