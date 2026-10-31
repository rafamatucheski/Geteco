# Logs por sessão

## Diagnóstico detalhado (schema 4)

O schema 4 acrescenta histórico por frame antes/depois dos picos, snapshots de GC,
contexto do jogador, limites observados de callbacks e detalhes rápidos de descarte.
Veja [captura detalhada e leitura](session-log-detail.md). Os eventos abaixo continuam
disponíveis e leitores de schemas anteriores podem ignorar os novos campos.

Desde 21/10/2026, o padrão no Jogar.cmd e em novas exports release é essencial:
início/fim da sessão, mensagens, avisos, erros, exceções e heartbeat para detectar
bloqueios. Não coleta métricas periódicas, inventário, contexto ou histórico de frames.
`HARBOR_SESSION_PROFILE=1` ativa explicitamente o perfil descrito abaixo, incluindo
métricas C# e operações instrumentadas. `tools/launchers/JogarDiagnostico.cmd` ativa esse perfil e
o StallLog adicional; na release, use essas mesmas variáveis antes de abrir o executável.
`HARBOR_STALL_LOG=1` habilita o StallLog separadamente. `HARBOR_SESSION_LOG=0`
desliga o logger de sessão, mas não o log nativo do Godot nem o StallLog independente.

- `slow_operations`: até 16 maiores trechos de pelo menos 2 ms por intervalo,
  mesmo quando o quadro inteiro não chega a 33,3 ms. Preserva os detalhes
  fornecidos pelo produtor (por exemplo região, orçamento e tamanho da fila).
  `frame_spike` também inclui esses trechos: não contar as duas listas como
  operações diferentes. `system_metrics.slow_calls` conta todas as chamadas
  de pelo menos 2 ms, inclusive as que ficaram fora da lista detalhada.
- `operation_begin` / `operation_end`: ID correlacionável, sistema, operação,
  arquivo de instrumentação, detalhes, duração e estado de término. A duração
  é de parede e inclui filhos e esperas. `returned` significa que o trecho
  retornou, não que todas as suas interações foram aprovadas.
- `operation_timing`: duração de etapas já cronometradas de ProductionWorld,
  agora também em partidas normais: preparação de regiões, modelos, shaders,
  recursos de combate, grafos, montagem e trabalho de população. Não possui
  evento de início; para bloqueios, consultar operações ativas e a etapa da
  cortina de carregamento.
- A inicialização dos sistemas com `configure(self)` em FullSession registra
  separadamente sua criação e configuração (atividades, serviços, transporte,
  inventário, montanha, deserto etc.). A cortina registra cada mudança de etapa
  e o tempo até a próxima mudança/remoção, sem mudar o texto visível do jogo.
- `operations_pending`: operações abertas há pelo menos 5 s, observadas pelo
  escritor independente aproximadamente a cada segundo. `main_thread_unresponsive`
  inclui as operações ativas. Demora de parede também pode ser uma espera
  legítima; esses registros não diagnosticam deadlock automaticamente.
- `error.active_operations`: contexto concorrente ao erro, junto da origem,
  função, linha e backtraces originais. `source_key` agrupa arquivo/função;
  quando o motor informa uma origem interna, o script chamador pode estar
  somente na pilha. Estar ativo não prova que um sistema causou o erro.
- `session_end.unfinished_operations`: operações sem fechamento no término.
  Sem `session_end`, os pares começo/fim ainda permitem localizar conclusões
  ausentes, sem distinguir sozinhos crash, interrupção e perda de registros.

Há limite de 128 operações ativas. `operation_tracking_overflow` torna sua
extrapolação explícita. Os limites preexistentes de fila, rótulos e trechos
continuam válidos; não existe promessa de captura ilimitada. JSON inválido de
um produtor gera `telemetry_error`, sem encerrar a gravação dos próximos eventos.

Resumo ordenado por sistema, carregamentos mais demorados, frequência de
chamadas lentas, erros por origem e operações sem fechamento:

```powershell
./tools/Read-SessionLog.ps1 -SessionPath "C:\caminho\da\sessao" -SummaryOnly
```

Os totais de sistemas são inclusivos e não devem ser somados entre pais e
filhos. O log cobre instrumentação explícita: não mede automaticamente cada
função, todo recurso carregado pelo motor, código anterior ao autoload, nem
identifica falhas lógicas que não emitam erros. Operações de `configure` não
medem separadamente o preload do script ou callbacks posteriores. Novos sistemas
devem usar `StallWorkTrace` para custo recorrente e `SessionOperations` para
etapas de ciclo de vida. Não enviar conteúdo de saves ou objetos Godot nos detalhes.

## Tempos por sistema e quadros lentos

O perfil por sistema liga automaticamente com o log de sessão (desde o schema 2).
`system_metrics` contém, aproximadamente a cada segundo, chamadas, tempo total e
maior chamada por trecho instrumentado. `frame_spike` registra cada intervalo
entre callbacks acima de 33,3 ms: quadro, relógio monotônico em microssegundos,
pausa/foco, tempos dos trechos que terminaram nesse intervalo e os 16 trechos
mais lentos acima de 2 ms. Quando disponível, inclui nó e script de origem.
O resumo PowerShell mostra os sistemas de maior tempo medido em cada pico.

A cobertura reutiliza `StallWorkTrace`: personagens (física, movimento, pose e
steering), veículos, combate, despacho/trânsito, efeitos e etapas instrumentadas
de streaming, construção e descarte. Não é um profiler automático de todos os
scripts. O consumidor da sessão é independente do StallLog e dos benchmarks;
não consome nem limpa os eventos ou totais deles. Limites: 128 rótulos por
intervalo/janela e 16 trechos detalhados por intervalo; descartes são explícitos.

Os tempos são **inclusivos e aninhados**: não some `vehicle.physics` com
`vehicle.move_and_slide`, por exemplo. A lista mostra trabalho efetivamente
cronometrado, não afirma que o maior trecho é a causa exclusiva do pico.
`unattributed` significa que nenhum trecho instrumentado terminou no intervalo.
Tempos CPU/GPU de render são a última amostra disponível do viewport e podem
ter atraso; não são uma medição GPU sincronizada com o pico. Trabalho interno
do motor/driver, esperas, scripts sem instrumentação e callbacks que falharam
antes de fechar o cronômetro ainda podem exigir investigação. Nenhum tempo
residual é inventado ou atribuído automaticamente a um sistema.

Para comparar o custo do perfil, use `HARBOR_SESSION_PROFILE=0` antes de abrir o
jogo; o restante do log continua ativo. A validação jogável e o comparativo de
performance desta ampliação ficam com o usuário, conforme solicitado.

Cada processo de jogo cria automaticamente uma pasta em `user://session-logs`.
Neste Windows: `%APPDATA%\GetecoV2\session-logs`. Abra com `tools/launchers/AbrirLogs.cmd`.
O nome contém data/hora UTC, PID e identificador aleatório. F5, F6, Jogar.cmd
e executáveis exportados com .NET usam o mesmo autoload.

Para ler um resumo e os erros da última sessão no PowerShell:
`powershell -NoProfile -File tools/Read-SessionLog.ps1`.
Use `-SessionPath "caminho da pasta"` para escolher outra sessão.

`session-000.jsonl` é texto UTF-8: um objeto JSON por linha. Arquivos seguintes
são criados a cada aproximadamente 32 MiB. Nenhuma sessão antiga é apagada
automaticamente; arquive/remova logs antigos quando necessário.

- `session_start`: motor, versão, CPU, GPU, renderer, resolução, limite e VSync.
- `stdout` / `stderr`: mensagens emitidas pelo motor após registrar o autoload.
- `error`: tipo (0 erro, 1 aviso, 2 script, 3 shader), origem, linha, mensagem e
  pilhas fornecidas pelo motor. Inclui erros GDScript e exceções C# encaminhadas
  pelo Godot. Não captura variáveis locais nem o conteúdo dos saves.
- `metrics`: intervalos reais de **todos** os quadros da janela, FPS calculado por
  quadros/tempo, p50/p95/p99, máximo e contagens acima de 33,3/66,7 ms. A cada
  aproximadamente um segundo: CPU do processo (100% = toda a capacidade lógica
  da máquina), RAM residente, heap gerenciado, memória gráfica reportada pelo
  motor, tempos de processamento/física, nós, objetos, draw calls, cena,
  pausa/foco, resolução e configuração de FPS. CPU do processo não é CPU total
  de outros aplicativos; tempo entre quadros não equivale a tempo de GPU.
- `main_thread_unresponsive`: escritor permaneceu ativo, mas não recebeu quadro
  por pelo menos 5 segundos. Pode ser carregamento, pausa do debugger ou bloqueio;
  é evidência, não diagnóstico de causa.
- `session_end`: saída normal da árvore e quadros restantes. Ausência pode ser
  crash, encerramento forçado, disco sem espaço ou falha do próprio registro.

O escritor roda em thread separada e descarrega buffers aproximadamente a cada
segundo. Fila limitada a 8192 registros; saturação não bloqueia o jogo e registra
`records_dropped` com a contagem perdida. Falha de disco encerra o escritor e é
reportada no stderr e em `SessionDiagnostics.WriterFailure`. No encerramento há
até 2 segundos para drenar a fila. Crash/energia perdida pode perder os últimos
registros; não é uma gravação síncrona com garantia de persistência física.

## Continuar depois de um erro

`editor/run/main_run_args="--ignore-error-breaks"` usa a opção nativa do Godot
4.7.2: o Play não pausa automaticamente em erros de script recuperáveis. Erros
continuam visíveis e registrados. Breakpoints deliberados continuam funcionando.
Para depurar pausando no erro, remova essa opção nos argumentos de execução do
projeto. Se o editor já estava aberto, recarregue o projeto para aplicar a configuração.

O callback que falhou pode ser interrompido e a interação afetada pode ficar
incompleta. O logger não faz rollback de missões, transações ou saves nem captura
genericamente exceções fatais de threads .NET. Crash nativo, falta de memória,
loop infinito, falha de inicialização/compilação ou deadlock não se tornam
recuperáveis. Mensagens anteriores ao primeiro autoload e posteriores à sua
remoção dependem do log nativo `user://logs/godot.log`.

O StallLog existente permanece independente. Para uma comparação controlada,
`HARBOR_SESSION_LOG=0` desativa apenas o novo autoload. Não use isso em partidas
das quais deseja guardar diagnóstico. Não habilitamos captura global de
variáveis/pilhas em builds release: disponibilidade das pilhas depende do motor.

Referências: [Logger](https://docs.godotengine.org/en/stable/classes/class_logger.html)
e [argumentos de execução do projeto](https://docs.godotengine.org/en/4.6/classes/class_projectsettings.html#class-projectsettings-property-editor-run-main-run-args).

## Validação em 10/10/2026

Godot 4.7.2 .NET; `dotnet build Harbor.csproj --no-restore -v quiet`: sem erros
ou avisos. `tests/test_session_diagnostics.py` usa o motor real: erro de GDScript,
exceção em `_Process` C#, execução do callback seguinte, mensagem de outra thread,
pausa/retomada, conteúdo JSON, métricas, encerramento e sessões com nomes distintos.
Um editor isolado inicia Play com debugger conectado e confirma execução depois
de um erro de script. O editor e os saves do usuário são preservados.

Medição renderizada em Main, ponto inicial de Harbor, RTX 4060 Laptop,
Mobile/Vulkan, 1920×1080, VSync ligado, limite efetivo de 144 FPS. Aquecimento
de 10 s depois de 20 s de acomodação; amostra de 30 s. Referência provisória:
60 FPS / 16,67 ms; aumento de p95/p99 acima de 5% exigiria confirmação.

| Logger | FPS médio | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms | NPCs / carros ao fim |
|---|---:|---:|---:|---:|---:|---:|---:|
| Desligado | 80,60 | 10,912 | 28,407 | 49,572 | 233,684 | 72 / 4 | 24 / 47 |
| Ligado | 133,33 | 6,757 | 12,660 | 16,245 | 42,074 | 1 / 0 | 23 / 45 |

Evidências: `evidence/session-diagnostics-off-20261010.json` e
`evidence/session-diagnostics-on-20261010.json`, incluindo intervalos brutos.
Não houve piora observada nesta dupla, mas a população/tráfego variou. A diferença
de FPS não comprova ganho causado pelo logger; atribuição causal e aprovação
global de performance permanecem inconclusivas. Nenhum script/cena/configuração
do produto teve modificação em disco durante essas duas rodadas. Havia um editor
aberto e nenhum outro runtime Godot concorrente. Não certifica sessões longas,
todos os mapas, combate intenso ou outras máquinas.

Na rodada renderizada ligada: 73 janelas de métricas, início/fim preservados,
nenhum `telemetry_error` ou descarte de fila. O aviso de ausência de quadros no
carregamento foi registrado pelo escritor independente.

Tentativas descartadas: runner antigo exigia população que o diretor já havia
reduzido; adaptação inicial acessava jogador antes de criá-lo e exportador antigo
assumia uma estrutura de trânsito diferente. Esses runners foram corrigidos no
teste novo, sem alterar a população nem o código do jogo para obter aprovação.
Disco cheio, saturação extrema, rotação de 32 MiB e crash fatal não foram
provocados nesta validação. O mecanismo é observação, não recuperação de estado.


## Schema 5 — diagnóstico ampliado (12/10/2026)

As partidas seguintes usam o schema 5 automaticamente, no autoload C# existente.
Não é necessário ligar um modo especial. `summary.json` é atualizado pelo escritor
aproximadamente a cada 30 segundos e no encerramento, com início da sessão,
contagem de eventos, erros por origem, maiores incidentes e etapas demoradas.
O resumo usa histogramas de memória limitada: percentis são limites superiores
em passos de 0,1 ms; acima de 819,1 ms usa o máximo. Para percentis exatos dos
intervalos brutos, use o leitor Python. Não confunda o resumo parcial com uma
sessão encerrada: consulte `normal_end_seen`.

### Correlação e custo

- Registros do schema 5 usam envelope uniforme (`sequence`, `elapsed_ms`, `utc`,
  `data`), inclusive o watchdog. A sequência identifica registros e pode aparecer
  fora de ordem entre produtores concorrentes; não é prova de ordem de execução.
- `context_update` publica snapshots a cada aproximadamente 250 ms. Contém
  região/lugar, posição e saúde do jogador, carro/velocidade, clima/horário,
  prontidão da sessão, população, densidade, regiões residentes e filas de streaming.
  Os campos são uma lista explícita; não serializam o conteúdo do save.
- `runtime_state_changed` registra cena, pausa, foco, resolução, VSync e limite.
  `metrics.frame_context_ids` e `frame_state_ids` associam cada intervalo aos IDs,
  sem atribuir toda uma janela ao estado do seu último frame. O estado é observado
  no fim do intervalo; uma transição dentro dele não é medida automaticamente.
- `location_changed` registra mudança observada; não afirma que uma transição
  terminou corretamente. Snapshots e inventário têm timestamps para expor sua idade.
- Inventário incremental: classes e scripts presentes na árvore, entradas/saídas,
  luzes visíveis na árvore, luzes com sombras, áudio tocando e SubViewports com modo
  de atualização diferente de desativado. Não há varredura recursiva por frame.
  Visibilidade na árvore não equivale a influência na câmera; o modo de atualização
  não comprova que um SubViewport renderizou. Até 128 classes, 512 scripts e 512 nós
  dinâmicos rastreados; omissões são explícitas e contagens dinâmicas podem ser parciais.
- Contadores de custo: callbacks C# do diagnóstico, callbacks GDScript do perfil,
  callbacks do inventário, tempo do escritor, bytes escritos e pico de fila. São
  medidas separadas; não incluem toda a instrumentação dos produtores nem provam
  sozinhas o impacto no frame time.
- Monitores adicionais do motor: memória nativa e pico, recursos, nós órfãos,
  objetos/primitivas renderizados, memória de texturas/buffers, corpos ativos e
  pares de colisão em física 2D/3D, ilhas de física 3D, navegação e latência de
  saída de áudio. São as últimas amostras disponíveis; monitores não suportados
  podem retornar zero. Latência reportada não certifica qualidade audível.
- Descartes distinguem orçamento de payload, capacidade da fila, registro grande
  demais e escritor indisponível/fechado em `writer.dropped_by_reason`.

### Incidentes e etapas

`frame_spike.phases` fornece timestamps de callbacks no início/fim do processamento,
marcadores antes/depois de render e total dos intervalos de callbacks de física.
Com `valid=true`, a decomposição cobre o intervalo entre callbacks: início até
callback tardio; callback tardio até pré-render; bracket de render; pós-render
até o próximo callback. São durações de parede: física e trechos de trabalho
podem sobrepor esses brackets. Não são tempos exclusivos de CPU nem GPU.
`render_sample_age_ms` e `render_frame` identificam o marcador de coleta dos
monitores; a API GPU é assíncrona e continua sem atribuição exata a um pico.

`frame_spike.coverage` calcula a união dos trechos lentos retidos, recortados
para o intervalo. Pai e filho não são somados. É um limite inferior da cobertura,
pois não inclui chamadas rápidas ou detalhes descartados. `unobserved_ms` é o
complemento dessa cobertura, não um custo atribuído ao motor, GPU ou driver.

Operações têm ID, relógio do motor no início, frame e `parent_id` explícito.
`SessionOperations.attach`, `load_resource` e `instantiate` registram a operação
antes de executar e fecham depois, preservando etapas pendentes em falhas.
Foram aplicadas às fronteiras de montagem de regiões, criação dos sistemas da
inicialização e load/instantiate/add_child dos modelos de `NativePlace`.
`native_ready` cobre também adaptação, sólidos e recompensas existentes, sem
alterar a apresentação ou os contratos de gameplay desses lugares.
Scripts novos podem usar esses helpers; não existe interceptação universal de
cada `load`, função ou `_Ready` do motor.

Exceções .NET não tratadas e Tasks não observadas têm hooks de registro adicionais.
Eles não suprimem exceções, não marcam Tasks como observadas nem tornam crashes
recuperáveis. Um erro fatal ainda pode encerrar o processo antes de descarregar a fila.

### Limites e leitura

A fila continua limitada a 8192 registros. Payloads JSON do perfil têm limite de
2 Mi caracteres por registro e orçamento de 32 MiB de caracteres UTF-16 enfileirados;
ao saturar, descarta explicitamente em vez de bloquear o jogo. Esse orçamento
limita os payloads de perfil, não é um limite de toda a memória CLR do processo.
A rotação continua em aproximadamente 32 MiB por parte. Histórico: até 360 frames;
detalhes lentos: 16 por intervalo; resumo: 64 cenários, 12 incidentes/etapas,
128 tipos de evento e 256 origens de erro. `summary_omitted` informa excesso de
cenários/origens. O leitor exato não usa os histogramas do resumo.
Não se apagam sessões antigas automaticamente. Disco cheio e saída forçada
continuam sendo limitações; `WriterFailure`, descarte e ausência de fim as expõem.

```powershell
python tools/read_session_log.py "C:/caminho/da/sessao" --top 10
python tools/read_session_log.py "C:/caminho/da/sessao/session-000.jsonl" --json
python tools/read_session_log.py "C:/caminho/da/sessao" --output "C:/caminho/relatorio.json"
./tools/Measure-SessionDiagnostics.ps1
```

O leitor aceita schemas antigos, todas as partes rotacionadas, linhas truncadas,
pausas dentro de uma janela e os frames restantes no encerramento. O medidor usa
Main renderizada, 20 s de acomodação + 10 s de aquecimento + 30 s medidos por
variante, logger desligado/ligado em sequência, `--no-save`, população normal e
prefixo único. Detecta concorrência e alteração de fontes; não encerra processos
alheios nem aprova automaticamente uma comparação. O cenário estacionário não
certifica todos os mapas, acessos, combate ou sessões longas.

Validação funcional: build Godot 4.7.2 .NET, teste dedicado de detalhes/watchdog,
leitor com rotação/truncamento/schemas antigos e integração Main/NativePlace.
A integração registrou defeitos externos à telemetria em `CobraModel.gd:57` e o
aviso de streaming inicial ainda pendente; não foram ocultados nem corrigidos
por esta mudança. Performance só pode ser julgada com as rodadas renderizadas
isoladas; a execução funcional concorrente não serve de benchmark.


Evidências desta rodada:

- `tests/test_session_log_reader.py`: dois contratos aprovados (rotação,
  truncamento, estados mistos dentro da janela, frames finais e schema antigo).
- `tests/test_session_detail.py`: watchdog, etapas pendentes, origem do erro,
  spans rápidos, detalhes limitados, histórico e recuperação após JSON inválido.
  Última sessão: `20261012-144645-139-65956-f8b19028` em `user://session-logs`.
- `tests/test_session_diagnostics.py`: callbacks GDScript/C#, mensagem de worker,
  pausa, duas sessões distintas e Play com debugger real; aprovado.
- `tests/test_session_observability.py --rendered`: Main real, criação/entrada do
  modelo `sewer_pipe`, inventário, pausa, configuração, brackets de render e
  igualdade da contagem de frames entre resumo e leitor; aprovado para diagnóstico.
  Sessão: `20261012-143716-229-65376-d414440f`; zero perda de registros e zero
  falha de escrita. Erros de `CobraModel.gd:57` registrados separadamente.
- `tests/test_session_budget.gd`: pressão de 200 payloads de aproximadamente
  1 Mi caracteres, rejeição por orçamento, registro acima do limite, JSON com
  shape inválido e fechamento do resumo; aprovado. Pasta de evidência:
  `user://session-budget-tests/20261012-144421-694-66912-a8948ef4`.
- `tools/Measure-SessionDiagnostics.ps1`: não iniciou benchmark porque detectou
  runtimes externos ativos. Não houve comparação isolada antes/depois e a
  performance permanece **não medida/inconclusiva**. A rodada renderizada acima
  foi validação funcional com concorrência, não aprovação de FPS ou overhead.
- Build final `dotnet build Harbor.csproj --no-restore -v quiet`: zero erros e avisos.

Hooks de exceções fatais, disco cheio, crash nativo, saturação de todas as origens
possíveis, todas as áreas e sessões de várias horas não foram certificados.
