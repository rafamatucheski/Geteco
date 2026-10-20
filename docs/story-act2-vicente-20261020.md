# Ato 2 — Sal e Sangue (roteiro de 20/10/2026)

Roteiro da campanha do deserto, do reencontro de Dante com Vicente até a missão que fecha o
capítulo e abre a passagem norte para o ato 3. Continua [o ato 1 de Harbor](story-harbor-act1-20261005.md)
e usa só lugares que já existem no mapa 2 ([mapa2-deserto.md](mapa2-deserto.md)): encontro da
arrancada, Estrada do Sal (Salinas, Balança, Motel Oásis, Capela, Arquibancada), cidade (Cobre,
Horizonte, oficina do Digo), vila Santa Lua, posto Miragem, cânion, cavernas de arenito e a
passagem norte em obra.

**Estado:** A2-01 "Oito anos" e A2-02 "Respeita a pista" estão jogáveis (`runtime/desert/act2/`,
teste `tests/test_desert_act2_reunion.gd`). As outras dez missões são roteiro. Até serem feitas, o
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
- Corrida tem resultado físico: perder não trava a história (muda a fala).
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
| **Teodoro Salles** | (aparece em A2-11) | Advogado de Vicente nos oito anos. Mentia para os dois irmãos |
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

### A2-03 · Peso morto

~30 min. Posto Miragem, Balança, volta ao Miragem.

1. **Raul** pede ajuda: um bitrem dos Cobras deixou um caixote no posto e ninguém voltou para buscar.
2. **Balança.** Dante leva o caixote (carga física no carro) até a Fiscal Rosa. Peso confere, mas o
   lacre não: é o mesmo modelo de lacre da carga apreendida na operação de Vicente.
3. Rosa lembra: oito anos atrás pesou o caminhão "do rapaz" e ele estava **duas toneladas mais leve**
   do que dizia o papel da apreensão. Ninguém perguntou a ela.
4. **Manifesto** no caixote do Miragem: o código da carga dos Cobras e um beneficiário que recebeu
   pelo Cobre antes da apreensão (marca existente `cargo_found`).

Recompensa: R$ 900 de frete (recibo novo).

### A2-04 · A ordem alterada — *primeira pista de quem armou*

~30 min. Banco Cobre, cidade, Horizonte.

1. **Irene** confere o número da transferência do manifesto. A ordem foi alterada **antes** da
   operação: o nome do motorista (Vicente) entrou depois.
2. Ela não pode mostrar o registro interno. Dante volta à noite: a sala dos fundos do Cobre, o
   arquivo de ordens, sem arma sacada (alarme se sacar).
3. Na ordem original, quem autorizou a troca do motorista assinou com uma **matrícula, não com um
   nome: 0417**. Dante reconhece o formato: é matrícula de polícia.
4. No Horizonte, Dante liga para Maciota pedindo que descubra de quem é a 0417. Maciota: "Isso vai
   demorar. E vai fazer barulho." (marca existente `bank_proof`)

Recompensa: nenhuma em dinheiro; a pista é o prêmio. A matrícula fica em aberto até A2-12.

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

### A2-08 · A reta da Jessica

~25 min. Encontro.

1. Jessica (provas de arrancada existentes) chama Dante para a prova dela. Resultado físico.
2. Depois da prova, no capô do Jetta: ela fez frete para a mesma transportadora dos Cobras. O
   comboio dos papéis originais passa pela Estrada do Sal **duas madrugadas por semana**.
3. Ela dá a hora e o ponto, e avisa que não vai junto ("eu já paguei a minha conta com eles").

Marca existente `jessica_met`. Recompensa: o prêmio de rival já existente.

### A2-09 · Comboio da madrugada

~35 min. Estrada do Sal entre a Balança e o Motel Oásis, madrugada.

1. Esperar o comboio (o assalto de carga existente, `DesertHeist`, em versão de história).
2. Parar o caminhão sem destruí-lo; dois guardas. O baú certo é o do arquivo, não o da carga.
3. Fugir com o **lacre original** e o livro de cargas. Estrelas da polícia possíveis.
4. Vicente espera no Motel Oásis; os dois conferem: o lacre do livro tem a numeração da Salinas.

Recompensa: o que o assalto já paga, mais R$ 1.500 (recibo novo).

### A2-10 · Sal na ferida

~35 min. Salinas, acampamento dos foras-da-lei da serra (outlaws_ridge).

1. **Seu Bento** reconhece a numeração: as cargas eram trocadas no pátio da salina, à noite, com o
   peso completado com sal. Por isso o caminhão de Vicente pesou duas toneladas a menos.
2. Ele recebeu ordem de queimar o caderno das trocas; deu o caderno a um "rapaz da serra".
3. **Acampamento.** Três foras-da-lei estão queimando papéis. Combate (os acampamentos existentes).
4. Sobram páginas: a troca da noite da operação, com a mesma 0417 no campo "autorizado".

Recompensa: R$ 2.200 do Bento (recibo novo).

### A2-11 · Teodoro

~30 min. Motel Oásis, Route 66, canteiro da passagem norte.

1. Dona Lurdes liga: um advogado de terno está no quarto 6 perguntando por Vicente.
2. **Teodoro Salles** oferece "acordo" a Vicente para esquecer o processo. Dante chega no meio.
   Teodoro se contradiz diante dos dois: o que disse a um, o que disse ao outro.
3. **Perseguição** pela Route 66 até a passagem norte. Teodoro passa pelos operários da obra a pé e
   some do outro lado da barreira (a obra continua fechada para carros).
4. Na pasta que ele largou: um recibo de hotel na cidade do norte e a palavra "0417" num cartão.

Recompensa: nenhuma em dinheiro; a pasta.

### A2-12 · Os oito anos — *final do ato*

~40 min. Arquibancada, encontro, passagem norte.

1. **Amanhecer na Arquibancada.** Dante leva tudo a Vicente: manifesto, ordem alterada, lacre,
   caderno da salina, a pasta. Vicente lê em silêncio. "E o que eu faço com os oito anos que eu
   perdi?" (a fala do registro do ato 2).
2. **Os Cobras chegam ao encontro** para tomar os papéis. A turma de Vicente e Dante defendem o
   encontro (combate com cobertura; a turma é protegida, como hoje).
3. **Os dois irmãos no mesmo carro** — o Coyote, se Dante o levou da caverna; senão o carro de
   Vicente — até a passagem norte.
4. **A obra acaba.** Os operários retiram a barreira; a passagem norte abre (marca existente
   `desert_story.delivered`, que `DesertNorthPassLayout.completed` já consulta).
5. **Maciota liga:** a matrícula 0417 está ativa, numa delegacia da cidade do norte. "Ele está
   esperando vocês, Dante. Os dois."

Recompensa: R$ 5.000 (recibo `desert_act2_finale`), e a passagem norte aberta. **Gatilho do ato 3.**

## Do esqueleto antigo para as missões

| Marca de `DesertStoryState` | Hoje (esqueleto) | Missão que vai assumir |
|---|---|---|
| `arrived` | entrar no deserto | (continua) |
| `met_vicente` | **A2-01 "Oito anos"** (feito) | A2-01 |
| oficina do Digo (`DigoProgress`) | **A2-02 "Respeita a pista"** (feito) | A2-02 |
| `cargo_found` | caixote do Miragem | A2-03 |
| `bank_proof` | conversa com Irene | A2-04 |
| (novas marcas) | — | A2-05, A2-06, A2-07 |
| `jessica_met` | vitória/fim da prova da Jessica | A2-08 |
| (novas marcas) | — | A2-09, A2-10, A2-11 |
| `delivered` | conversa final com Vicente | A2-12 (abre a passagem norte) |

Cada missão nova guarda as próprias etapas numa chave dela (como `vicente_act2`) e só marca a
flag antiga na conclusão. Assim saves antigos continuam válidos: quem já passou de uma marca pelo
esqueleto conta a missão como feita (sem a recompensa nova, como em A2-01).

## A2-01 e A2-02 por dentro

- `runtime/desert/act2/VicenteAct2State.gd`: chave `vicente_act2` (`version`, `stage` ∈ "",
  "motel", "chapel", "done"), avanço uma etapa por vez, validação contra a carteira (envelope de
  R$ 1.500 se e só se concluída; concluída implica `met_vicente`; `met_vicente` sem a chave só para
  save antigo). Entra em `DesertSaveContract.valid`.
- A mesma chave guarda A2-02 em `vicente_act2_track`; a etapa efetiva olha a oficina do Digo, então
  a corrida feita por qualquer caminho leva à Arquibancada. Etapa depois de `""` exige A2-01 feita;
  `grandstand`/`done` exigem a corrida.
- `runtime/desert/act2/VicenteReunion.gd`: etapas, diálogos, ator do Vicente no motel, na capela e na
  Arquibancada (monta a até 85 m com o lugar da Estrada do Sal pronto, devolve a 120 m e ao
  morrer), objetivo e marcador; a conversa da Bia abre A2-02.
- `runtime/desert/DesertCampaign.gd`: a conversa única de antes virou a primeira etapa; o Vicente
  do encontro some enquanto espera no motel ou na capela; objetivo e marcador delegam à missão.
- Sem luz, shader, malha ou varredura nova: o ator é o mesmo `DesertCharacter` do encontro.
