# Proposta — a história depois do deserto e o fechamento de Dante e Vicente (31/10/2026)

Documento **só de texto**: nenhum código, cena ou áudio foi alterado. Continua
[o roteiro de diretor](roteiro-diretor-geteco-20261021.md) (que deixou o "Ato 3 — Norte" como esboço de
sete passos e três finais) e [o ato 2](story-act2-vicente-20261020.md), e amarra os fios soltos que
ficaram em [secret-headquarters.md](secret-headquarters.md), [roteiros-arquivo-vicente-20261031.md](roteiros-arquivo-vicente-20261031.md),
[forte-expansao-20261031.md](forte-expansao-20261031.md) e [fitas-piloto-20261031.md](fitas-piloto-20261031.md).

O esboço do diretor vira aqui **três atos curtos** (3, 4 e 5) com **14 missões**. O que já estava
decidido continua valendo: Prado (matrícula 0417) é o rosto da armação, Teodoro vira e morre, Cascavel
corre limpo no fim, Jessica volta, a cidade final é escura, cinza e com neblina (direção da cidade 4 em
`AGENTS.md`). O que muda é o **porquê** da armação, que passa a sair do setor selado, e os finais, que
caem de três para dois.

## Premissa

A pasta de Teodoro provou que Vicente foi armado, mas não disse por quê. A resposta está debaixo da
terra: o forte da serra, o QG embaixo da Vila e o setor lacrado com a maca e o vidro quebrado são pontas
da mesma coisa. Antes de ser preso, Vicente dirigia frete para a Vértice e fazia turno no forte; ele
assinou um lacre sem saber o que lacrava, e oito anos atrás o caminhão da blitz levava o último lote.
Dante não prendeu o irmão por acaso: Prado precisava apagar a única testemunha que podia ligar a
assinatura à carga, e usou o policial mais obediente que tinha para fazer isso. Agora, com Helena
ferida, a Monaliza no norte e o irmão que ainda deve aos Cobras, Dante tem que descer ao que lacraram,
subir até a cidade cinza onde Prado manda, e decidir quem estende os pulsos no fim.

## Cânone do setor selado — dois caminhos

Regra do projeto: **nada confirma origem sobrenatural.** Os dois caminhos respeitam isso; a diferença é
quanto o jogo explica.

**Caminho A — explicação humana (conspiração).** O setor 7 do forte e o setor lacrado do QG eram uma
**quarentena clandestina**. Em 1998 (a escala do alojamento), uma carga de solvente industrial que a
Vértice trazia pelo Porto Sul vazou num pátio; trabalhadores adoeceram e foram levados para baixo da
terra para "observação" em vez de ir para hospital, porque um hospital registra. A maca, o soro, os
frascos sem rótulo, a cal e o lacre de chumbo são isso. As marcas de unha e o vidro "quebrado de dentro
pra fora ou de fora pra dentro" são de gente que queria sair. Prado, então tenente, cuidou do sumiço;
a Vértice pagou; os Cobras herdaram as rotas. A carga que Vicente transportava na noite da blitz eram
os últimos tambores. A explicação fecha tudo: o motivo da armação, o "Ninguém desce sem o V.", a fita
"enviada para a cidade" e o número de cofre do crachá.

**Caminho B — ambíguo até o fim.** As mesmas pistas existem, mas o cofre do setor lacrado guarda
**metade** da resposta: prova que houve gente presa ali e que Prado sabia, e para aí. Os laudos estão
riscados; ninguém vivo diz o que adoeceu as pessoas. O jogo fecha a história de Prado e dos irmãos e
deixa o setor como ferida aberta: uma fita no epílogo, um ruído no túnel quando a energia cai.

**Recomendação: A**, com uma única sombra deixada de propósito (o rato que não aparece em nenhuma rota
fixa, um último registro de Vicente que ele mesmo diz não entender). Motivos: (1) a campanha inteira é
sobre **prova física**; Vicente "só muda de ideia com prova, nunca por discurso", e uma história de
prova pede que a prova termine em algo; (2) A dá ao vilão um motivo maior que dinheiro e transforma a
algema do prólogo em queima de arquivo, o que pesa mais; (3) o tom do jogo é crime pé-no-chão
(guincho, recibo, banco), e um mistério sem fundo quebraria esse contrato no último ato; (4) a sombra
mantém o setor assustador para quem volta ao túnel no mundo aberto. B fica como plano reserva se o
dono quiser uma continuação que explore o setor.

## Ato 3 — "Cal": do deserto à cidade cinza

Começa no plano final do ato 2 (os três no Bison entrando na neblina da passagem norte), mas
**volta antes de subir**: a passagem leva à serra, e Helena ferida obriga a parada. O ato reabre
lugares que o jogador já conhece com outro olhar. ~2 h 30.

### A3-01 · Raspão
- **Região:** passagem norte → serra (pé da serra, Abrigo dos Lenhadores).
- **Objetivo:** levar Helena viva ao posto de saúde da serra sem tirar o carro da estrada.
- **Mecânica:** direção com passageira ferida (o sistema de passageiro de M05 e do táxi), neve e frio
  (`ColdSurvival`), Cobras na cola com a perseguição GTA já existente; sem estrela, ou o posto recusa.
- **Gancho:** no curativo, Helena acha no bolso de Vicente o crachá do forte com o número de cofre
  "que não é do forte". Vicente: "Eu trabalhei lá. Antes. Não pergunta agora."
- **Recompensa:** sem dinheiro. Abre o hospital da serra como ponto de retorno da campanha.

### A3-02 · Setor 7
- **Região:** Forte da Serra.
- **Objetivo:** entrar no forte com Vicente e abrir o cofre do comando.
- **Mecânica:** a expansão inteira (`FortExpansionState`): mesa de comando, alojamento furtivo,
  arsenal, comando. Vicente conhece os corredores e aponta as sentinelas dormindo (fala, não IA nova).
- **Gancho:** a ordem de lacre com a assinatura de Vicente e o motivo cortado com tesoura. Vicente
  reconhece a própria letra e emudece. Dante: "Você assinou o quê?" — "Um papel. Eles davam papel
  toda noite."
- **Recompensa:** as que já estão no código (R$ 2.500 + 1.500 silencioso, fuzil de caça, R$ 12.000).

### A3-03 · A última porta
- **Região:** Harbor, Casa 1 da Vila → QG subterrâneo → setor lacrado.
- **Objetivo:** juntar os quatro números (3194), abrir a porta redonda do setor.
- **Mecânica:** o Arquivo de Vicente com as **quatro gravações** ligadas; o jogador ouve a voz de
  Vicente de oito anos atrás **com o Vicente de hoje do lado**. Na fita 04 ("Depois disso, não volte"),
  Vicente desliga o gravador antes do fim. Restaurar energia com os três disjuntores.
- **Gancho:** dentro do cofre, o manifesto de 1998 com o carimbo 0417 e a pulseira de identificação
  de um trabalhador. Não há corpo nem criatura. Fala-chave de Helena: "Isso não é laboratório. É lugar
  pra esconder gente."
- **Recompensa:** libera o **ramal do Porto Sul** no terminal do QG (a "continuação planejada" de
  `secret-headquarters.md`).

### A3-04 · Lacre de chumbo
- **Região:** ramal Porto Sul → pátio da Vértice.
- **Objetivo:** achar o contêiner de tambores que ainda está no pátio e fotografar a numeração.
- **Mecânica:** o turno da noite da Vértice (M06-C: vigias, visão, derrubada silenciosa, alarme) e
  as empilhadeiras dirigíveis para tirar dois contêineres da frente. Se o alarme tocar, vira fuga de
  barco ou de carro pelo porto.
- **Gancho:** o contêiner está etiquetado para a cidade 4. Neco, que guinchou carro roubado no ato 1,
  liga: "Os Cobras tão pagando o dobro pra quem levar caminhão pro norte essa semana."
- **Recompensa:** R$ 3.000 (recibo do seguro de carga que o Neco cobra) e o ramal fica de ida e volta.

### A3-05 · Valores em trânsito
- **Região:** North Pier → estrada → Cobre.
- **Objetivo:** com Jessica (que ainda não "voltou" de vez), interceptar o carro-forte que leva os
  extratos de Prado para o norte.
- **Mecânica:** o transporte de valores North Pier ↔ Cobre já implementado (comboio e escolta), agora
  do lado do assalto; Jessica dirige o Jetta, o jogador para o comboio. Corrida limpa ou suja (escolha
  de abordagem muda a fala, não a história).
- **Gancho:** os extratos chegam pela metade; a outra metade "já subiu de trem". Jessica: "Eu vou subir
  junto. O Cascavel me chamou pra correr lá."
- **Recompensa:** o malote (dinheiro real do sistema de assalto) e a reputação com Jessica.

### A3-06 · O trem da neblina
- **Região:** ramal da serra → trem → chegada na cidade 4.
- **Objetivo:** embarcar sem estrela, achar o malote no vagão de carga antes da última estação.
- **Mecânica:** `RailwayTransit` (embarque, viagem, câmera externa) com uma etapa nova a pé dentro da
  composição; o trem entra no túnel e sai na neblina. **É o primeiro plano da cidade 4.**
- **Gancho:** o malote está vazio, com um bilhete de Prado: "Bem-vindo, Ferraz. Procedimento." Ele
  sabe que eles chegaram. Na plataforma, Vicente some na multidão.
- **Recompensa:** a cidade 4 abre no mapa; viagem de trem entre as três cidades.

## Ato 4 — "A matrícula": a cidade 4

Cidade de concreto molhado, sódio amarelo apagando no cinza, neblina que come a terceira quadra. Pouca
cor: a única saturada é o vermelho do giroflex. ~3 h.

### A4-01 · Pensão Cinza
- **Região:** cidade 4, centro velho.
- **Objetivo:** achar um quarto para Helena e o antigo colega honesto, **Ribas**, que não quer ajudar.
- **Mecânica:** bar da cidade (o mesmo kit de Lastro e Sede: bilhar e dardos). Ribas só fala se Dante
  ganhar a partida de bilhar; perder também funciona, mas ele fala menos.
- **Gancho:** Ribas: "O Prado não manda na polícia daqui. Ele é a polícia daqui." E entrega o endereço
  da oficina dos Cobras.
- **Recompensa:** a pensão vira casa (salvar e dormir) na cidade 4.

### A4-02 · A Monaliza
- **Região:** zona portuária da cidade 4, oficina dos Cobras.
- **Objetivo:** tirar a Monaliza de lá sem acordar o pátio.
- **Mecânica:** infiltração noturna (padrão alojamento do forte); se o alarme tocar, perseguição GTA
  pela cidade molhada. Alternativa barulhenta: o **guincho** — Dante arrasta a Monaliza com o
  reboque, mais lento e mais divertido.
- **Gancho:** no porta-malas, o adesivo que o Maciota colou e um envelope de Vicente: ele esteve aqui
  antes de Dante. Vicente está negociando sozinho.
- **Recompensa:** a Monaliza de volta à garagem (registro igual ao Coyote).

### A4-03 · Do lado de dentro
- **Região:** circuito de rua da cidade 4 (avenidas do porto e viaduto).
- **Objetivo:** correr na noite do Cascavel e deixar Jessica plantar o rastreador no carro dele.
- **Mecânica:** corrida de rua (o sistema das arrancadas e da corrida de Takeshi, com checkpoints);
  Jessica é rival na pista e aliada no rádio. Resultado físico: perder não trava.
- **Gancho:** o rastreador leva a um prédio da Vértice; Teodoro está escondido lá, com medo.
- **Recompensa:** prêmio da corrida (recibo único) e peça de motor para a Monaliza.

### A4-04 · Testemunha
- **Região:** prédio da Vértice → ruas → delegacia central.
- **Objetivo:** escoltar Teodoro até a corregedoria antes do amanhecer.
- **Mecânica:** escolta com passageiro (M05/A3-01), polícia de Prado atrás (perseguição com estrelas
  que **não somem** nesta missão), rotas bloqueadas pela neblina.
- **Gancho:** Teodoro é morto na escada da corregedoria, por um tiro que ninguém vê. Antes de cair
  entrega uma chave: "Cofre do porto. O original." Prado sabe tudo o que Dante sabe.
- **Recompensa:** a chave; nenhuma recompensa em dinheiro (a missão termina mal de propósito).

### A4-05 · Chuva limpa
- **Região:** cidade 4, do porto à serra do norte.
- **Objetivo:** última corrida com o Cascavel, sem aposta, sem sabotagem.
- **Mecânica:** corrida ponto a ponto, Monaliza contra o carro dele. Ganhando ou perdendo, ele conta
  que Vicente foi pego por Prado na noite anterior.
- **Gancho:** Cascavel, encostado no carro: "Seu irmão foi oferecer a cabeça dele pela sua. Burro
  igual." Ele entrega o número do píer.
- **Recompensa:** respeito do norte (fala), e o Cascavel some do jogo vivo.

### A4-06 · Delegacia vazia
- **Região:** delegacia central da cidade 4, noite.
- **Objetivo:** entrar na sala de Prado e pegar o original da ordem de frete no cofre do porto.
- **Mecânica:** infiltração com vigias (M06-C) e o keypad do QG reaproveitado no cofre. Prado está lá.
  Cara a cara, sem tiro: diálogo longo, a cena mais quieta do jogo.
- **Gancho:** Prado não nega nada. Explica o setor (Caminho A) sem levantar a voz:
  > **Prado:** Doze pessoas, Ferraz. Ninguém ia acreditar em doze. Acreditaram num motorista.
  Ele deixa Dante sair com o original — porque Helena já não está na pensão.
- **Recompensa:** o original da ordem; o porto do norte marcado no mapa.

## Ato 5 — "Procedimento": o fechamento

Uma noite, um lugar, duas missões. ~1 h.

### A5-01 · A noite do porto
- **Região:** porto da cidade 4 (grua, contêineres, rampa do cais), neblina fechada.
- **Objetivo:** Prado prendeu Helena num contêiner pendurado na grua e Vicente num carro com freio
  solto na rampa. Pelo rádio: "Você escolhe um. Ou escolhe você."
- **Mecânica:** tudo que o jogador aprendeu: tiro e cobertura contra os homens de Prado, **guincho**
  para segurar o carro na rampa (o cabo prende, o motor do reboque aguenta por um tempo medido), a
  cabine da grua para descer o contêiner, Jessica no rádio com o Jetta cercando o portão. Diferente do
  esboço do diretor, **dá para salvar os dois** — mas só com ajuda: Jessica segura o guincho enquanto
  Dante sobe na grua. O custo não é uma vida; é quem paga pelo que foi feito.
- **Gancho:** com os dois vivos, o porto se enche de giroflex. Prado ainda tem a polícia; Dante tem o
  original, a fita 04 e o assalto ao North Pier nas costas. Alguém precisa assinar a confissão que
  torna tudo prova.
- **Recompensa:** a escolha final.

### A5-02 · A carta
- **Região:** depende do final (presídio, deserto, Santa Lua).
- **Objetivo:** o epílogo jogável.
- **Mecânica:** a rima do jogo: o mesmo botão segurado do prólogo, a algema, a carta lida em off
  pelas vozes que já existem.
- **Recompensa:** o mundo aberto continua, com marcas do final.

## Os dois finais

O jogador escolhe no rádio, segurando o botão — o único comando, como no prólogo.

**Final 1 — "Procedimento" (Dante se entrega).** Dante pega o rádio e confessa: o assalto ao North
Pier, a algema de oito anos atrás, onde está o original. A corregedoria de Ribas chega com a imprensa;
Prado é algemado na frente de doze nomes lidos em voz alta. Dante estende as próprias mãos e a câmera
fecha no clique do metal. **Epílogo:** sala de visitas. Vicente do outro lado do vidro: "Primeira carta.
O advogado disse que escrever ajuda." Corte. O mundo continua com o jogador como Vicente, com a
Monaliza. É o fim que o roteiro do diretor já queria; aqui vira o "certo" que custa caro.

**Final 2 — "Os irmãos" (Vicente toma o lugar).** Dante hesita no rádio e Vicente o arranca da mão
dele. Confessa ele: o lacre assinado, o frete dos Cobras, os carros sumidos de Harbor (o "irmão culpado
do presente" do roteiro do diretor) — e mente que o assalto do banco também foi dele. Prado cai do
mesmo jeito. Vicente estende os pulsos para Dante: "Dessa vez cê sabe o que tá fazendo." O jogador
algema o irmão de novo, agora com escolha. **Epílogo:** caixa-d'água de Santa Lua, Dante e Helena;
Dante escreve, não lê: "Primeira carta, Vicente." O jogo continua como Dante; a cadeira de Vicente no
encontro da arrancada fica vazia até o fim do save.

Nenhum final mata alguém amado; os dois fazem um Ferraz pagar. A diferença é se Dante finalmente faz
o que devia ter feito oito anos atrás (pagar ele) ou deixa o irmão escolher por ele. Os finais A e B do
diretor (morre Helena / morre Vicente) podem ficar como **falha jogável** de A5-01 (se o jogador demora
demais, um dos dois cai), mas não como final escolhido.

## Reviravoltas, em ordem

1. **A3-02:** a assinatura no lacre é de Vicente. O irmão inocente estava dentro do esquema sem saber.
2. **A3-03:** o setor lacrado não guarda monstro nem experiência: guardava gente.
3. **A3-06:** Prado esperava por eles; o malote vazio diz que alguém avisa o norte.
4. **A4-02:** quem avisava era Vicente — negociando a própria cabeça pela de Dante, não traindo.
5. **A4-04:** a testemunha morre; o caso passa a depender só do que Dante tem e de quem confessa.
6. **A4-06:** o motivo da algema do prólogo: queima de arquivo. Dante foi a arma, não o erro.
7. **A5-01:** dá para salvar os dois; o preço é outro.

## Pontas soltas que esta proposta fecha

| Fio existente | Onde fecha |
|---|---|
| Crachá com número de cofre "que não é do forte" | A3-01 → cofre do setor lacrado (A3-03) |
| "Ninguém desce sem o V.", ordem de lacre, setor 7 | A3-02 |
| Quatro gravações do Arquivo de Vicente (roteiros já escritos) | A3-03, ouvidas com Vicente presente |
| Ramais Porto Sul e serra | A3-04 e A3-06 |
| Fita "enviada para a cidade" | A4-06, no cofre de Prado |
| Carro-forte North Pier ↔ Cobre | A3-05 |
| Fitas do piloto e galpão | Paralela do ato 4: as dez fitas são do Cascavel jovem; o carro do galpão é o que ele deixa para Dante depois de A4-05 |
| Cartas de Vicente | Epílogos (a primeira carta, escrita por quem fica de fora) |

## O que dá com o que existe vs. o que é novo

**Dá com o que existe (falas, etapas e lugar):** A3-02 (forte: falta só a geometria das três salas já
propostas), A3-03 (QG, keypad, energia, ratos; falta ligar os streams), A3-04 (Vértice, vigias,
empilhadeiras, Porto Sul), A3-05 (carro-forte e assalto), A4-03 e A4-05 (sistema de corrida), A4-01
(kit de bar), o guincho, a perseguição GTA, o passageiro.

**Arte nova:**
- **Cidade 4 inteira** — o item grande: região em streaming nova, paleta cinza, neblina, chuva, porto
  com grua operável, delegacia, pensão, oficina dos Cobras, um bar. Sugestão: começar por **um bairro
  portuário fechado** (porto + centro velho + delegacia) em vez de cidade completa.
- Interior do vagão de carga (A3-06), a cabine da grua com contêiner suspenso (A5-01), interior do
  cofre do setor lacrado (pulseiras, arquivo de 1998), sala de visitas do presídio (epílogo 1).
- Personagens: **Ribas**, **Prado** (rosto já previsto desde M00 na TV) e figurantes da polícia do norte
  (reaproveitar `PoliceModel` com outra farda).
- Shaders/materiais novos da cidade 4 entram em pré-aquecimento; luzes do porto pelo `LightBudget`.

**Voz nova:** Prado (calmo e educado; peso maior do jogo), Ribas, Cascavel, Teodoro; mais as falas novas
do elenco fixo (Dante, Vicente, Helena, Jessica, Maciota, Neco) — estimo 250–350 falas para os três
atos. As quatro gravações de Vicente já têm texto aprovável.

## Ordem sugerida de implementação

1. **Decidir o cânone** (A recomendado) e o nome da cidade 4.
2. **A3-03 A última porta** — só liga áudio e um cofre no QG que já existe; é a revelação mais barata e
   mais forte, e fecha o card das gravações.
3. **A3-02 Setor 7** — geometria das três salas do forte, que o código já espera.
4. **A3-01, A3-04, A3-05** — falas e etapas sobre sistemas prontos (podem ir em paralelo por agentes
   diferentes).
5. **Bairro portuário da cidade 4** (arte e desempenho primeiro, medido em release) e **A3-06** como
   porta de entrada pelo trem.
6. **A4-01 a A4-06** na ordem, cada uma jogável antes da próxima.
7. **A5-01 e A5-02** por último, quando guincho, grua e todos os atores estiverem no lugar.
8. Vozes por ato, depois que as legendas estiverem jogadas de ponta a ponta.

Nada disto foi jogado ou medido; tempos e tamanhos são estimativas de roteiro.
