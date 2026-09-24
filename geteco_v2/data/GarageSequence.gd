extends RefCounted

## V2 adaptation, not the complete V1 arrival mission.
const ID := "harbor_arrival_v2"
const PHASES := ["meet_maciota", "talk_mechanic", "collect_part", "return_maciota", "complete"]
const OBJECTIVES := {
	"meet_maciota": "Converse com Maciota na garagem.",
	"talk_mechanic": "Converse com o mecânico.",
	"collect_part": "Pegue a peça ao lado da bancada.",
	"return_maciota": "Leve a peça para Maciota.",
	"complete": "Serviço concluído. Explore o bairro.",
}
# Original greeting: characters/JagerNPC.gd, DIALOGUES[0].
const GREETING := "Olha só quem resolveu dar as caras na minha humilde garagem... Dante, meu consagrado. Sentiu o cheiro do dinheiro ou foi o meu perfume francês?"
# New connective writing for the limited V2 sequence.
const REQUEST := "Fala com o mecânico. Ele separou uma peça pra mim."
const MECHANIC_REQUEST := "A peça está ao lado da bancada. Pode levar pro Maciota."
const THANKS := "É isso, Dante. Serviço feito. Depois a gente conversa sobre os próximos."
