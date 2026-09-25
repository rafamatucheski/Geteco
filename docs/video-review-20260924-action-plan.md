# Plano de ação — revisão do vídeo de 24/09/2026

## Objetivo e evidências

Restabelecer uma partida estável e corrigir os problemas confirmados no vídeo, preservando o trabalho local de outras sessões. A gravação é da build v0.2.0 (8bd083a); o código atual já contém alterações posteriores e cada ocorrência precisa ser confrontada com ele.

Relatório completo dos 36 achados: `C:/Users/rafae/.codex/visualizations/2026/09/24/01a0d558-4410-7471-98cb-1032e2e21647/relatorio-video.md`.
Relatos/requisitos: `C:/Users/rafae/.codex/visualizations/2026/09/24/01a0d558-4410-7471-98cb-1032e2e21647/contexto-do-usuario.md`.

## Divisão do trabalho

| Frente | Responsável | Arquivos reservados inicialmente | Primeira entrega |
|---|---|---|---|
| Estabilidade e veículos | Agente 1, `revisao_movimento` | `runtime/ProductionWorld.gd`, `scripts/Driving.gd`, `scripts/Vehicle.gd`, `gameplay/VehicleBoardingPresentation.gd`, `gameplay/VehicleDoorPresentation.gd`; teste novo `test_video_vehicle_lifecycle.gd` | Referência de veículo liberado, transferência/remoção de ocupantes, integridade de embarque e saída, prompt específico da moto |
| Interiores e interações | Agente 2, `revisao_visual` | `runtime/WeaponShopEntrance.gd`, `runtime/BankGuardModel.gd`, `runtime/RobberyActor.gd`, `world/places/NativePlace.gd`; após achado renderizado, somente silhueta em `world/city_look/CityLook.gd` e seu shader | Posição/apoio do jogador, vendedor acessível junto ao balcão, poses dos guardas, transições e oclusão |
| Performance e comprovação | Agente 3, `performance_execucao` | Novos `tests/measure/video_review_*`, `evidence/video-review-20260924/` | Baseline renderizado, captura dos cenários, diagnóstico de congelamentos e comparação após correções |
| Integração | Agente principal | `runtime/FullSession.gd`, `runtime/Weather.gd`, `ui/ClassicGameplayHUD.gd`, teste novo `test_video_session_transitions.gd`, documentação/checklist | Integrar pontos compartilhados, preservar regras de garagem, revisar alterações e consolidar validações |
| Catálogo e personalização | Claude, quando o usuário enviar o prompt | **Reservados:** `runtime/HarborAmmunationCatalog.gd`, `runtime/HarborWeaponWorkbench.gd`; novos testes `test_claude_arsenal_ui_*` | Descrição coerente com seleção, contraste e preço/posse claros, sem alterar a economia |

Não editar `scripts/Actor.gd`, `scripts/CameraRig.gd`, dispatch, geometria urbana ou outros arquivos compartilhados sem combinar a responsabilidade. Eles têm trabalho pré-existente. Alterações externas durante a tarefa não devem ser sobrescritas. Cada agente lê o arquivo imediatamente antes de aplicar um patch pequeno; mudanças inesperadas são comunicadas.

## Sequência de execução

1. **Preservar e diagnosticar.** Registrar estado local, ler diffs e confirmar o que ainda falha. Capturar baseline antes de editar runtime, se houver janela exclusiva de medição. Três agentes já acionados.
2. **Estabilidade — prioridade máxima.** Corrigir erro de respawn/save com veículo removido; impedir perda do veículo ocupado por limpeza de entidades; verificar carro que sai do mapa após embarque. Testar entrada, roubo, remoção, morte e restauração sem tocar no save real.
3. **Personagens e interiores.** Corrigir apoio no piso, oclusão, interação do vendedor e mira dos guardas. Separar falha física de falha de apresentação; conferir em imagens reais. Preservar Maciota/mecânico invulneráveis e garagem sem armas.
4. **Fluidez.** Reproduzir rota de moto/porto e primeira explosão; separar aquecimento e regime estável. Corrigir apenas gargalos demonstrados, preservando qualidade e jogabilidade. Comparar p50/p95/p99, máximo e frames acima de 33,3/66,7 ms.
5. **Acessos.** Integrar porta por proximidade, zoom de entrada e saída nos locais pedidos; não duplicar implementações já existentes. Corrigir chuva, vazio e atualização tardia de luz/HUD. Sem E para a passagem solicitada; manter ações funcionais de NPC/objetos.
6. **Porto e polícia.** Tornar o porto útil e jogável, com atividades/recompensas legíveis pela aparência, sem obrigação de copiar V1. Remover letreiro da Garagem do Chefe, trocar North Pier por cifrão, ajustar polícia comum com pistola e escalonamento. Antes de editar, verificar sobreposição com sessões que já alteram dispatch e fachadas.
7. **Interface e acabamento.** Frente do Claude no catálogo; integração posterior dos prompts de morte, garagem fechada, salvamento e navegação, além dos detalhes de materiais/legibilidade.

## Rastreamento dos achados

| Lote | IDs do relatório | Estado após quarto lote |
|---|---|---|
| Respawn, carros e moto | 01, 07, 08, 10, 11, 24, 26, 34 | Lifecycle, corpo, piloto, portas, prompt, saúde na morte e minimapa testados. Impulso residual e retomada de IA no roubo corrigidos; queda original abaixo do mapa (07) continua aberta |
| Quedas/congelamentos/carregamento | 02–06 | Construção da loja otimizada com equivalência de geometria/materiais; texturas da primeira carcaça preparadas no carregamento. Diagnóstico da loja: 186→151 ms na entrada e 148→115 ms na reentrada. Hitch e certificação de FPS continuam abertos; comparação isolada pendente |
| Piso, atores, NPCs e serviço | 09, 12, 13, 22, 27 | Corpo após veículos, mira e balcão corrigidos/testados; reações do banco, porto, Vance e atendimento implementadas com recuo físico/retorno e proteção da garagem |
| Transições/chuva/luz/HUD contextual | 14–19, 23, 28, 31 | Câmera, chuva, HUD, prompt da morte e ruído de autosave corrigidos/testados; nove acessos automáticos. Vazio, luz completa e outros 23 acessos permanecem abertos |
| Arte, materiais e legibilidade do mundo | 20, 21, 25, 35, 36 | Cifrão do banco, remoção do letreiro do Chefe e fachada Union tratados. Arte, materiais, modelo de Vance e iluminação noturna ainda sem aprovação integral |
| Prévia da pistola | 29 | Duas barras duplicavam o guarda-mato nativo; removidas e confirmadas em fotos reais de catálogo/bancada |
| Catálogo/personalização | 30, 32, 33 | Entrega do Claude integrada; bancada ampliada passou 59 verificações funcionais + 9 PNGs em duas resoluções com controle. Scroll do foco, montagem da M4 e boca/clarão de acessórios corrigidos. Revisão de todas as combinações visuais não está concluída |

## Validação e condição de entrega

- Regressões funcionais específicas e integração dos fluxos reais; não rodar suítes completas repetidamente.
- Saves isolados, sem modificar save pessoal. Não encerrar processos Godot de terceiros.
- Capturas reais antes/depois para alterações visuais/interiores; colisão e oclusão verificadas separadamente.
- Performance comparável na cena real: mesma máquina, renderer, resolução, câmera, rota, população e clima; janela de pelo menos 30 segundos por cenário crítico. Meta provisória 60 FPS / 16,67 ms. Aumento maior que 5% em p95/p99 exige confirmação, não aprovação automática.
- Se outro runtime impedir exclusividade, registrar performance **pendente**, prosseguir nas correções funcionais possíveis e não usar benchmark contaminado como comprovação.
- Atualizar este plano e o checklist de interiores com resultados reais. Um item implementado mas sem comprovação obrigatória permanece pendente de validação.

## Registro de execução

- Início: 59 arquivos rastreados já modificados, além de arquivos não rastreados de outras frentes. Nenhuma limpeza, reset ou restauração executada.
- Três agentes acionados; diagnóstico em paralelo, runtime temporariamente preservado enquanto se tenta obter baseline.
- Dois processos Godot pré-existentes identificados (76560 e 86396), preservados. Não houve janela exclusiva para benchmark comparável; a validação visual foi registrada separadamente.

### Primeiro lote implementado

- A limpeza do porto removia veículos ainda classificados como trânsito ambiente, inclusive a moto ocupada. O roubo agora retira essa propriedade e a limpeza protege o veículo selecionado. A remoção limpa a referência usada por direção/save/respawn; revisão adicional verifica que um veículo definitivamente removido não reapareça pelo save.
- A apresentação de embarque acumulava o deslocamento vertical temporário do corpo. O encerramento restaura o deslocamento original. A parada para embarcar também zera a velocidade horizontal residual, além do velocímetro; o voo completo observado no vídeo ainda não foi reproduzido e não está encerrado.
- O piloto embutido nas três motos é ocultado ao tomar o veículo, e Dante passa a ocupar o assento. Portas substitutas só aparecem enquanto abertas; as portas reais do cupê permanecem no sistema existente. Cancelar roubo em movimento invalida sua continuação assíncrona.
- Atendimento das duas Ammu-Nation deslocado para o lado acessível do balcão. Guardas usam pose, mãos, cano e muzzle do rig nativo. Não se elevou o piso: suporte físico isolado passou, e o defeito corporal tinha outra causa.
- Zoom de saída da Ammu-Nation acompanha o fluxo já existente de entrada. O primeiro quadro do zoom é sincronizado; banco e demais locais continuam no lote de acessos.
- Clima/luz atualizados na mesma transição da sala; partículas vivas de chuva/neve/granizo ficam invisíveis sob cobertura. Saída e resgate sincronizam a câmera antes de devolver o quadro. Morte/prisão eliminam o prompt de interação.
- Restrições de armas na garagem preservadas. Sem alteração de dano/morte de Maciota e mecânico, nem edição de `Actor.gd`, `CameraRig.gd`, dispatch ou fachadas por esta frente.
- O controle renderizado atrás do balcão encontrou um efeito de silhueta atravessando o tampo; na moto, o mesmo efeito causava mancha sobre o piloto. Desativá-lo temporariamente no fixture eliminou os dois resíduos, confirmando a causa. O ajuste de escopo preserva sua utilidade exterior sem reaplicar esse efeito sobre móveis internos.

Validação funcional final: **138 verificações passaram** — 51 de veículos, 39 de interiores, 31 de integração e 17 de escopo/atualização da silhueta. Incluem não restauração indevida de veículo removido, preservação de outro snapshot, teste do zoom real, HUD/arma no primeiro quadro da garagem e profundidade interior sem efeito de raio X. Evidências e ressalvas no [relatório do primeiro lote](video-review-20260924-first-batch.md). Performance continua **pendente**, conforme [protocolo e limitações](../evidence/video-review-20260924/performance-status.md).

### Próximos lotes ainda abertos

1. Completar cobertura de colisão/oclusão dos interiores e certificar performance com comparação isolada. Oclusão específica do balcão e silhueta da moto já passaram na confirmação renderizada. Reproduzir especificamente carro saindo do mapa e travamentos na rota da moto/porto/explosões.
2. Demais entradas por proximidade/zoom: banco, Maciota e Chefe na segunda fase; Union, conveniência e hospital na terceira. Há nove acessos automáticos; os outros 23 acessos físicos/21 interiores precisam de avaliação própria, especialmente bombeiros, navio, alçapão e caverna.
3. Atividades e revisão do conjunto do porto. Portaria, persistência da visita pelo navio, sinais e três famílias de armamento policial foram testados na segunda fase; trabalhadores/atendentes reagindo a tiros/fogo e retomando serviço foram testados na terceira.
4. Contraste/materiais/void, iluminação noturna, navegação ampla e geometria da prévia da pistola. Minimapa no embarque, ruído de autosave e saúde da morte foram tratados na terceira fase. Interface inicial do Claude passou integração e quatro telas; ampliações posteriores e outras resoluções/controle seguem com validação própria pendente.

Não foi declarado que os 36 achados estão resolvidos. Este lote inicia o plano com correções das cadeias mais graves e mantém requisitos sem comprovação explicitamente abertos.

## Segunda fase — execução autorizada

O usuário enviou o prompt ao Claude e autorizou continuar com três agentes. Catálogo e bancada permanecem reservados ao Claude, sem edição por esta equipe.

| Frente | Escopo deste lote | Responsável |
|---|---|---|
| Acessos | Banco, Maciota e Garagem do Chefe por aproximação/travessia e zoom; preservar horários e os três acessos automáticos existentes | `revisao_visual` |
| Porto e sinalização | Corrigir conversa/autorização na portaria existente; retirar letreiro do Chefe e usar símbolo de cifrão no banco | `revisao_movimento` |
| Polícia | Preservar armamento da equipe despachada: patrulha com pistola, resposta especializada com armas progressivas | `performance_execucao` |
| Integração | FullSession, áudio pontual de disparos policiais, capturas antes/depois e documentação | Agente principal |

Diagnóstico inicial: a portaria emitia uma ação sem consumidor no fluxo normal; o desembarque policial recalculava a categoria pelas estrelas atuais em vez de conservar a equipe enviada. Os acessos especiais de navio, alçapão e caverna não serão migrados cegamente. Os dois processos Godot do usuário seguem abertos; performance comparável continua pendente. Evidências desta fase em `evidence/video-review-phase2-20260924/`.

### Resultado da segunda fase

Três acessos implementados, com porta física no banco, zoom/retorno e cancelamentos; portaria e autorização da visita ao navio corrigidas; cifrão e remoção do letreiro aplicados; polícia comum com pistola, interceptor com SMG e equipes táticas com M4A1, preservando o armamento da equipe enviada.

Passaram 76 verificações funcionais de acesso (mais 16 capturas), 52 de porto e 93 de polícia. Integração de estabelecimentos: 77; regressões de sessão: 31; garagem: 47 + 26 + 11. Resultados, fotos, avisos de retenção ao encerrar e integração com o Claude estão no [relatório do segundo lote](video-review-20260924-second-batch.md). Performance e aprovação integral dos interiores continuam pendentes; não há declaração de que os 36 achados foram resolvidos.

## Terceira fase — execução autorizada

O usuário pediu a próxima leva com três agentes e forneceu o relatório inicial do Claude. Esse relatório é evidência de sua frente, não uma instrução para dispensar validações da integração atual.

| Frente | Escopo finito | Responsável |
|---|---|---|
| Veículos | Reproduzir o deslocamento/queda após roubo, medir altura e deslocamento no fluxo real e corrigir apenas causa demonstrada | `performance_execucao` |
| Reações | Trabalhadores do porto e atendentes sob tiros/fogo; movimento com colisão e recuperação do posto, protegidos excluídos | `revisao_movimento` |
| Acessos | Union, conveniência e Bay Medical: três novos acessos com portas físicas, zoom e retorno | `revisao_visual` |
| Integração e HUD | Minimapa durante embarque, sucesso silencioso de autosave, saúde coerente na morte por queda, hooks de NPC e sinais das fachadas alteradas | Agente principal |

Bombeiros requer recorte maior da fachada e não integra este lote. Sem alteração do conteúdo de armas reservado ao Claude. Capturas renderizadas das frentes são sequenciais; editor/jogo do usuário preservados e performance comparável continua pendente enquanto não houver janela exclusiva.

### Resultado da terceira fase

Implementados os três novos acessos; reação física e retomada de trabalhadores/atendentes, incluindo Vance; eliminação do impulso residual de batida durante embarque e da retomada indevida de trânsito no roubo. Minimapa permanece durante a animação; autosave não apaga mensagens funcionais; saúde, colisão e física ficam coerentes na morte por queda ou durante embarque. Foco e conexão de serviço na reentrada receberam correções após falhas observadas.

Veículos: 78 verificações; acessos: 99 funcionais + 18 PNGs; reações: 60 no cenário principal, 5 de escopo e 28 na confirmação dirigida, com sobreposição. HUD: 33 funcionais + 4 PNGs e 10 verificações dirigidas da morte durante embarque. Integração: estabelecimentos 77, sessão 31; garagem 26 + 11. [Relatório do terceiro lote](video-review-20260924-third-batch.md) reúne evidências, diagnósticos e ressalvas.

Total atual: 9 acessos automáticos/9 interiores, restando 23 acessos/21 interiores. Zero novas certificações integrais. Queda original do carro e performance seguem abertas; não há declaração de que os 36 achados foram resolvidos.

## Quarta fase — execução autorizada

O usuário autorizou avançar com três agentes, priorizando queda do carro e travamentos. Divisão: `performance_execucao` reproduz a sequência banco → morte/resgate → cupê original junto ao Maciota; `revisao_visual` instrumenta primeira entrada real na Ammu-Nation e comparação de frame time; `revisao_movimento` verifica utilidade/fluxos de carga do porto. Coordenador integra e verifica as pendências de combate/bancada relatadas pelo Claude.

A silhueta do veículo que cai no vídeo sugere um cupê distinto do sedan usado entre Ammu-Nation e banco; não há telemetria para confirmar seu ID/arquetipo. A investigação acompanha essa hipótese durante o afastamento e retorno do jogador, sem considerar os reparos anteriores como prova da causa dessa queda. O vídeo começa em CONTINUAR; o estado exato daquele save não foi recuperado.

A medição exige liberar a partida preexistente PID 86396; autorização para encerrar somente essa partida foi solicitada, mantendo o editor PID 76560. Enquanto a resposta não chega, inspeção e provas funcionais independentes continuam. Nenhuma medição contaminada será apresentada como aprovação de FPS.

### Resultado da quarta fase

Porto recebeu três fretes limitados, R$300 por carga, com aceite, percurso físico, desembarque e devolução do caminhão. Corrigidos restauração do motorista durante a inicialização, preservação do carro anterior durante streaming e salvamento da última posição apoiada. A confirmação dirigida a partir do checkpoint real do depósito passou 42 checks e gerou três fotos; carro anterior 12, piso 9 e garagens 26 passaram. A queda original de 02:21 continua sem reprodução comprovada.

Na Ammu-Nation, agrupamento de malhas e caches reduziram trabalho de construção, com 144 + 29 verificações de equivalência e isolamento. O diagnóstico renderizado registrou 151 ms na primeira entrada e 115 ms na reentrada: melhoria parcial, ainda com travamentos e sem aprovação de FPS. A primeira explosão passou a preparar texturas na carga inicial; cerca de 4,39 ms foram transferidos de etapa, não eliminados.

Bancada final: 59 verificações funcionais + 9 fotos, em duas resoluções e com controle. Corrigidos scroll do foco, guarda-mato duplicado da pistola, encaixe da M4 e detalhe flutuante da SMG. Boca, clarão e luz dos acessórios: 89 verificações. Fixture antiga de combate foi corrigida para aguardar contato real da animação; 210/210, sem alterar dano para satisfazer o teste.

[Relatório do quarto lote](video-review-20260924-fourth-batch.md) contém imagens, evidências e limitações. Permanecem queda original, travamentos/FPS, 23 acessos/21 interiores, cobertura integral de colisão/oclusão e revisão artística ampla. Nenhuma nova certificação integral e nenhuma afirmação de que os 36 achados foram encerrados.

## Quinta fase — execução objetiva em 25/09

Usuário limitou a equipe a um auxiliar e pediu somente checagens essenciais, ficando com a validação jogando. Implementados acesso dos bombeiros, proteção física do carro estacionado durante streaming e redistribuição das luzes da garagem do Chefe. Smoke do carro 10/10, bombeiros 14/14, parse da garagem aprovado. Sem nova suíte extensa ou benchmark. [Relatório curto](video-review-20260925-fifth-batch.md).

Total atualizado: **10 acessos automáticos/10 interiores; restam 22 acessos/20 interiores**. Queda original, custo restante das explosões e revisão visual/física integral continuam abertos. Ammu-Nation permanece reservada ao Claude conforme o [prompt de 25/09](claude-ammunation-performance-20260925-prompt.md).

## Sexta fase — conclusão da implementação dos acessos

Implementados os 22 acessos restantes, total **32 acessos físicos automáticos / 30 interiores existentes**. Inclui portas reais por família, fachadas ausentes do abrigo, retorno pela origem e tratamento próprio para esgoto/navio/caverna. Proteção de streaming estendida à suspensão de carros antes de retirar seu piso. Explosões tiveram sons preparados na carga e recursos de fogo compartilhados; primeira detonação observada em CPU caiu de 21,471 para 6,524 ms, sem declaração de FPS.

Somente checagens essenciais, conforme pedido: seis famílias e aliases cobertos; repetição pontual da loja 10/10; três acessos especiais, fogo e suspensão/retomada do carro 20/20. [Relatório da sexta leva](video-review-20260925-sixth-batch.md).

**Implementação dos acessos encerrada; aguardando teste do usuário.** Permanecem a reprodução da queda original, revisão artística ampla, circulação/colisão/oclusão completas e avaliação renderizada de FPS, inclusive moto/porto. Ammu-Nation continua reservada ao Claude. Não há declaração de encerramento dos 36 achados originais nem novas certificações integrais.
