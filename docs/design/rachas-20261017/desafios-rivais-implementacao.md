# Desafios dos rivais — implementação de 18/10/2026

Entrada pelo quadro das arrancadas, em **Desafios dos rivais**. Cada rival propõe duas provas verificadas durante uma corrida real. Cumprir o objetivo vale mesmo que o adversário chegue antes. Os dois carimbos conquistam uma peça funcional e abrem o próximo rival; essa cadeia não altera as vitórias do ranking, a campanha ou a ponte.

| Rival | Primeira prova | Segunda prova | Peça conquistada |
|---|---|---|---|
| Digo | 201 m, largada boa/ideal | 402 m, duas boas trocas e nenhum erro | Mapa Digo: resposta em baixa, menos giro máximo |
| Lívia | 201 m, patinagem média até 25% nos primeiros 60 m | 402 m, boa largada, sem nitro, limitador até 0,5 s | Pneus Lívia: compromisso entre asfalto e terra |
| Raul | 402 m, três boas trocas e nenhum erro | 800 m, até 0,35 s de limitador nos 200 m finais | Relação Raul: alongamento intermediário de 6% |
| Jessica | Registrar uma passagem de 402 m | Repetir carro/acerto com diferença até 0,30 s | Turbo Jessica: resposta rápida, menor pico que o esportivo |
| Nadir | 800 m sem nitro | Conservar pelo menos 90% da velocidade de entrada nos 100 m finais | Alívio Nadir: menos redução de peso, mais resistência preservada |
| Rauhz | 402 m, boa largada e duas boas trocas sem erro | 800 m, boa largada, três boas trocas sem erro e até 0,5 s de limitador | Nitro Rauhz: força e duração intermediárias |

A peça entra na posse do carro que completou a conquista, sem substituir automaticamente o acerto em uso. O quadro permite instalar e receber cópias gratuitas para outros carros. A oficina normal reconhece a posse e permite remover/reinstalar. Não há venda nem moeda paralela.

O texto dos Pneus Lívia informa a perda líquida na terra, arredondada para 3,2%: os multiplicadores de tração e superfície resultam em `1,18 × 0,82 = 0,9676`. O quadro também explicita que o bônus exige melhorar um recorde existente em **mais de 0,01 s**. As duas descrições têm tradução em inglês; esta revisão ajustou somente apresentação, sem alterar critérios, preços ou multiplicadores.

Cada prova pode ser repetida depois de concluída. Os recordes separam rival, objetivo, perfil mecânico e peças instaladas; pintura/neon não criam recordes artificiais. Melhorar uma marca já existente em mais de 0,01 s, cumprindo o objetivo, dá R$ 200 até cinco vezes por rival. A primeira marca de uma preparação não paga esse bônus. Os recordes continuam funcionando depois dos cinco bônus, sem calendário diário ou perda de progresso.

Jessica guarda uma referência separada e persistente. A segunda prova exige o mesmo carro e as mesmas peças mecânicas. Correr novamente a primeira prova permite adotar outra referência; uma peça já conquistada continua conquistada.

## Categorias da Noite de Acerto

Livre preserva o comportamento e os hashes dos recordes anteriores. **Acerto R$ 6 mil** e **Acerto R$ 12 mil** limitam o valor de catálogo das peças mecânicas instaladas. O valor não é o preço do carro nem o dinheiro gasto na sessão. Peças de rivais têm valores de referência de R$ 1.800, 2.400, 2.200, 4.300, 2.600 e 3.900, respectivamente; cosméticos não contam.

A categoria fica fixa nas quatro passadas. A preparação do adversário usa apenas suas peças autorais e respeita o mesmo teto. A inscrição, o despacho da fila e a conclusão recusam um acerto acima do limite. O segundo 402 m continua exigindo o mesmo acerto do primeiro. Categorias têm recordes separados. Saves anteriores, sem o novo campo opcional, continuam em Livre.

## Resultado e preparação

O resultado mostra largada, boas trocas e uso de nitro. **Ver passagem** abre parciais, tempo no limitador, nitro, velocidade máxima e a dica medida pelo sistema de telemetria. As ações de repetir, voltar e ficar continuam disponíveis. O quadro explica objetivo, carimbos e peça antes da inscrição.

## Contratos e validação

- O observador dos desafios acumula valores até a chegada física do jogador; frenagem/retorno não entram nos objetivos. Não cria tempos nem termina corridas.
- Tentativas têm IDs monotônicos. Cancelar, trocar carro/acerto na fila, repetir callback ou restaurar checkpoint não concede carimbos ou prêmios extras.
- A garagem aceita peças de conquista sem recibo de compra; o contrato completo de save exige as duas provas válidas do rival correspondente.
- Bônus usam no máximo trinta IDs econômicos únicos, com valor e quantidade validados. Carteira cheia mantém pagamento pendente.
- `test_drag_rival_challenges.gd`: **127 verificações aprovadas**, incluindo os doze objetivos simulados no motor real de transmissão em três carros de entrada sem peças: Faísca GT, Metro Hatch e Sedan Classic. Cobre SaveStore isolado real (inclusive entre as duas provas de Jessica), corrupção, derrotas, tentativas duplicadas, peças instaláveis, carteira cheia e recorte correto do último frame. Patinagem parada também conta nos primeiros 60 m. Essa calibração não substitui a execução física em Main.
- Evidência final do lote: `output/rival-final-test_drag_rival_challenges-20261018.log`. O próprio log identifica os diretórios isolados dos roundtrips de arquivo.
- Primeira execução física renderizada de `test_drag_rival_session.gd`: **8 provas aprovadas** (Digo, Lívia, Raul e Jessica), inclusive cancelamento/retentativa, perda para o rival sem perda do objetivo, retorno e restauração de snapshot. Log `output/drag-rival-session-20261018.log`; fotos em `evidence/drag-rival-session-192228-10717637`. A nona prova identificou o corte antigo de 8 s após o adversário: Nadir terminava cedo e interrompia o Faísca original antes de sua chegada válida. A integração foi corrigida para deixar desafios técnicos aguardarem Dante, mantendo limite absoluto de 60 s.
- A retomada usa os oito resultados físicos registrados como **pré-requisitos de fixture**, validados novamente pelo reducer e contrato de save, e executa somente Nadir/Rauhz na pista. Não conta esses oito resultados como nova execução. Resultado: **76/76 verificações, exit 0**, quatro chegadas reais, todas em Faísca original; confirmou explicitamente que Nadir não interrompe o objetivo oito segundos após chegar. Log `output/drag-rival-session-resume-20261018.log`; fotos e snapshots em `evidence/drag-rival-session-222652-9135976`. O conjunto das duas execuções cobre os **12 objetivos físicos**, com Faísca sem peças em ambas e sem instalar prêmios entre provas. A retomada cria outra instância do mesmo modelo; as duas passagens comparadas de Jessica aconteceram na primeira execução, com a mesma instância e preparação.
- A instalação da ECU de Digo ocorreu pelo botão real do quadro e aparece em `completed-installed.json`, validado pelo contrato de produção. `night-budget-category.png` mostra a peça gratuita contabilizada como R$ 1.800, com categoria R$ 6 mil selecionada. Quadro, referência de Jessica, recompensa, telemetria expandida e HUD com objetivo longo foram inspecionados em 1280×720, sem cortes ou sobreposição entre instrumentos. As fotos finais da microtipografia dos controles pertencem à captura específica de HUD do agente de áudio.
- A retomada rodou como teste funcional/layout com uma fila headless e capturas externas concorrentes; seus contadores de FPS **não são medição de performance**. Não houve erro de script durante a execução. Depois de `RIVAL_SESSION_DONE`, o encerramento relatou recursos GPU ainda em uso. O agente principal identificou folhas destacadas na `GpuReleaseQueue` e acrescentou drenagem na saída; a confirmação desse fechamento pertence à rodada dele, sem repetir as provas já aprovadas.
- Testes dirigidos adicionais aprovados: categorias **56/56**, despacho **13/13**, painel dos desafios/resultado **13/13**. Regressões: Noite **58/58**, painel da Noite **14/14**, abandono/fila **13/13**, garagem/save **34/34** e progressão de tuning **PASS**. Logs `output/rival-final-*-20261018.log`, sem erros de script ou parsing. A verificação de foco encontrou e corrigiu uma referência ao botão oculto de telemetria; sem dados, Tab agora volta à ação principal.

As provas de oficina e os painéis não acrescentam NPCs, luzes ou SubViewports ao mundo. O acumulador vive apenas durante a tentativa e guarda números, sem histórico crescente por frame. O comparativo renderizado de desempenho pertence à validação integrada conduzida pelo agente principal.
