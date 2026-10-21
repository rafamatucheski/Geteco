extends RefCounted
## Falas das missões A2-05 a A2-13 (roteiro em docs/roteiro-diretor-geteco-20261021.md, seção "Ato 2").
## Escritas pela seção "Como escrever as falas" do roteiro: fala curta, português falado, subtexto,
## ninguém explica o que o outro já sabe. Parênteses são direção (o registro de vozes tira do texto
## falado). Só legenda por enquanto: tools/build_voice_registry.py lista cada fala com a chave da voz.
## Cada função devolve linhas [quem fala, texto] para VicenteReunion._say.

# --- A2-05 "Racha de irmãos" ---------------------------------------------------------------------

static func brothers_start() -> Array:
	return [
		["Lívia", "Ô, turma! Hoje tem uma que eu não achei que ia ver."],
		["Vicente", "Eu e você. Oitocentos. Sem aposta."],
		["Dante", "E se eu ganhar?"],
		["Vicente", "Aí eu te conto aquela noite. Se perder, conto igual."],
		["Vicente", "Só queria te ver largando do meu lado de novo. Encosta na concentração."],
	]

static func brothers_after(won: bool) -> Array:
	var rows: Array = []
	if won:
		rows.append_array([
			["Vicente", "Ainda segura o giro até doer."],
			["Dante", "Aprendi com você."],
			["Vicente", "Aprendeu a ganhar de mim, isso sim."],
		])
	else:
		rows.append_array([
			["Vicente", "Cê tirou o pé no fim."],
			["Dante", "Não tirei."],
			["Vicente", "Tirou. Eu conheço meu irmão."],
		])
	rows.append_array([
		["Vicente", "Lá dentro eu pensava nessa reta todo dia."],
		["Vicente", "(pausa longa) A Monaliza do Maciota tá contigo, né? Bonito carro."],
		["Vicente", "A mesa de pedra. Ao sul do leito seco. Me acha lá e eu te conto. Inteiro."],
	])
	return rows

# --- A2-06 "Mesa de pedra" ------------------------------------------------------------------------
# Entre cave_before e cave_after entra o flashback jogável da blitz pelo ponto de vista do Vicente
# (sessão do prólogo; quando ela não existe, a conversa segue direto).

static func cave_before(letters_done: bool, coyote_taken: bool) -> Array:
	var rows: Array = [
		["Vicente", "A gente acampava aqui com o pai. Ele chamava essa pedra de mesa posta."],
		["Dante", "E o Coyote?"],
	]
	if coyote_taken:
		rows.append(["Vicente", "Cê levou. Leu tudo e veio buscar. (pausa) Fiquei uma noite olhando a vaga vazia."])
	elif letters_done:
		rows.append(["Vicente", "Debaixo da lona. A chave do cadeado tá na última carta, cê sabe."])
	else:
		rows.append(["Vicente", "Debaixo da lona, com cadeado. A chave tá nas cartas. Lê todas e ele é teu."])
	rows.append_array([
		["Dante", "Conta aquela noite."],
		["Vicente", "Um conhecido do Cobre me ofereceu um frete na última hora. Pagava o dobro. Era só não abrir a carga."],
		["Vicente", "Eu precisava pagar o Teodoro. Peguei."],
		["Vicente", "Chovia. O rádio não parava: não para, não para, não para..."],
	])
	return rows

static func cave_after() -> Array:
	return [
		["Vicente", "Você sabia. Na hora. Eu vi no teu olho."],
		["Dante", "Sabia."],
		["Vicente", "E fechou."],
		["Dante", "Achei que o processo te tirava de lá em um mês."],
		["Vicente", "(ri sem graça) O processo. Oito anos de processo."],
		["Dante", "Na véspera, eu recebi a escala. Teu nome já tava escrito."],
		["Vicente", "Na véspera."],
		["Dante", "Antes do banco mexer na ordem. Alguém sabia que cê ia estar naquele caminhão antes de você."],
		["Vicente", "E minhas cartas voltando. Quem faz isso com carta de preso?"],
		["Dante", "Quem mexe na correspondência do presídio. A Dona Fátima, da capela, viu alguém perguntando de você."],
		["Vicente", "(silêncio. joga um graveto no fogo) Vai lá então. Eu não vou."],
	]

# Compatibilidade: a conversa inteira, sem o flashback no meio.
static func cave(letters_done: bool, coyote_taken: bool) -> Array:
	return cave_before(letters_done, coyote_taken) + cave_after()

# --- A2-07 "Destinatário desconhecido" ----------------------------------------------------------

static func fatima() -> Array:
	return [
		["Dona Fátima", "O moço da vela. O Vicente acende uma toda semana."],
		["Dante", "Alguém mais perguntou dele?"],
		["Dona Fátima", "Um homem de jaqueta de polícia. Faz um mês. Deixou uma vela \"pelo rapaz\" e saiu correndo."],
		["Dona Fátima", "Polícia não acende vela, meu filho. Anotei a placa."],
		["Dante", "A senhora anotou?"],
		["Dona Fátima", "Atrás do santinho. Leva. E reza um pouquinho, que mal não faz."],
		["Dante", "Aqui não pega celular. A torre da Rua Principal alcança Harbor."],
	]

static func tower() -> Array:
	return [
		["Dante", "Maciota. Mais uma placa."],
		["Maciota", "Cê tá onde? Parece que tá dentro de uma lata."],
		["Dante", "Numa torre. Carro que andou perguntando do Vicente."],
		["Maciota", "Espera."],
		["Maciota", "Dante. É do norte. Garagem da polícia. Viatura sem identificação."],
		["Dante", "Lá em cima de novo."],
		["Maciota", "E outra: o malote do presídio passava pela cooperativa de Santa Lua. Se as cartas voltaram, passaram por lá."],
		["Maciota", "(pausa) Santa Lua. Não é de lá a moça do banco?"],
	]

static func coop() -> Array:
	return [
		["Joana · rádio", "Malote antigo? Aqui ninguém joga papel fora. Minha sobrinha tá organizando tudo."],
		["Helena · rádio", "Achei, tia. (pausa) Dez envelopes devolvidos. Vicente Ferraz."],
		["Dante", "Tem alguma coisa atrás?"],
		["Helena · rádio", "Carimbo de conferência. Zero, quatro, um, sete."],
		["Dante", "De novo."],
		["Vicente · rádio", "Eu ouvi. A Joana deixou o rádio aberto."],
		["Vicente · rádio", "Então não foi você. Nem o carteiro."],
		["Dante", "Não."],
		["Vicente · rádio", "Então agora é com nós dois."],
		["Joana · rádio", "O rádio tá consertado, a cooperativa paga o combinado. E a Helena falou pra você subir na caixa-d'água. Disse que é lá que dá sinal."],
	]

static func water_tower() -> Array:
	return [
		["Helena", "Aqui não dá sinal nenhum."],
		["Dante", "Eu desconfiei."],
		["Helena", "Minha tia é péssima mentindo. (pausa) Senta."],
		["Helena", "Minha mãe subia aqui pra ver a estrada. Dizia que um dia ia passar alguém que valesse a pena."],
		["Dante", "Passou?"],
		["Helena", "Passou um monte de caminhão."],
		["Dante", "A minha rezava. Por mim e pelo meu irmão. Mais por mim."],
		["Helena", "Por quê?"],
		["Dante", "Porque eu era o que prendia."],
		["Helena", "(encosta a cabeça no ombro dele)"],
		["Helena", "Não estraga isso prometendo coisa."],
	]

# --- A2-08 "Chave na chave" -----------------------------------------------------------------------

static func jessica_bet() -> Array:
	return [
		["Jessica", "Melhorou. Lembra de Harbor ainda?"],
		["Dante", "Lembro. Preciso do comboio dos Cobras."],
		["Jessica", "Eu fazia frete pra eles. Duas madrugadas por semana, pela Estrada do Sal."],
		["Jessica", "Hora certa, só o piloto deles sabe. O Cascavel. (aponta com o queixo) Tá olhando teu carro desde que cê chegou."],
	]

static func cascavel() -> Array:
	return [
		["Cascavel", "O irmão do Vicente. Falam de você por aqui."],
		["Dante", "Cê sabe a hora do comboio."],
		["Cascavel", "Sei. Chave na chave: ganhou, leva a hora e a rota. Perdeu, me dá a chave daquela Monaliza."],
		["Vicente", "Dante. Não aposta carro com essa gente. Eles não perdem."],
		["Dante", "Fechado."],
		["Cascavel", "Assina o quadro. Te espero na concentração."],
	]

static func cascavel_keys(won: bool) -> Array:
	var rows: Array = []
	if won:
		rows.append_array([
			["Cascavel", "Bonito. Pena que aqui a regra é minha."],
			["Cascavel", "Meus meninos tão do lado da tua Monaliza. A chave. Ou ninguém sai inteiro."],
		])
	else:
		rows.append_array([
			["Cascavel", "Chave na chave. Regra é regra."],
			["Dante", "O turbo morreu no meio da reta."],
			["Cascavel", "Carro velho. Acontece."],
		])
	rows.append_array([
		["Bia", "Chave na chave é o carro, não o que tem dentro. Tirei tudo do porta-malas. Fica comigo."],
		["Cascavel", "A Monaliza vai passear lá no norte. Quer, vai buscar."],
		["Vicente", "(segura uma mangueira cortada) Tava no chão da concentração."],
		["Vicente", "Eu te falei."],
		["Jessica", "Eu te pus nessa. Pelo menos isso: depois da meia-noite, saindo da Estrada do Sal pro leste."],
		["Jessica", "E arruma outro carro. Sem porta-malas ninguém anda por aqui."],
	])
	return rows

# --- A2-09 "Porta-malas novo" ---------------------------------------------------------------------

static func nonato() -> Array:
	return [
		["Nonato", "Carro? Tem um Bison lá no fundo. Motor cansado, sem placa, banco rasgado."],
		["Nonato", "Pra mim não vale nada. Pra você vale o que cê conseguir fazer andar."],
		["Dante", "Quanto?"],
		["Nonato", "O Vicente me pagou um café uma vez, quando ninguém pagava. Leva. Tá na baia."],
	]

static func trunk_ready(nonato_car: bool) -> Array:
	var rows: Array = [
		["Bia", "Deixa o Digo olhar."],
		["Digo", "Motor ruim. Acerta. Me dá uma hora."],
	]
	if nonato_car: rows.append(["Digo", "Esse Bison do Nonato vai andar melhor que muito carro de loja."])
	rows.append_array([
		["Digo", "Fundo falso, trava dupla, o mesmo espaço da Monaliza. Só acha quem souber."],
		["Bia", "E a caixa. Tudo que tava na Monaliza. Agora mora aqui."],
		["Digo", "Agora, Dante. Mangueira de turbo não corta sozinha. Quem fez sabia o que tava fazendo."],
		["Bia", "(olha pro lado) Tem coisa que eu vi e não sei se devia ter visto."],
		["Dante", "Fala."],
		["Bia", "Hoje não."],
	])
	return rows

# --- A2-10 "Comboio da madrugada" -----------------------------------------------------------------

static func convoy_motel() -> Array:
	return [
		["Vicente", "Pegou?"],
		["Dante", "O livro de cargas. E o lacre. Do baú certo."],
		["Vicente", "Deixa eu ver. (vira o lacre na luz) Esse não raspado. Número da salina."],
		["Dante", "Igual ao da Vértice. A carga da operação saiu das Salinas."],
		["Vicente", "O Seu Bento manda lá faz vinte anos. Se trocaram carga no pátio dele, ele viu."],
		["Vicente", "Toma. Metade do baú era dinheiro dos Cobras."],
		["Dante", "E a outra metade?"],
		["Vicente", "(guarda a mão no bolso) A outra metade era de quem deve pra eles. Melhor com você."],
	]

# --- A2-11 "Sal na ferida" ------------------------------------------------------------------------

static func bento() -> Array:
	return [
		["Seu Bento", "Esse lacre é meu. Quer dizer, da salina."],
		["Dante", "A carga da operação saiu daqui?"],
		["Seu Bento", "Os caminhões dos Cobras paravam no pátio de noite. Trocavam a carga. Completavam o peso com sal."],
		["Seu Bento", "Por isso o do teu irmão pesou menos na balança da Rosa. Tinha sal no lugar."],
		["Dante", "O senhor anotava?"],
		["Seu Bento", "Num caderno. Mandaram queimar. Dei pra um rapaz da serra guardar."],
		["Seu Bento", "Lá no sul, perto do leito seco, tem um acampamento. Se o caderno ainda existe, tá com aquela gente."],
	]

static func ledger() -> Array:
	return [
		["Dante", "Meio queimado. Dá pra ler."],
		["Dante", "A noite da operação. Carga trocada. Peso com sal. Caminhão liberado."],
		["Dante", "Autorizado: zero, quatro, um, sete."],
	]

static func helena_home() -> Array:
	return [
		["Helena", "Não encosta em nada. A tia já chamou a polícia. A daqui, que é a mesma coisa que nada."],
		["Dante", "Você tá bem?"],
		["Helena", "Eu tô. A pasta não. Levaram tudo. A conta dos Cobras, a cópia da ordem, tudo."],
		["Dante", "(abaixa, pega alguma coisa do chão) Chave de carro. Chaveiro de oficina de Harbor."],
		["Helena", "Conhece?"],
		["Dante", "Conheço."],
		["Helena", "Dante. Quem?"],
		["Dante", "Fica com a tua tia hoje. Não abre a porta pra ninguém."],
	]

# --- A2-12 "Teodoro" ------------------------------------------------------------------------------

static func teodoro_motel() -> Array:
	return [
		["Dona Lurdes · rádio", "Dante? É a Lurdes, do Oásis. Teu irmão tá no seis com um homem de terno. Tão discutindo."],
		["Teodoro", "Dante Ferraz. Chegou cedo."],
		["Dante", "(olha a pasta na mão dele) Essa pasta é da Helena."],
		["Vicente", "Eu ia te contar."],
		["Dante", "A Monaliza. A mangueira. A casa dela."],
		["Vicente", "O Prado mandou recado pelo Teodoro. Ou a pasta, ou você. Eu escolhi você."],
		["Dante", "Cê escolheu pagar tua dívida."],
		["Vicente", "Eu devo a vida inteira pra essa gente, Dante! A vida inteira!"],
		["Teodoro", "Bom. Vejo que vocês têm o que conversar."],
	]

static func brothers_fight_after() -> Array:
	return [
		["Vicente", "(no chão, cuspindo areia) Ainda bate igual o pai."],
		["Dante", "Levanta."],
		["Vicente", "Ele foi pra norte. Pela obra. Com metade da pasta."],
		["Dante", "E a outra metade?"],
		["Vicente", "(tira um caderno da jaqueta) Não dei tudo. Nunca dou tudo."],
	]

static func teodoro_gate(caught: bool) -> Array:
	var rows: Array = []
	if caught:
		rows.append_array([
			["Teodoro", "Não chega perto. Eu só faço o que mandam."],
			["Dante", "Quem manda?"],
			["Teodoro", "Cê sabe quem. Ele te deu medalha uma vez."],
			["Teodoro", "(joga a pasta no chão e passa pela barreira, a pé)"],
		])
	else:
		rows.append(["Dante", "Passou a pé pela obra. Carro não atravessa a barreira."])
	rows.append_array([
		["Dante", "Largou a pasta. Recibo de hotel no norte. E um cartão: zero, quatro, um, sete."],
	])
	return rows

# --- A2-13 "Os oito anos" -------------------------------------------------------------------------

static func finale_grandstand() -> Array:
	return [
		["Vicente", "Desculpa."],
		["Dante", "Pelo quê?"],
		["Vicente", "Por tudo que eu fiz esse mês. (devolve o caderno) Tá aqui o que sobrou. Com o do Bento."],
		["Dante", "O manifesto, a balança, a ordem, as cartas, o lacre, o caderno, a pasta. Tudo com o mesmo número."],
		["Vicente", "E o que eu faço com os oito anos que eu perdi?"],
		["Dante", "O que eu faço com os oito que eu deixei você perder?"],
		["Lívia · rádio", "Vicente! Os Cobras tão descendo pro encontro. Muita gente. Armada."],
		["Vicente", "Vieram buscar o caderno. Vamos."],
	]

static func finale_gate() -> Array:
	return [
		["Helena", "(segura o braço, sangrando de raspão) Foi de raspão. Para de olhar assim."],
		["Vicente", "A obra acabou. Olha. Tão tirando a barreira."],
		["Dante", "Lá em cima tá quem assinou."],
		["Maciota · telefone", "Dante. A matrícula. Delegado Aurélio Prado."],
		["Dante", "(fecha os olhos)"],
		["Maciota · telefone", "Teu antigo chefe. E a minha Monaliza tá lá também, numa oficina dos Cobras."],
		["Maciota · telefone", "Ele tá esperando vocês. Os dois. E eu quero minha Monaliza de volta."],
		["Helena", "Três. Ele tá esperando três."],
		["Vicente", "Dirige você. Eu fico de olho na estrada."],
	]
