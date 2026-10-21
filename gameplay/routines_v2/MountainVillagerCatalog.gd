extends RefCounted
## Moradores de fora da serra (rotina V2). Vieram do catálogo V1 com as mesmas
## posições, nomes e falas, mas montam o corpo Meshy de `MountainVillagerModel` em
## vez do `WinterResidentModel` antigo, e o lenhador não faz mais o golpe de machado:
## a serraria/lenha da V1 não existe nesses pontos do mapa V2 e ele batia no nada.
## O ciclo de vida continua no `RoutineDirector` (proximidade, conversa, dano).

const SCALE := 1.0 / 16.0
const MOUNTAIN_OFFSET := Vector2(4300, -4960)

static func _world_point(point: Vector2) -> Vector3:
	point += MOUNTAIN_OFFSET
	return Vector3(point.x, 0.0, point.y) * SCALE

static func definitions() -> Array[Dictionary]:
	var records := [
		[Vector2(8030,895),"ELIAS","logger",Color("93624a"),["O comboio dos Lobos passou antes da nevasca.","Lenha seca vale ouro por aqui."],false],
		[Vector2(8560,785),"NORA","ranger",Color("3d6873"),["Não siga os rastros grandes na mata.","O abrigo de patrulha fica antes do mirante."],false],
		[Vector2(6560,-1205),"TOMAS","ranger",Color("59715a"),["Espere a rajada passar antes de subir.","Acima do bunker, as luzes já são da outra cidade."],false],
		[Vector2(5910,700),"LIA","trader",Color("648ea0"),[],false],
		[Vector2(6280,665),"RAUL","logger",Color("ae5c43"),[],false],
		[Vector2(7500,825),"BENTO","logger",Color("6b7950"),[],false],
		[Vector2(8360,795),"INES","trader",Color("896b9b"),[],false],
		[Vector2(7760,-95),"CAIO","ranger",Color("536c82"),[],false],
		[Vector2(6530,-1870),"HELENA","ranger",Color("ba7645"),[],false],
		[Vector2(6610,-1855),"OTTO","logger",Color("547b83"),[],false],
		[Vector2(7090,-1460),"RUTE","ranger",Color("8b4e55"),[],false],
		[Vector2(7160,-1450),"NOE","logger",Color("60816a"),[],false],
		[Vector2(6900,-2695),"IRIS","ranger",Color("5f719e"),["Bem-vindo ao Resort Cume Branco! O acesso rodoviário ao concourse está limpo.","A Boutique Alpina ao lado do chalé tem trajes de alta proteção térmica.","O teleférico da face norte opera até as 18:00 com acesso livre para hóspedes."],true],
		[Vector2(5870,755),"DORA","visitor",Color("985b71"),[],false],
		[Vector2(6225,730),"FELIPE","truck_driver",Color("aa703e"),[],false],
		[Vector2(7540,885),"ANA","visitor",Color("527b88"),[],false],
		[Vector2(8405,850),"RUI","logger",Color("7c7750"),[],false],
		[Vector2(7820,-135),"MILA","visitor",Color("8c6d9c"),[],false],
		[Vector2(6650,-1885),"PEDRO","bus_driver",Color("456781"),[],false],
		[Vector2(6660,-1810),"LUISA","visitor",Color("ab6545"),[],false],
		[Vector2(7200,-1560),"BRUNO","truck_driver",Color("957338"),[],false],
		[Vector2(7140,-1420),"CECILIA","visitor",Color("688959"),[],false],
		[Vector2(6830,-2710),"SERGIO","visitor",Color("5c7177"),["A vista da cordilheira no mirante antes da largada é incrível.","O braseiro central na praça do resort é perfeito para aquecer antes de subir ao teleférico."],true],
	]
	var shared_lines := ["Pode se aquecer no abrigo. A nevasca chega sem aviso.","O pessoal do porto sobe por aqui todos os dias."]
	var original_names := {"TOMAS":"TOMÁS","INES":"INÊS","NOE":"NOÉ","IRIS":"ÍRIS","LUISA":"LUÍSA","CECILIA":"CECÍLIA","SERGIO":"SÉRGIO"}
	var result: Array[Dictionary] = []
	for index in records.size():
		var record: Array = records[index]
		var lines: Array = record[4] if not record[4].is_empty() else shared_lines
		result.append({
			"id":"mountain_resident_%s" % str(record[1]).to_lower(),
			"display_name":original_names.get(record[1],record[1]), "region":"mountain", "place_id":"",
			"kind":"mountain_resident", "role":record[2], "coat_color":record[3], "body":"mountain_villager",
			"position":_world_point(record[0]), "stationary":record[5],
			"wander_radius":9.0, "appearance_variant":index, "lines":lines,
			"source":"V1 MountainSettlement.gd, migrado para a rotina V2",
		})
	return result
