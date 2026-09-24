extends RefCounted
# Verbatim production dialogue: HarborHospitalInterior3D, HarborPoliceInterior,
# HarborFireStationInterior; terminal text from the corresponding interior.
const PEOPLE := {
	"hospital_miguel":{"speaker":"Dr. Miguel","messages":["Pode pegar a vida junto aos leitos. Vou cuidar de você.","Procure atendimento sempre que precisar."]},
	"hospital":{"speaker":"Enfermeira Clara","messages":["Pode pegar a vida junto aos leitos. Vou cuidar de você.","Procure atendimento sempre que precisar."]},
	"police":{"speaker":"Sargento Morales","messages":["Harbor Patrol, 1º Distrito. Mantenha as mãos onde eu possa vê-las, cidadão.","O cais de Breakwater tá tenso ultimamente. Carga sumindo dos contêineres e os Cobras de Ferro rondando.","Se você vir algo suspeito nos becos da Foundry Avenue, venha direto ao balcão.","Não toleramos rachas nem tiroteios no perímetro do porto. Considere isso um aviso amigável."]},
	"ribeiro":{"speaker":"Detetive Ribeiro","messages":["Estamos mapeando a rede de receptação dos Cobras de Ferro no Píer Leste.","Motores adulterados, nitro contrabandeado... eles estão montando uma frota para disputas pesadas.","Aquele mural na parede não mente: cada foto tem ligação direta com os galpões do porto."]},
	"ferreira":{"speaker":"Policial Ferreira","messages":["Custódia temporária. Mantenha distância das grades, cidadão.","O suspeito ali dentro foi apanhado tentando desviar peças nos trilhos da ferrovia.","Delegacia não é ponto turístico. Faça o que veio fazer e siga seu caminho."]},
	"prisoner":{"speaker":"Dente de Ouro","messages":["Tá encarando o quê? Sai da frente da grade, moleque.","Eles acham que essas barras de ferro vão segurar os Cobras... logo, logo meu advogado chega.","Se você veio procurar o Vicente... aquele sumiu no mapa faz tempo, tá correndo em outro nível."]},
	"cida":{"speaker":"Dona Cida","messages":["Vim prestar queixa sobre umas corridas barulhentas no cais de madrugada.","Estou esperando há quase uma hora... esses policiais só correm atrás de caso grande.","Tome cuidado pelas ruas à noite, meu jovem. O porto não perdoa distrações."]},
	"fire_station":{"speaker":"Capitão Rocha","messages":["Quartel 03 em alerta constante. O porto tem risco químico e contêineres inflamáveis 24 horas por dia.","Nossas três viaturas precisam de saída livre nas baias. Nunca obstrua o pátio externo de manobra.","Se soar o alarme, todo mundo se afasta dos portões e abre caminho pro caminhão.","Temos trajes de combate a incêndio nos armários à esquerda se você quiser verificar o equipamento."]},
	"police_terminal":{"speaker":"Terminal","messages":["OCORRÊNCIA #304: Suspeita de desvio de contêiner com motores preparados no Píer Leste.\nALERTA GERAL: Facção Cobras de Ferro monitorada nas imediações da Foundry Avenue.\nSTATUS DO DISTRITO: Patrulha tática em prontidão • 1 detento sob custódia temporária."]},
	"hospital_triage":{"speaker":"Triagem","messages":["TRIAGEM MÉDICA (BAY MEDICAL):\n• Sinais vitais avaliados: Pressão arterial 120/80 mmHg, Pulso 72 BPM regular.\n• Quadro clínico geral estável.\n• Para atendimento ambulatorial ou curativos, consulte a Enfermeira Clara."]},
	"fire_alarm":{"speaker":"Alarme","messages":["TESTE DE SIRENE E PRONTIDÃO DE RESGATE:\n• Sirene de teste acionada e sinalizadores operacionais.\n• Pressão da rede de hidrantes: 15 bar (Nominal).\n• Equipamentos de combate a incêndio e macas inspecionados."]}
}
static func lines(id: String) -> Array:
	var result: Array = []
	var source: Dictionary = PEOPLE.get(id,{})
	for message in source.get("messages",[]): result.append({"speaker":source.speaker,"message":message})
	return result
