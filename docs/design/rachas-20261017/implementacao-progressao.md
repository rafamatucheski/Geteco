# Noite de Acerto — implementação de progressão

Registro de 18/10/2026. Este documento descreve o corte implementado da direção escolhida em [01.png](conceitos/01.png). A [proposta original](progressao.md) contém referências e expansões; essas expansões não devem ser tratadas como conteúdo entregue.

## O que o jogador encontra

O quadro de rivais oferece **Noite de Acerto** para um adversário já acessível pela progressão existente. Uma inscrição usa o mesmo carro em três provas, com quatro passagens físicas:

| Prova | Passagens | Ponto |
| --- | --- | --- |
| Saída | 201 m | Tempo menor que o rival |
| Marca | 402 m + 402 m | Melhor tempo do jogador menor que o melhor tempo do rival |
| Desafio | 800 m | Tempo menor que o rival |

Vencer pelo menos duas provas vence a noite. Empate de tempo não concede ponto. A diferença entre as duas passagens de 402 m aparece como feedback de consistência; **não decide a pontuação**. As duas passagens de 402 m exigem a mesma preparação mecânica.

Antes de Saída, Marca e Desafio, o painel permite reinstalar peças já possuídas e aplicar um dos ajustes existentes `rua`, `drag` e `terra`. A compra continua na oficina do Digo. O carro inscrito mantém identidade, arquétipo e perfil; trocar de carro exige encerrar a noite incompleta. Encerrar não concede conclusão, dinheiro ou mérito.

Após cada passagem, o resultado oferece continuar, ver a noite ou ficar no local. Continuar e ver a noite usam o retorno físico existente à concentração. Após a quarta passagem, continuar vira repetir a noite. Não há cronômetro de menu obrigando outra tentativa.

O quadro associa cada rival a uma especialidade e famílias de peças: resposta em baixa, tração, relação de marcha, giro/turbo, fôlego em alta e preparação completa. São orientações para experimentar o acerto, não promessas de peças gratuitas ou desbloqueios exclusivos por rival.

## Recompensas e peças

- Concluir as quatro passagens paga **R$ 600**.
- Vencer a noite acrescenta **R$ 300**.
- A primeira noite vencida conta como **uma prova distinta** para a oficina. Repetições podem pagar, mas não acumulam novos méritos.
- As seis vitórias ranqueadas existentes mais essa primeira noite vencida chegam a sete provas distintas: a condição atual de `nitro_pro` pode ser satisfeita sem uma vitória de corrida da campanha.

Isso não desbloqueia a ponte, não substitui a campanha e não concede vitórias ranqueadas. Cada rival mantém sua ordem de disponibilidade, seus primeiros prêmios e seu histórico anterior. A integração da corrida distingue a noite antes de disparar a progressão narrativa legada.

Os valores 600/300 são a primeira calibração aprovada. Agora integram contratos persistidos de recibos: uma mudança futura de valor requer um novo domínio ou migração compatível, não apenas alterar os números do catálogo.

## Estado e compatibilidade

[DragNightProgress.gd](../../../activities/desert_drag/DragNightProgress.gd) guarda um campo opcional `world.drag_night`, versão 1. Saves antigos sem esse campo continuam válidos e não são modificados ao consultar os padrões.

O estado mantém:

- identificador monotônico da próxima inscrição;
- contadores de noites concluídas e vencidas, rivais vencidos;
- inscrição atual, carro inscrito e resultados já terminados;
- última noite concluída;
- até 256 recordes, separados por perfil mecânico, peças mecânicas e distância.

Pintura, acabamento, rodas e neon não fragmentam recordes. A assinatura inclui a versão de regra `rules1`. Ao exceder 256 configurações distintas, a mais antiga é removida; melhorar um registro existente não remove outro. Não há ranking online nem comparação artificial entre preparações diferentes.

A restauração retoma a próxima passagem, inclusive a segunda de 402 m. A condução em curso e o ticket de fila são transitórios: nenhum deles é convertido em resultado no carregamento. Repetir um callback de chegada, enviar outra distância, outra identidade de carro, outro perfil ou outra etapa não altera o estado.

Cancelar apenas o ticket ou interromper a arrancada limpa o contexto transitório e preserva a inscrição e a próxima passagem. **Encerrar a noite** remove também a inscrição incompleta. Se ela ainda estiver na fila, o controlador cancela primeiro o ticket correspondente, depois apaga a inscrição e salva; assim um ticket sem contexto de noite não pode ser despachado como uma arrancada ranqueada comum. O cancelamento considera o rival e o identificador da inscrição armada, sem assumir que qualquer ticket pendente pertence à noite.

Os recibos novos em [RecurringReceipts.gd](../../../systems/economy/RecurringReceipts.gd) usam os domínios contíguos `drag_night_finish` e `drag_night_win`, separados dos prêmios ranqueados. Cada domínio começa em 1 e só pode estar pago até o contador correspondente. Os IDs de inscrição nunca são reciclados, mesmo após abandono; os recibos contam as conclusões/vitórias realmente registradas.

Se faltar capacidade na carteira, o direito ao prêmio permanece no estado. Abrir a noite tenta liquidar os pendentes, no máximo oito recibos de cada domínio por chamada. A liquidação é idempotente e pode ser parcial: o resultado mostra tanto o recebido quanto o saldo pendente. O validador rejeita recibos sem conclusão correspondente, intervalos iniciados fora de 1 e pagamentos opacos que imitem os novos domínios.

## Integração no código

| Responsabilidade | Arquivo |
| --- | --- |
| Regras, recordes, validação e pagamento | [DragNightProgress.gd](../../../activities/desert_drag/DragNightProgress.gd) |
| Inscrição, preparação e retorno físico | [DragNightController.gd](../../../activities/desert_drag/DragNightController.gd) |
| Cartão da noite | [DragNightPanel.gd](../../../activities/desert_drag/DragNightPanel.gd) |
| Especialidades e falas dos rivais | [DragNightCatalog.gd](../../../activities/desert_drag/DragNightCatalog.gd) |
| Entrada no quadro | [DesertDragBoard.gd](../../../activities/desert_drag/DesertDragBoard.gd) |
| Ações do quadro e resultado | [DesertDragBoardController.gd](../../../activities/desert_drag/DesertDragBoardController.gd) |
| Resultado por passagem e por noite | [DesertDragResults.gd](../../../activities/desert_drag/DesertDragResults.gd) |
| Contrato compartilhado de save | [DesertSaveContract.gd](../../../runtime/desert/DesertSaveContract.gd) |
| Contagem de provas distintas | [RaceWins.gd](../../../systems/campaign/RaceWins.gd) |
| Distância real, callback e contexto da fila | [DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), integração do agente principal |

APIs de integração: `configure(owner_race)`, `open(identity)`, `status()`, `request_next()`, `record_finish(player_seconds, rival_seconds, car)` e `cancel_attempt(reason)` no controlador. A corrida fornece `start_night_pass(identity, metres)` e `cancel_waiting_context(reason)`. `record_finish` retorna `finished: true`, `night: true`, pontos, término, recorde e pagamentos; a distância vem da corrida efetiva.

## Evidência e limites

A suíte [test_drag_night_progress.gd](../../../tests/test_drag_night_progress.gd) teve **58 verificações aprovadas e nenhuma falha**, executada pelo agente principal no Godot 4.7.2 .NET: [log final](../../../output/drag-final-test_drag_night_progress.log). Ela cobre estados antigos, ordem e identidade de callbacks, serialização e restauração real pelo `SaveStore`, trava das duas passagens de 402 m, pontuação, recordes, repetição, perda, abandono, pagamento idempotente, carteira cheia e mérito para `nitro_pro`. A suíte legada de progressão também passou: **49 verificações, nenhuma falha**, [log](../../../output/drag-final-test_desert_drag_progress.log).

O [save isolado intermediário](../../../evidence/drag-night-save-42940-6751403/progress.json) foi gravado e carregado pela API de produção após a primeira passagem de 402 m. A comparação cobre o ledger serializado completo; os números inteiros em memória são representados como `float` pelo parser JSON do Godot e são validados como inteiros exatos pelo contrato.

A verificação de pagamento parcial passou no run final: com espaço para R$ 300, somente o bônus é recebido e o contrato informa R$ 600 pendentes; após abrir espaço, a conclusão é paga uma vez e o saldo pendente chega a zero. Isso valida o valor enviado ao feedback do resultado, sem simular créditos diretamente na carteira.

O teste final na cena Main completou **58 verificações sem falhas**, incluindo cancelamento e retomada da primeira passagem, quatro cruzamentos reais, ações Continuar/Voltar habilitadas nas quatro aberturas do quadro, retorno à concentração, checkpoint intermediário, 3/3 pontos, R$ 900 recebidos sem pendência e preservação do ranking e da campanha: [log integrado final](../../../output/drag-night-seams-fixed-20261018.log), [resultado final](../../../evidence/drag-night-session-43108-7127425/night-result-4.png). O tempo de 800 m foi 19,938656 s; o runner também verificou ausência de desaceleração física abrupta nessas quatro passagens. O primeiro problema de contexto de noite cancelado indevidamente pelo encontro já estava corrigido nessa execução.

A inspeção visual intermediária revelou que Continuar e Voltar permaneciam desabilitados após o retorno; a emissão direta do sinal pelo runner não havia coberto essa restrição de uso humano. `show_state` agora reabilita as ações antes de reaplicar as travas de preparação. O teste específico [test_drag_night_panel.gd](../../../tests/test_drag_night_panel.gd) monta o Control real e exercita busy → reabertura nas três etapas seguintes; valida disponibilidade de Continuar/Voltar, trava do par de 402 m e presets possuídos. **14 verificações aprovadas, nenhuma falha**, [log final da interface](../../../output/drag-final-test_drag_night_panel.log). A execução integrada final também verificou a disponibilidade dos botões antes de emitir as ações.

Os oito screenshots finais abaixo foram inspecionados em 1280 × 720: textos em PT-BR legíveis, sem sobreposição; ponto ativo e distâncias corretos; Continuar/Voltar disponíveis; preparação bloqueada somente na segunda passagem de 402 m; tempos, pontos, consistência e pagamento correspondentes aos resultados.

| Passagem | Quadro | Resultado |
| --- | --- | --- |
| 201 m | [quadro 1](../../../evidence/drag-night-session-43108-7127425/night-board-1.png) | [resultado 1](../../../evidence/drag-night-session-43108-7127425/night-result-1.png) |
| Primeiro 402 m | [quadro 2](../../../evidence/drag-night-session-43108-7127425/night-board-2.png) | [resultado 2](../../../evidence/drag-night-session-43108-7127425/night-result-2.png) |
| Segundo 402 m | [quadro 3](../../../evidence/drag-night-session-43108-7127425/night-board-3.png) | [resultado 3](../../../evidence/drag-night-session-43108-7127425/night-result-3.png) |
| 800 m | [quadro 4](../../../evidence/drag-night-session-43108-7127425/night-board-4.png) | [resultado 4](../../../evidence/drag-night-session-43108-7127425/night-result-4.png) |

A revisão final de cancelamento identificou um ticket remanescente ao encerrar uma noite ainda na fila. O controlador foi corrigido para cancelar essa inscrição antes de limpar seu contexto. O novo [test_drag_night_abandon.gd](../../../tests/test_drag_night_abandon.gd) exercita a ação do painel/controlador real com dublê da fila, verificando ausência de dispatch ranqueado e de prêmio, persistência após desbloquear o save e preservação da passagem quando apenas a fila é cancelada. **13 verificações aprovadas, nenhuma falha**, [log de abandono](../../../output/drag-final-abandon-20261018.log). Nenhum motor adicional foi iniciado por este agente; toda execução ficou coordenada pelo agente principal.

Os testes puros não comprovam fila física, sensação de dirigir, mix de áudio, estabilidade temporal do horizonte ou FPS.

Este corte usa classe **Livre**. Classes Original/Preparado, carro emprestado, modo autônomo com save separado, ghosts, peças exclusivas por rival e história completa de rivalidade permanecem fora da implementação. As falas do catálogo são texto autorado para uso pelo encontro; este módulo não adiciona dublagem. A localização inglesa completa das novas frases também permanece pendente. Os screenshots integrados em PT-BR foram inspecionados sem sobreposição de texto; a comparação de performance deve constar da validação integrada do agente principal.
