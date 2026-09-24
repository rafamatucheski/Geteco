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
## Full original HarborStoryArrival and Localization lines, in original order.
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
	["MACIOTA", "Maciota. E você?", "Maciota. And you?"],
	["DANTE", "Dante. Foi você que me ligou?", "Dante. Were you the one who called?"],
	["MACIOTA", "Fui eu, sim. Vamos dar uma volta.", "That was me. Let's go for a ride."]]
const TOUR := [
	["MACIOTA", "Aqui é o ferro-velho do Neko. Sempre tem gente atrás de peça por aqui.", "This is Neko's scrapyard. People are always looking for parts here."],
	["MACIOTA", "O porto vive de carga e de oficina. Muita gente se conhece por causa de carro.", "The port runs on cargo and workshops. Cars bring a lot of people together."],
	["MACIOTA", "Mas tem quem misture trabalho com contrabando e corrida. É melhor saber com quem você está falando.", "Some mix work with smuggling and racing. You should know who you're talking to."],
	["MACIOTA", "Minha garagem fica mais à frente. Lá a gente conversa com calma.", "My garage is up ahead. We can talk properly there."]]
static func lines(source: Array) -> Array:
	var result := []
	for line in source: result.append({"speaker":line[0],"message":line[2] if TranslationServer.get_locale().begins_with("en") else line[1]})
	return result
