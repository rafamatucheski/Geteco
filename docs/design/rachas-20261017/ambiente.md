# Rachas — encontro, população, fila e continuidade visual

Data: 17/10/2026. Eixo de ambiente da auditoria Product Design, coordenada com três agentes. Este documento registra diagnóstico e proposta; não representa implementação nem aprovação do jogo.

## Escopo e método

Leitura de AGENTS.md, fontes atuais, testes existentes e evidência histórica. Skills consultadas: Product Design/index, testes-com-criterio, performance-do-jogo e guardiao-do-jogo. Nenhum código, asset, save ou processo do usuário foi alterado por este agente. A execução atual descrita abaixo foi realizada pelo coordenador; o log foi lido para incorporar seus resultados. A interpretação do código não substitui observação da experiência renderizada.

## Conclusão de produto

O encontro tem uma quantidade considerável de elementos autorados, mas essa quantidade não está convertida em atividade percebida, identidade sonora ou variedade. Corrigir a fila e dar continuidade à apresentação da corrida precede acrescentar população. O objetivo deve ser um lugar onde preparar, observar, disputar e retornar tenham significado, mantendo a corrida interessante para quem quer jogar somente esse modo.

## Evidência atual: fila reprovada na execução do coordenador

Execução: `tests/test_drag_open_meet.gd --no-save --night`, na Main renderizada, Godot **4.7.2 .NET**, Vulkan/Forward Mobile, NVIDIA GeForce RTX 4060 Laptop GPU. Fonte: [log da execução](../../../output/rachas-design-audit-20261017.log); saída de evidências: [open-drag-34456-7486015](../../../evidence/open-drag-34456-7486015/).

O teste passou na inicialização da Main, ativação das rotas nativas .NET, admissão do carro do jogador, embarque comum e restauração do controle. Falhou ao esperar **dois competidores autônomos e um par físico aguardando**. Resultado final: seis verificações executadas, cinco aprovadas e uma falha. As etapas posteriores do teste não foram alcançadas.

Os seis carros permaneceram em `routing=arrival`, `waypoint=5`, velocidade zero:

| Visitante | x | y | z |
|---|---:|---:|---:|
| Bruno | -1041,901 | 0,000942 | -1279,958 |
| Célia | -1048,834 | 0,000942 | -1279,951 |
| Ivo | -1055,698 | 0,000942 | -1279,948 |
| Mara | -1062,632 | 0,000942 | -1279,948 |
| Denis | -1069,505 | 0,000942 | -1279,948 |
| Luna | -1076,426 | 0,000942 | -1279,948 |

**Fato:** a chegada travou antes de formar a bateria nesse cenário. **Hipótese a investigar:** o primeiro carro parou por suporte, colisão ou geometria do acesso e os seguintes respeitaram a distância de segurança; o log não identifica o obstáculo. Inspecionar o contato físico do líder e o segmento do waypoint 5 deve preceder nova execução equivalente.

Este resultado **não demonstra** que o estado `phase=blocked` descrito adiante causou a falha. A falha observada é na chegada; o outro problema é uma lacuna independente de recuperação depois do alinhamento ou durante a prova.

## Achados técnicos e impacto na experiência

### 1. Fila: recuperação incompleta e estados pouco claros

**Fato de código:** em [DragOpenMeet.gd](../../../activities/desert_drag/DragOpenMeet.gd), linhas 141–147, um alinhamento ou corrida com mais de 45 segundos define `phase = "blocked"`, cancela a inscrição do jogador e zera os movimentos, mas mantém `heat` ocupada. A máquina de estados não possui um ramo que recupere `blocked` quando a obstrução desaparece. `clear_visit` limpa a visita ao sair do escopo, morrer ou satisfazer outras condições; remover o obstáculo local não basta.

**Fato de código:** a admissão em `_admit`, linha 161, exige que o primeiro ponto esteja fora da câmera e a pelo menos 90 m. Isso evita nascimento visível, mas torna a chegada dependente do enquadramento. O comportamento real ao observar o acesso precisa ser exercitado; esta condição isolada não comprova um defeito.

**Fato de código:** `_dispatch`, linhas 214–247, registra motivos como espera do adversário e alinhamento em `last_admission_reason`; o HUD de `_refresh`, linha 405, continua usando mensagens genéricas. Há cancelamentos após 20 ou 60 segundos em alguns ramos, enquanto uma inscrição com bateria à frente depende da progressão física dessa bateria. Sair do carro cancela a inscrição imediatamente.

**Proposta:** tratar inscrição, chamada, alinhamento, obstrução e recuperação como estados explícitos com responsável único. Exibir o motivo efetivo e uma ação útil quando há bloqueio. Preservar o número da inscrição durante uma recuperação local. Reposicionar ou remover veículos só com procedimento físico/visual definido, evitando desaparecimento na frente do jogador. O comportamento de sair do carro pode ser revisto como decisão de produto, com período de chamada e cancelamento compreensível.

### 2. NPCs: a migração visual é contornada pelos atores do encontro

**Fato de código:** [Actor.gd](../../../scripts/Actor.gd), linhas 199–201, aplica `BODY_CATALOG.apply` ao pedestre genérico. [DragMeetGuest.gd](../../../runtime/desert/drag_meet/DragMeetGuest.gd), linhas 18–24, chama `super._ready()`, remove o modelo recém-criado e instancia outro `CivilianModel` sem o catálogo. Os membros em [DragMeetMember.gd](../../../runtime/desert/drag_meet/DragMeetMember.gd), linha 23, e os contatos em [DesertCharacter.gd](../../../runtime/desert/DesertCharacter.gd), linha 44, também criam o corpo procedural diretamente. Jessica tem um caminho próprio e não deve ser generalizada para os demais.

**Cuidado de implementação:** [CivilianBodyCatalog.gd](../../../assets/civilians/CivilianBodyCatalog.gd), linhas 42–45, recusa guarda-roupa fixo com chaves além de `female`. Acrescentar a chamada depois de definir as roupas atuais não resolveria a migração. Escolher explicitamente um corpo compatível por identidade/função antes de entrar na árvore, preservando sexo, constituição, acessórios e leitura dos líderes. Consultar [RoleBodyCatalog.gd](../../../assets/civilians/RoleBodyCatalog.gd) e [RigBodySwap.gd](../../../assets/civilians/RigBodySwap.gd) antes de criar outra infraestrutura.

**Proposta:** modernizar os corpos e atribuir ações legíveis: conferir roda, conversar em dupla, acompanhar a largada, encerrar preparação e celebrar chegada. Reações devem responder à bateria real, com interrupção por ameaça, dano e transição. Evitar produzir um modelo caro para removê-lo logo em seguida.

### 3. Quantidade não significa variedade nem lugar vivo

**Fato de código:** [DesertDragMeet.gd](../../../world/desert/drag_meet/DesertDragMeet.gd), `car_spots`, autoria 52 carros no paddock: oito pontos específicos e 44 displays. `strip_records` acrescenta 12 carros e 24 espectadores distribuídos em seis grupos ao longo da pista. [DragMeetLife.gd](../../../runtime/desert/drag_meet/DragMeetLife.gd) prevê seis membros e 28 convidados, além dos contatos mantidos por outros controladores. Esses números são capacidade autorada, não contagem simultânea comprovada em câmera.

Os 44 displays ciclam sete IDs que representam quatro bases: Faísca, Coyote, Siroco e Mirage, com três edições. A fila de [DragOpenRoster.gd](../../../activities/desert_drag/DragOpenRoster.gd) tem seis pessoas e cinco IDs de veículo:

| Visitante | Carro | Base mecânica |
|---|---|---|
| Bruno | Faísca GT | Hatch FWD |
| Célia | Siroco T | Sedã AWD |
| Ivo | Coyote 440 | Muscle RWD |
| Mara | Mirage R | Cupê RWD |
| Denis | Faísca RX | Mesma mecânica-base do Faísca GT |
| Luna | Siroco T | Mesmo carro-base de Célia |

[DesertCarCatalog.gd](../../../gameplay/desert_cars/DesertCarCatalog.gd), linhas 16–21, declara que as edições compartilham mecânica e dimensões de colisão com os doadores. [RedesignedFleet.gd](../../../runtime/RedesignedFleet.gd) já inclui os IDs do deserto: recriar os mesmos carros por `FleetCatalog` não acrescenta variedade.

**Proposta:** selecionar uma variedade maior da frota existente, sem aumentar inicialmente o total. Organizar grupos por escola de preparação e rotacionar parte dos visitantes por sessão. Diferenciar silhueta, rodas, preparação, áudio e comportamento, mantendo identidades estáveis. Um visitante inesperado ou um carro simples muito bem acertado tem mais valor do que outra fila do mesmo modelo recolorido.

### 4. Som genérico e desacoplado dos acontecimentos

**Fato de código:** [DragMeetAmbience.gd](../../../runtime/desert/drag_meet/DragMeetAmbience.gd), linhas 16–23, usa loops de café, `porto_groove`, motores e oficina. O orçamento é de dois loops de multidão, uma música, dois motores e uma oficina. A animação `talk` dos convidados não representa fala autorada. Existem diálogos dos contatos em [DesertCampaign.gd](../../../runtime/desert/DesertCampaign.gd), a partir da linha 141; portanto não se deve afirmar ausência absoluta de diálogo.

Durante a corrida, `DragMeetLife` marca o ambiente como suprimido e o mixer reduz 20 dB. Ao ultrapassar 112 m do centro, elimina toda a instância de ambiência. Pela geometria atual, o carro na pista sai desse raio aproximadamente 31 m depois da largada. Isso explica uma descontinuidade de projeto entre som da concentração e som da prova; a intensidade percebida exige audição. A torcida lateral não fornece uma identidade sonora própria nesta implementação.

**Proposta:** criar uma identidade musical do encontro, chamadas de organizador e reações curtas contextualizadas: preparação, inscrição chamada, largada, vantagem apertada e chegada. Reutilizar um mixer limitado com prioridade, distância e cooldown. Música baixa durante a chamada, não desaparece por um corte global prematuro. O motor do jogador deve ser a referência sonora da corrida; o rival informa distância e pressão. Esse ajuste de motor deve ser integrado ao eixo de pilotagem/áudio.

### 5. Streaming e horizonte: a câmera vê além do cenário detalhado residente

**Fato de código:** [DesertRegion.gd](../../../world/desert/DesertRegion.gd) usa células de 96 m, inicia 3×3 células ao redor do foco e limita retenção a duas células. Cenário, carros estáticos e espectadores da pista pertencem a esses chunks. `GPU_RELEASE.retire` oculta o conteúdo removido antes de liberar seus recursos gradualmente. [DesertDrag.gd](../../../activities/desert_drag/DesertDrag.gd), linha 264, configura a câmera lateral com alcance de 2.200 m. [DesertHorizon.gd](../../../world/desert/DesertHorizon.gd) mantém terreno/relevo distante persistente.

**Hipótese:** parte do carregamento/descarregamento relatado pelo usuário ocorre em objetos de média distância visíveis pela câmera lateral, fora do conjunto de chunks carregados. O alcance da câmera e a política de residência tornam isso plausível, mas é necessário identificar os objetos e frames na versão atual. Não atribuir automaticamente ao horizonte persistente todos os desaparecimentos.

**Proposta:** compor três camadas — pista e barreiras próximas, estruturas/grupos de média distância e relevo distante — com uma silhueta reconhecível. Manter a representação visual estática essencial do corredor durante a prova; continuar usando física e NPCs conforme necessidade. Validar o custo antes de adotar essa residência. Não aumentar globalmente o raio do deserto nem cobrir o problema com neblina pesada. A geometria da pista, retorno, acessos e segurança física deve permanecer coerente.

### 6. Primeira impressão e distribuição espacial

**Fato de código:** em [DragMeetLife.gd](../../../runtime/desert/drag_meet/DragMeetLife.gd), admite-se um residente por ciclo de 0,18 s, somente após `is_streaming_idle()` de toda a região. Trinta e quatro residentes exigem no mínimo cerca de 6,1 s depois de cumprido esse requisito; a distância de cada âncora pode reduzir o conjunto admitido. O raio inicial é 88 m, com saída em 112 m.

**Hipótese:** numa primeira visita ou ao movimentar rapidamente o foco, a espera pelo streaming inteiro agrava a percepção de lugar vazio. Não foi medida a latência de admissão neste trabalho.

**Proposta:** garantir primeiro os papéis que comunicam atividade no acesso e perto da inscrição, admitindo o resto conforme o orçamento. Pré-aquecer somente os recursos do encontro relevantes para a aproximação, com suporte e colisão conferidos. Não admitir personagens sobre móveis ou carros para preencher uma contagem.

## Direção proposta para o encontro

O encontro deve formar um ciclo espacial legível: **chegar → preparar → observar/ser chamado → disputar → retornar e ser reconhecido**. Cinco focos próximos ajudam a dar sentido ao cenário:

1. Entrada e inscrição junto a um organizador reconhecível, com fila física e número funcional.
2. Preparação em torno de grupos com escolas distintas de carro, com ferramentas e ações reais.
3. Bateria que se pode assistir antes de participar; largada e retorno alimentam o ritmo do lugar.
4. Torcida distribuída onde o jogador percebe sua reação, mantendo corredores seguros.
5. Retorno ao box com comentário do rival, comparação de desempenho e acesso às peças/desafios definidos no plano de progressão.

Não se propõe adicionar placas decorativas, slogans ou explicações sobre o cenário. O usuário deve entender a atividade por pessoas, posição dos carros, som e ferramentas. Textos funcionais de inscrição, chamada, objetivos e diálogos continuam necessários.

Uma pequena rotação de visitantes e desafios por visita pode produzir novidade sem dependência do relógio real. A ideia de peças liberadas deve ser conectada a domínio e especialização, conforme o eixo de progressão, preservando acesso prazeroso à corrida livre e sem transformar o encontro numa obrigação repetitiva da campanha.

## Custos e limites de implementação

- Usar inicialmente os orçamentos de população existentes. Melhorar composição, diversidade e relevância antes de aumentar quantidade.
- Direção de evento por sinais de inscrição/largada/chegada/retorno, com atualizações espaçadas para escolhas sociais; evitar um novo loop individual complexo em todo figurante.
- Modelos novos exigem avaliação de materiais, ossos, animação, carregamento e descarregamento. Reutilização de GLBs e texturas ajuda, mas não comprova baixo custo.
- Carros expostos devem continuar sem controlador completo, luzes ou áudio individual desnecessário. Interação, roubo ou dano devem materializar o veículo conforme o contrato atual.
- Mixer com vozes limitadas e prioridade; não reproduzir uma fala por NPC simultaneamente.
- Residência visual do corredor deve ser específica da prova e ter limpeza/restauração. Comparar custo de draw calls, malhas e memória; não carregar a região inteira.
- Preservar o agrupamento estático já usado pelo projeto. Não alterar globalmente streaming, iluminação ou modelos fora do escopo dos rachas.
- Oficina acessível, mobiliário ou acesso alterados exigem `padrao-interiores`, contrato de colisão/profundidade e validações pertinentes. Luzes/sombras alteradas exigem `validar-iluminacao` e evidência temporal.

## Ordem de execução sugerida

1. Diagnosticar o contato físico que bloqueou a chegada no waypoint 5 e corrigir a causa local; validar o caminho produtivo.
2. Resolver recuperação de `blocked`, clareza da inscrição/chamada e retorno ao controle.
3. Dar continuidade ao corredor visual e equilibrar áudio da corrida com o eixo de pilotagem.
4. Migrar os corpos, selecionar variedade de frota e reorganizar os focos de atividade.
5. Implementar reações de evento, chamadas e identidade musical.
6. Integrar rotação de visitantes, desafios e reconhecimento por peças/desempenho.

## Validação necessária e cobertura

### Funcional

Reutilizar [test_drag_open_meet.gd](../../../tests/test_drag_open_meet.gd) depois de entender a falha atual. Cobrir chegada real, par aguardando, inscrição, chamada, corrida, retorno e cancelamento. Acrescentar proteção durável para a regressão de obstrução/recuperação quando sua causa e contrato estiverem definidos.

Casos dirigidos: entrada observando o ponto de admissão; obstruir e desobstruir; cancelar e reinscrever; sair e voltar; pausa; morte/resgate ou prisão pertinentes; corrida em sequência. Verificar controle, câmera, áudio, fila, população residual e suporte físico. O teste atual usa checkpoint e não prova o acesso inteiro desde outra região.

### Apresentação

Captura temporal na Main da primeira aproximação, espera, corrida de 800 m e retorno, com dia/noite conforme os cenários alterados. Identificar os objetos que entram/saem e os limites de residência. Inspecionar colisão e oclusão separadamente para pessoas, carros e ferramentas. Revisar mudanças de corpo/gestos em movimento; uma foto não aprova animação.

Audição de aproximação, inscrição, espera, largada, trocas, rival próximo/distante, chegada e retorno. Estado `playing` ou volume configurado não prova equilíbrio percebido. Garantir prioridade do carro do jogador sem apagar indevidamente o mundo.

### Performance

Antes/depois na mesma máquina, Godot 4.7.2 .NET, renderer, resolução, qualidade, câmera, save, horário e carga. Registrar VSync e limitador. Pelo menos 30 s por cenário crítico: encontro estável e corrida/retorno com streaming; medir primeira visita e transições separadamente. Coletar FPS por frames/tempo, p50/p95/p99, máximo e frames acima de 33,3/66,7 ms. Não medir com gravação de imagem por frame nem com outros testes renderizados simultâneos.

O objetivo provisório, se não houver outro acordo, é 60 FPS/16,67 ms no hardware de referência; isso precisa ser tratado como alvo, não aprovação presumida. Comparação sem baseline ou com edição concorrente em dependências é inconclusiva. Melhorar uma base ruim não basta para aprovar a experiência.

## Evidência anterior e limites

[Revisão de 7/10](../../reviews/drag-race-redesign-20261007.md) documenta implementações e testes, mas declara performance inconclusiva e ausência de validação auditiva humana. Não deve aprovar automaticamente o estado atual.

A captura histórica [ambient.png](../../../evidence/open-drag-116260-6618267/ambient.png), inspecionada por este agente, mostra o grid isolado em grande espaço vazio. Serve de referência da composição anterior; não comprova a apresentação atual após alterações da frota ou cenário.

Estado desta entrega: **diagnóstico documentado**; fila atual **reprovada no cenário executado pelo coordenador**; causa da obstrução de chegada **não determinada**; defeito de recuperação de `blocked` **identificado por leitura**; apresentação atual, qualidade auditiva e desempenho **não aprovados por este documento**. Nenhuma correção de runtime foi realizada neste eixo.
