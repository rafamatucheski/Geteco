# Ato 2 — Sal e Sangue (roteiro de 20/10/2026)

Roteiro da campanha do deserto (13 missões), do reencontro de Dante com Vicente até a missão que fecha o
capítulo e abre a passagem norte para o ato 3. Continua [o ato 1 de Harbor](story-harbor-act1-20261005.md)
e usa só lugares que já existem no mapa 2 ([mapa2-deserto.md](mapa2-deserto.md)): encontro da
arrancada, Estrada do Sal (Salinas, Balança, Motel Oásis, Capela, Arquibancada), cidade (Cobre,
Horizonte, oficina do Digo), vila Santa Lua, posto Miragem, cânion, cavernas de arenito e a
passagem norte em obra.

**Estado:** A2-01 a A2-04 estão jogáveis (`runtime/desert/act2/`, teste
`tests/test_desert_act2_reunion.gd`). As outras nove missões são roteiro. Até serem feitas, o
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
  ato é a aposta da Monaliza (A2-08), e ela vem de sabotagem física no carro, não de resultado
  escrito: a corrida acontece de verdade, com o motor perdendo força no meio da reta.
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

### A2-05 · Racha de irmãos

~25 min. Encontro, à noite (20h–5h; descansar no Horizonte adianta a hora).

1. Lívia anuncia: Vicente aceitou correr com Dante. A turma inteira para.
2. **Prova de 800 m contra Vicente** (rival novo do `DesertDrag`, carro dele, preparação de arrancada
   que ele mesmo monta). Resultado físico.
3. Venceu: "Ainda acelera do mesmo jeito." Perdeu: "Lá dentro eu pensava nessa reta todo dia."
   Os dois casos seguem.
4. Vicente chama Dante para a mesa de pedra ao sul do leito seco: "lá eu conto aquela noite".

Recompensa: primeira vitória paga R$ 2.000 (recibo único, como os prêmios de rival).

### A2-06 · Mesa de pedra

~30 min. Caverna escondida do Coyote (DesertWilds `cave_brother`, -1170, -1730).

1. Dirigir até a caverna (sem as dez cartas a lona continua presa; Vicente tem a chave do cadeado
   mas não abre: "ainda não").
2. **A fogueira.** Vicente conta a noite da operação: um "conhecido do Cobre" ofereceu o frete na
   última hora, pagando o dobro, e mandou não abrir a carga.
3. Dante conta o lado dele: recebeu a escala da operação com o nome do motorista **já** escrito,
   na véspera — antes da ordem que Irene mostrou ter sido alterada.
4. Se Dante já achou as dez cartas e levou o Coyote: Vicente vê o carro e fica quieto um tempo. Se
   não: Vicente deixa o cadeado e diz que as cartas mostram o caminho.

Recompensa: nenhuma (o Coyote continua sendo o prêmio das cartas; nada de pagar duas vezes).

### A2-07 · Destinatário desconhecido

~30 min. Capela, torre de rádio, vila Santa Lua.

1. **Dona Fátima** conta que, um mês atrás, um homem de jaqueta de polícia perguntou por Vicente e
   deixou uma vela "pelo rapaz". Ela anotou a placa do carro.
2. **Torre de rádio.** Dante sobe e liga para Maciota com a placa. Maciota: registrada no norte.
3. **Santa Lua.** O correio da cooperativa (Joana) guarda o malote antigo: as cartas de Vicente
   foram devolvidas pelo setor de correspondência do presídio com o mesmo carimbo da matrícula
   **0417** no verso.
4. Vicente ouve pelo rádio da cooperativa. Primeira vez que ele diz "nós" em vez de "você".

Recompensa: R$ 1.200 da cooperativa pelo conserto do rádio (recibo novo).

### A2-08 · Chave na chave

~40 min. Encontro da arrancada, à noite. A missão em que Dante **perde a Monaliza**.

1. **A prova da Jessica** (as provas de arrancada que já existem; resultado físico). Depois, no capô do
   Jetta, ela conta que fez frete para a transportadora dos Cobras e que o comboio dos papéis originais
   passa pela Estrada do Sal duas madrugadas por semana. A hora exata, só o piloto deles sabe.
2. **Cascavel**, o piloto dos Cobras, aparece no encontro com a turma dele. Propõe **chave na chave**:
   se Dante ganhar, leva o horário e a rota do comboio; se perder, entrega a chave da Monaliza.
   Vicente chama Dante de lado: "Não aposta o carro com essa gente. Eles não perdem." Dante aposta.
3. **Antes da largada**, a Monaliza fica parada na concentração enquanto Dante assina o quadro. Na
   reta, a pressão do turbo cai depois dos 400 m (mangueira cortada): o carro perde força **de verdade**
   (motor com potência reduzida, sem vitória ou derrota escrita), e o Cascavel passa. Se o jogador
   abandonar ou queimar a largada, a aposta também está perdida (a regra do chave na chave).
4. **A chave.** Cascavel leva a Monaliza na hora. Antes de entregar, Bia e Vicente tiram o que estava
   no porta-malas: "chave na chave é o carro, não o que tem dentro". Vicente acha a mangueira cortada
   no chão da concentração e não diz nada; só olha para Dante.
5. Jessica, com culpa, dá o horário do comboio mesmo assim: "Eu te pus nessa. Pelo menos isso."

Marca existente `jessica_met`. Recompensa: o prêmio de rival da Jessica que já existe. A Monaliza vai
para o norte com os Cobras e só volta no ato 3.

### A2-09 · Porta-malas novo

~25 min. Ferro-velho do Nonato, oficina do Digo.

1. Sem a Monaliza, o porta-malas some junto: tudo que estava guardado nele fica com a Bia, numa caixa
   trancada na oficina do Digo. Objetivo: arranjar outro carro.
2. **Ferro-velho do Nonato:** ele tem um carro velho no fundo do pátio (sem motor bom, sem placa).
   "Esse aí não vale nada pra mim. Pra você, vale o que você conseguir fazer andar." Dante leva o
   carro para o Digo (rebocado pelo guincho ou empurrado no ponto morto, conforme o que o jogo tiver).
   Quem já tem um carro próprio no deserto (comprado no Digo, o Supra do Takeshi, o Coyote das
   cartas) pode escolher um desses em vez do carro do Nonato.
3. **Oficina do Digo:** Digo deixa o carro andando e **transforma o porta-malas no armazém**: fundo
   falso, travas e o mesmo espaço do porta-malas da Monaliza. Bia devolve a caixa: tudo que estava na
   Monaliza volta para o porta-malas novo.
4. Digo, mexendo no motor: "Mangueira de turbo não corta sozinha, Dante. Quem fez isso sabia o que
   estava fazendo." Primeira vez que alguém fala em voz alta da sabotagem.

Recompensa: o carro novo, com o armazém. Sem dinheiro.

### A2-10 · Comboio da madrugada

~35 min. Estrada do Sal entre a Balança e o Motel Oásis, madrugada.

1. Esperar o comboio no horário que a Jessica deu (o assalto de carga existente, `DesertHeist`, em
   versão de história), já no carro novo.
2. Parar o caminhão sem destruí-lo; dois guardas. O baú certo é o do arquivo, não o da carga.
3. Fugir com o **lacre original** e o livro de cargas. Estrelas da polícia possíveis.
4. Vicente espera no Motel Oásis; os dois conferem: o lacre do livro tem a numeração da Salinas.

Recompensa: o que o assalto já paga, mais R$ 1.500 (recibo novo).

### A2-11 · Sal na ferida

~35 min. Salinas, acampamento dos foras-da-lei da serra (outlaws_ridge).

1. **Seu Bento** reconhece a numeração: as cargas eram trocadas no pátio da salina, à noite, com o
   peso completado com sal. Por isso o caminhão de Vicente pesou duas toneladas a menos.
2. Ele recebeu ordem de queimar o caderno das trocas; deu o caderno a um "rapaz da serra".
3. **Acampamento.** Três foras-da-lei estão queimando papéis. Combate (os acampamentos existentes).
4. Sobram páginas: a troca da noite da operação, com a mesma 0417 no campo "autorizado".

Recompensa: R$ 2.200 do Bento (recibo novo).

### A2-12 · Teodoro

~30 min. Motel Oásis, Route 66, canteiro da passagem norte.

1. Dona Lurdes liga: um advogado de terno está no quarto 6 perguntando por Vicente.
2. **Teodoro Salles** oferece "acordo" a Vicente para esquecer o processo. Dante chega no meio.
   Teodoro se contradiz diante dos dois: o que disse a um, o que disse ao outro.
3. **Perseguição** pela Route 66 até a passagem norte. Teodoro passa pelos operários da obra a pé e
   some do outro lado da barreira (a obra continua fechada para carros).
4. Na pasta que ele largou: um recibo de hotel na cidade do norte e a palavra "0417" num cartão.

Recompensa: nenhuma em dinheiro; a pasta.

### A2-13 · Os oito anos — *final do ato*

~40 min. Arquibancada, encontro, passagem norte.

1. **Amanhecer na Arquibancada.** Dante leva tudo a Vicente: manifesto, ordem alterada, lacre,
   caderno da salina, a pasta. Vicente lê em silêncio. "E o que eu faço com os oito anos que eu
   perdi?" (a fala do registro do ato 2).
2. **Os Cobras chegam ao encontro** para tomar os papéis. A turma de Vicente e Dante defendem o
   encontro (combate com cobertura; a turma é protegida, como hoje).
3. **Os dois irmãos no mesmo carro** — o carro novo de A2-09, com o armazém — até a passagem norte.
4. **A obra acaba.** Os operários retiram a barreira; a passagem norte abre (marca existente
   `desert_story.delivered`, que `DesertNorthPassLayout.completed` já consulta).
5. **Maciota liga:** a matrícula 0417 está ativa, numa delegacia da cidade do norte. E a Monaliza
   foi vista lá em cima, numa oficina dos Cobras. "Ele está esperando vocês, Dante. Os dois. E a
   minha Monaliza também."

Recompensa: R$ 5.000 (recibo `desert_act2_finale`), e a passagem norte aberta. **Gatilho do ato 3.**

## Do esqueleto antigo para as missões

| Marca de `DesertStoryState` | Hoje (esqueleto) | Missão que vai assumir |
|---|---|---|
| `arrived` | entrar no deserto | (continua) |
| `met_vicente` | **A2-01 "Oito anos"** (feito) | A2-01 |
| oficina do Digo (`DigoProgress`) | **A2-02 "Respeita a pista"** (feito) | A2-02 |
| `cargo_found` | **A2-03 "Peso morto"** (feito) | A2-03 |
| `bank_proof` | **A2-04 "A ordem alterada"** (feito) | A2-04 |
| (novas marcas) | — | A2-05, A2-06, A2-07 |
| `jessica_met` | vitória/fim da prova da Jessica | A2-08 (com a aposta da Monaliza) |
| (novas marcas) | — | A2-09, A2-10, A2-11, A2-12 |
| `delivered` | conversa final com Vicente | A2-13 (abre a passagem norte) |

Cada missão nova guarda as próprias etapas numa chave dela (como `vicente_act2`) e só marca a
flag antiga na conclusão. Assim saves antigos continuam válidos: quem já passou de uma marca pelo
esqueleto conta a missão como feita (sem a recompensa nova, como em A2-01).

## A Monaliza no ato 2 e no ato 3

Como funciona hoje (conferido no código em 20/10): a Monaliza é o carro pessoal `personal_monaliza`
de `GarageRewards`, e o porta-malas dela não guarda nada no carro: é o contêiner `trunk` do inventário
em grade da carteira (`Economy`), que só abre com Dante a pé atrás da Monaliza
(`FieldInventoryRuntime.trunk_access` → `PersonalCar._near_trunk`).

Isso deixa a perda segura:

- **Nada é apagado.** Perder a Monaliza não mexe no contêiner `trunk`; os itens e as armas continuam no
  save (as armas compradas têm recibo e não podem sumir, regra 11/12 do HOW-TO-DEVELOP). Na história,
  é a "caixa da Bia". No jogo, o contêiner só fica sem acesso até A2-09.
- **Perder** = uma marca nova (por exemplo `monaliza.lost_to = "cascavel"`) que faz `GarageRewards` não
  montar o carro e `PersonalCar` não oferecer o porta-malas. Salvar, carregar, morrer e ser preso
  respeitam a marca; o carro não pode reaparecer na garagem do Maciota.
- **A2-09** grava qual carro tem o armazém (`trunk_car = <vehicle_id>`). `trunk_access` passa a valer
  atrás desse carro, onde ele estiver.
- **Ato 3:** recuperar a Monaliza limpa a marca de perda. O armazém continua no carro de A2-09 até o
  jogador pedir ao Digo (ou ao Maciota) para voltar com ele para a Monaliza. Só um carro tem o
  armazém por vez.
- A sabotagem de A2-08 usa a mesma física de potência do câmbio do deserto (`DesertDrivetrain`):
  potência reduzida depois dos 400 m, sem mexer na posição nem na velocidade do carro.

## A2-01 a A2-04 por dentro

- `runtime/desert/act2/VicenteAct2State.gd`: chave `vicente_act2` (`version`, `stage` ∈ "",
  "motel", "chapel", "done"), avanço uma etapa por vez, validação contra a carteira (envelope de
  R$ 1.500 se e só se concluída; concluída implica `met_vicente`; `met_vicente` sem a chave só para
  save antigo). Entra em `DesertSaveContract.valid`.
- A mesma chave guarda A2-02 em `vicente_act2_track`; a etapa efetiva olha a oficina do Digo, então
  a corrida feita por qualquer caminho leva à Arquibancada. Etapa depois de `""` exige A2-01 feita;
  `grandstand`/`done` exigem a corrida.
- A2-03 e A2-04 estão na tabela `CHAIN` do mesmo arquivo: chave própria, começa quando a anterior
  acaba, e `chain_finish` paga (se houver), fecha a etapa e marca a flag antiga de uma vez. Recibo se
  e só se concluída; flag antiga se e só se concluída (save com a chave); save sem a chave e com a
  flag passou pelo esqueleto e conta como feito.
- `runtime/desert/act2/VicenteReunion.gd`: etapas, diálogos, ator do Vicente no motel, na capela e na
  Arquibancada (monta a até 85 m com o lugar da Estrada do Sal pronto, devolve a 120 m e ao
  morrer), objetivo e marcador; a conversa da Bia abre A2-02, a do Raul abre e fecha A2-03, a da
  Irene no balcão abre A2-04. Pontos de ação sem ator (caixote, Fiscal Rosa, orelhão) e a Irene na
  porta do Cobre, só à noite. `DesertRuntime.nearest_action` pergunta à missão antes da beira de
  estrada, para a etapa valer no lugar da conversa comum da Fiscal Rosa.
- `runtime/desert/DesertCampaign.gd`: a conversa única de antes virou a primeira etapa; o Vicente
  do encontro some enquanto espera no motel ou na capela; objetivo e marcador delegam à missão.
- Sem luz, shader, malha ou varredura nova: o ator é o mesmo `DesertCharacter` do encontro.
