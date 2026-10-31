extends RefCounted
static var ring: AudioStreamWAV
static func phone_ring() -> AudioStreamWAV:
	if ring: return ring
	var data := PackedByteArray()
	data.resize(39690 * 2)
	for i in 39690:
		var t := float(i) / 22050.0
		var ringing := t < .45 or (t >= .65 and t < 1.10)
		var bell := (sin(TAU * 853 * t) + sin(TAU * 960 * t)) * .35 * (.8 + .2 * sin(TAU * 20 * t)) if ringing else 0.0
		data.encode_s16(i * 2, clampi(int(bell * 32767), -32768, 32767))
	ring = AudioStreamWAV.new()
	ring.format = AudioStreamWAV.FORMAT_16_BITS
	ring.mix_rate = 22050
	ring.data = data
	return ring
## As conversas antigas de polícia/pátio ficam como dados para migrações; a chegada atual usa
## só a ligação em casa, o encontro no terminal e a viagem até a oficina.
const HOME_CALL := [
	["DANTE", "Alô?", "Hello?"],
	["VOZ AO TELEFONE", "Seu irmão está em Harbor.", "Your brother is in Harbor."],
	["DANTE", "Vicente? Quem está falando?", "Vicente? Who is this?"],
	["VOZ AO TELEFONE", "Se você ainda quer falar com ele, vem. Eu te encontro na chegada.", "If you still want to talk to him, come. I'll meet you when you arrive."],
	["DANTE", "Espera...", "Wait..."],
]
const POLICE := [
	["DANTE", "Vim procurar meu irmão. Vicente Ferraz. Ele estava preso aqui.", "I'm looking for my brother. Vicente Ferraz. He was in custody here."],
	["ATENDENTE", "Sim. Ele foi solto há alguns meses.", "Yes. He was released a few months ago."],
	["DANTE", "Há meses? E vocês sabem onde ele está?", "Months ago? Do you know where he is?"],
	["ATENDENTE", "Ele está envolvido com contrabando de mercadorias para carros e rachas ilegais. Estamos procurando por ele.", "He's involved in smuggling car goods and illegal street races. We're looking for him."],
	["DANTE", "Espera... contrabando? Eu não estou entendendo.", "Wait... smuggling? I don't understand."]]
const PHONE := [
	["DANTE", "Alô?", "Hello?"],
	["CONTATO", "Preciso falar com você. Encontra comigo no ferro-velho do Neko.", "I need to talk to you. Meet me at Neko's scrapyard."],
	["DANTE", "Quem está falando?", "Who's calling?"],
	["CONTATO", "Você vai me reconhecer. Estou perto de um sedã preto preparado, estilo M8 Competition.", "You'll recognize me. I'm next to a black performance sedan, M8 Competition style."]]
const MEETING := [
	["MACIOTA", "Dante, temos muito que conversar.", "Dante, we have a lot to talk about."],
	["DANTE", "Foi você que me ligou?", "Were you the one who called?"],
	["MACIOTA", "Fui eu. Maciota. Vamos até a minha oficina.", "That was me. Maciota. Let's go to my workshop."],
	["DANTE", "Como você me reconheceu?", "How did you recognize me?"],
	["MACIOTA", "Um contato conseguiu uma foto do teu histórico da polícia. Entra, no carro a gente conversa.", "A contact got me a photograph from your police record. Get in. We'll talk in the car."],
]
const TOUR := [
	["MACIOTA", "Esse porto vive de carga e oficina. Teu irmão passou por aqui.", "This port runs on cargo and workshops. Your brother came through here."],
	["MACIOTA", "Vi o Vicente. Depois começaram a aparecer clientes com carro sumido e conta pra pagar.", "I saw Vicente. Then customers started coming in with missing cars and debts to pay."],
	["MACIOTA", "Tem gente que conhece o caminho dele. Preciso confirmar umas coisas antes de te colocar no meio.", "Some people know where he went. I need to confirm a few things before bringing you into this."],
	["MACIOTA", "Minha oficina fica entre esses galpões. Lá a gente conversa com calma.", "My workshop is between those warehouses. We can talk properly there."],
]
static func lines(source: Array) -> Array:
	var result := []
	for line in source: result.append({"speaker":line[0],"message":line[2] if TranslationServer.get_locale().begins_with("en") else line[1]})
	return result
