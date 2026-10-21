extends RefCounted
## Falas das missões A2-05 a A2-13 (roteiro em docs/story-act2-vicente-20261020.md). Só legenda: não há
## gravação de voz para elas. Cada função devolve linhas [quem fala, texto] para VicenteReunion._say.
## O ato prova a armação e aponta o norte, mas não diz quem é a matrícula 0417: isso é o ato 3.

# --- A2-05 "Racha de irmãos" ---------------------------------------------------------------------

static func brothers_start() -> Array:
	return [
		["Lívia", "Atenção, turma. Hoje tem uma prova que eu nunca achei que ia ver."],
		["Vicente", "Você e eu, Dante. Oitocentos metros. Sem aposta, sem plateia comprada."],
		["Dante", "E se eu ganhar?"],
		["Vicente", "Aí eu te conto aquela noite. Se perder, eu conto do mesmo jeito. Só queria ver você largar do meu lado de novo."],
		["Vicente", "Encosta o carro na concentração. Eu vou com o meu."],
	]

static func brothers_after(won: bool) -> Array:
	var rows: Array = []
	if won:
		rows.append_array([
			["Vicente", "Ainda acelera do mesmo jeito. Segurando o giro até doer."],
			["Dante", "Aprendi com você."],
			["Vicente", "Aprendeu a ganhar de mim, isso sim. Lá dentro eu pensava nessa reta todo dia."],
		])
	else:
		rows.append_array([
			["Vicente", "Lá dentro eu pensava nessa reta todo dia. Achei que tinha esquecido como era."],
			["Dante", "Não esqueceu."],
			["Vicente", "Você tirou o pé no fim. Não precisava ter feito isso."],
			["Dante", "Eu não tirei."],
			["Vicente", "Tirou, sim. Eu conheço meu irmão."],
		])
	rows.append_array([
		["Vicente", "A mesa de pedra, ao sul do leito seco. A caverna. Me encontra lá."],
		["Vicente", "Lá eu conto aquela noite. Inteira."],
	])
	return rows

# --- A2-06 "Mesa de pedra" ------------------------------------------------------------------------

static func cave(letters_done: bool, coyote_taken: bool) -> Array:
	var rows: Array = [
		["Vicente", "A gente acampava aqui com o pai. Ele dizia que essa pedra tinha a forma de uma mesa posta."],
		["Dante", "E o Coyote?"],
	]
	if coyote_taken:
		rows.append_array([
			["Vicente", "Você levou. Leu as dez cartas e veio buscar."],
			["Vicente", "Fiquei olhando a vaga vazia uma noite inteira. Não sei se fiquei com raiva ou aliviado. Feito a carta dois."],
		])
	elif letters_done:
		rows.append(["Vicente", "Debaixo da lona, esperando. Você leu as cartas. A chave do cadeado é a última delas."])
	else:
		rows.append(["Vicente", "Debaixo da lona, com cadeado. A chave está nas cartas. Quando você ler todas, ele é seu."])
	rows.append_array([
		["Dante", "Conta aquela noite."],
		["Vicente", "Um conhecido do Cobre me ofereceu um frete na última hora. Pagava o dobro. Só pediu pra eu não abrir a carga."],
		["Vicente", "Eu precisava do dinheiro do advogado. Peguei."],
		["Dante", "Na véspera da operação, eu recebi a escala. O nome do motorista já estava escrito: Vicente Ferraz."],
		["Vicente", "Na véspera?"],
		["Dante", "Antes de o banco alterar a ordem. Alguém sabia que você ia estar naquele caminhão antes de você saber."],
		["Vicente", "Então você sabia que era eu."],
		["Dante", "Soube na hora de fechar a algema. Tentei sair da escala de manhã. Não deixaram."],
		["Vicente", "E você fechou do mesmo jeito."],
		["Dante", "Fechei. E passei oito anos tentando abrir."],
		["Vicente", "As minhas cartas voltaram todas. Destinatário desconhecido. Quem faz isso com carta de preso?"],
		["Dante", "Quem tem acesso à correspondência do presídio. A capela, Vicente. A Dona Fátima viu alguém perguntando por você."],
	])
	return rows

# --- A2-07 "Destinatário desconhecido" ----------------------------------------------------------

static func fatima() -> Array:
	return [
		["Dona Fátima", "O moço da vela. O Vicente acende uma toda semana."],
		["Dante", "Alguém mais andou perguntando por ele?"],
		["Dona Fátima", "Um homem de jaqueta de polícia, faz um mês. Deixou uma vela \"pelo rapaz\" e foi embora com pressa."],
		["Dona Fátima", "Polícia não deixa vela, meu filho. Achei estranho e anotei a placa do carro."],
		["Dante", "A senhora tem a placa?"],
		["Dona Fátima", "Atrás do santinho. Leva. E reza um pouco também, que mal não faz."],
		["Dante", "Daqui o celular não pega. A torre de rádio da Rua Principal alcança Harbor."],
	]

static func tower() -> Array:
	return [
		["Dante", "Maciota, é o Dante. Preciso de mais uma placa."],
		["Maciota", "Você está numa torre? Parece que está dentro de uma lata."],
		["Dante", "Estou. A placa é de um carro que andou perguntando pelo Vicente."],
		["Maciota", "Já te ligo. Fica aí."],
		["Maciota", "Dante. Carro registrado no norte, numa garagem da polícia. Viatura descaracterizada."],
		["Dante", "Lá em cima, de novo."],
		["Maciota", "E tem mais: o malote do presídio vinha pela cooperativa de Santa Lua. Se as cartas voltaram, passaram por lá."],
	]

static func coop() -> Array:
	return [
		["Joana · rádio", "Malote antigo? A cooperativa guarda tudo. A gente não joga papel fora aqui."],
		["Joana · rádio", "Dez envelopes devolvidos ao presídio, nome Vicente Ferraz. Carimbo de destinatário desconhecido."],
		["Dante", "Tem alguma coisa no verso?"],
		["Joana · rádio", "Um carimbo de conferência. Zero, quatro, um, sete."],
		["Dante", "A mesma matrícula."],
		["Vicente · rádio", "Eu ouvi. A Joana deixou o rádio aberto."],
		["Vicente · rádio", "Então não foi você. Nem o carteiro. Foi a mesma gente que me pôs no caminhão."],
		["Dante", "Foi."],
		["Vicente · rádio", "Então isso agora é com nós dois."],
		["Joana · rádio", "Pelo rádio consertado, a cooperativa paga o combinado. E boa sorte, vocês dois."],
	]

# --- A2-08 "Chave na chave" -----------------------------------------------------------------------

static func jessica_bet() -> Array:
	return [
		["Jessica", "Você melhorou. Ainda lembra daquele serviço em Harbor?"],
		["Dante", "Lembro. Preciso de outra coisa agora: o comboio dos Cobras."],
		["Jessica", "Eu fiz frete pra transportadora deles. Os papéis originais passam pela Estrada do Sal duas madrugadas por semana."],
		["Jessica", "A hora exata só o piloto deles sabe. O Cascavel. E ele está ali, olhando o teu carro desde que você chegou."],
	]

static func cascavel() -> Array:
	return [
		["Cascavel", "O irmão do Vicente. A turma fala de você."],
		["Dante", "Você sabe a hora do comboio."],
		["Cascavel", "Sei. Chave na chave: se você ganhar, leva a hora e a rota. Se perder, me dá a chave daquela Monaliza."],
		["Vicente", "Dante. Não aposta o carro com essa gente. Eles não perdem."],
		["Dante", "Fechado."],
		["Cascavel", "Assina o quadro. Te espero na concentração."],
	]

static func cascavel_keys(won: bool) -> Array:
	var rows: Array = []
	if won:
		rows.append_array([
			["Cascavel", "Bonita prova. Pena que aqui a regra é minha."],
			["Cascavel", "Os meninos estão do lado da tua Monaliza. A chave, Dante. Ou ninguém sai inteiro."],
		])
	else:
		rows.append_array([
			["Cascavel", "Chave na chave. Regra é regra."],
			["Dante", "O turbo morreu no meio da reta."],
			["Cascavel", "Carro velho, irmão. Acontece."],
		])
	rows.append_array([
		["Bia", "Chave na chave é o carro, não o que tem dentro. Tirei o porta-malas inteiro. Fica comigo na oficina."],
		["Cascavel", "A Monaliza vai passear lá no norte. Se quiser, vai buscar."],
		["Vicente", "Achei isso no chão da concentração. Mangueira de turbo. Cortada."],
		["Vicente", "Eu te falei."],
		["Jessica", "Eu te pus nessa. Pelo menos isso: madrugada, depois da meia-noite, saindo da Estrada do Sal pro leste."],
		["Jessica", "E, Dante. Arruma outro carro. Com o porta-malas que você tinha, não dá pra andar a pé por aqui."],
	])
	return rows

# --- A2-09 "Porta-malas novo" ---------------------------------------------------------------------

static func nonato() -> Array:
	return [
		["Nonato", "Carro? Tenho um Bison no fundo do pátio. Motor cansado, sem placa, banco rasgado."],
		["Nonato", "Esse aí não vale nada pra mim. Pra você vale o que você conseguir fazer andar."],
		["Dante", "Quanto?"],
		["Nonato", "O Vicente pagou um café pra mim uma vez quando ninguém pagava. Leva. Está na baia."],
	]

static func trunk_ready(nonato_car: bool) -> Array:
	var rows: Array = [
		["Bia", "Trouxe o carro. Deixa o Digo olhar."],
		["Digo", "Motor ruim, mas acerta. Deixa comigo uma hora."],
	]
	if nonato_car: rows.append(["Digo", "Esse Bison do Nonato vai andar melhor que muito carro de concessionária."])
	rows.append_array([
		["Digo", "Fundo falso, trava dupla, o mesmo espaço do porta-malas da tua Monaliza. Ninguém acha se não souber."],
		["Bia", "E aqui está a caixa: tudo que estava na Monaliza. Agora mora no porta-malas novo."],
		["Digo", "Agora uma coisa, Dante. Mangueira de turbo não corta sozinha. Quem fez isso sabia o que estava fazendo."],
		["Dante", "Eu sei quem fez. Ainda não sei quem mandou."],
	])
	return rows

# --- A2-10 "Comboio da madrugada" -----------------------------------------------------------------

static func convoy_motel() -> Array:
	return [
		["Vicente", "Pegou?"],
		["Dante", "O livro de cargas e o lacre original. Tirei do baú certo antes de eles voltarem."],
		["Vicente", "Deixa eu ver o lacre."],
		["Vicente", "Numeração da salina. Igual ao do caixote do Raul. Só que esse aqui não foi raspado."],
		["Dante", "Então a carga da operação saiu das Salinas."],
		["Vicente", "O Seu Bento manda lá faz vinte anos. Se alguém trocou carga no pátio dele, ele viu."],
		["Vicente", "Toma. Metade do que o baú tinha de dinheiro era dos Cobras. A outra metade era de quem eles devem. Melhor com você."],
	]

# --- A2-11 "Sal na ferida" ------------------------------------------------------------------------

static func bento() -> Array:
	return [
		["Seu Bento", "Esse lacre é meu. Quer dizer, da salina."],
		["Dante", "A carga da operação de oito anos atrás saiu daqui?"],
		["Seu Bento", "Os caminhões dos Cobras paravam no pátio à noite. Trocavam a carga e completavam o peso com sal."],
		["Seu Bento", "Por isso o caminhão do teu irmão pesou menos na balança da Rosa. Tinha sal no lugar."],
		["Dante", "O senhor anotava?"],
		["Seu Bento", "Num caderno. Mandaram queimar. Eu dei pra um rapaz da serra guardar."],
		["Seu Bento", "O acampamento lá no sul, perto do leito seco. Se ainda existir caderno, está com aquela gente."],
	]

static func ledger() -> Array:
	return [
		["Dante", "Meio queimado, mas dá pra ler."],
		["Dante", "A troca da noite da operação. Carga trocada, peso completado com sal, caminhão liberado."],
		["Dante", "No campo \"autorizado\": zero, quatro, um, sete."],
		["Dante", "A mesma matrícula na ordem do banco, nas cartas e na troca da carga."],
	]

# --- A2-12 "Teodoro" ------------------------------------------------------------------------------

static func teodoro_motel() -> Array:
	return [
		["Dona Lurdes · rádio", "Dante? É a Lurdes, do Oásis. Tem um advogado de terno aqui perguntando pelo teu irmão. Vem logo."],
		["Teodoro", "Dante Ferraz. Quanto tempo."],
		["Dante", "Teodoro. O advogado que não deixava eu ver o processo."],
		["Teodoro", "Eu vim fazer uma proposta ao Vicente. Um acordo. Ele esquece o caso e recebe uma indenização generosa."],
		["Vicente", "Você me disse oito anos que o meu irmão nunca apareceu."],
		["Teodoro", "E disse a verdade."],
		["Dante", "E a mim você dizia que o Vicente não queria me ver."],
		["Teodoro", "Vocês dois estão cansados. Pensem na proposta."],
		["Vicente", "Quem paga essa indenização, Teodoro?"],
		["Teodoro", "Eu preciso ir."],
	]

static func teodoro_gate(caught: bool) -> Array:
	var rows: Array = []
	if caught:
		rows.append_array([
			["Teodoro", "Não chega perto. Eu só faço o que me mandam."],
			["Dante", "Quem manda?"],
			["Teodoro", "Pergunta pro teu antigo chefe. Ele assina com número, não com nome."],
		])
	rows.append_array([
		["Dante", "Passou a pé pela obra. Carro não atravessa a barreira."],
		["Dante", "Largou a pasta. Recibo de hotel na cidade do norte. E um cartão: 0417."],
	])
	return rows

# --- A2-13 "Os oito anos" -------------------------------------------------------------------------

static func finale_grandstand() -> Array:
	return [
		["Vicente", "Amanhecendo. Eu vinha aqui de manhã pra ver o sol bater na reta."],
		["Dante", "Trouxe tudo. O manifesto do Raul, a balança da Rosa, a ordem da Irene, as cartas da cooperativa, o lacre, o caderno do Bento, a pasta do Teodoro."],
		["Vicente", "Em todos o mesmo número."],
		["Dante", "Zero, quatro, um, sete. Uma matrícula de polícia. Foi armado, Vicente."],
		["Vicente", "E o que eu faço com os oito anos que eu perdi?"],
		["Dante", "Não sei. Mas não vou deixar você fazer isso sozinho."],
		["Lívia · rádio", "Vicente! Os Cobras estão descendo pro encontro. Muitos. Armados."],
		["Vicente", "Vieram buscar os papéis. Vamos."],
	]

static func finale_gate() -> Array:
	return [
		["Vicente", "A obra acabou. Olha isso. Os operários tirando a barreira."],
		["Dante", "Lá em cima está quem assinou."],
		["Vicente", "Então a gente sobe."],
		["Maciota · telefone", "Dante. Descobri a matrícula. Está ativa, numa delegacia da cidade do norte."],
		["Maciota · telefone", "E a minha Monaliza foi vista lá também, numa oficina dos Cobras."],
		["Maciota · telefone", "Ele está esperando vocês, Dante. Os dois. E a minha Monaliza também."],
		["Vicente", "Dirige você. Eu fico de olho na estrada."],
	]
