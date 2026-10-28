extends RefCounted
## Acessórios avulsos da Union: valem sobre qualquer roupa, um por encaixe.
## kind escolhe a peça em assets/outfits/DanteAccessories.gd; color a tinge.
## covers_eyes: a máscara tapa os olhos, então os óculos somem enquanto ela estiver no rosto.

const SLOTS := ["head", "eyes", "face", "neck"]
const SLOT_NAMES := {"head":"Cabeça", "eyes":"Óculos", "face":"Rosto", "neck":"Pescoço"}

const ITEMS := {
	# Cabeça
	"cap_harbor": {"name":"Boné Porto", "slot":"head", "kind":"cap_front", "color":Color("1f3550"), "price":180,
		"description":"Boné azul-marinho de aba curva, o mais visto no cais."},
	"cap_red": {"name":"Boné Vermelho", "slot":"head", "kind":"cap_front", "color":Color("b8262f"), "price":180,
		"description":"Boné vermelho de aba curva."},
	"cap_back_black": {"name":"Boné Preto Virado", "slot":"head", "kind":"cap_backwards", "color":Color("17171b"), "price":160,
		"description":"Boné preto usado com a aba para trás."},
	"beanie_gray": {"name":"Gorro Cinza", "slot":"head", "kind":"beanie", "color":Color("5b6066"), "price":120,
		"description":"Gorro de lã grossa para as noites frias."},
	"beanie_orange": {"name":"Gorro Laranja", "slot":"head", "kind":"beanie", "color":Color("d9692a"), "price":120,
		"description":"Gorro laranja de estivador, impossível de perder na neblina."},
	"cowboy_black": {"name":"Chapéu de Couro", "slot":"head", "kind":"cowboy_hat", "color":Color("231c18"), "price":650,
		"description":"Chapéu de abas largas em couro preto."},
	"fedora_black": {"name":"Fedora Preto", "slot":"head", "kind":"fedora", "color":Color("1c1c22"), "price":480,
		"description":"Fedora de feltro com fita escura, de quem resolve negócios à noite."},
	"panama": {"name":"Panamá de Palha", "slot":"head", "kind":"fedora", "color":Color("d8c79a"), "price":420,
		"description":"Chapéu de palha trançada para o sol da orla."},
	"bucket_olive": {"name":"Chapéu de Pescador", "slot":"head", "kind":"bucket", "color":Color("5d6a3c"), "price":260,
		"description":"Chapéu de lona com a aba caída, bom para a pesca no píer."},
	"beret_wine": {"name":"Boina Vinho", "slot":"head", "kind":"beret", "color":Color("6e1b27"), "price":300,
		"description":"Boina de lã cor de vinho, caída para o lado."},
	# Olhos
	"shades_black": {"name":"Óculos Escuros", "slot":"eyes", "kind":"shades", "color":Color("1b1b1f"), "price":250,
		"description":"Lentes retas e escuras."},
	"aviator_gold": {"name":"Aviador Dourado", "slot":"eyes", "kind":"aviator", "color":Color("d4a64a"), "price":550,
		"description":"Armação dourada fina e lentes em gota."},
	"sport_mirror": {"name":"Espelhado Azul", "slot":"eyes", "kind":"sport", "color":Color("2f7fd0"), "price":380,
		"description":"Lente única envolvente com espelhamento azul."},
	"round_retro": {"name":"Redondo Retrô", "slot":"eyes", "kind":"round", "color":Color("b07a2a"), "price":340,
		"description":"Armação redonda de metal e lente âmbar."},
	"thick_frame": {"name":"Armação Grossa", "slot":"eyes", "kind":"thick", "color":Color("141416"), "price":220,
		"description":"Armação de acetato preta com lente fumê."},
	"goggles_work": {"name":"Óculos de Proteção", "slot":"eyes", "kind":"goggles", "color":Color("e1a055"), "price":300,
		"description":"Óculos de oficina com elástico."},
	# Rosto
	"bandit_red": {"name":"Bandana de Bandido", "slot":"face", "kind":"bandit", "color":Color("a8232c"), "price":150,
		"description":"Lenço vermelho cobrindo nariz e boca."},
	"bandit_black": {"name":"Bandana Preta", "slot":"face", "kind":"bandit", "color":Color("1a1a1e"), "price":150,
		"description":"Lenço preto cobrindo nariz e boca."},
	"surgical": {"name":"Máscara Cirúrgica", "slot":"face", "kind":"surgical", "color":Color("8fc3d8"), "price":60,
		"description":"Máscara descartável azul-clara."},
	"skull": {"name":"Máscara de Caveira", "slot":"face", "kind":"skull", "color":Color("e4ddc8"), "price":500,
		"description":"Meia máscara de osso com dentes pintados."},
	"balaclava": {"name":"Balaclava", "slot":"face", "kind":"balaclava", "color":Color("18181b"), "price":400,
		"description":"Gorro de malha que cobre a cabeça e o rosto, deixando só os olhos."},
	"hockey": {"name":"Máscara de Hóquei", "slot":"face", "kind":"hockey", "color":Color("ece6d6"), "price":700, "covers_eyes":true,
		"description":"Máscara branca de goleiro com furos de respiro."},
	# Pescoço
	"chain_gold": {"name":"Corrente de Ouro", "slot":"neck", "kind":"chain", "color":Color("e0b54a"), "price":1200,
		"description":"Corrente grossa de ouro com pingente."},
	"chain_silver": {"name":"Corrente de Prata", "slot":"neck", "kind":"chain", "color":Color("c8ccd2"), "price":600,
		"description":"Corrente de prata com pingente."},
	"scarf_gray": {"name":"Cachecol Cinza", "slot":"neck", "kind":"scarf", "color":Color("6b7078"), "price":200,
		"description":"Cachecol de lã com uma ponta caída no peito."},
	"bandana_blue": {"name":"Bandana Azul", "slot":"neck", "kind":"bandana", "color":Color("27508f"), "price":140,
		"description":"Bandana azul amarrada no pescoço."},
	"bowtie": {"name":"Gravata-Borboleta", "slot":"neck", "kind":"bowtie", "color":Color("141418"), "price":280,
		"description":"Gravata-borboleta de cetim preto."},
}

const ORDER := [
	"cap_harbor", "cap_red", "cap_back_black", "beanie_gray", "beanie_orange", "cowboy_black", "fedora_black", "panama", "bucket_olive", "beret_wine",
	"shades_black", "aviator_gold", "sport_mirror", "round_retro", "thick_frame", "goggles_work",
	"bandit_red", "bandit_black", "surgical", "skull", "balaclava", "hockey",
	"chain_gold", "chain_silver", "scarf_gray", "bandana_blue", "bowtie",
]
