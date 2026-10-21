# Ato 2 — Sal e Sangue (roteiro de 20/10/2026)

Roteiro da campanha do deserto (13 missões), do reencontro de Dante com Vicente até a missão que fecha o
capítulo e abre a passagem norte para o ato 3. Continua [o ato 1 de Harbor](story-harbor-act1-20261005.md)
e usa só lugares que já existem no mapa 2 ([mapa2-deserto.md](mapa2-deserto.md)): encontro da
arrancada, Estrada do Sal (Salinas, Balança, Motel Oásis, Capela, Arquibancada), cidade (Cobre,
Horizonte, oficina do Digo), vila Santa Lua, posto Miragem, cânion, cavernas de arenito e a
passagem norte em obra.

**Estado:** as 13 missões estão jogáveis (`runtime/desert/act2/`, teste da sessão real
`tests/test_desert_act2_reunion.gd`, que percorre o ato inteiro). Até serem feitas, o
jogo continua completável pelo esqueleto antigo de `DesertCampaign.gd` (Digo → manifesto →
Irene → Jessica → prova), cujas marcas cada missão nova vai substituir (tabela no fim).

## Tamanho

O jogo inteiro mira **~14 horas**. Proposta de divisão:

| Parte | Missões principais | Paralelas e mundo | Total |
|---|---:|---:|---:|
| Ato 1 — Harbor (M00–M07) | ~3 h | ~1 h | ~4 h |
| Serra (avião dos Cobras, descida, jipe) | — | ~1 h 30 | ~1 h 30 |
| **Ato 2 — deserto (este roteiro)** | **~5 h** | ~1 h 30 (Bia/Raul, Santa Lua, cartas, arrancadas, cânion) | **~6 h 30** |
| Ato 3 e cidade 4 | ~2 h | — | ~2 h |

Por isso cada missão do ato 2 tem **três a cinco etapas**, dois ou três lugares, diálogo de
verdade (10 a 25 falas por missão, só em legenda até haver gravação) e uma direção entre os
lugares. Uma missão dura 20 a 40 minutos jogando sem pressa.

## Regras do ato

- Vicente lê os oito anos como abandono. Ele só muda de ideia com prova física, nunca por discurso.
- **O ato prova que houve armação, mas não diz quem armou.** A trilha aponta para o norte: o
  beneficiário e o advogado Teodoro sobem a estrada que a obra da passagem norte está fechando.
  Quem armou é o ato 3.
- Corrida tem resultado físico: perder não trava a história (muda a fala). A única derrota certa do
  ato é a aposta da Monaliza (A2-08), e ela vem de sabotagem no carro, não de resultado escrito: a
  corrida acontece de verdade, com o motor perdendo força no meio da reta.
- Nada de pagamento por abrir diálogo. Cada recompensa é um recibo único com id estável
  (`Economy.grant_world_reward`), validado pelo contrato de save do deserto; valor gravado
  nunca muda.
- Cada etapa só conta no **fim** do diálogo ou da ação, com Dante vivo, solto e no deserto.
  Morte, prisão e carregar voltam para a mesma etapa (o save guarda a etapa, não a cena).
- Maciota e o mecânico continuam intocáveis; a garagem continua sem armas.

## Personagens

| Quem | Onde | Papel no ato |
|---|---|---|
| **Vicente Ferraz** | encontro da arrancada; motel, capela, caverna do Coyote | Irmão. Lidera a turma das arrancadas. Desconfia de tudo que vem de Dante |
| **Lívia** | encontro | Organiza as provas. Neutra, respeita quem respeita a pista |
| **Digo e Bia** | oficina e pátio do Digo | Preparação do carro; Digo é a primeira prova |
| **Raul** | posto Miragem | Caminhoneiro velho; achou o manifesto da carga dos Cobras |
| **Irene** | banco Cobre | Gerente; lê a transferência e a ordem alterada |
| **Jessica** | encontro | Volta de Harbor; corre por conta própria e sabe do comboio |
| **Dona Lurdes** | Motel Oásis | Hospedou Vicente na primeira noite livre |
| **Dona Fátima** | Capela da Estrada | Zeladora; viu quem andou perguntando por Vicente |
| **Seu Bento** | Salinas | Encarregado; as cargas eram trocadas no pátio dele |
| **Fiscal Rosa** | Balança | Pesou o caminhão da operação de oito anos atrás |
| **Seu Zé do Cronômetro** | Arquibancada | Guarda os tempos de todo mundo, inclusive os de Vicente |
| **Cascavel** | encontro (A2-08), depois o norte | Piloto dos Cobras. Ganha a Monaliza numa aposta roubada e leva para o norte |
| **Nonato** | ferro-velho | Tem o carro velho que vira o carro novo de Dante (A2-09) |
| **Teodoro Salles** | (aparece em A2-12) | Advogado de Vicente nos oito anos. Mentia para os dois irmãos |
| **Maciota** | por telefone | Liga nos momentos certos; abre o ato 3 |

## Missões

### A2-01 · Oito anos — *jogável*

O reencontro em três lugares, ~20–25 min.

1. **Encontro da arrancada.** Objetivo: "Encontre Vicente no encontro da arrancada." Vicente
   recebe Dante na frente da turma: "Oito anos, Dante. Oito. Agora você aparece?". Dante fala do
   processo pedido de volta e de ter largado a polícia; Vicente fala da parede e do prego. Não
   aceita conversar na frente da turma e marca o Motel Oásis, quarto 6: "se ainda souber chegar sem
   sirene". Vicente sai do encontro.
2. **Motel Oásis.** Objetivo: "Vá ao Motel Oásis, na Estrada do Sal, e fale com Vicente." Ele espera
   na calçada, na porta do quarto 6. A conversa muda conforme as cartas achadas (nenhuma, algumas,
   as dez). **Semente 1:** as cartas voltaram com "destinatário desconhecido" para um endereço que
   nunca mudou. **Semente 2:** o advogado Teodoro dizia a Vicente que Dante nunca aparecia, e a Dante
   que não podia ver o processo. Vicente vai na frente para a capela.
3. **Capela da Estrada.** Objetivo: "Encontre Vicente na Capela da Estrada." A vela (a carta 9), a
   mãe, o depósito mensal na cantina que Vicente nunca gastou. Ele devolve o envelope: **R$ 1.500**
   (recibo `desert_act2_reunion_envelope`). Condição dele: "aqui você é piloto, não policial. Corre
   com o Digo." Dante: "E se eu provar que alguém armou aquilo?" — "Então prova. Promessa eu já
   ouvi demais."

Conclusão marca `desert_story.met_vicente` (destrava o resto). Carteira cheia: a missão espera na
capela e a próxima conversa paga. Save antigo que já tinha a conversa única conta como feito, sem
envelope.

### A2-02 · Respeita a pista — *jogável*

~25 min. Pátio do Digo, encontro da arrancada, Arquibancada.

1. **Bia** (objetivo "Fale com Bia no pátio do Digo."): "Se ele vier, mostra a reta pra ele e não
   deixa ele se matar", palavras de Vicente. Ela explica relação, turbo, troca de marcha e nitro.
2. **Corrida com o Digo** na reta de 800 m (prova existente pelo quadro da concentração; ganhar ou
   perder vale). Terminar a prova com o Digo, mesmo sem ter falado com a Bia, já leva adiante.
3. **Arquibancada.** Seu Zé do Cronômetro lê o tempo de Dante no caderno e lembra que Vicente
   largava igual, "num Coyote sem nitro". Vicente assistiu de longe: queria ver se Dante corria para
   ganhar ou para provar alguma coisa. Ele corria para pagar o advogado Teodoro (semente 2 de novo).
   A fala muda se Dante ganhou ou perdeu do Digo.
4. Vicente aponta Raul: "o Raul tem um papel que não é dele. Pergunta pro velho no posto Miragem."

Recompensa: oficina do Digo liberada (marca existente `DigoProgress`), sem dinheiro novo. Chave
`vicente_act2_track` (`""` → `race` → `grandstand` → `done`); save antigo que já tinha a oficina
conta como feito.

### A2-03 · Peso morto — *jogável*

~25–30 min. Encontro da arrancada, posto Miragem, Balança, de volta ao encontro.

1. **Raul** (objetivo "Fale com Raul no encontro da arrancada."): um bitrem dos Cobras deixou um
   caixote no Miragem e ninguém voltou para buscar. "Carga que ninguém volta pra buscar é carga que
   não devia existir." Ele não abre ("eu tenho neto").
2. **Caixote no Miragem** ("Abrir o caixote dos Cobras"): lacre de chumbo da salina, o mesmo modelo
   da carga da operação, e o manifesto: beneficiário pago pelo Cobre **dois dias antes** da apreensão.
3. **Fiscal Rosa na Balança** ("Mostrar o lacre à Fiscal Rosa", que vale no lugar da conversa comum
   dela durante a etapa): ela pesou o caminhão de Vicente na noite da operação. A apreensão dizia
   22 t; a balança, 20 t. Ninguém da polícia nem o advogado foram perguntar.
4. **De volta ao Raul:** "Então o menino carregou uma coisa e prenderam ele com outra." Ele paga
   **R$ 900** (recibo `desert_act2_cargo_freight`) e manda Dante à Irene. Pede que Dante conte a
   Vicente quando tiver certeza.

Conclusão marca `cargo_found`. Chave `vicente_act2_cargo` (`""` → `crate` → `weigh` → `raul` →
`done`). Carteira cheia: a última conversa com o Raul paga na próxima vez.

### A2-04 · A ordem alterada — *jogável; primeira pista de quem armou*

~25 min. Banco Cobre, a porta do Cobre à noite, orelhão do Horizonte.

1. **Irene no balcão** confere o manifesto: transferência paga dois dias antes da apreensão; a ordem de
   frete saiu **sem motorista** e o nome de Vicente entrou depois. Lá dentro ela não pode imprimir
   nada: "Depois das oito da noite eu fecho o caixa. Me espera na porta. Sozinho."
2. **Na porta do Cobre, depois das 20h** (de dia ela não está; descansar no Horizonte adianta a hora):
   a cópia da ordem e da alteração. Quem autorizou não assinou com nome, mas com uma **matrícula:
   0417** — matrícula de polícia, do mesmo formato da de Dante. "Então quem pôs teu irmão naquele
   caminhão usava a mesma farda que você."
3. **Orelhão do Horizonte:** Dante liga para Maciota pedindo que descubra de quem é a 0417. "Isso vai
   fazer barulho." Maciota cobra que Dante conte a Vicente logo.

Conclusão marca `bank_proof`. Sem dinheiro: a pista é o prêmio. A matrícula fica em aberto até A2-13.
Chave `vicente_act2_order` (`""` → `night` → `call` → `done`).

### A2-05 · Racha de irmãos — *jogável*

~20 min. Encontro da arrancada.

1. **Vicente** (objetivo "Fale com Vicente no encontro da arrancada."): Lívia anuncia a prova; "Você e
   eu, Dante. Oitocentos metros. Sem aposta, sem plateia comprada."
2. **Prova contra Vicente** ("Alinhar contra Vicente", parado de carro na concentração): rival de
   história do `DesertDrag`, Coyote de arrancada com a preparação dele. Resultado físico; chegar muito
   atrás (mais de 8 s depois dele) também conta como derrota, não como prova anulada.
3. **Vicente de novo:** ganhou — "Ainda acelera do mesmo jeito"; perdeu — "Você tirou o pé no fim. Não
   precisava." Os dois casos seguem: ele chama para a mesa de pedra.

Sem dinheiro. Chave `vicente_act2_brothers` (`""` → `race` → `won`/`lost` → `done`).

### A2-06 · Mesa de pedra — *jogável*

~15–20 min (mais a ida). Caverna escondida do Coyote (DesertWilds `cave_brother`, -1170, -1730).

1. Vicente espera perto da fogueira da caverna (o ator só monta com a caverna montada).
2. **A conversa:** o "conhecido do Cobre" que ofereceu o frete pelo dobro; Dante conta que recebeu a
   escala na véspera com o nome de Vicente **já** escrito, antes de o banco alterar a ordem; a algema;
   as cartas devolvidas. A fala muda se as dez cartas foram achadas e se o Coyote já foi levado.

Sem dinheiro (o Coyote continua sendo só o prêmio das cartas). Chave `vicente_act2_cave`.

### A2-07 · Destinatário desconhecido — *jogável*

~25 min. Capela, torre de rádio da Rua Principal, rádio da cooperativa de Santa Lua.

1. **Dona Fátima** ("Perguntar à Dona Fátima", no lugar da vela durante a etapa): um homem de jaqueta
   de polícia deixou uma vela "pelo rapaz"; ela anotou a placa.
2. **Torre de rádio** ("Subir na torre e ligar para o Maciota"): placa de uma viatura descaracterizada
   do norte; o malote do presídio passava pela cooperativa.
3. **Rádio de Santa Lua:** Joana acha os dez envelopes devolvidos com o carimbo **0417** no verso.
   Vicente ouve pelo rádio: "Então isso agora é com nós dois."

**R$ 1.200** (recibo `desert_act2_coop_radio`). Chave `vicente_act2_letters`.

### A2-08 · Chave na chave — *jogável; Dante perde a Monaliza*

~30 min. Encontro da arrancada.

1. **A prova da Jessica** (a que já existe; marca `jessica_met`). Com a missão aberta, a fala antiga de
   fim de prova não aparece: a conversa é a da missão.
2. **Jessica** ("Conversar"): o comboio dos papéis passa duas madrugadas por semana; a hora exata só o
   Cascavel sabe.
3. **Cascavel** na beira da concentração: chave na chave — a hora e a rota do comboio contra a chave da
   Monaliza. Vicente: "Não aposta o carro com essa gente. Eles não perdem."
4. **A prova** ("Alinhar contra Cascavel"): depois dos 400 m o acelerador do carro de Dante fica limitado
   a 20% e sem nitro (mangueira do turbo cortada). O carro anda de verdade, só sem força; Dante chega
   muito atrás. Se mesmo assim ganhar, o Cascavel não paga: os meninos dele estão do lado da Monaliza.
5. **A chave:** Bia tira o porta-malas inteiro ("chave na chave é o carro, não o que tem dentro"),
   Vicente acha a mangueira cortada, Jessica dá a hora do comboio por culpa.

Conclusão marca a Monaliza como perdida (`monaliza_act2.lost`). Sem dinheiro. Chave `vicente_act2_bet`.

### A2-09 · Porta-malas novo — *jogável*

~20 min. Ferro-velho do Nonato, pátio do Digo.

1. **Nonato** ("Perguntar ao Nonato por um carro"): dá o Bison do fundo do pátio, na baia do
   ferro-velho. Vira carro da frota do deserto (`act2_nonato_bison`, recibo de valor zero
   `desert_act2_nonato_car`). É opcional: qualquer carro da frota do deserto serve.
2. **Bia, com o carro estacionado no pátio** (até 18 m dela): Digo acerta o motor e monta o fundo falso;
   Bia devolve a caixa. O porta-malas desse carro passa a ser o armazém. Digo: "Mangueira de turbo não
   corta sozinha."

Sem dinheiro. Chave `vicente_act2_trunk`; o carro do armazém fica em `monaliza_act2.trunk_car`.

### A2-10 · Comboio da madrugada — *jogável*

~30 min. Estrada do Sal, de madrugada (0h às 5h), e Motel Oásis.

1. **O assalto do comboio** é o `DesertHeist` que já existe (interceptar, tomar o caminhão, a desova,
   abrir o contêiner). A missão avança quando a carga é recolhida (fase `looted`), pagando o que o
   assalto já paga.
2. **Vicente no Motel Oásis:** o lacre original não foi raspado; numeração das Salinas, como o do
   caixote do Raul. "O Seu Bento manda lá faz vinte anos."

**R$ 1.500** (recibo `desert_act2_convoy`). Chave `vicente_act2_convoy`.

### A2-11 · Sal na ferida — *jogável*

~25 min. Salinas, acampamento dos foras-da-lei ao sul do leito seco (DesertWilds `outlaws_ridge`).

1. **Seu Bento** ("Mostrar o lacre ao Seu Bento"): as cargas eram trocadas no pátio da salina e o peso
   completado com sal; o caderno foi para "um rapaz da serra".
2. **Acampamento:** três foras-da-lei (os que já existem). O caderno ("Pegar o caderno meio queimado")
   só sai com o acampamento sem ninguém de pé: na página da noite da operação, "autorizado: 0417".

**R$ 2.200** (recibo `desert_act2_salt_ledger`). Chave `vicente_act2_salt`.

### A2-12 · Teodoro — *jogável*

~20 min. Motel Oásis, passagem norte.

1. **Teodoro no Motel Oásis** (Dona Lurdes chamou pelo rádio): a proposta de "indenização", as mentiras
   dele para os dois irmãos frente a frente; "Eu preciso ir."
2. **Na obra da passagem norte** ("Alcance Teodoro"): ele cede ("Pergunta pro teu antigo chefe. Ele
   assina com número, não com nome."), passa a pé pela barreira e larga a pasta: recibo de hotel no
   norte e um cartão com 0417. A obra continua fechada para carros.

Sem dinheiro. Chave `vicente_act2_teodoro`.

### A2-13 · Os oito anos — *jogável; final do ato*

~25 min. Arquibancada, encontro da arrancada, passagem norte.

1. **Arquibancada:** Dante entrega tudo. "E o que eu faço com os oito anos que eu perdi?" — "Não sei.
   Mas não vou deixar você fazer isso sozinho." Lívia pelo rádio: os Cobras estão descendo.
2. **Ataque ao encontro:** quatro Cobras (os mesmos agentes dos foras-da-lei) chegam pelo lado da pista
   quando Dante se aproxima. Salvar fica bloqueado durante a briga; morrer ou sair de perto desfaz o
   ataque, que volta inteiro na próxima aproximação.
3. **Vicente na passagem norte:** os operários tiram a barreira; Maciota liga — a 0417 está ativa numa
   delegacia do norte, e a Monaliza foi vista numa oficina dos Cobras lá em cima.

Conclusão marca `desert_story.delivered`, que abre a passagem norte (`DesertNorthPassLayout.completed`)
— **gatilho do ato 3**. **R$ 5.000** (recibo `desert_act2_finale`). Chave `vicente_act2_finale`.

## Do esqueleto antigo para as missões

| Marca de `DesertStoryState` | Missão que a marca agora |
|---|---|
| `arrived` | entrar no deserto (como antes) |
| `met_vicente` | A2-01 "Oito anos" |
| oficina do Digo (`DigoProgress`) | A2-02 "Respeita a pista" (a corrida que já existia) |
| `cargo_found` | A2-03 "Peso morto" |
| `bank_proof` | A2-04 "A ordem alterada" |
| `jessica_met` | a prova da Jessica que já existia; pré-requisito de A2-08 |
| `delivered` | A2-13 "Os oito anos" (abre a passagem norte) |

Os atalhos do esqueleto (caixote que marcava `cargo_found`, Irene que marcava `bank_proof`, Vicente
que marcava `delivered`) saíram: só as missões marcam. Saves antigos continuam válidos: quem já passou
de uma marca pelo esqueleto conta a missão como feita (sem a recompensa nova), e quem terminou o
esqueleto inteiro (`delivered`) conta o ato todo como feito.

## A Monaliza no ato 2 e no ato 3

A Monaliza é o carro pessoal `personal_monaliza` de `GarageRewards`, e o porta-malas dela não guarda
nada no carro: é o contêiner `trunk` do inventário em grade da carteira (`Economy`), que só abre com
Dante a pé atrás do carro do armazém (`FieldInventoryRuntime.trunk_access` → `PersonalCar._near_trunk`).

- **Nada é apagado.** Perder a Monaliza não mexe no contêiner `trunk`; itens e armas continuam no save.
  Entre A2-08 e A2-09 ele só fica sem acesso (na história, a "caixa da Bia").
- **Perdida** (`monaliza_act2.lost`): `GarageRewards` não monta mais o carro (suspende se estiver no
  mundo, menos com Dante ao volante) e o "Recuperar à baia" do Maciota responde que ela está com os
  Cobras. O registro do carro continua no save (identidade, pintura) para o ato 3.
- **A2-09** grava o carro do armazém (`monaliza_act2.trunk_car`); `PersonalCar._car()` passa a ser esse
  carro, onde ele estiver.
- **Validação:** perdida se e só se A2-08 terminou; armazém em outro carro se e só se A2-09 terminou,
  num carro da frota do deserto; o Bison do Nonato só com o recibo dele.
- **Ato 3:** recuperar a Monaliza limpa `lost`. O armazém fica no carro de A2-09 até o jogador pedir
  para voltar com ele para a Monaliza. Só um carro tem o armazém por vez.

## Por dentro

- `runtime/desert/act2/VicenteAct2State.gd`: A2-01 (`vicente_act2`) e A2-02 (`vicente_act2_track`)
  com regras próprias; A2-03 a A2-13 na tabela `CHAIN` (ordem em `ORDER`): chave por missão, começa
  quando a anterior acaba, `chain_finish` paga (se houver), fecha a etapa, marca a flag antiga e a
  Monaliza de uma vez. Tudo validado em `DesertSaveContract.valid` contra a carteira.
- `runtime/desert/act2/VicenteReunion.gd`: quem espera onde (`scene_def`), atores próprios (Vicente,
  Irene, Cascavel, Teodoro) só perto e com o lugar montado, pontos de ação sem ator, as provas de
  história, o ataque final (com span `desert.act2.raid`), objetivos e marcadores.
- `runtime/desert/act2/Act2Lines.gd`: falas de A2-05 a A2-13 (A2-01 a A2-04 ficam no próprio
  `VicenteReunion.gd`).
- Ganchos: `DesertCampaign` (Vicente, Bia, Raul, Irene, Jessica, fim das provas), `DesertRuntime`
  (ação da missão antes das outras, rota `act2:`, salvar bloqueado no ataque), `DesertDrag` (rivais
  de história, turbo cortado, derrota por distância), `DesertCharacter` (Cascavel e Teodoro),
  `GarageRewards` e `PersonalCar` (Monaliza perdida, armazém em outro carro), `DesertSaveContract`.
- Nenhuma luz, shader, textura ou malha nova; os atores reaproveitam `DesertCharacter` e os Cobras do
  ataque reaproveitam `CobraAgent`.
