# Engasgos intermitentes — investigação de 4/10/2026

**Estado atualizado:** a [continuação com contraprovas e pendências](intermittent-stalls-continuation-20261004.md) inclui a extensão do cache CPU de caixas aos três builders urbanos, mais 616 checks aprovados, a espera nativa ShaderRD e o comparativo de cache 2+2. O isolamento de userdata também tornava o cache de shaders frio em cada captura anterior. As duas assinaturas de draw de 54–57 ms desapareceram nos dois braços com seed verificado; as capturas frias permanecem válidas para primeira execução, sem representar automaticamente o estado de um jogador com cache persistente. O runner agora declara essa condição. As outras famílias de travadas continuam abertas. A [linha do tempo consolidada da continuação](../../evidence/intermittent-stalls-20261004/continuation-stall-timeline-v3.csv) contém 1302 intervalos, além dos registros iniciais preservados abaixo.

Seis mecanismos demonstrados foram corrigidos no código atual: batches de caixas, load tardio do Digo, primeira rota C#, geometria fria dos passageiros, repetição dos corpos dos quatro coaches e recriação do recurso de material do sangue. As provas valem para essas operações e assinaturas. Ainda há travadas de outras famílias; o jogo não recebe aprovação global de performance. Foram preservados o loading inicial, as rampas anteriores ao acúmulo de passos físicos e as pausas sem avanço de CPU. Alterações concorrentes e saves pessoais foram preservados.

O ambiente foi Godot 4.7.2 .NET console, instalado em `D:/Downloads Chrome/Godot_v4.7.2-stable_mono_win64/Godot_v4.7.2-stable_mono_win64`. `Harbor.csproj` atual compilou com zero avisos e zero erros; saída live `D:/geteco/game/.godot/mono/temp/bin/Debug/Harbor.dll`. As três capturas finais usaram o projeto congelado `D:/geteco/game/evidence/intermittent-stalls-20261004/final-current`, com seu próprio assembly no mesmo caminho relativo. Cada execução compilou antes de abrir o motor e removeu `HARBOR_NO_CSHARP` do ambiente de teste. ON e o contrato de rota exigiram sondas/planos C# reais; OFF desliga essas sondas, mas o router C# do mundo terminou ativo nas três capturas. Os 12 contratos da cadeia alterada passaram 1233 verificações. Testes headless verificam semântica e recursos; os frames foram medidos exclusivamente no gameplay renderizado. Dois agentes dividiram auditoria/contratos/revisão e diagnóstico nativo/CLR, com benchmarks exclusivos coordenados pelo controlador.

## Sangue: evidência, hipótese, experimento e correção

O profiler oficial havia apontado `GroundBlood._allocate` em 18,646 ms. Native-blood-01 válido confirmou allocation de 19,968 ms, dos quais 19,828 ms estavam na configuração. A subdivisão seguinte localizou o custo em `material_override`. S1 registrou 21,867 ms na primeira atribuição e 19,844 ms depois da expiração total, enquanto `cast_shadow` custava até 0,005 ms. S1 perdeu foco durante todo o gameplay: seus dados positivos orientaram a contraprova, mas sua medição de FPS foi invalidada.

O controle focalizado S2 confirmou primeira atribuição de 25,311 ms, allocation de 25,495 ms, no frame 1747, READY +9,715735 s. Com todas as manchas expiradas, nova atribuição custou 18,644 ms e allocation 18,772 ms no frame 12808, READY +97,848389 s, fase recovery. Esse frame de 98,052 ms também tinha draw de 53,522 ms e três passos físicos; a atribuição explica apenas parte do frame.

A hipótese foi perda do cache compartilhado do recurso depois da liberação do último material. A fonte oficial de [GeometryInstance3D](https://github.com/godotengine/godot/blob/4.7/scene/3d/visual_instance_3d.cpp) passa a atribuição por `material.get_rid()`. [BaseMaterial3D](https://github.com/godotengine/godot/blob/4.7/scene/resources/material.cpp) atualiza o recurso e remove a entrada compartilhada quando seu último usuário desaparece. A fonte 4.7 orienta a hipótese; não identifica tempo exclusivo de compilação, GPU ou driver no binário 4.7.2.

Uma variável foi alterada: um material imutável, configurado pelo método original, fica retido durante a vida do GroundBlood. Seu RID é preparado em `_ready`, sob a cortina. O template nunca é atribuído a uma mancha. Todas continuam com materiais individuais, mesmos meshes, RNG, raycast, cores, fade, sombras e limite de 64 manchas. Custo extra: um Resource por dono, liberado junto com ele. Main cria StreetPhysics/GroundBlood antes de levantar a cortina; o caminho standalone lazy fora dessa cadeia não foi certificado.

W1 preservou `get_rid` de 21,904 ms no loading, mas reteve apenas três allocations com manchas existentes. Primeira criação e recriação fora da janela foram consideradas inconclusivas. W2 adicionou retenção seletiva de até 512 parents, sem segundo consumo de WorkTrace. Preservou 14 parents e onze subspans privados por operação, sequência completa e zero drops. Primeira criação e recriação de zero para uma mancha custaram ambas 0,103 ms, atribuição de 0,015 ms. Preparação de 18,317 ms permaneceu no loading. A borda anterior da segunda janela perde 4,629 ms de um frame que a cruza; operação e filhos estão completos.

As duas capturas finais ON confirmaram o resultado no código mínimo atual. ON1: primeira allocation de 0,079 ms e recriação de 0,081 ms. ON2: primeira de 0,082 ms e recriação de 0,081 ms. Template vivo e identidade constante em todos os 17 e 29 parents de cada processo, sequência completa, zero drops e contexto de três segundos antes/depois das quatro operações. Preparação de RID de 18,719/20,360 ms permaneceu no loading. Só os spans totais de allocation/preparação/RID foram portados; onze subspans continuam privados. A correção valida a atribuição fria recorrente no gameplay, sem declarar eliminado o loading ou todo draw.

A alternativa de passar adiante somente o primeiro material passou contratos semânticos, mas foi rejeitada antes da integração porque perderia o último usuário após expiração total. O template retido passou 1022 verificações de equivalência, RNG, parâmetros, raycast, descarte, fade, expiração, recriação e liberação do dono.

[Análise causal](../../evidence/intermittent-stalls-20261004/continuation-native/ground-blood-causal-summary.md), [retenção W2](../../evidence/intermittent-stalls-20261004/continuation-native/blood-template-02-pin-audit.json), [plano e emendas prospectivas](../../evidence/intermittent-stalls-20261004/ground-blood-causal-plan.md), [manifesto de integração](../../evidence/intermittent-stalls-20261004/production-blood-integration-manifest.json), [confirmação final](../../evidence/intermittent-stalls-20261004/continuation-native/final-current-causal-summary.md).

## Perfil nativo, CLR e observadores

O helper WPR existente foi reutilizado. O usuário autorizou o prompt UAC; as duas tentativas retornaram do Windows “operação cancelada”. O helper não elevou e não produziu ETL. Foi cancelamento do Windows, não rejeição do auto-review. Foram verificados o token sem `SeSystemProfilePrivilege`, o perfil circular de 256 MiB com CSwitch/ReadyThread/SampledProfile/stacks e a ausência de PDB nativo compatível encontrado para o motor. Cobertura, perdas e stacks nativos continuam sem captura. Contadores quantizados em 15,625 ms não distinguem duração executando, pronta ou esperando por frame.

O fallback native-blood-01 amostrou estados pontuais a 20 Hz: 2500 pontos válidos, sendo 2441 Running, 39 Waiting, 18 Standby e 2 DeferredReady, entre READY +0,246 e +125,202 s. Consulta p50/p95/p99/máximo: 3,768/5,524/10,626/19,155 ms; CPU: 7,962% de um core. Pontos de estado não são durações ou stacks. A sonda cara saiu das comparações finais; seu custo não foi subtraído dos frames.

CLR na primeira rota registrou 201 pares `JittingStarted→MethodLoadVerbose`, com PID/TID/CLR/module/method correspondentes. União inclusiva de 22,8439 ms dentro do plano de 28,671 ms, perdas e erros de payload zero. Planos posteriores de 0,404/0,360 ms não tiveram pares nas janelas cobertas. Isso demonstra contribuição de JIT, sem medir CPU exclusiva. O profiler posterior registrou GC `InducedLowMemory`: suspend/restart de 6,0983 ms em READY +85,572 s, depois da rampa em aproximadamente +83 s. Pode contribuir ao frame, mas não demonstrou iniciar a rampa. A cobertura terminou 5,6 s antes do fim do gameplay. Native-blood-01 perdeu 143 eventos CLR: pares positivos valem como evidência; ausência não refuta a hipótese. CLR não substitui o perfil nativo do motor.

CPU/memória externa a 2 Hz identificou `ccusage.exe` do pacote npm, pai `node.exe`. Ancestrais históricos não foram recuperados: os pais já haviam saído. Em native-blood-01, um burst acumulou 62,6 CPU-s. Working set subiu de aproximadamente 13 MB para 8,4 GB e private para 18,5 GB em cerca de 0,5 s; memória disponível caiu de 20,9 para 9,2 GB e commit subiu de 27,9 para 49,8 GB. Rampa em +107 s precedeu GC em +108,071 s. Várias rodadas G/H também têm bursts; há pausas com CPU total do Godot sem avanço em brackets de 500 ms. Competição externa permanece hipótese: não houve intervenção causal nem encerramento de processo externo, controle de sessão concorrente ou alteração de política, afinidade e energia.

ABBA inicial reproduziu travadas com sondas OFF. Self-timing de aproximadamente 76 µs/frame, cerca de 1%, é limite inferior. Escritas de até 919 ms em outra thread não demonstraram bloquear a principal. Logger, boundary, captura, signal/pin e coletor externo têm escopos distintos; parcelas inclusivas não foram somadas ou subtraídas para fabricar FPS. W2 mediu signal/entity/pin combinados de 367/179 µs nos frames seguintes às duas ocorrências, sem pin exclusivo. Hooks: 282 µs em 154 chamadas; context: 1,261 s em 17608 chamadas; CPUv3: aproximadamente 1,562% de um core. Custos finais ON/OFF e limites estão adiante.

Profiler GDScript oficial: 9907 perfis consecutivos, sem gaps ou duplicatas; limite de 512 métodos pode truncar cobertura e receptor custou 11,76% de um core. Motocross tinha self de 76,784 ms, enquanto a criação do Skate começava 78,992 ms depois do início do tick. Skate/Footbridge foi refutado como gatilho daquele frame; preload Digo forneceu a contraprova causal. Callbacks GDScript/C#, desenho de parede e spans físicos foram separados. Solver, processamento nativo, flush e esperas continuam sem atribuição. Endpoints em E-cores foram raros, abaixo de 0,1% do gameplay, e ausentes nas recuperações analisadas; migração persistente não foi demonstrada. Cycles/wall não foram interpretados como GHz.

Na integração final ON1, a rampa começa em READY +93,786676 s: um tick sobe de 6,518 para 8,701 e 13,315 ms, enquanto draw sobe de 3,170 para 4,968 e 7,063 ms. Pessoas/veículos/unidades ficam em 26/36/5, sem criação/liberação nos três frames. Dois passos e 52 criações aparecem depois. O coletor externo também executa sua consulta de 50,845 ms nessa transição, com proveniência de 36,022 ms, sobrepondo o precursor. Sua contribuição não foi isolada e não pode ser descartada. A atividade ccusage em recovery e a pressão de memória são hipóteses; nenhuma delas recebe atribuição causal exclusiva.

As duas ON usam ClockAnchor pareado QPC/Godot/FILETIME. OFF conserva timestamps de frames e eventos, porém ClockAnchor/TID/counters internos vazios. O alinhamento OFF com CPU externa usa UTC nominal, com limite de erro desconhecido; permite apontar fases/brackets aproximados, sem medir agendamento de um frame. A pausa OFF de 1203,039 ms tem um bracket de aproximadamente 500 ms sem avanço de CPU em nenhuma thread Godot. Os picos de draw de 52–61 ms em ambas ON também permanecem. Nenhuma dessas assinaturas foi declarada resolvida pela correção de sangue, rota ou geometria.

[Resumo nativo alinhado](../../evidence/intermittent-stalls-20261004/continuation-native/native-blood-01-native-summary.md), [preflight WPR](../../evidence/intermittent-stalls-20261004/native-capture-readiness.md), [segunda tentativa UAC](../../evidence/intermittent-stalls-20261004/continuation-native/native-blood-01-uac-launch.json), [CLR/JIT](../../evidence/intermittent-stalls-20261004/continuation-native/clr-alignment-analysis.json), [auditoria final de sangue/startup/CPU](../../evidence/intermittent-stalls-20261004/continuation-native/final-current-causal-summary.md).

## Estado causal atual

| Assinatura | Evidência causal e uma variável | Correção e alcance | Pendência |
|---|---|---|---|
|Append/readback repetido de caixas dos ônibus|Dois controles/dois candidatos anteriores reproduziram a redução por arrays unitários CPU; geometria/batches/UV/normal/tangente e conservação verificadas|StaticBoxBatch e dois callers integrados; redução específica validada|Não elimina outros custos de construção nem todas as primeiras frames|
|Primeira resolução privada C# da rota terminal|Plan frio 28,671 ms: 201 pares JittingStarted→MethodLoadVerbose da mesma thread intersectam a chamada, união de intervalos 22,8439 ms; próximas plans 0,404/0,360 ms têm zero pares JIT; sem GC/Suspend nessa janela|Resolver e reter a mesma Curve da rota real sob a cortina. A1/A2 route interativa 32,135/25,358 ms → B1/B2 0,007/0,008 ms, com prepare 36,563/25,409 ms registrado em loading, C# ativo|União JIT é parede inclusiva, não CPU exclusiva; o residual de 5,8271 ms daquele plan não ficou atribuído. Frame terminal completo ainda lento|
|Primeiro load de DigoAmarok no callback Motocross|A1/A2 load 92,463/69,146 ms, Digo ausente e nenhum carro criado; o load era executado antes das guardas mesmo longe. C1/C2 alteraram só a retenção/preload e registraram acesso de 0,003 ms, update 0,052/0,067 ms e frames 5,663/6,350 ms. Rota continuou cara nos C, e Digo continuou caro nos B|Mesmo Script mantido por const preload, só dois hunks de Motocross. Causa interativa específica validada; contratos Digo 64 checks pelo controlador|Custos de parse/dependências passam a loading e permanecem no registro. C1 loading alto não foi repetido em C2; não atribuí-lo automaticamente à correção|
|Dezesseis readies de passageiros com cache frio|B1/B2 readies 19,971/18,386 ms, 46/38 misses; G1/G2 zero misses/uploads dentro do build e readies 5,107/4,600 ms. Wardrobes/cortes/RNG e geometria idênticos em contratos independentes|Preparar somente cortes imutáveis KIT dos IDs 80–95, antes da cortina abrir. Nenhum Actor/Coach/Gate antecipado, sem timer ou RNG global novo|Prewarm ativo 19,596/18,644 ms, slices com budget suave de 4 ms, maior 6,110/5,872 ms. Frame terminal G ainda 35,824/35,703 ms|
|Quatro corpos visuais estáticos repetidos|G1/G2 coaches 13,675/11,742 ms → H1/H2 5,067/5,214 ms; model_ready 5,851/4,744 → 2,617/2,674 e batch_body 7,125/6,403 → 1,858/1,907 ms inclusivos. H tem uma montagem cold e exatamente três reuse, cada soma reuse 0,225 ms|Sete ArrayMeshes completos do primeiro coach compartilhados; somente as três montagens seguintes evitam caixas temporárias. Materiais, rodas, labels, portas e colisões próprios. 41 contratos de equivalência/isolamento + lifecycle 5 + gates 10 passaram; os dois arquivos mínimos portados têm backups preservados|Duplicação específica corrigida em duas repetições; frame terminal 30,699/37,749 ms ainda tem residual 15,620/22,178 fora de callbacks/draw. Não declarar resolução do frame inteiro|
|Primeiro material de sangue e recriação após zero stains|S2 focado mediu material_override 25,311/18,644 ms. W2 preservou 14 parents/seq 0..13/drop0 e primeira/recriação0→1 com setter 0,015 ms, allocate 0,103 ms; getter positivo 18,317 ms está registrado em loading. As duas ON finais retiveram 17/29 parents, primeira/recriação allocate 0,079/0,081 e 0,082/0,081 ms, template vivo/ID estável|Um material template imutável por dono retido desde _ready, mantendo os materiais próprios das manchas e nenhuma criação antecipada de nós/stains. Port mínimo e 1022 contratos atuais passaram; operações inicial e após zero foram repetidas na integração|W1 perdeu primeira/recriação no ring; a prova positiva vem de W2 e das duas ON finais. Getter 18,719/20,360 ms permanece em loading. Não atribuir tempo exclusivo a GPU/pipeline/JIT nem a frame inteira ao setter|

O port live em [manifesto](../../evidence/intermittent-stalls-20261004/production-startup-integration-manifest.json) preservou os arquivos concorrentes via backups integrais. A [revisão independente](../../evidence/intermittent-stalls-20261004/production-startup-independent-review.md) conferiu quatro hashes before/after e três novos arquivos e não encontrou bloqueio no escopo medido. Não se portaram wrappers diagnósticos de Digo/CivilianModel/router. A preparação da rota/cortes conserva timers, identidade/persistent_id, quatro coaches/dezesseis passageiros/duas gates, running/resident e admissão atômica posterior. A mesma sequência de RNG local e overrides foi conservada; global RNG e recursos visuais equivalentes foram testados. Rota respeita o contrato existente de invalidação por identidade/contagens/extremos do grafo; mutação interna mantendo essa assinatura e auditoria de todos os cruzamentos continuam fora da cobertura.

## Linha do tempo dos gatilhos, sem chamar os iniciais de aquecimento

Tempos usec são monotônicos do processo correspondente; READY+ é alinhamento da mesma coleta. Não comparar tempos absolutos de processos diferentes. Cada causa abaixo já ocorre com um passo, antes de eventual catch-up; pais/filhos não são somados.

| Coleta/frame | Monotônico / relativo | Assinatura e contexto | Contraprova/limite |
|---|---|---|---|
|net-diagnostic-02 f728|23300178→23328849 usec|Primeira plan privada C# 28,671 ms, thread principal 27268, 201 pares JIT intersectam a chamada|Próximas duas plans sem pares JIT. CLR cobre READY−18,9918→+36,0257 s, não recuperação|
|A1 f741|build 25103474→25171132 usec; READY+0,549005 s|Frame 86,800 ms, um passo69,418 ms; build 67,658, rota 32,135, coaches 13,219 e readies 21,378 (níveis inclusivos distintos)|B1 rota 0,007; terminal frame 47,794 ainda tem readies/coaches|
|A1 f819|Digo 25707847→25800405 usec; READY+1,153378 s|Frame 98,689 ms, um passo94,924; update 92,558 contém load 92,463, Digo ausente/carrosnull. Skate é criado depois do load|C1/C2 mesmo evento inicial tem frame 5,663/6,350. Coincidência do Skate não demonstra seu custo|
|A2 f570|build 23617260→23677804 usec; READY+0,547115 s|Build 60,544 ms, rota 25,358, frame 79,805|B2 route 0,008, prepare 25,409 preservado antes de READY|
|A2 f657|Digo 24189211→24258457 usec; READY+1,119066 s|Update 69,246 contém load 69,146; frame 75,690|C2 acesso 0,003. Nenhuma atribuição genérica a JIT/GC desse load GDScript/resource|
|G1 f535|build 28455847→28475584 usec; READY+0,457167 s|Build 19,737, passageiros 5,107, coaches 13,675; frame 35,824 e tick 21,197|Misses de passageiros zerados; frame inteiro permanece acima de33,3|
|G2 f640|build 24023903→24041077 usec; READY+0,548488 s|Build 17,174, passageiros 4,600, coaches 11,742; frame 35,703, um tick 18,836, draw parede2,304, residual 14,563 fora de ambos|Residual não atribuído a solver/processamento/agendamento/espera. Compartilhar coaches não comprova eliminar essa parcela|
|G2 f575, urbano inicial|Ver detalhe bruto preservado|Frame 83,437, dois ticks37,939/1,528, draw 10,883 e residual 33,087|Primeira apresentação urbana continua aberta; G1 teve episódio571,566 ms que também permanece no registro|

H1/H2 first_terminal_build f655/f555, READY+0,566253/+0,530648 s: build 10,658/10,721 ms, um tick 12,581/12,666 e frame 30,699/37,749 ms. Loading 18,949/18,816 s; zero misses de passageiros e readies 4,659/4,654 preservados. H2 mantém pausa global1709,388 ms, distinta do frame terminal; seus brackets de CPU e limites estão abaixo, sem causa exclusiva demonstrada. Counts detalhados/plataformas/quantis 120 s estão consolidados na comparação causal dos coaches. Na integração final, build 11,621/10,604 ms, rota 0,009/0,008 ms, coaches 5,610/5,334 ms e readies 5,030/4,420 ms conservaram os ganhos; as frames do build medem 19,365/24,090 ms. Picos vizinhos de apresentação/desenho e a rampa posterior persistem. Sangue tem repetição positiva inicial/recriação nas duas ON; sua atribuição é ao custo da operação, sem inferência por pipelines.

## Comparações finitas e quantis atuais

Ordem previamente definida A1/B1/C1/A2/C2/B2, uma variável por braço; depois G1/G2 comparados a B1/B2. Main renderizada normal, Foundry107→180→107, eventos 30 s e recuperação 30 s. Primário 120 s; loading e tail 3 s registrados separadamente. População solicitada40, renderer Mobile1920×1080, settings/seed iguais, física 60 Hz e teto 3 original preservado. APPDATA/LOCALAPPDATA isolados, --no-save e somente settings pessoais copiados. Quantis pooled abaixo vêm de todos os frames dos dois runs, sem média de percentis nem subtração do observador.

| Braço / frames 120 s | p50/p95/p99 ms | Máximo ms | >33,3 / frequência por s | >66,7 / frequência por s |
|---|---:|---:|---:|---:|
|A controles /30645|5,905/13,942/18,443|983,078|116 /0,483|25 /0,104|
|B rota /32749|5,569/13,548/17,073|1260,626|97 /0,404|19 /0,079|
|C Digo /31193|5,858/14,353/16,686|718,486|69 /0,287|15 /0,062|
|G cortes passageiros /32770|5,821/13,201/14,784|105,466|63 /0,262|11 /0,046|
|H corpos compartilhados /30372|6,115/14,588/17,257|1709,388|95 /0,396|22 /0,092|
|Finais ON /33844|5,588/12,880/14,820|102,204|57 /0,237|18 /0,075|

O pool G tem mean7,32456 ms versus B7,32937 ms e p50 maior; isso impede transformar percentis de cauda menores em causalidade global. O pool H tem mean7,90295 ms e cauda maior: p99 14,784→17,257, frames>33,3 63→95 e >66,7 11→22. A cauda global observada piorou, apesar da redução causal reproduzida nos quatro coaches; não há aprovação global nem atribuição desse aumento ao cache sem discriminar carga/tempo externo. H1/H2 primário 120 s têm 8/87 frames>33,3; o tail H2 tem um adicional, registrado separadamente. As condições de carga externa variaram. A1/B1/C1/A2/C2/B2 têm loading 19,412/19,514/26,235/18,684/18,855/18,931 s; maiores intervalos7975/7981/15135/7725/8005/7791 ms. O excesso C1 não se repetiu. G1/G2 loading 23,530/18,952 s; cerca de 19 ms ativos de prewarm não explicam os4–5 s extras G1. Loading/picos iniciais ficaram registrados, sem descartá-los como aquecimento nem ocultar trabalho movido sob a cortina.

Conservação H1/H2: quatro plataformas0–3, dezesseis IDs80–95 e eventos de criação4 coaches/16 passageiros/2 gates em ambos. Append/free248→62 e commits28→7; três reuse reutilizam21 batches em cada candidato. Model_ready cria79 filhos no cold e17 nos warm, e depois os sete batches completam o mesmo total final24; nenhum corpo ou passageiro é admitido antes. Mask/layer não são emitidas nesses spans; sua equivalência é evidência dos contratos físicos, não um contador por-frame inventado. Deltas runtime versus G1 são somente CoachModel/TerminalCoach, além de três novos arquivos de teste/fixtures; G1/G2 têm hashes idênticas. Todos os quatro validity passaram, zero drops retidos/overflow/mismatches. WINDOW logger em13 janelas/run teve p95 máximo0,421/0,422/0,424/0,428 ms e maior callback1,279/1,314/1,194/1,742 ms (G1/G2/H1/H2); writer sem perdas. Context/input self custou0,886%/0,095%,0,902%/0,099%,0,839%/0,090%,0,866%/0,096% do tempo total medido, respectivamente. São custos mínimos/escopados; não se subtraem dos frames.

## Carga externa, observadores e cobertura

O telemetry2 Hz observa bursts de ccusage com aproximadamente64–70 CPU-segundos e pico de12–15,5 cores equivalentes somados entre threads durante A1/A2/C2/B2. B1 não teve atividade desse processo observada; C1 teve burst somente em loading, sobrepondo o maior intervalo. Isso é confusão observada para a comparação global, não demonstração da causa de cada frame: não houve intervenção nesse processo e brackets 500 ms não resolvem scheduling de um frame. Na pausa A2 de 983 ms, um bracket de aproximadamente 500 ms tem CPU Godot totalzero, distinta das sequências com execução lenta dos callbacks. Ready e Waiting não derivam desses contadores.

Telemetry externo custou1,141/1,295/1,179/1,384/1,211/1,449 % de um core nos seis runs; querywall p95 8,494/6,901/7,485/8,941/9,207/7,866 ms. Esses custos pertencem ao observador externo, permanecem incluídos na condição e não são adicionados aos callbacks nem subtraídos dos FPS. A1 tinha guardFILETIMEv1; os seguintes usam GetExitCodeProcessv2, mesma cadência/counters e sem encerramento prematuroA1. Cobertura começa antes de READY e termina +124,4..125,1 s. Processos protegidos/inacessíveis ou breves limitam enumeração. Manter as medições ABBA originais de observadores; estes counters complementam, não substituem aquela contraprova.

Na comparação G/H, ccusage consumiu67,969 CPU-segundos sobretudo em loading G1 (READY−13,750→+0,247 s),64,750 em G2 (+45,203→58,710 s), e65,344/66,156 em H2 (+27,183→40,670 e+74,182→88,181 s); H1 não teve CPU positiva observada desse processo. Isso confunde a atribuição global dos quantis. O pico H2f11966, READY+80,526 s,1709,388 ms, tem dois brackets de aproximadamente 500 ms com CPU zero em todas as threads Godot; H2f6901,+34,570 s,827,475 ms, contém outro. O segundo callback físico de822,842 ms mede parede que inclui esse intervalo sem execução observada, não822,842 ms de CPU do solver. São signatures distintas de callbacks progressivamente mais lentos. Não houve intervenção externa nem identificação nativa de Ready/Waiting, e o coletor não resolve cada frame. G2f8508,+40,612 s,82,055 ms, precede o burst ccusage; o processo não explica todos os picos. Coletor G1/G2/H1/H2 custou1,139/1,174/1,342/1,351 % de um core e querywall p95 7,125/7,265/6,907/9,317 ms, incluídos na condição. A [análise CPU independente dos coaches](../../evidence/intermittent-stalls-20261004/terminal-coach-external-cpu-summary.md) conserva brackets e identidade PID/start/QPC.

As seis rodadas e G1/G2 têm validity exit 0, fontes estáveis e sem errors. Probes armados antes de Main conservam loading, windows±3 s, picos>=25 ms e todos os frames para métricas; ring_overflow/dropped_details/tick_mismatches/CPUinválida zero nos summaries analisados. Dados de work são selecionados pelo ring, inclusivos e com limites por intervalo; counts retidos não significam censo global de chamadas. Sem soma de pais/filhos. Draw parede não é GPU exclusivo, residual não é solver exclusivo e amostras GetThreadTimes de15,625 ms não separam executar/pronto/esperando.

CLR alinhado teve EventsLost 0 e payloaderrors 0 no primeiro plan; sem GC/Suspend nessa janela específica. A atribuição inclui RoadGraphSearch/MinHeap e pontes Godot/coleções, não somente um método. Eventos .NET não substituem perfil nativo do motor. As duas tentativas UAC foram canceladas e não produziram ETL nativo válido; estados executar/pronto/esperando e símbolos/stacks do motor continuam sem cobertura. O perfil de script/CLR e os counters positivos não preenchem essa lacuna.

A [síntese causal do sangue](../../evidence/intermittent-stalls-20261004/continuation-native/ground-blood-causal-summary.md) localizou o setter material_override lento em S2 e a antecipação/retenção em W2. O template prepara/get_rid em loading 18,355 ms, sem antecipar stains; em W2 a primeira0→1 tem frame 6,663/tick 3,160 ms e a recriação0→1 frame 13,354/tick 7,181 ms. Isso não torna os frames exclusivos desse setter. W2 reteve os 14 parents e respectivos filhos; contexto±3 s da recriação perde somente o frame que cruza o início,4,629 ms após o limite, preservando a operação. Onze hooks diagnósticos somaram282 µs em154 chamadas, sem begin/parent/dispatch/pin; não foram portados para produção. State/CLR/profiler estavam OFF em S2/W1/W2; CPU externo2 Hz custou1,695/1,557/1,562 % de um core e querywall p95 10,273/10,467/9,197 ms. A melhora global também se confunde com bursts externos distintos. O diagnóstico CLR anterior do sangue teve143 eventos perdidos; positivos continuam úteis, ausência de GC/JIT não prova completude. Essa perda não se refere ao primeiro plan comEventsLost0. Depois das duas tentativas UAC canceladas não há ETL nativo válido para estados de agendamento.

Após os ports live, audit_evidence executou uma vez os12 contratos dirigidos no projeto atual:1233/1233 checks, todos exit 0, stderr vazio, sem retry. Harbor.csproj compilado antes com zero avisos/erros; rota exige e confirmou três plans C# reais. Preparação de cortes conserva oito nós antes/depois e zero admissão. Os30 hashes registrados antes/depois ficaram estáveis; saves isolados. [Resultados e limites dos contratos atuais](../../evidence/intermittent-stalls-20261004/final-current-contracts-summary.md). Headless valida esses contratos, sem substituir a medição renderizada final.


## Caixas dos ônibus: contraprova inicial preservada

[StaticBoxBatch.gd](../../runtime/transit/StaticBoxBatch.gd) reaproveita arrays de uma caixa unitária para alimentar os mesmos SurfaceTools. [TerminalCoach.gd](../../runtime/terminal/TerminalCoach.gd) e [BiarticulatedModel.gd](../../runtime/transit/BiarticulatedModel.gd) passam tamanho/transform originais e conservam índices, normais, tangentes e UV. Outros meshes/subdivisões/flip/UV2 mantêm fallback. Rodas, labels, portas e colisões continuam independentes; população, horários, inputs e ciclo de vida não foram alterados.

Os spans adicionais em UrbanBusService/BiarticulatedBus/TerminalOperations/TerminalRoutes/TerminalCoach/BiarticulatedModel medem os caminhos implicados. Timestamps internos são zero com StallWorkTrace desligado. Pais/filhos são inclusivos e não são somados. A primeira aquisição unitária permanece dentro da primeira passagem: máximo individual 0,670/0,521 ms nas candidatas. Nenhum custo foi transferido para loading como solução.

| Custo disjunto/inclusivo identificado, ms | Controle 1 | Controle 2 | Candidata 1 | Candidata 2 |
|---|---:|---:|---:|---:|
| Append terminal, 248 operações disjuntas | 39,006 | 39,315 | 2,521 | 2,367 |
| Batch completo dos quatro coaches | 45,811 | 46,175 | 6,470 | 6,086 |
| Build terminal completo | 105,293 | 102,233 | 62,930 | 64,686 |
| Append urbano, 176 operações disjuntas | 28,970 | 27,970 | 2,324 | 2,241 |
| Loop append/free dos seis modelos urbanos | 32,184 | 31,225 | 3,704 | 3,661 |
| Build urbano completo | 46,708 | 45,767 | 17,968 | 18,342 |
| Primeiro plano privado C#, permanece | 30,236 | 26,926 | 28,216 | 31,179 |
| Ready dos dezesseis passageiros, permanece | 20,298 | 20,339 | 19,387 | 19,222 |

Mantidos 4×62 caixas/4×7 batches no terminal e 2×(34+26+28) caixas/2×(7+5+6) batches no urbano. Primitivas, model_ready, poses e commit não acompanham a queda de append; commit total fica <0,8 ms por família. A redução acompanha o tick contendo o build, sem menos entidades ou menor simulação. Esse A/B demonstra o componente corrigido; não separa dentro da API o tempo de motor/driver/sincronização.

O [código oficial de PrimitiveMesh](https://github.com/godotengine/godot/blob/master/scene/resources/3d/primitive_meshes.cpp) mostra que trocar cada `append_from` por `get_mesh_arrays()` individual continua usando `surface_get_arrays`; essa alternativa foi rejeitada por leitura. A intervenção reutiliza arrays. A equivalência foi conferida no motor instalado, comparando com o caminho antigo, inclusive ordem/índices e transform espelhado. Fonte master auxilia a hipótese, não substitui perfil nativo nem símbolos correspondentes ao binário.


## Validação final da integração e custo das sondas

Três capturas prospectivas ON1/OFF1/ON2 terminaram válidas e focadas durante gameplay, com o mesmo snapshot independente, sistemas normais, população configurada 40 e a rota definida. Primário 120 s; loading e tail 3 s permanecem separados. Nenhum novo jogo ou retry foi executado para esta análise. Quantis pooled foram recalculados sobre os frames, sem média de percentis ou subtração de overhead.

Loading aqui começa quando o medidor é armado antes de Main. A inicialização anterior do processo/motor não tem série de frames interna nessa captura e continua uma lacuna; não foi classificada como aquecimento. A janela anterior aos primeiros picos de loading é limitada pelo início da própria observação, portanto pode ter menos de três segundos. Nas quatro operações de sangue auditadas ao final, as janelas de três segundos antes/depois estão completas. Os brutos e a linha do tempo conservam essas fronteiras.

|Gameplay 120 s|Frames|s|p50/p95/p99 ms|Máximo ms|>33,3 ms / Hz|>66,7 ms / Hz|
|---|---:|---:|---:|---:|---:|---:|
|final-current-on-01|16273|120.020|5.586/12.807/15.848|87.052|50 / 0.417|13 / 0.108|
|final-current-off-01|16631|120.002|5.766/12.743/14.694|1203.039|13 / 0.108|5 / 0.042|
|final-current-on-02|17571|120.017|5.590/12.911/14.078|102.204|7 / 0.058|5 / 0.042|
|Pool duas ON|33844|240.036|5.588/12.880/14.820|102.204|57 / 0.237|18 / 0.075|

|Rodada/fase|Frames|s|p50/p95/p99 ms|Máximo ms|>33,3 ms / Hz|>66,7 ms / Hz|
|---|---:|---:|---:|---:|---:|---:|
|final-current-on-01/loading|659|20.749|2.471/67.660/138.670|8912.497|53 / 2.554|35 / 1.687|
|final-current-on-01/first_pass|5574|30.010|4.252/9.367/11.219|87.052|6 / 0.200|2 / 0.067|
|final-current-on-01/return|4100|30.001|5.543/11.753/12.866|40.348|2 / 0.067|0 / 0.000|
|final-current-on-01/event|3660|29.999|6.332/12.414/13.517|26.937|0 / 0.000|0 / 0.000|
|final-current-on-01/recovery|2939|30.009|10.804/15.313/38.620|79.084|42 / 1.400|11 / 0.367|
|final-current-on-01/tail|393|3.000|5.507/11.728/12.398|13.378|0 / 0.000|0 / 0.000|
|final-current-off-01/loading|605|18.733|1.976/64.847/114.948|7739.229|53 / 2.829|28 / 1.495|
|final-current-off-01/first_pass|5314|30.002|4.137/9.851/17.877|1203.039|13 / 0.433|5 / 0.167|
|final-current-off-01/return|4601|29.999|4.967/10.992/12.449|31.971|0 / 0.000|0 / 0.000|
|final-current-off-01/event|3439|30.002|9.597/13.623/15.024|27.250|0 / 0.000|0 / 0.000|
|final-current-off-01/recovery|3277|29.999|10.876/13.110/13.995|25.684|0 / 0.000|0 / 0.000|
|final-current-off-01/tail|360|3.010|9.845/11.973/12.442|13.450|0 / 0.000|0 / 0.000|
|final-current-on-02/loading|550|23.727|2.896/90.053/176.086|8015.373|58 / 2.444|43 / 1.812|
|final-current-on-02/first_pass|6379|30.011|3.729/8.534/10.212|102.204|5 / 0.167|5 / 0.167|
|final-current-on-02/return|4854|30.003|4.706/10.613/11.813|41.157|1 / 0.033|0 / 0.000|
|final-current-on-02/event|3138|30.002|11.254/13.692/15.245|27.508|0 / 0.000|0 / 0.000|
|final-current-on-02/recovery|3200|30.001|11.116/13.450/14.376|38.654|1 / 0.033|0 / 0.000|
|final-current-on-02/tail|314|3.001|11.496/13.372/13.637|14.550|0 / 0.000|0 / 0.000|

As duas ON conservam os ganhos locais reproduzidos nos experimentos anteriores; os números globais acima não aprovam todas as assinaturas. Os maiores picos, rampas e variação de carga continuam no registro. Loading não foi descartado como aquecimento nem ocultado no primário.

|ON / primeiro terminal|Build ms|Rota ms|4 coaches ms|16 readies ms|Frame ms|Tick / draw / residual ms|
|---|---:|---:|---:|---:|---:|---|
|final-current-on-01|11.621|0.009|5.610|5.030|19.365|13.187 / 1.831 / 4.347|
|final-current-on-02|10.604|0.008|5.334|4.420|24.090|12.145 / 2.031 / 9.914|

As duas ON registram plataformas 0–3, identidades 80–95 e create_ready positivos 4 coaches/16 passageiros/2 gates; append/free 62/62, commits 7 e reuse 21 batches em três coaches. Todos os três plans privados por ON usam C# ativo, e o router do mundo está ativo ao final dos três braços. O falso inicial do router do mundo é inicialização lazy e não exclui a instância privada do terminal. OFF não conserva seus plans individuais; engine/build, flags e estado final são evidência positiva de C#, sem inventar uma medição dos plans ausentes.

|Rodada|Context/input self % total|Boundary/capture/signal retidos µs|WINDOW logger p95 máximo / callback máximo ms|Detalhes / pins|
|---|---:|---:|---:|---:|
|final-current-on-01|0.903 / 0.102|681433 / 204176 / 40239|0.424 / 1.570|11089 / 17|
|final-current-off-01|0.000 / 0.152|0 / 0 / 0|0.424 / 1.260|0 / 0|
|final-current-on-02|0.871 / 0.098|734433 / 219388 / 43528|0.422 / 1.316|12642 / 29|

Self timings são limites inferiores: excluem begin/finish de work, dispatch e parcela imposta ao motor. Totais de boundary/capture/signal pertencem somente aos detalhes retidos. Quantis WINDOW são por janela, sem fingir um p95 global; writer sem registros perdidos. OFF conserva StallLog normal, input e CPU externo 2 Hz, e desliga contexto circular/thread/work/pins. Um braço OFF e carga variável limitam a atribuição: diferenças globais entre ON/OFF são inconclusivas como custo causal do observador. Nenhum tempo foi subtraído dos FPS.

|Rodada / estado final|Pessoas|Veículos|Unidades|Stars|Física ativa / pares|
|---|---:|---:|---:|---:|---:|
|final-current-on-01|24|34|6|3|44.0 / 276.0|
|final-current-off-01|29|39|4|3|51.0 / 291.0|
|final-current-on-02|24|34|6|3|47.0 / 257.0|

População configurada idêntica não torna a carga instantânea idêntica: os estados finais acima diferem. Contextos por fase e bins de 10 s estão no JSON, são amostras retidas tendenciosas aos picos. OFF não tem contexto circular; os poucos estados/eventos finais não sustentam igualdade de carga em toda a rota. O input normal alcançou x≈179,043 e retornou a≈107,992 em todos, sem teleporte durante gameplay. Física 60 Hz/teto 3 e intenção visual/gameplay preservados; esse teto já era anterior e não foi a intervenção.

|Rodada / maior pico gameplay|Frame / fase|READY+s|Frame ms|Passos|Ticks / draw / residual ms|
|---|---|---:|---:|---:|---|
|final-current-on-01|4571 / first_pass|21.278|87.052|3|5.645 / 3.690 / 4.219; draw 52.454; residual 21.044|
|final-current-on-01|706 / first_pass|0.569|85.969|3|2.377 / 1.672 / 1.891; draw 60.849; residual 19.180|
|final-current-on-01|14452 / recovery|94.828|79.084|3|20.614 / 16.111 / 13.912; draw 12.019; residual 16.428|
|final-current-on-02|617 / first_pass|0.617|102.204|3|2.587 / 1.513 / 1.543; draw 52.480; residual 44.081|
|final-current-on-02|550 / first_pass|-0.009|92.298|3|46.139 / 2.305 / 1.100; draw 7.310; residual 35.444|
|final-current-on-02|5574 / first_pass|22.992|78.756|3|8.843 / 6.143 / 4.113; draw 53.275; residual 6.382|

A recuperação ON1 reproduziu a rampa: 42 frames acima de 33,3 ms e 11 acima de 66,7 ms, contra somente um frame acima de 33,3 ms na recuperação ON2. No bin READY+90–100 s, ON1 tem 28 frames com dois passos e 28 com três; p95/p99 de frame 33,927/67,855 ms. Os 410 callbacks retidos de um passo desse bin têm p50/p95 6,129/8,169 ms e máximo 13,315 ms, sem considerar isso distribuição de toda a simulação. OFF não reproduziu essa recuperação, porém conservou uma pausa de 1.203,039 ms na primeira passagem. Ausência de uma família numa repetição não demonstra sua eliminação. Os bins de 10 s preservam os callbacks de um passo antes/depois das rampas e os counts de 2/3 passos; callbacks são parede, não CPU exclusiva. Catch-up amplifica atraso e não identifica o primeiro gatilho. Pre/post_draw não é GPU exclusivo. Contadores por thread não separam executar/pronto/esperar. OFF possui métricas de todos os frames e zero detalhes por desenho: seus picos não podem receber decomposição retrospectiva.

As três validity têm exit 0, errors/invalid/source_changed vazios e zero perda de foco em gameplay. Todas as 1.641 hashes capturadas coincidem entre os três braços; o snapshot não teve drift durante a cópia. A conferência física posterior dos 30 arquivos de contracts-inputs confirmou as mesmas hashes before/live/snapshot, sem diferença. Destes, 29 constam da whitelist das capturas; RunStallContracts.ps1 não é incluído nesse censo de fontes, mas foi conferido fisicamente. Ausência da whitelist é limite de cobertura, não drift. Nenhum arquivo concorrente foi sobrescrito. O recibo final-live-source-state.json de 22:07:37 UTC confere ainda toda a whitelist de 1.641 arquivos live/frozen/capturados: zero diferenças ou ausências, world_edits SHA256 preservada. Essa whitelist não abrange todo arquivo do projeto. Os 12 contratos atuais passaram 1.233/1.233, sem retry, build Harbor.csproj 0 avisos/erros antes do Godot 4.7.2 .NET; os três plans C# reais foram requisito do contrato de rota. Isso valida a cadeia alterada, não toda cidade ou FPS global.

A análise independente do agente native_capture encontrou ccusage em ON1 READY+93,801→107,281 s, 63,375 CPU-segundos, sobrepondo a recuperação; ON2 teve 61,547 CPU-segundos somente em loading, READY−14,744→−1,282 s, e nenhuma CPU positiva desse processo observada em gameplay. OFF teve 63,391 CPU-segundos em READY+3,248→16,743 s nominal. O alinhamento OFF usa unix_seconds, com erro desconhecido porque ClockAnchor está vazio, e não equivale a um par Godot→QPC. Esses bursts em fases distintas e a população variável confundem a atribuição global da diferença ON/OFF ao observador. Não houve intervenção causal sobre ccusage. Coletor ON1/OFF1/ON2 custou 1,419/1,378/1,327% de um core e querywall p95 7,440/8,533/8,890 ms; CPU soma threads, sem inferir frequência ou estados Ready/Waiting. A auditoria dos pins de sangue/primeiro loading complementa este resultado. A conclusão de resolução permanece restrita às operações com evidência causal/repetição positiva; rampas, esperas/desagendamento, frames completos de terminal/urbano e loading continuam abertos.

Evidência numérica integral: final-integration-analysis.json; brutos final-current-on-01/final-current-off-01/final-current-on-02; final-current-contracts-summary.md e final-snapshot-state.json. Assinatura: audit_evidence; análise offline, nenhuma nova execução ou edição live/save.

## Pendências por assinatura

|Assinatura|Evidência/hipótese atual|Experimento discriminante seguinte|
|---|---|---|
|Rampa antes de acumular passos físicos|Custo de um passo e de múltiplas famílias cresce antes do catch-up; GC vem depois e CPU/memória ccusage se sobrepõem em várias rodadas|WPR elevado com stacks/CSwitch/ReadyThread, símbolos e perdas auditadas; uma intervenção controlada somente na carga externa identificada, sem encerrar trabalho concorrente por inferência|
|Pausas de centenas de ms a 1,7 s|Há brackets de 500 ms sem avanço de CPU em todas as threads Godot; draw/callbacks são parede, incluem espera/desagendamento desconhecidos|Mesmo evento/rota com perfil nativo; separar tempo executando/pronto/esperando e dono do wait; não reduzir física/população/qualidade|
|Frame terminal/urbano completo ainda lento|As operações de rota/geometria/batch caíram causalmente; residual fora dos callbacks/draw segue presente|Perfil do motor/solver/processamento/flush, sem somar pais e filhos nem rotular residual como solver|
|Loading inicial de vários segundos|Main.load custa 2860,513/2547,038 ms nas ON finais; instantiate 0,057/0,034 ms e add_child/ready síncrono 2,226/1,859 ms. Isso não explica todos os intervalos de 7–15 s nem continuações assíncronas de ready|Separar dependências carregadas e trabalho assíncrono do primeiro intervalo; testar uma variável, mantendo custos iniciais e perfil nativo|
|Spawn/desembarque policial histórico de 730,635 ms|Criação tier1 grande foi capturada, mas não reproduzida na família pequena posterior; otimização de kit não passa por esse caminho|Captura dirigida com etapas indivisíveis _ready/porta/desembarque e perfil nativo; uma rodada sem reproduzir permanece inconclusiva|
|Primeiro draw com material/geometria e recuperações não cobertas|Cache de recurso do sangue resolve atribuição/RID demonstrada, não todo draw de 53 ms nem driver/GPU|Perfil nativo/draw alinhado ao primeiro evento, cobertura/perdas e APIs compatíveis; pipelines sozinhos não comprovam compilação|
|Interferência do observador e cauda global|Custos positivos/escopados medidos; ON/OFF e carga externa/população variáveis limitam conclusão agregada|Usar comparação finita já coletada e seus limites; não subtrair overhead, repetir até favorável ou aprovar regressão confirmada|

Os 12 contratos são da cadeia alterada e suas transições/recuperação: não certificam toda cidade, interiores, iluminação, viabilidade de todo trânsito nem todo caos possível. Não há migração GDScript/C#, mudança de save pessoal, redução de qualidade/população, alteração de física ou ação sobre processos externos. Só as operações e assinaturas com repetição positiva descritas acima são consideradas corrigidas. As famílias remanescentes ficam abertas.

## Histórico auditado: 2–3 de outubro

Fonte principal: [auditoria de arquitetura e performance](performance-architecture-20261002.md). Evidências brutas ficam em `evidence/performance-implementation-20261002/` e `evidence/stall-logs/`. A leitura de 4/10 separa provas locais, episódios ainda abertos e limitações do protocolo; não transforma a última rodada suave em comprovação de eliminação.

### Correções já demonstradas e integradas

| Causa/contrato local | Evidência antes/depois | Limite da conclusão |
|---|---|---|
| Upload das marcas de pneus por segmento | 320 segmentos: método 949,09 → 416,29 µs; geometria, cor, fade e limpeza preservados | Redução de trabalho desse método; não explica todas as travadas |
| Malha intermediária/readback dos equipamentos policiais | 33 primeiras montagens: 62,960 → 29,803 ms somados; identidade em 646 checks/variante | O pico de 730,635 ms era tier1, que não usa a montagem tática otimizada |
| Construção repetida do SkateModel | 25 construções: 430,809 → 1,642 ms; pivôs por instância e recursos imutáveis compartilhados | Prova dirigida; o comparativo integrado posterior não criou skates na janela |
| Primeira apresentação de polícia/reação após configuração final do ambiente | Corpo policial: desenho 18,941 → 2,824 ms; balão: 26,494 → 1,870 ms; pipelines posteriores zerados nas fixtures cobertas | Primeiros usos desses modelos; contadores de pipeline não atribuem duração dos demais picos |
| Primeiros materiais compartilhados do interior | Controle/candidato com eventos em memória: maior frame 51,793 → 10,049 ms; pre→post draw 49,670 → 2,242 ms | Main renderizada com callbacks do mundo suspensos; não comprova correção do episódio de 1,4 s |
| Construção de porto sem malhas intermediárias e seleção conservadora de geometria | Builders: 8,667 → 5,832 ms; superfícies do chunk (3,3): 10,594 → 7,182 ms; identidade de malhas/colisão verificada | Trabalho local; o maior pico integrado do candidato não executou esses builders |
| Consulta booleana de sangue e marcas expiradas | Contato inicial: 43,575 → 1,114 ms/2.000 consultas; atualizações expiradas: 5,872 → 0,887 ms/100 chamadas | Contato final/ausente não melhorou; custo adicional durante fade preservado no relatório |
| Integridade de filhos da frota | Colisão de nomes reproduziu referências incorretas/órfãos/crash; nomes únicos legíveis passaram no ciclo de 264 checks | Causa de integridade/ciclo de vida, sem prova de ganho global de FPS |
| Logger, suspensão/retomada, reservas de cruzamentos e limites de persistência | Baselines funcionais falharam, candidatos passaram nos contratos descritos no relatório | Contratos funcionais não substituem medição renderizada nem eliminam gatilhos de engasgos |

As 24 integrações históricas têm provas de escopo diferente. As compactações econômicas, a recusa prévia de save grande e a recuperação de equipes/carcaças preservam contratos; não devem ser apresentadas como solução causal de assinaturas de frame sem correlação e contraprova próprias.

### Linha do tempo histórica dos episódios ainda abertos

| Coleta/frame/tempo | Assinatura e evidência | O que permanece sem atribuição |
|---|---|---|
| `before-chaos-fixed-aim`, ~99,08–101,51 s do StallLog | Vários frames 140–198 ms com 6–8 passos; corpos/pares relativamente estáveis | Gatilho anterior ao acúmulo; recuperação de física é amplificação medida |
| `remaining-chaos-diagnostic-before`, frames 7949–7956, ~11,518 s em diante | Passos/frame crescem 2→3→4; frame 7956: 131,011 ms, um passo 50,237 ms | Custo anterior ao maior spawn; cerca de 55 ms dos callbacks do frame 7956 sem cobertura dos três rótulos citados |
| Mesma coleta, frame 7957, terminando aos 12,854364 s | 908,821 ms; primeiro passo 747,120 ms; `officer.spawn:tier1` 730,635 ms dentro de ~735 ms do despacho | Caminho criação/desembarque demonstrado; não separa objeto, `_ready`, porta nem execução versus espera |
| Mesma coleta, frame 7958 e seguintes | 151,314 ms no 7958; oito passos, callbacks 105,218 ms, passos 10,692–15,802 ms | Recuperação posterior não pode ser confundida com o gatilho anterior |
| Mesma coleta, frames 8293/8673 | 148,029/159,166 ms; pre→post draw 94,207/83,893 ms; GPU viewport ~4,5 ms | Espera/sincronização/compilação/driver/agendamento continuam hipóteses; draw de parede não é GPU exclusiva |
| `remaining-spawn-boundaries`, ~21,26–23,51 s, frame 12000 | 154,041 ms; oito passos totalizam 123,610 ms; 29 pessoas, 39 veículos, quatro unidades, 17.807 nós; streaming ocioso | Sem spawn/policial a pé nesse intervalo; muitas chamadas menores e 31,839 ms dentro dos callbacks sem cobertura dos três rótulos disjuntos |
| Mesma coleta, spawns ~23,95/25,03 s, depois da sequência | Três spawns: `_ready` até 1,893 ms, desembarque até 12,902 ms | Não reproduziu 730,635 ms; não atribuir retroativamente à porta |
| `native-cpu-chaos`, frame 12495 | 92,159 ms; draw 54,590 ms; GetThreadTimes sem avanço nessa parte, ciclos +10,8 milhões; GPU 3,01 ms | Compatível com espera/desagendamento; resolução CPU 15,625 ms impede divisão exata por frame; nenhum spawn nos frames vizinhos |
| `diagnostic-wct-chaos`, frame 10122, 21,098856 s | 100,143 ms; draw 58,966 ms; quatro passos 8,778/8,244/8,149/7,899 ms; WarmUp e Surface +2 | WCT retornou somente Thread estado 3, sem cadeia de espera; 74 erros do logger invalidam aprovação FPS; nenhum novo GC .NET nessa janela |
| `live-warmup-identity-chaos-20261003`, frame 11082 | 1.397,965 ms; WarmUp Union criado 3,943 ms após início; pre→post draw 1.323,755 ms; Surface/Draw/Specialization constantes no intervalo | Coincidência de WarmUp não prova shader/driver; GPU 3,78 ms e render CPU 1,64 ms não explicam toda espera; outro WarmUp sport_coupe ficou em 14,296 ms |
| `live-physics-boundaries-chaos-20261003`, frame 12596 | 34,349 ms; um passo entre sentinelas 22,807 ms; draw 4,244 ms; pipelines constantes | Pico abaixo do filtro histórico de 40 ms; método/caminho nativo dentro do callback ainda desconhecido |

Fontes de atribuição: [diagnóstico restante](../../evidence/performance-implementation-20261002/remaining-diagnostic-analysis.md), [CPU/OS](../../evidence/performance-implementation-20261002/native-cpu-system-analysis.md), [WCT](../../evidence/performance-implementation-20261002/wct-chaos-analysis.md), [fronteiras físicas](../../evidence/performance-implementation-20261002/live-physics-boundaries-chaos-20261003/live-physics-boundaries-chaos-20261003-physics-boundaries.json). Tempos inclusivos de spawn/controlador e pais/filhos dos veículos não são somados.

O novo analisador foi verificado por leitura das séries históricas completas: coincidiu exatamente em frames, p50/p95/p99, máximo e contagens >33,3/66,7 ms com a janela medida de `live-physics-boundaries-chaos-20261003` (3.337 frames/30,00439 s; 10,210/13,422/15,030 ms; máximo 34,349; 1/0, ou 0,033328/0 por segundo). Preservou separadamente 1.170 intervalos iniciais: máximo 33,746 ms. Há sete picos ≥25 ms na série completa, incluindo cinco medidos abaixo de 40 ms: frames 11228/11297/11314/12596/14250, de 27,153/30,954/25,902/34,349/32,148 ms. O callback individual de 24,638 ms no frame 11297 também permaneceu visível. A diferença entre o máximo inicial das fronteiras e o medidor base vem das fronteiras do primeiro intervalo, não de descarte de aquecimento.

### Hipóteses rejeitadas ou restringidas por contraprova

- Reatribuir energia de faróis: 12 pares AB/BA não mostraram ganho consistente; candidato não integrado.
- Readback redundante de superfícies intactas nas portas: zero oportunidades nas três viaturas reais medidas; candidato não integrado. `_cut_part` ainda é indivisível e pode exceder o orçamento.
- Projeção de veículo exatamente imóvel: incidiu 28.948 vezes/30 s, total 151,040 ms, teto teórico de ~0,084 ms/passo; não explica espiral de 117 ms. Rotação exatamente repetida: zero oportunidades nessa coleta.
- Turbo supostamente desativado por `PROCTHROTTLEMAX=99%`: classe rápida tinha `PROCTHROTTLEMAX1=100%`; passos ruins nos núcleos rápidos e até 4.363 MHz em outra amostra. Nenhuma política de energia foi alterada.
- Primeiro prewarm de reação antes de glow: zerou Surface mas deixou Draw +1; foi corrigida a ordem de preparo após a configuração final, sem aprovar o primeiro candidato.
- Prewarm somente de vidros do interior: pausa ainda 65,134 ms; recurso não mantido como solução. Construção de spec/malha sozinha produziu 62,476 ms no frame seguinte, sem nó WarmUp.
- Somente coincidência de pipelines não prova compilação; contadores estáticos também não descartam preparação de materiais. Nenhuma exclusividade GPU/solver decorre de sinais pre/post_draw ou monitores máximos do segundo anterior.
- Processo OneDrive consumiu CPU durante telemetria de 1 Hz; isso demonstra carga externa, não que causou os picos específicos.

### Lacunas e observadores no início da investigação

WPR anterior não iniciou: `0xc5585011`, política de perfil do sistema, token sem `SeSystemProfilePrivilege`. O helper [capture-native-cpu.ps1](../../evidence/performance-implementation-20261002/capture-native-cpu.ps1) usa sessão própria, deadline 50–60 s e [perfil CPU/agendamento](../../evidence/performance-implementation-20261002/game-cpu.wprp) com CSwitch/ReadyThread/SampledProfile e stacks em buffers circulares de 256 MiB. Foi validado por parsing, não por ETL concluído. Cobertura, perda de eventos e símbolos compatíveis continuavam pendentes; símbolos PDB do Godot e ferramentas WPA/xperf/PerfView/dotnet-trace não haviam sido localizados. Escalação de sandbox não equivale a elevação Windows.

`measure_physics_boundaries` mediu custo próprio observado de ~0,779% da janela final, incluído nas métricas, sem cobrir todo o despacho do motor. Coletas com censo/agregação registravam apenas parte do overhead. A telemetria externa levava mediana de 54,02 ms de parede por consulta de 1 Hz e adicionava carga. Prints intermediários de fase coincidiram com 1.342,968 ms numa consulta de cache; retirados os prints, ela custou 27 µs. Essa interferência não prova retrospectivamente a origem de todos os picos no desenho.

No estado inicial de 4/10, `StallWorkTrace` principal mantém limite 256 e filtros por chamada; os agregados uniformes históricos existiam no snapshot. `DispatchTrace` continua filtrando <20 ms antes de encaminhar. `StallLog` retém somente detalhes dos frames ≥40 ms por padrão, sem janela circular com população/posição em cada frame. `ThreadCpuProbe` resolve contadores da thread, não pronto versus esperando. Qualquer coleta nova precisa preencher somente essas lacunas necessárias e medir o custo dos observadores.

### Estado de fontes no início de 4/10

Conferência por SHA-256 contra `live-physics-boundaries-chaos-20261003/source-hashes.json`: `runtime/StallLog.gd`, `StallWorkTrace.gd`, `StallLogWriter.gd`, os medidores `measure_performance_plan.gd`/`measure_physics_boundaries.gd`, `ThreadCpuProbe.cs`, `PoliceModel.gd`, `VehicleTireEffects.gd` e `SkateModel.gd` coincidiram. Os arquivos `VehicleInterior.gd`, `VehicleDoorBuilder.gd`, `Vehicle.gd`, `Driving.gd`, `World.gd`, `NativeRegion.gd`, `OriginalSouthPort.gd`, `VehicleDamage.gd` e os builders HarborRoadGeometry/HarborUrbanSurface diferem. São alterações concorrentes preservadas; as coletas antigas não certificam o conteúdo atual.

O diff corrente inclui cabines Digo/cupê e exclusão de peças autorais do recorte, empinada de motos/input, duração do fogo 3,5→10 s, propriedade única de pisos no porto e sombras de superfícies planas. Durante a leitura apareceu também edição nova em `FullSession.gd` e a documentação de empinada. Nenhuma dessas mudanças foi descartada. Atribuição a código novo exige hashes estáveis da rodada; diferenças de população, câmera, eventos e teto de passos tornam comparativos históricos inconclusivos para ganho global.

### Experimentos que discriminam as assinaturas

| Assinatura | Hipótese verificável | Experimento de uma variável |
|---|---|---|
| Pico antecedendo recuperação física | Callback curto distribuído, solver ou espera/agendamento fora dos spans | Mesma rota/carga/teto, capturar fronteiras e stacks nativos; observar primeiro frame da janela antes do crescimento, mantendo simulação normal |
| Criação/desembarque policial excepcional | Etapa indivisível em `_ready`, porta/readback ou espera | Primeira ocorrência com spans separados já existentes/dirigidos e nativo; somente após reproduzir, antecipar uma etapa e contraprovar em repetições finitas |
| Pausa no caminho draw com recursos novos | Primeira materialização/upload/compilação ou espera externa | Mesma família/ambiente final, mudar apenas preparação do recurso sob a cortina; preservar retorno e coletar stack/scheduling durante pausa |
| Streaming ao mover/retornar | Uma construção, colisão, material/malha ou descarte excede o orçamento | Rota produtiva primeira passagem/retorno; spans por unidade indivisível e filas; mudar só unidade demonstrada, mantendo entidades/colisão |
| Pico causado pelo observador | Serialize, stdout ou aquisição de contadores interfere | Par com mesmos sistemas/rota e apenas observadores opcionais ligados/desligados; custos incluídos, sem prints na janela e sem subtrair overhead para fabricar FPS |

Uma rodada sem a assinatura é inconclusiva. Reduzir teto de física é experimento de recuperação que exige avanço da simulação equivalente; não comprova eliminação do gatilho.


## Evidências e reprodução

- [Plano inicial de coleta](../../evidence/intermittent-stalls-20261004/continuation-plan.md), [experimentos seguintes](../../evidence/intermittent-stalls-20261004/follow-up-plan.md), [integração final](../../evidence/intermittent-stalls-20261004/final-validation-plan.md).
- [Matriz A/B/C](../../evidence/intermittent-stalls-20261004/initial-trigger-matrix-analysis.md), [passageiros](../../evidence/intermittent-stalls-20261004/terminal-geometry-causal-analysis.md), [coaches](../../evidence/intermittent-stalls-20261004/terminal-coach-cache-causal-analysis.md), [CPU externa dos coaches](../../evidence/intermittent-stalls-20261004/terminal-coach-external-cpu-summary.md).
- [ABBA dos observadores](../../evidence/intermittent-stalls-20261004/abba-observer-analysis.md), [contraprovas de batching](../../evidence/intermittent-stalls-20261004/causal-batching-analysis.md), [integração final completa](../../evidence/intermittent-stalls-20261004/final-integration-analysis.json), [sangue/startup/CPU final](../../evidence/intermittent-stalls-20261004/continuation-native/final-current-causal-summary.md).
- [Port inicial](../../evidence/intermittent-stalls-20261004/integration-manifest.json), [preparação de startup](../../evidence/intermittent-stalls-20261004/production-startup-integration-manifest.json), [corpos coaches](../../evidence/intermittent-stalls-20261004/production-terminal-body-integration-manifest.json), [material sangue](../../evidence/intermittent-stalls-20261004/production-blood-integration-manifest.json), todos com hashes/backups antes e depois.
- [1233 contratos atuais](../../evidence/intermittent-stalls-20261004/final-current-contracts-summary.md), [revisão independente](../../evidence/intermittent-stalls-20261004/production-startup-independent-review.md), [snapshot sem drift](../../evidence/intermittent-stalls-20261004/final-snapshot-state.json), [1.641 fontes atuais conferidas](../../evidence/intermittent-stalls-20261004/final-live-source-state.json).
- [Linha do tempo](../../evidence/intermittent-stalls-20261004/final-stall-timeline.md), [todos os 308 intervalos de pelo menos 25 ms](../../evidence/intermittent-stalls-20261004/final-stall-timeline.csv). Origem temporal READY, loading negativo preservado; spans correlacionados por timestamps monotônicos, inclusive quando entregues em frame posterior.
- [Runner](../../tests/measure/RunIntermittentStalls.ps1), [coletor circular](../../tests/measure/measure_intermittent_stalls.gd), [analisador](../../tests/measure/analyze_intermittent_stalls.py). Rodadas são preservadas sob evidence/intermittent-stalls-20261004; o runner recusa labels existentes, compila antes, isola userdata/no-save, audita hashes/foco/C# e aborta só processos próprios se houver motor concorrente.
