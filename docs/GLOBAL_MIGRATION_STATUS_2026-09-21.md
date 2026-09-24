# Panorama consolidado V1 → V2

## Atualização após as quatro entregas de integração

Esta seção substitui os estados antigos abaixo quando houver diferença. Recebidos os relatórios de integração central, persistência/economia, controles/interface/áudio e Claude. Conferência pontual por leitura, sem executar Godot, testes ou parsers.

- **NPCs e teleférico:** ProductionWorld agora instancia RoutineDirector; NativeRegion mantém mecanismos e chama set_operating/set_animation_active. A entrega central relata conexão de interação, horário e atualização de contexto. Não continuam classificados como módulos inteiramente desconectados; rotas, montagem e horário não foram validados em execução.
- **Ski e save:** MountainProgression referencia V1OptionalRewardPolicy. GameState usa schema 3 e inclui canonical_campaign no snapshot, com migração explícita de schema 2. Recuperação de temporários e publicação de importação foram relatadas como implementadas, não executadas.
- **Controles/áudio:** entrega central relata exclusão mútua das transições, arbitragem dos botões e modais. WorldAudio agora consome radio_previous. Remapeamento/configurações foram corrigidos segundo a equipe. Actor consome sprinting segundo Claude.
- **Luneta:** CameraRig lê scope_active e aplica multiplicador 0.5 ao tamanho da câmera com retícula. Portanto zoom/retícula já estão conectados. Ainda usa zoom fixo e não scope_part, introduzido depois pelo Claude; isso é diferença de contrato a decidir, não ausência total de luneta.
- **Progressão, recompensas e serviços:** `FullSession` usa `purchase_body_armor`, publica recompensas físicas somente após `Economy.grant_world_reward` concluir toda a concessão e não contém mais o reparo genérico de R$ 150. A abertura apresentada conclui somente `prologue_call` no ledger canônico; nenhum beat posterior é inferido das missões distintas de Harbor.

### Pendências de integração confirmadas nesta leitura

1. Dos nove beats canônicos, somente `prologue_call` possui hoje um evento V2 equivalente comprovado: conclusão ou pulo da apresentação de abertura. `bus_terminal_arrival` exige também encontrar o contato que oferece o trabalho do porto; as etapas seguintes e os quatro contratos continuam sem adaptadores físicos V2 e não são concluídos pelas seis missões distintas de Harbor.
2. Conversor V1 e interface de importação continuam fora desta rodada; os novos contratos estabilizam snapshots V2, sem importar progresso V1.
3. GameInput ainda alterna sprint por botão com guarda de pausa/visibilidade, sem guarda explícita de modal no trecho lido. Reavaliar contexto de menus antes da correção.

### Limites restantes

Claude informa que clipes armados traseiro/direito só entram em baixa velocidade analógica; a velocidade comum de 3.5m/s cai na caminhada normal. Não registrar locomoção armada completa, nem reduzir velocidade de mira sem avaliar a decisão de jogabilidade. Mistura dos golpes e tipagem receberam revisão, mas não compilação real. Integridade da documentação restaurada não comprova preservação de edições de terceiros não presentes no histórico do autor.

A frente de progressão posterior fechou os consumidores de colete, recompensa mundial e reparo genérico. O avanço canônico foi ligado somente onde existe equivalência física comprovada; completar os demais beats continua dependendo de conteúdo próprio, não de adaptação nominal das missões de Harbor.

Data: 21/09/2026. Consolidação dos relatórios recebidos, com conferência pontual do código atual. Não é uma auditoria exaustiva. A frente de progressão executou um diagnóstico Godot isolado dos módulos de economia/campanha; os testes oficiais do projeto não chegaram ao script por contenção na importação compartilhada e não são considerados aprovados. Nenhum benchmark foi executado.

## Entregas e conexão

| Frente | Estado | Pendências |
|---|---|---|
| Cidade–serra | ProductionWorld referencia WorldConnection3D, mantém regiões residentes e muda contexto lógico preservando instâncias; NativeRegion contém tratamento da ligação | Travessia a pé/veículo/passageiro, tráfego, túnel, colisão e custo da sobreposição não executados |
| Terreno e cenário | Relevo, decoração, cemitério e Porto Sul integrados na rodada anterior; MountainDetailFactory referencia EnvironmentalParityFactory | Inventário visual completo, acessos, operação portuária, cemitério e fachadas ainda parciais |
| Áudio | WorldAudio instancia perfis/contexto, resolução de superfícies e ActivityAudioBridge | Audição/mixagem não validadas; eventos próprios de carga/guincho pendentes; radio_previous continua sem consumidor no arquivo lido |
| Sessão, transições e controles centrais | FullSession usa geração exclusiva compartilhada com Driving para interiores, garagem e resgate; a sala candidata permanece local até admissão; save/load/menu incluem chegada bloqueada; X e D-pad têm arbitragem contextual; modais recebem foco e cancelamento | Compilação e todos os cenários concorrentes permanecem sem execução; módulos externos de Arrival/GarageRewards não foram alterados |
| Rotinas de NPCs | RoutineDirector é instanciado uma vez por ProductionWorld; FullSession consulta/executa suas ações na prioridade documentada e força refresh em interior, exterior e troca lógica de região | Rotas físicas, turnos, diálogo, colisão/profundidade, duplicação e custo não validados |
| Teleférico | Registro e montagem por chunk conectados em NativeRegion; animação é suspensa antes do descarregamento; ProductionWorld aplica operação somente em mudança da faixa 08h–18h | Posição, colisão, movimento, desligamento, remontagem e custo não validados em runtime; não confundir com picape já conectada |
| Combate | Claude relata cheat, controles, efeitos, áudio, mira e camada corporal conectados | Luneta sem câmera/retícula, locomoção armada parcial, atraso visual do golpe e interrupções precisam de execução; relatório não equivale a validação independente |
| Atividades | Corridas, drift, ski e coleta conectados segundo revisão específica | MountainProgression ainda usa recibos ski_finish/ski_record únicos; helper V1OptionalRewardPolicy não aparece conectado no arquivo lido |
| Serviços | Reparo genérico remoto removido; Maciota encaminha à bancada da Monaliza e Northgate conserva baia exterior de R$ 100, único reparo que limpa procurado | Execução física das duas baias e mensagens contextuais da sessão ainda não validada nesta rodada |
| Persistência | Schema 3 conserva campanha canônica; recompensas mundiais agora têm recibo atômico e reconciliação de marcador; contratos cruzados rejeitam recibo de arma sem a arma | Compatibilidade/importação V1 permanece fora de escopo; teste oficial completo ficou bloqueado na importação concorrente do projeto |

Ambiência da serra não deve continuar listada simplesmente como ausente: a entrega de áudio é posterior e está conectada por leitura. Ainda falta confirmar o resultado na travessia. Da mesma forma, continuidade regional passou de ausência para implementação sem execução validada.

### Frente de progressão desta rodada

**Conectado:** `FullSession._show_shop` delega o débito a `Economy.purchase_body_armor` e só aplica `armor` após sucesso; proteção completa não cria débito nem save. `Economy.grant_world_reward` trata dinheiro, item e arma + munição como uma concessão atômica, grava recibo durável e diferencia concessão nova de reconciliação. `FullSession._collect_reward` só acrescenta o marcador mundial depois desse retorno; carteira/inventário/munição cheios deixam recompensa e marcador disponíveis. `GameState` aceita recibo de dinheiro sem marcador para reparo idempotente, rejeita marcador de dinheiro sem recibo e rejeita recibo de arma sem a arma concedida.

O menu genérico de reparo de R$ 150 foi removido. O serviço `garage` encaminha à bancada física da Monaliza; `auto_service` encaminha à baia exterior da Northgate. Somente a Northgate mantém seu contrato produtivo de R$ 100 e limpeza de procurado após permanência válida na baia; a sessão não limpa procurado por encaminhamento ou diálogo.

`Arrival` chama `canonical_campaign.complete_beat("prologue_call_completed")` após o término ou pulo da apresentação que contém a ligação e reconcilia esse evento quando `opening_completed` já está persistido. Ordem e idempotência permanecem no ledger. Nenhuma aproximação, abertura de diálogo ou missão Cobra conclui beat canônico. O V1 produtivo também só liga essa apresentação a `prologue_call`; `bus_terminal_arrival` e os sete beats seguintes continuam pendentes de seus próprios eventos físicos.

**Evidência e limites:** os diagnósticos Godot isolados passaram 11 cenários de economia/campanha (`PROGRESSION_ATOMICITY PASS`) e nove de `GameState` (`GAME_STATE_PROGRESSION PASS`), usando cópias exatas desses módulos e stubs somente para dependências alheias aos contratos exercitados. Foram cobertos compra de colete, colete cheio, restauração conjunta de débito/proteção, concessão e repetição de dinheiro/arma + munição, roundtrip, repetição após carga, carteira cheia, ordem e restauração canônica, marcador órfão, reconciliação de recibo e recibo de arma órfão. `test_campaign_economy.gd` e `test_full_save.gd` receberam os mesmos cenários duráveis, mas duas tentativas oficiais ficaram na importação concorrente sem iniciar o script; foram encerrados apenas os processos dessas tentativas. UI, coleta física no mapa, bancada, baia e persistência integral da sessão não estão validadas em execução.

### Frente de integração central desta rodada

**Conectado por leitura:** `FullSession` concentra um token de geração para entrada/saída a pé, transferência/restauração de veículo e resgate. Entradas reentrantes são recusadas antes de criar uma segunda sala; o nó candidato não substitui `room` antes dos `awaits`; região, lugar, saúde, carro ocupado e geração são revalidados em cada retomada. Falhas anteriores ao commit descartam somente o candidato próprio e restauram locks, ocupação, visibilidade/física do jogador e parâmetros de câmera capturados. `Driving` consulta o mesmo contrato e não aceita desembarque/embarque externo durante a transferência. A restauração de local recusa Maciota fora de Harbor e qualquer definição cujo `region` não coincida com `state.region_id`, preservando o save como inválido e retomando pelo exterior conhecido sem alterar o schema.

Save, load e retorno ao menu agora consultam o mesmo bloqueio, que inclui `Arrival.controls_locked` e `Arrival.phase == "opening"`; o evento de pausa é consumido nessas sequências. Avisos são explicitamente exibidos acima dos painéis e continuam com tempo de vida durante pausa. Nos modais criados por `FullSession`, o primeiro botão recebe foco, os botões consecutivos recebem vizinhança vertical e `B/ui_cancel` fecha quando não é o modal obrigatório de resgate. No jogo, X prioriza uma ação contextual real e só recarrega quando não há ação; D-pad para baixo abre o porta-malas apenas se `PersonalCar.nearest_action()` oferece essa ação, usando mãos livres no restante.

`RoutineDirector` depende exatamente de `configure(world, session, controller)`, `refresh_context()`, `nearest_action()` e `perform(id)`. O teleférico depende de `MountainDetailFactory.get_environmental_records()`/`populate_environmental_chunk()`, dos métodos `set_operating(bool)` e `set_animation_active(bool)` do mecanismo e de `Weather.time_of_day` normalizado, convertido para hora por `* 24.0`. As integrações de chegada, garagem e região dependem somente dos contratos já existentes de `Arrival`, `GarageRewards`, `PlaceCatalog`, `WorldConnection3D` e `logical_region_changed`; nenhum desses módulos externos, nem GameInput, menus, save schema, câmera, Actor, Vehicle, combate, áudio ou economia foi modificado nesta frente.

**Continuidade preservada por contrato:** a travessia física cidade–serra continua usando o mesmo jogador e a mesma instância de veículo dirigido ou de transporte de passageiro. A troca lógica apenas atualiza região/metadados e contexto dos consumidores; esta integração não chama `Driving.leave()`, `PassengerTransport.cancel_for_transition()` nem teleporte no limite físico. Viagem rápida e restauração mantêm seus caminhos separados existentes.

**Pendente e não validado:** não houve execução de Godot, teste, benchmark ou percurso. Permanecem obrigatórias as tentativas reentrantes quadro a quadro, desembarque nos três frames da transferência, falhas de colisão em ambos os sentidos, morte durante transição, save/load/menu em cada fase da chegada, foco por teclado/controle, arbitragem real de X/D-pad, restauração de câmera a partir de interior e exterior, rotina diurna/noturna, teleférico às 07:59/08:00/17:59/18:00, descarregamento/reentrada do chunk e travessia cidade–serra a pé, dirigindo e como passageiro. Colisão, profundidade, ausência de nós órfãos, compilação e desempenho não estão aprovados por inspeção estática.

## Ordem recomendada de integração

1. **Estabilidade e estado do jogador.** Corrigir exclusão mútua da entrada em interiores e desembarque durante transferência de garagem; centralizar bloqueios de save/load/menu durante transições e chegada; rejeitar pares incompatíveis de região/interior. FullSession.enter_place ainda escreve room compartilhado antes de dois awaits sem guarda própria de admissão no trecho conferido.
2. **Controles utilizáveis.** Resolver arbitragem X interação/recarga e D-pad porta-malas/mãos livres; foco/cancelamento dos modais; sprint alternável, remapeamento, restauração de câmera e feedback na pausa. Achados detalhados são dos revisores; reconferir cada trecho antes de editar.
3. **Conectar entregas prontas.** RoutineDirector/interações, teleférico/horário, pagamento repetível do ski, luneta via scope_active. Um responsável pelos encaixes centrais evita sobreposição entre equipes.
4. **Progresso e economia.** Executar os testes oficiais já ampliados quando a importação compartilhada estiver livre; implementar eventos físicos próprios para os oito beats canônicos restantes e definir separadamente a política de importação V1. Preservar arquivos originais e nunca manipular saves pessoais na validação.
5. **Carregamento e distribuição.** Tratar retorno nulo da frota e temporários abandonados; definir inclusão de JSON e cenas dinâmicas na exportação. A revisão encontrou as 49 cenas da frota; não relatou ausência atual. Falta de preset é risco de distribuição, não prova da causa dos erros anteriores no editor.
6. **Validar e completar paridade.** Após autorização de execução, primeiro compilação/carregamento e percursos críticos; depois comparação física/visual/sonora e frame time renderizado. Completar diferenças do mapa com evidência V1.

## Riscos técnicos separados de defeitos

- Chunk inteiro construído sincronamente, preparação global de até 734 árvores/4.404 tentativas e reconstrução de interiores: custos potenciais identificados, sem duração ou FPS medidos.
- Consultas de catálogo/recurso por quadro no áudio, atualização repetida de equipamento e buscas globais: oportunidades de investigação, não prioridade sobre perda de estado sem medição.
- Entrada reentrante e reconstrução de interior são achados distintos: concorrência lógica versus custo de montagem.
- A tentativa integrada de uma equipe falhou por tipagem em Gameplay na ocasião; não autoriza afirmar que o código atual mantém esse erro. gdparse não certifica compilação Godot. Sem validação atual de inicialização.

## Referências de revisão

- REPORTS_INTEGRATION_INBOX_2026-09-21.md: recebimento e responsabilidades.
- reviews/static-loading-review.md: recursos, frota, temporários e flags.
- reviews/static-lifecycle-review.md: transições, saves e chegada.
- reviews/static-runtime-cost-review.md: riscos de custo e cenários de medição.
- MAP_MIGRATION_COVERAGE.md: fontes e diferenças geográficas.
- AUDIO_AMBIENCE_MIGRATION.md, NPC_ROUTINES_MIGRATION.md, SCENARIO_MODELS_MIGRATION.md: entregas ambientais.
- OPTIONAL_ACTIVITIES_HANDOFF_2026-09-21.md, SERVICES_FLOW_HANDOFF_2026-09-21.md, SAVE_PROGRESSION_CONTRACT_REVIEW_2026-09-21.md: atividades, serviços e persistência.

Não há base para porcentagem global confiável de conclusão. O V2 possui mais conteúdo implementado do que integrado e validado; a migração integral permanece aberta.
