extends RefCounted

## Stable legacy save phases plus the current Harbor introduction.
const ID := "harbor_arrival_v2"
const PHASES := ["meet_maciota", "talk_mechanic", "collect_part", "return_maciota", "complete"]
const OBJECTIVES := {
	"meet_maciota": "Converse com Maciota na garagem.",
	"talk_mechanic": "Converse com o mecânico.",
	"collect_part": "Pegue a peça ao lado da bancada.",
	"return_maciota": "Leve a peça para Maciota.",
	"complete": "Serviço concluído. Explore o bairro.",
}
# The legacy bench task remains readable for saves already inside that sequence.
const GREETING := "Olha só quem resolveu dar as caras na minha humilde garagem... Dante, meu consagrado. Sentiu o cheiro do dinheiro ou foi o meu perfume francês?"
const REQUEST := "Fala com o mecânico. Ele separou uma peça pra mim."
const MECHANIC_REQUEST := "A peça está ao lado da bancada. Pode levar pro Maciota."
const THANKS := "É isso, Dante. Serviço feito. Depois a gente conversa sobre os próximos."

# Current campaign: the conversation opens real favors instead of asking Dante
# to carry a prop across the same room. Speaker / Portuguese / English.
const INTRO_LINES := [
	["MACIOTA", "Entra, Dante. Vi o Vicente por aqui. Ele deixou muita gente com problema nesta região.", "Come in, Dante. I saw Vicente around here. He left a lot of people in trouble in this district."],
	["DANTE", "Você sabe onde ele está?", "Do you know where he is?"],
	["MACIOTA", "Ainda não tenho um endereço. Tenho clientes que fizeram serviço pra ele. Vou conversar com essa gente.", "I don't have an address yet. Some of my customers worked for him. I'll talk to them."],
	["DANTE", "E como você conhece nós dois?", "And how do you know both of us?"],
	["MACIOTA", "Você recuperou um carro pra mim, anos atrás. Roubaram durante um transporte e disseram que eu tinha feito parte do negócio. Eu quase perdi a oficina.", "You recovered a car for me, years ago. It was stolen during a transport job and they said I was involved. I nearly lost the workshop."],
	["DANTE", "Não lembro de você.", "I don't remember you."],
	["MACIOTA", "Imagino. Pra você era trabalho. Pra mim era tudo. Você achou o carro e mostrou que tinham me enganado.", "I figured. For you it was work. For me it was everything. You found the car and proved I'd been deceived."],
	["DANTE", "E o Vicente?", "And Vicente?"],
	["MACIOTA", "Passou pela oficina. Fazia serviço com os Cobras. Depois começou a aparecer em cobrança, carro sumido, corrida que ninguém queria comentar.", "He came through the workshop. He worked with the Cobras. Then his name started coming up in collections, missing cars and races nobody wanted to talk about."],
	["MACIOTA", "Eu quero te ajudar. Mas preciso que você me faça um favor. Uma mão lava a outra nesta cidade.", "I want to help you. But I need you to do me a favor. We look out for each other in this city."],
	["DANTE", "O que você precisa?", "What do you need?"],
	["MACIOTA", "Uma peça minha ficou no porto. Primeiro resolve o comprovante com a Helena. Traz a encomenda e eu vou atrás de quem trabalhou com teu irmão.", "One of my parts is still at the port. First sort out the receipt with Helena. Bring back the shipment and I'll find the people who worked with your brother."],
]
