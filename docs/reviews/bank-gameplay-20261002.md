# Banco North Pier — revisão de gameplay

Escopo: banco existente, seu assalto, saída, consequências e apresentação dos NPCs. Godot 4.7.2 .NET, C# compilado; cena produtiva `Main.tscn`, renderer Mobile, RTX 4060 Laptop. Saves pessoais preservados: execuções com `--no-save --skip-arrival`. Outras sessões alteraram arquivos distintos e partes de serviços compartilhados; nenhum trabalho alheio foi descartado.

## Comportamento entregue

- Guardas: 160 HP; atendentes: 100 HP. Apenas entrar ou carregar arma não dispara o combate. Disparo/agressão inicia alarme; antecipação de 1,25 s e proteção de admissão de 2 s antecedem a resposta. Dano/cadência dos guardas ajustados localmente.
- Cartão flutuante com giro, halo e coleta ao caminhar. Cofre conserva o minijogo de três travas e abertura de três segundos. Progresso ao segurar a ação fica visível.
- Três conjuntos de R$ 5.000: flutuação, giro, halo e absorção. O HUD distingue **saque em mãos** da carteira. Sair vivo deposita o saque; sair com parte deposita somente essa parte. Recibos por ciclo/máscara impedem duplicação.
- Morrer durante o assalto perde o saque em mãos e desconta R$ 5.000 da carteira (ou o saldo disponível, sem dívida). Recibo por morte evita cobrar novamente pelo mesmo callback. Conquistas monetárias são avaliadas no depósito, evitando bônus atrasado durante a morte.
- Morte dentro do banco com alarme habilita a investigação. É necessário um dia contínuo longe (>65 m e fachada fora do enquadramento); retornar reinicia a ausência. O banco fica fechado por três dias do calendário produtivo, exibe faixas externas e reabre fora de vista com novos perfis de guardas. Fuga viva e retorno imediato não interditam.
- Saves v1/v2 migram para v3 preservando dinheiro já recebido, sem duplicar recompensas nem perpetuar o fechamento automático antigo. Descanso contabiliza virada de dia, inclusive 24 horas exatas.
- A folha do cofre gira junto com suas colisões. Divisórias, painéis e molduras usam alfa de material compatível com Mobile. Saída tem vão de ativação mais amplo e indicação funcional no piso.
- Queda articulada substitui rotação rígida dos NPCs pelos pés. Limites das malhas apoiam os corpos no piso real; sangue orgânico pertence à sala e desaparece ao descarregá-la. O mesmo adaptador cobre o frentista sem alterar sua recompensa.

## Evidência

| Teste | Resultado e alcance |
|---|---|
| `test_bank_gameplay.gd` | 54 checks aprovados em Main. Caminhada real da porta exterior, primeira bala real, cartão, minijogo/cancelamento, travessia do cofre, saque, saída deslocada do centro, retorno, morte, resgate, interdição e reabertura. Dano adicional para concluir guardas é injetado; calendário avançado diretamente para abreviar quatro dias. |
| `test_bank_depth.gd` | 42 checks renderizados: colisão varrida de jogador/NPC na porta e balcões, espaço para coletar, oclusão antes/depois de transparência e controles positivos na sala/saída. |
| `test_bank_fallen_bodies.gd` | 41 checks: apoio durante/depois da queda, guardas, duas atendentes, frentista em piso elevado, sangue, restauração de morto e limpeza. |
| `test_bank_aftermath.gd` | 34 checks: morte exigida, retorno interrompe ausência, calendário, três dias, migração, snapshots, faixas/postes e sobra de tempo persistida. |
| `test_bank_stakes.gd` | 20 checks: R$ 15.000 em risco, perdas, carteira insuficiente, saídas parciais, idempotência e rejeição de snapshot inválido. |
| `test_robberies.gd` | 33 checks: regressão de cofre/cartão, ciclo, intimidação física do frentista e recompensa original de R$ 180 do posto. |
| `test_video_session_transitions.gd` | 31 checks Main: restrições de armas da garagem, clima, câmera/controle de saída e morte/resgate do banco. |

A execução renderizada do fluxo completo aprovou apresentação e calendário, mas sua última assertion financeira inicialmente encontrou um bônus de conquista de R$ 250 disparado no evento de morte. Corrigido avaliando conquistas junto com o depósito; nova execução Main aprovou os 54 checks. Não se tratava de duplicação do saque. O fixture antigo de roubos também precisou receber os sinais reais de reação civil e novas expectativas monetárias.

O primeiro teste de profundidade revelou que desabilitar processamento removia corpos do espaço físico do fixture; `DISABLE_MODE_KEEP_ACTIVE` preservou as queries. As capturas estáticas passaram a desabilitar interpolação para não medir a posição anterior com FPS alto. Os critérios de visibilidade e colisão foram preservados.

## Fotos reais

Primeira revisão desta tarefa (já incluía cartão animado/saída, ainda sem corrigir corpos e transparência): [corpos/cartão](../../evidence/bank-gameplay-20261002/first-review/02-card.png), [cofre opaco](../../evidence/bank-gameplay-20261002/first-review/04-inside-vault.png).

Resultado: [cartão e corpos](../../evidence/bank-gameplay-20261002/02-card.png), [cofre transparente, dinheiro, sangue e HUD](../../evidence/bank-gameplay-20261002/04-inside-vault.png), [saque completo](../../evidence/bank-gameplay-20261002/05-haul.png), [morte/penalidade](../../evidence/bank-gameplay-20261002/07-death-penalty.png), [faixas exteriores](../../evidence/bank-gameplay-20261002/08-closed-bank.png), [nova equipe](../../evidence/bank-gameplay-20261002/09-new-guards.png).

Logs, máscaras de oclusão e dados brutos ficam em `evidence/bank-gameplay-20261002/`.

## Desempenho e limites

Comparação antes/depois **inconclusiva**: outras sessões de captura/benchmark estavam em execução antes da implementação, impedindo uma base isolada. Capturas bonitas e o contador do HUD não são aprovação de FPS. Medição atual em Main com cofre aberto, dinheiro animado, corpos/sangue e resposta urbana ativa é registrada separadamente (5 s de aquecimento + 30 s de amostra, 1280×720, MSAA 2×, VSync e limite de 60).

Resultado atual: **59,999 FPS médios**, 1.801 frames / 30,017 s; p50 **16,673 ms**, p95 **18,146 ms**, p99 **19,171 ms**, máximo **35,934 ms**; 1 frame acima de 33,3 ms e nenhum acima de 66,7 ms. Inventários de processos nas extremidades da execução encontraram apenas o editor além do processo medido; não houve monitor contínuo de concorrência. [Dados brutos](../../evidence/bank-gameplay-20261002/performance/bank-current.json), [contexto](../../evidence/bank-gameplay-20261002/performance/bank-current-context.json), [captura da cena medida](../../evidence/bank-gameplay-20261002/performance/bank-current.png). Alvo provisório de 60 FPS observado em média; margem GPU e ausência de regressão não certificadas sem comparativo.

A amostra solicitou população 40 no lançamento e registrou 20 pedestres ativos e 27 veículos ao final, com streaming normal; os diretores não foram desligados. A captura inclui dois policiais que chegaram ao cofre durante a medição.

Não há certificação integral do interior: testes cobrem a cadeia afetada e sólidos principais, não cada móvel/arma/clima. Persistência foi verificada por contratos e roundtrip JSON, sem ciclo completo de save/load produtivo em disco no meio do assalto. Não foi realizada auditoria global de iluminação ou do jogo.

## Estado concorrente na checagem final

Após o fluxo Main e a medição terem terminado, outra sessão acrescentou `gameplay/urban_v1/CobraRaceDriver.gd`. Uma execução encontrou erros de inferência de tipo nas variáveis `hit` (linha 49) e `toward` (linha 58), propagados por `CobraStreetRace`/`MissionWorld` até o autoload `SessionLaunch`. O arquivo alheio foi preservado e o bloqueio informado ao usuário. A própria sessão corrigiu as tipagens; a última inicialização e os 33 checks de roubos passaram sem erros/avisos (`final-parse-and-robberies.log`). A limpeza do fixture agora também encerra seus canais de áudio antes do teardown. Build C# final sem erros/avisos e `git diff --check` aprovado. Isso não certifica o gameplay novo de Cobra, fora deste escopo.
