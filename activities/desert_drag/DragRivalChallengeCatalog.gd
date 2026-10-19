extends RefCounted
## Workshop proofs reward control, not the price of the player's car.
const IDS := ["digo","livia","raul","jessica","nadir","rauhz"]
const RIVALS := {
	"digo":{"name":"Digo","part":"rival_digo_ecu","theme":"Saída e resposta","goals":[
		{"name":"Primeiro metro","distance":201.0,"objective":"Faça uma largada boa ou ideal e complete 201 m."},
		{"name":"Motor na mão","distance":402.0,"objective":"Suba 2 marchas com troca boa ou ideal. Sem erros nem reduções."}]},
	"livia":{"name":"Lívia","part":"rival_livia_tires","theme":"Tração no chão","goals":[
		{"name":"Sem desperdício","distance":201.0,"objective":"Mantenha a patinagem média até 25% nos primeiros 60 m."},
		{"name":"Saída limpa","distance":402.0,"objective":"Largue bem, sem nitro e sem passar 0,5 s no limitador."}]},
	"raul":{"name":"Raul","part":"rival_raul_gear","theme":"Cada marcha conta","goals":[
		{"name":"Escada certa","distance":402.0,"objective":"Suba 3 marchas com troca boa ou ideal. Sem erros nem reduções."},
		{"name":"Fôlego de câmbio","distance":800.0,"objective":"Nos 200 m finais, fique no máximo 0,35 s no limitador."}]},
	"jessica":{"name":"Jessica","part":"rival_jessica_turbo","theme":"Repetir é dominar","goals":[
		{"name":"Sua referência","distance":402.0,"objective":"Complete 402 m para registrar este carro e acerto."},
		{"name":"Na mesma marca","distance":402.0,"objective":"Repita o mesmo carro e acerto com diferença de até 0,30 s."}]},
	"nadir":{"name":"Nadir","part":"rival_nadir_weight","theme":"Até o último metro","goals":[
		{"name":"Motor por inteiro","distance":800.0,"objective":"Complete 800 m sem acionar o nitro."},
		{"name":"Chegada cheia","distance":800.0,"objective":"Nos últimos 100 m, conserve pelo menos 90% da velocidade de entrada."}]},
	"rauhz":{"name":"Rauhz","part":"rival_rauhz_nitro","theme":"Preparação completa","goals":[
		{"name":"Tudo no lugar","distance":402.0,"objective":"Boa largada e 2 marchas boas/ideais. Sem erros nem reduções."},
		{"name":"Domínio da reta","distance":800.0,"objective":"Boa largada, 3 marchas limpas sem redução e limitador até 0,5 s."}]},
}

static func spec(identity: String) -> Dictionary:
	return RIVALS.get(identity,{}).duplicate(true)

static func goal(identity: String, step: int) -> Dictionary:
	return RIVALS[identity].goals[step].duplicate(true) if identity in IDS and step in [0,1] else {}

static func evaluate(identity: String, step: int, metrics: Dictionary, seconds: float, reference: Dictionary = {}) -> Dictionary:
	var good_launch: bool=metrics.get("launch","") in ["LARGADA IDEAL","BOA LARGADA"]
	var good: int=int(metrics.get("good_shifts",0))
	var bad: int=int(metrics.get("bad_shifts",0))
	var limiter: float=float(metrics.get("limiter_seconds",0.0))
	var nitro: float=float(metrics.get("nitro_seconds",0.0))
	var success := false
	var detail := ""
	match identity+":"+str(step):
		"digo:0": success=good_launch; detail=str(metrics.get("launch","Sem largada registrada"))
		"digo:1": success=good>=2 and bad==0; detail="%d boas trocas · %d erros"%[good,bad]
		"raul:0": success=good>=3 and bad==0; detail="%d boas trocas · %d erros"%[good,bad]
		"livia:0":
			var spin: float=float(metrics.get("spin60_seconds",0.0))/maxf(.001,float(metrics.get("first60_seconds",0.0)))
			success=spin<=.25 and float(metrics.get("first60_seconds",0.0))>0.0
			detail="Patinagem média: %.1f%% / 25%%"%(spin*100.0)
		"livia:1": success=good_launch and nitro==0.0 and limiter<=.5; detail="%s · nitro %.1f s · limitador %.2f s"%[str(metrics.get("launch","")),nitro,limiter]
		"raul:1": success=float(metrics.get("late_limiter_seconds",0.0))<=.35; detail="Limitador nos 200 m finais: %.2f s / 0,35 s"%float(metrics.get("late_limiter_seconds",0.0))
		"jessica:0": success=true; detail="Referência registrada: %.3f s"%seconds
		"jessica:1":
			var gap := absf(seconds-float(reference.get("seconds",-100.0)))
			success=not reference.is_empty() and gap<=.30
			detail="Diferença: %.3f s / 0,300 s"%gap if not reference.is_empty() else "Registre uma referência primeiro."
		"nadir:0": success=nitro==0.0; detail="Nitro usado: %.2f s"%nitro
		"nadir:1":
			var entry: float=float(metrics.get("tail_entry_speed",0.0))
			var retained: float=float(metrics.get("tail_min_speed",0.0))/maxf(.001,entry)
			success=entry>0.0 and retained>=.90
			detail="Velocidade conservada: %.1f%% / 90%%"%(retained*100.0)
		"rauhz:0": success=good_launch and good>=2 and bad==0; detail="%s · %d boas trocas · %d erros"%[str(metrics.get("launch","")),good,bad]
		"rauhz:1": success=good_launch and good>=3 and bad==0 and limiter<=.5; detail="%d boas trocas · %d erros · limitador %.2f s"%[good,bad,limiter]
	return {"success":success,"detail":detail}
