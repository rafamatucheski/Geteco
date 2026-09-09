class_name MountainRangerNPC
extends HarborConversationalNPC

## Guarda Florestal da Serra (Silas Vance):
## Personagem 3D top-down com traje de inverno, ushanka de pele e jaqueta térmica.
## Oferece ambientação, avisos sobre o frio extremo, lore sobre a gangue Lobos de Gelo
## e orientações sobre a picape 4x4 e armas de caça.

func _ready() -> void:
	character_name = "Guarda Florestal Silas"
	title_color = Color("#27ae60")
	shirt_color = Color("#c0392b") # Jaqueta xadrez vermelha/térmica
	pants_color = Color("#2c3e50") # Calça de neve reforçada
	skin_color = Color("#c89d7c")  # Rosto queimado do vento frio
	hat_color = Color("#4a2e1b")   # Ushanka / gorro de pele com abas
	has_hat = true
	is_female = false

	dialogues = [
		"Feche essa porta depressa! O vento polar da montanha congela um homem em dez minutos.",
		"Aproxime-se da lareira para aquecer o sangue. Enquanto o fogo arder, a hipotermia não te alcança.",
		"Os Lobos de Gelo tomaram o bunker no cume. Montaram metralhadoras e barricaram a pista de pouso.",
		"Deixei uma picape 4x4 com tração integral e quebra-mato estacionada aqui fora. A chave tá na ignição se precisar subir a serra.",
		"Se precisar de fuzil de caça ou munição de grosso calibre, a loja do velho Vance fica na descida da estradinha de terra.",
		"Dizem que tem um esconderijo na gruta perto das corredeiras do lago. Se atravessar a ponte pênsil a pé, você acha a entrada."
	]

	super._ready()

	if viewport_3d:
		for c in viewport_3d.get_children():
			if c is Camera3D:
				c.size = 1.35
