# Pausa de 1709,627 ms — investigação dirigida de 5/10/2026

**Estado: assinatura ainda pendente. Nenhuma correção da pausa de 1,7 s foi demonstrada ou aprovada.** Dois agentes trabalharam em auditoria causal e perfil nativo. Foram concluídas duas capturas dirigidas, uma com cobertura nativa ampliada, duas exposições controladas à carga externa e duas rodadas com WPR elevado, todas renderizadas, finitas e válidas. A pausa original não reproduziu nessas condições; esse resultado é inconclusivo sobre sua eliminação.

O [relatório de arquitetura/performance de 02–03/10](D:/geteco/game/docs/reviews/performance-architecture-20261002.md) já restringe suas 24 correções aos cenários medidos e mantém travadas/cobertura global pendentes. As correções de outras assinaturas e os resultados da continuação de 04/10 permanecem separados deste alvo. O teto de três passos é a condição herdada do controle e do atalho; não foi reduzido nesta investigação nem usado como prova de eliminação do gatilho.

## Localização da assinatura original

Controle anterior `shader-cache-a1`, frame16083, recuperação, READY+102,102540 s: intervalo124882684–126592311 µs,1709,627 ms. O desenho observado dura3,660 ms; um callback físico dura8,701 ms. A lacuna dominante é **124897739–126592311 µs,1694,572 ms, depois do último callback físico e antes do próximo process_frame**. Os contadores kernel/user da main permanecem iguais entre as duas amostras que cercam a lacuna; a quantização impede chamar isso de zero execução absoluto. Há9.499.089 ciclos adicionais, sem conversão arbitrária para wall. O catch-up de três passos vem no frame seguinte.

População29 pessoas/39 carros/4 unidades;16 chunks; filas de streaming observadas zeradas; nenhum nó criado/liberado nesse intervalo. Não há WORK abrangendo a lacuna. Isso localiza o problema, mas não separa solver, filas do motor, deferred, runtime, driver e espera/agendamento. Os monitores physics/process publicados em outra cadência não preenchem a lacuna; os tempos inclusivos de pais/filhos não são somados.

O frame15918,1512,399 ms, é outra localização: vehicle.street_pre1486,015 ms dentro de um callback físico1499,414 ms. Não foi agrupado automaticamente à pausa pós-callback. Detalhes, antecedentes, snapshots e evidência que rejeita a atribuição direta ao logger medido: [auditoria A1](D:/geteco/game/evidence/stalls-1709-20261005/a1-pause-audit.md).

## Capturas novas e condições

[Plano prospectivo D1/D2](D:/geteco/game/evidence/stalls-1709-20261005/plan.md) e [mudança discriminante WIDE1](D:/geteco/game/evidence/stalls-1709-20261005/wide-plan.md) foram escritos antes dos motores correspondentes. Cada rodada usa120 s de gameplay+3 s de cauda. Percurso Foundry107→180→107,30 s de primeira passagem, retorno, evento e recuperação; inputs normais, sem teleport em runtime. Diretores/tráfego/despacho/colisão/efeitos continuam ativos; fixtures de sobrevivência/arsenal mantidas iguais ao controle anterior, sem saves. Seed21092026, população configurada40, VulkanMobile,1920×1080,MSAAenum1,escala1,VSyncOFF,sem limitador, física60 Hz/teto3. Loading e primeiros engasgos são preservados e reportados separadamente.

Harbor.csproj compilado antes de cada motor. Godot4.7.2.NET mono, official.ed1daf0bf; ThreadCpuProbe C# válido, plans privadas do terminal nativas ativas em loading e router principal ativo ao término. READYactive=false é inicialização lazy, não fallback silencioso. O projeto é uma cópia independente do controle pós-correções, com1650 fontes verificadas. A única mudança de runtime é a retenção do ring; o receipt da cópia é a outra diferença de metadata esperada. Cada runner terminou exit0, sem erros/drift e sem frames desfocados.

| Rodada | p50/p95/p99 ms | Máximo GP ms | >33,3 ms / frequência s⁻¹ | >66,7 ms / frequência s⁻¹ | Recuperação: máximo ms |
|---|---|---:|---|---|---:|
| D1 |6,028/13,233/15,078|888,783|23/0,191637|4/0,033328|42,868|
| D2 |6,104/14,176/16,558|302,623|23/0,191633|7/0,058323|31,224|
| WIDE1 |5,870/13,124/15,233|80,618|28/0,233313|2/0,016665|28,099|
| Carga A1 |5,892/14,146/20,041|93,441|68/0,566595|8/0,066658|75,130|
| Carga A2 |5,723/13,681/20,205|114,403|75/0,624909|8/0,066657|89,411|

Estas são rodadas **diagnósticas com suspensão breve da main para obter contexto**, não braços antes/depois de uma correção nem aprovação de FPS. Loading: máximos6998,212/6850,543/6785,782 ms; não foram removidos como aquecimento. Percentis, contagens e frequências por fase/loading/tail e timeline de todos os picos≥25 ms estão nos [D1](D:/geteco/game/evidence/stalls-1709-20261005/d1-analysis.json), [D2](D:/geteco/game/evidence/stalls-1709-20261005/d2-analysis.json) e [WIDE1](D:/geteco/game/evidence/stalls-1709-20261005/wide1-analysis.json).

Nas exposições à carga, loading também permanece: máximos 7033,372/6696,303 ms. A [análise A1](D:/geteco/game/evidence/stalls-1709-20261005/memory-a1-analysis.md) e a [análise A2](D:/geteco/game/evidence/stalls-1709-20261005/memory-a2-analysis.md) registram os percentis e a linha do tempo de cada fase, incluindo frames abaixo de 40 ms. Não há comparação antes/depois de uma correção da pausa de 1,7 s: nenhum candidato foi justificado por causa demonstrada.

As auditorias independentes dos dois agentes estão em [D1/D2/WIDE](D:/geteco/game/evidence/stalls-1709-20261005/d1-d2-wide-causal-audit.md), [exposições A1/A2](D:/geteco/game/evidence/stalls-1709-20261005/memory-a1-a2-causal-audit.md) e [síntese nativa](D:/geteco/game/evidence/stalls-1709-20261005/memory-native-summary.md). Elas incluem hashes, confirmação do caminho C#, validade, métricas por fase, custos e perdas.

## Linha do tempo discriminante

| Captura/frame | READY s | Duração ms | Localização demonstrada | Limite causal |
|---|---:|---:|---|---|
| A1/15918 |97,393732|1512,399|street_pre1486,015 dentro callback|sem filhos/stack cobrindo a pausa|
| A1/16083 |102,102540|1709,627|gap pós-callback1694,572|sem CPU/agendamento nativo na pausa|
| D1/2787 |9,949680|888,783|dispatch.prepare_ground869,265 dentro callback879,632|fora da janela nativa85–120; wrapper não mede prepare_collision_at isoladamente|
| D1/14850 |104,611 s aprox.|42,868|espera pontual NtWaitMultiple após último callback, gap18,665|caller além de Kernelbase ausente; não é reprodução1,7 s|
| D2/7084 |37,461570|302,623|ground_blood.allocate287,964 dentro callback294,923|fora da janela nativa85–120; alocação/material/driver ainda indivisíveis|
| WIDE1/719 |0,565429|80,618|maior GP dessa rodada|nenhuma pausa longa equivalente|
| WIDE1/6565 |34,517192|47,166|vehicle.drive35,497 dentro callback40,871|não confundir amostras nativas anteriores ao início com este pico|

Os spans prepare_ground e allocate são inclusivos, com CPU principal quantizada baixa. Não justificam atribuição a algoritmo GDScript, chunk inteiro, material ou compilação. D1 mantém17 chunks/filas0 no frame anterior e o rótulo não é prepare_ground.build; o custo da chamada isolada a prepare_collision_at não foi capturado. Em todas as novas rodadas não há gap pós-callback≥250 ms.

## Instrumentação, perdas e limites

StallLog, StallWorkTrace, measure_physics_boundaries e ThreadCpuProbe foram reutilizados. O ring detalha≥25 ms, incluindo abaixo40 ms, e guarda posição, população, passos, filas, criação/liberação, eventos e relógio monotônico. O sampler dirigido cobre85–120 s a cada20 ms, com1750 contextos e175 snapshots próprios em cada rodada. WIDE cobre0–120 s a cada50 ms:2399/2400 pontos, slot0 perdido antes do attach e registrado;600 snapshots. Em todos os pontos capturados, retomada com contador anterior1; erros, identityfail e perdas adicionais0. Não houve suspensão de workers nem acesso/controle a threads alheias.

CPU do observador nativo/um núcleo: D1 4,867%,D2 3,438%,WIDE1 3,063%. Estados/CPU Nt a cada200 ms são snapshots **antes** da suspensão, não durações contínuas Running/Ready/Waiting; consultas de CPU por thread não são atômicas. Holds/queries/lateness e custos por fase estão nos brutos, sem subtração dos frames. Logger D1/D2: máximo próprio1,354/1,674 ms; sort0,155/0,116 ms; escritor0,143/0,170 ms; drops0. WIDE hooks somam1.308.158 µs em17178 chamadas; dispatch/work hooks ficam fora desse limite inferior.

WIDE mantém arquivo **privado** de contexto completo1232 bytes+stack≤16 KiB por ponto, limitado a2400, salvo apenas após FINISHED antes do decode. Não há dump completo do processo nem publicação dos bytes. Escrita+hash:203,125 msCPU/238,413 mswall após gameplay. Isso permitiu reconstrução offline conservadora pelos metadados PE/pdata/UNWIND_INFO, sem varrer endereços de retorno. O ajuste offline que ignora REX.B comum quando não há candidato de epílogo bateu com43/43 endereços de uma cadeia original. Algoritmo e resultados anteriores foram preservados; opcodes/patches/JIT não disponíveis param a cadeia explicitamente.

O executável oficial tem pdata, mas não PDB nativo compatível disponível. Símbolos exportados próximos, especialmente NoHotPatch, não são nomes de função confiáveis. A stack primária é RIP+module+RVA; identificação de chamada exige range/callsite e fonte correspondente. PDB portátil managed não substitui símbolos do motor. [Metadados AMD64 de unwind](https://learn.microsoft.com/en-us/cpp/build/exception-handling-x64?view=msvc-170).

O WPR elevado anterior não cobriu os picos; o ETL com0 EventsLost ainda perdeu prefixos por buffer circular. Solicitações UAC equivalentes posteriores não entraram no helper. A autorização do usuário permanece registrada, mas privilégio/cobertura real não foram presumidos. Nesta etapa não foram repetidas essas tentativas equivalentes. CPU nativa amostrada não substitui CSwitch/ReadyThread/IRQ/DPC contínuos: essa lacuna permanece.

## Correção efetivamente aplicada

O ring podava detalhes relativos ao **fim** da pausa antes de reconhecer o pico. A1/15918 perdeu84 detalhes/771,583 ms do prefixo de3 s apesar de overflow0. Agora o cutoff de um intervalo≥25 ms usa previous−PRE_USEC; os limites/drops continuam explícitos. As janelas D1/2787 e D2/7084 retêm3 s completos antes do início e após o fim, com0 detalhe faltante. Frame0 não pode ter histórico anterior ao início da coleta, e essa limitação permanece explícita.

Apenas essas duas linhas lógicas e comentário foram portados para [measure_intermittent_stalls.gd](D:/geteco/game/tests/measure/measure_intermittent_stalls.gd:171), sem copiar diagnósticos privados ou mudar gameplay. SHAantesE92165700B9AC3B74CF59E47C90A159978E6FD978DF0BEAB5528575523D60F84; depois4ebe87e47303b166c2edcc11b7d02c1ab961ecba2020959a7f9315de2d98b99f. Harbor compilado0 avisos/erros e Godot.NET--check-only do collector exit0. A validação de retenção é renderizada; o check-only valida parse, não FPS. Alterações concorrentes e saves foram preservados.

Limite de borda separado do defeito corrigido: o último frame que cruza o corte de POST pode não ter seu detalhe retido. Três janelas WIDE terminam 2,508/0,728/5,722 ms antes do corte solicitado em relação aos detalhes; uma janela de retorno A2 tem déficit de 7,125 ms. Os timestamps de todos esses frames continuam no vetor completo; drops/overflow permanecem zero. Não foi afirmada integridade estrita de todas as janelas ±3 s. As janelas dos picos ≥250 ms D1/D2 têm prefixo e sufixo completos. Incluir o frame que cruza POST é uma melhoria pequena para coleta futura, sem relação demonstrada com a trava.

O wrapper D1 reportou falso erro por ExitCode=null apesar de dados nativos válidos. D2 wrapper ficou ativo depois da saída do Game/helper e da persistência de validity; somente o PID55380, comando/nascimento conferidos, foi encerrado antes da WIDE. Game/helper D2 têm dados válidos e os receipts históricos foram preservados. WIDE usa duas sessões próprias de ferramenta, watcher e runner, e ambas terminam exit0; não carrega o wrapper defeituoso para o gameplay seguinte.

## Causa versus hipótese e próximos discriminantes

| Hipótese | Evidência | Experimento que decide |
|---|---|---|
| Logger sort/serialize/enqueue medido causa1,7 s | custos pequenos, callbacks antes do draw, spans seguintes começam depois da pausa | atribuição direta rejeitada; não corrigir logger por especulação |
| Catch-up inicia a pausa | acumulação de passos ocorre depois do gap | rejeitada como gatilho; teto físico3 preservado |
| Compilação explica1,7 s apenas por pipelines | draw curto e pipelines sem delta nessa pausa | não demonstrada; cache corrige outra assinatura do relatório anterior |
| Solver/fila/deferred/driver/espera após callback | gap1694,572 ms e CPU principal baixa | nova reprodução com stack+estados dentro do próprio gap; WPR com cobertura/perdas auditadas se privilégio disponível |
| GC/JIT CLR | nenhuma evidência CLR dentro da pausa original | capturar eventos .NET se stack apontar runtime; não substituir CPU nativa do motor |
| Carga externa ccusage | bursts sobrepostos, todos os threads Godot com pouca CPU em brackets do pico; dono atual identificado como OpenUsage | duas exposições controladas não reproduziram a pausa; hipótese permanece inconclusiva. Uma nova comparação exige controle positivo e cobertura dentro da pausa |

População, qualidade visual, colisão, steps, prioridades/afinidade, energia, políticas Windows e sistemas do jogo foram preservados. Apenas o utilitário OpenUsage identificado foi pausado temporariamente nas duas exposições, condição comum planejada, e restaurado ao fim com a configuração intacta. Uma rodada sem o pico não aprova nenhuma dessas hipóteses. Não há braço candidato antes/depois da pausa de 1,7 s porque ainda falta causa demonstrada.

O [alinhamento nativo concluído](D:/geteco/game/evidence/stalls-1709-20261005/native-diagnostic-summary.md) identifica ShaderRD/WorkerThreadPool no draw59,108 ms de WIDE/4308. Os waits NVIDIA de aquisição de imagem pertencem a frames comuns5375/6552,5,744/11,691 ms; não são o pico RETURN6565. O wait de fence no slot26 ocorre antes de pre_draw; o slot1100 não tem detalhes circulares. Essas observações não preenchem a lacuna retrospectivamente.

A observação dirigida de 04:10 UTC identificou o dono atual da carga: ccusage→node→cmd→node→cmd→OpenUsage 0.6.37→Explorer. Working set atual 13.150.212.096 bytes e memória privada 13.982.359.552 bytes; a máquina tem 31,73 GiB físicos. A RAM observada posteriormente estava livre em 22,63 GiB, logo não é prova de paging no pico anterior. Proveniência histórica não registrou memória/command line completos. O [experimento finito de carga externa](D:/geteco/game/evidence/stalls-1709-20261005/memory-plan.md) variou apenas a exposição a uma consulta própria. O flag --speed muda precificação e não foi usado como otimização.

## Resultado do experimento de carga e encerramento

A1/A2 iniciaram o mesmo binário ccusage 20.0.2, com os argumentos seguros registrados, em READY+95 s. As consultas terminaram naturalmente, exit0, após 17,572/18,502 s, com 82,438/83,594 segundos de CPU somada em todas as threads. Isso confirma exposição substancial. A configuração herdada e o diretório do launcher histórico não foram capturados; equivalência completa com a carga histórica não é presumida.

Nenhuma das duas exposições teve frame de gameplay ou gap pós-callback ≥250 ms. Os máximos de recuperação foram 75,130/89,411 ms; houve 60/64 frames >33,3 ms e 5/6 >66,7 ms nessa fase. Esses picos menores não demonstram a causa da pausa de 1709,627 ms. A regra prospectiva encerra o experimento após dois controles negativos; B1/B2 não foram executados. Não se conclui que desativar o OpenUsage resolveria o problema.

Na A1, a RAM global disponível caiu de cerca de 21,48 GB para 3,802 GB, enquanto o working set do Godot permaneceu perto de 2,26 GB. PageFaultCount inclui faults leves e pesados; nenhum desses dados prova leitura de disco ou trim do Godot. O sampler perdeu nove slots consecutivos após um guard de identidade demorar 506,277 ms **antes** de suspender a main, além do slot inicial. O maior hold da main foi 1,263 ms. A distinção impede atribuir o atraso do coletor a uma suspensão de meio segundo.

Na A2, disponibilidade global 21,40→4,235→21,54 GB; working set do Godot durante a dose 2,262–2,275 GB. São GB decimais. Não foram coletados contadores de memória da CLI própria, e não se transfere para ela a medida de 13 GB da instância externa observada antes do experimento. A [síntese nativa das duas exposições](D:/geteco/game/evidence/stalls-1709-20261005/memory-native-summary.md) reúne memória, sobreposição das suspensões, custos do Logger/trigger e seus limites.

O sampler consumiu 4,235%/3,257% de um núcleo em A1/A2. A2 capturou 2399/2400 pontos e 600 snapshots, perdendo somente o slot inicial; maior hold 2,092 ms, p99 0,540 ms. Todos os pontos capturados nas duas exposições tiveram ResumeThread com contador anterior1, sem erros de identidade/retomada. Anchors de loading/READY/fim concordam entre relógio Godot e QPC. Consultas de estado/memória, guard e cópia têm custos inclusivos registrados; não são somados novamente ao custo total nem subtraídos dos frames. Os observadores afetam o ambiente, portanto estes resultados permanecem diagnósticos.

Houve um ponto coreclr.dll em cada exposição, dentro de frames comuns de 9,188/9,128 ms, fora da dose. Isso confirma execução do runtime, sem indicar GC/JIT nem causa dos picos. Não há símbolos suficientes para atribuir a função por export vizinho. Nenhuma indicação específica justificou outra captura .NET nesta etapa; eventos curtos entre pontos não foram excluídos.

O OpenUsage foi reaberto em 05/10 às 04:41:15 UTC, PID68872, com path/nascimento verificados. SHA256 de settings.json antes e depois: 4D96A7AD5789891BB4EC9C05800E45391B186ECF9CEC95D2A037442E7A23B4AD. [Recibo de restauração](D:/geteco/game/evidence/stalls-1709-20261005/openusage-restored.json). Nenhuma configuração do utilitário foi editada; outras sessões e saves foram preservados.

A pendência específica é capturar novamente o intervalo longo com cobertura nativa dentro dele, distinguindo execução, espera e pronto para executar. Os pontos obtidos não oferecem durações contínuas de agendamento; não autorizam escolher entre driver, solver, deferred, CLR ou pressão externa. A correção entregue nesta etapa é a retenção do contexto circular, já validada; a pausa de 1,7 s permanece aberta.

Histórico de correções comprovadas de outras assinaturas: [relatório anterior](D:/geteco/game/docs/reviews/intermittent-stalls-continuation-20261004.md).

## Continuação: perfil de agendamento com privilégio confirmado

Em 05/10, o prompt visível abriu PowerShell administrativo e o helper confirmou seu token elevado, PID, fonte e perfil. A preparação rec1 excedeu a espera de 300 s porque o coordenador não iniciou o runner a tempo; nenhum jogo ou WPR começou nesse label. O erro e o boot foram preservados. A consulta extra a CommandLine/ExecutablePath de um processo elevado retornava campos protegidos; a confirmação passou a usar o boot próprio e o nome do processo, sem presumir que campos indisponíveis significavam falta de privilégio.

O usuário executou rec2 na janela administrativa existente. Depois houve rec3 com novo boot administrativo, a segunda e última medição deste lote. [Plano WPR](D:/geteco/game/evidence/stalls-1709-20261005/recovery-wpr-plan.md), [critérios](D:/geteco/game/evidence/stalls-1709-20261005/recovery-wpr-signature-criteria.md) e [emenda rec3](D:/geteco/game/evidence/stalls-1709-20261005/rec3-plan.md) antecedem os motores. O jogo permaneceu no processo normal; Harbor compilou com zero avisos/erros em 0,53/0,66 s. Fontes do jogo, saves e processos alheios foram preservados. OpenUsage permaneceu ativo normal, sem consulta própria programada nesta etapa.

Perfil CPU/agendamento Memory com 1 GiB, CSwitch/ReadyThread/SampledProfile/Loader e demais keywords originais. READY+85 s de delay, até 40 s de gravação, stop antecipado após FINISHED/saída. Início efetivo e retenção são auditados pelos clocks e eventos, sem promessa de 85 s exatos. Ambos salvaram após FINISHED e confirmaram cleanup da própria instância GUID. ETL rec2: 377.487.360 bytes; rec3: 607.125.504 bytes. Não houve stop/cancel global, alteração de política, prioridade, dispositivo ou driver.

| Rodada | p50/p95/p99 GP ms | Máximo GP ms | >33,3 / frequência s⁻¹ | >66,7 / frequência s⁻¹ | Recuperação: máximo ms | Cauda: máximo ms |
|---|---|---:|---|---|---:|---:|
| WPR rec2 |5,603/12,988/14,624|83,432|9/0,074992|3/0,024997|57,256|121,552|
| WPR rec3 |6,198/14,026/15,735|94,667|13/0,108318|4/0,033329|40,514|16,265|

Os máximos de loading, preservados, são 7933,544/7173,424 ms. Todas as fases, contagens, frequências e timelines ≥25 ms constam nas análises [rec2](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-analysis.md) e [rec3](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-analysis.md). Nenhum gameplay/cauda ≥250 ms reproduziu o alvo. Não há correção do jogo validada por essas duas observações; p95/p99 GP também subiram em rec3, portanto não se declara ganho de FPS pela redução do observador.

### Estado real e comparação pertinente

Rec2 já iniciou recuperação com 1 estrela/5 unidades, diferente das 3 estrelas/4 unidades da original. Em READY+116,589–116,613 s, mudou de 107,99/23 para 66/125,728, zerou estrelas/unidades e liberou 520 nós. Cinco eventos dispatch.unit_finished ocorreram no mesmo intervalo. O destino coincide com a custódia definida no catálogo e com o caminho FullSession._respawn; prisão é uma inferência forte, pois o sinal player_arrested não foi coletado. Godmode bloqueia dano, não prisão. O máximo de recuperação de 57 ms e os picos de cauda rec2 ocorreram depois dessa transição: não são carga/local comparáveis ao frame histórico.

Rec3 iniciou recuperação com 3 estrelas/4 unidades no local inicial, mantendo esse estado nos detalhes próximos de +97,39 e +102,11 s e no fim. Nessas amostras: 29 pessoas, 38 veículos, 16 chunks e filas observadas zeradas. A original tinha 29/39/4 e 3 estrelas. Essa equivalência pertinente de estado não produziu o gap pós-callback longo. Rota/seed iguais são condições nominais; a população instantânea e a evolução dos eventos continuam explicitamente qualificadas.

As auditorias completas do jogo estão em [rec2](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-causal-audit.md) e [rec3](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-causal-audit.md). O maior gap pós-último callback retido foi 6,246/4,584 ms, respectivamente, e nenhum chegou a 250 ms. O coletor externo não observou CPU positiva de ccusage no gameplay de nenhuma dessas duas rodadas; em rec2 houve duas instâncias durante loading. A carga externa sobreposta à pausa antiga não foi reproduzida nesta etapa: estado local comparável em rec3 não implica host idêntico.

### Nova assinatura localizada na cauda rec2

A [auditoria nativa rec2](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-native-summary.md) verifica frequências, anchors, EventsLost=0, LastDroppedTimes dos 20 CPUs zerados e continuidade da main. A revisão offline v1 aparentava 690 anomalias: ReadyThread poucos µs antes de Out apagava retroativamente a residência anterior, e o valor nativo 7 DeferredReady era confundido com Unknown do enum .NET. V2 usa pares completos CSwitch In→Out no mesmo CPU; preserva os casos realmente desconhecidos e corrige essas duas interpretações. ETL e v1 permanecem intactos; não houve interpolação para preencher a pausa antiga.

| Frame rec2 | Total ms | post_draw→primeiro callback físico ms | Scheduled running no gap ms | Ready ms | Waiting ms |
|---|---:|---:|---:|---:|---:|
|17284|114,673|80,150|1,211|0,323|78,616|
|17285|121,552|93,984|93,453|0,460|0,071|
|17299|105,158|83,090|82,995|0,095|0,000|
|17384|112,176|89,522|1,102|0,341|88,079|
|17385|117,392|92,583|92,461|0,108|0,015|
|17399|114,956|91,959|90,383|1,382|0,195|

Esses gaps estão antes do primeiro callback físico; o alvo de 1,7 s ficava depois do último. Stacks ligados aos CSwitch-IN de retomada e samples da própria main apontam PeekMessageW/NtUserPeekMessage e DirectInput/RegOpenKeyExW/NtOpenKeyEx. São muitas esperas pequenas, não uma espera única de 80 ms. Não há stack Out correspondente nesse export: o vínculo mostra contexto de retomada durante a chamada, não duração exclusiva da API ou seu lock/sinalizador.

Exports, pdata e imports foram confrontados com checksum/SizeOfImage do rundown. Sem PDB nativo Godot aprovado, fonte/faixa/callsite são inferências explicitadas; export vizinho NoHotPatch não nomeia função. O caminho é compatível com process_events/SDL e EnumDevices de game controllers, sem provar que algum controle foi encontrado ou usado. O usuário informou nenhum controle ativo; a presença de DualSense no registro Bluetooth não confirma conexão. Nada foi removido/desativado. SDL_HINT_JOYSTICK_THREAD=1 já é definido pelo motor, logo repetir esse flag não é correção. [Fonte exata do motor](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/drivers/sdl/joypad_sdl.cpp).

A operação/caminho desses picos menores está localizado; por que a detecção/configuração ficou lenta e sua correção permanecem pendentes. Essa evidência não identifica a causa do gap histórico pós-física. Scheduled running inclui interrupções que o perfil não separa; faltam providers específicos para DPC/IRQ/hard faults. Não se atribui esse tempo exclusivamente a GDScript, GPU, solver ou GC/JIT.

### Correção do observador, separada do jogo

Get-Identity do helper consultava Get-Process/MainModule repetidamente. Rec2: 1843 consultas, 27,474 s de parede acumulada, máxima 130,901 ms; CPU do helper durante recording 3625 ms/38,470 s, 9,423% de um núcleo. Rec3 mudou apenas essa consulta no aparato para handles com direitos de leitura limitados, verificando PID, nascimento FILETIME, imagem e liveness, fechados em finally. Parent/child, perfil, janela, timeout e cleanup foram preservados; nenhuma fonte do jogo mudou.

A [preflight funcional e de custo](D:/geteco/game/evidence/stalls-1709-20261005/query-limited-helper-review.md) passou em 50 pares próprios com identidades iguais e recusou um PID próprio encerrado. Na captura renderizada rec3: 2201 consultas, 0,301 s de parede acumulada; CPU do helper durante recording 609,375 ms/38,536 s, 1,581% de um núcleo. A redução observada de cerca de 83% no custo dessa fase valida a melhoria do observador nesse cenário. Não isola todo overhead ETW/kernel, não é ganho de FPS e não corrige a pausa original, que foi capturada sem esse helper.

Outros observadores permanecem medidos e qualificados: v4 externo 3,174%/3,392% de um núcleo em rec2/rec3; queries p95 25,763/20,578 ms. Logger self máximo 1,458/1,200 ms; sort 0,659/0,113 ms; writer 0,253/0,106 ms. São scopes distintos e limites inferiores, sem somar pais/filhos nem subtrair custos para anunciar FPS hipotético. O último frame que cruza POST ainda pode perder detalhe: até 11,998 ms em rec2 e 9,214 ms em rec3. Todos os timings permanecem; prefixos corrigidos foram retidos e drops/overflow são zero. Picos de cauda rec2 também têm pós-contexto finito truncado, explicitado na auditoria.

O desaparecimento dos picos de cauda em rec3 não é atribuído ao helper: o estado/local da cauda difere de rec2 após custódia. A [síntese nativa rec3](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-native-summary.md) concluiu a cobertura READY+85,491807..124,189231 s, QPC10MHz, EventsLost0 e LastDroppedTimes dos 20 CPUs zerados. Pares CSwitch v2 não têm anomalias; as seis partições de recuperação selecionadas não têm Unknown. No maior frame dessa fase, 40,514 ms: scheduled running34,431 ms, Ready0,733 ms e Waiting5,350 ms; esses tempos não são exclusivos de callbacks ou GPU.

O lote WPR termina com dois jogos válidos. A dependência restante é uma reprodução do gap pós-último callback longo com perfil dentro dele. Rec3 corresponde ao local/procura/unidades pertinentes, mas não reproduziu o burst ccusage do controle antigo; as duas exposições próprias anteriores também foram negativas e continuam inconclusivas. Input/DirectInput dos picos menores foi localizado em outra fronteira e pede investigação própria da detecção/configuração; não foi corrigido nem transferido como causa histórica. Não há outra rodada equivalente implícita. **A pausa de 1,7 s permanece pendente e sem correção causal demonstrada.**
