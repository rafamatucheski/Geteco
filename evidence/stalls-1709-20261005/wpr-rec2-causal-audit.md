# Auditoria do jogo e dos observadores — WPR rec2

A captura `stall1709-wpr-rec2` terminou válida, exit 0, sem mudança de fonte ou erro de runtime. Não reproduziu a assinatura histórica: **zero frames de gameplay ou cauda ≥250 ms e zero gaps ≥250 ms depois do último callback físico**. O maior gap desse tipo foi 6,246 ms, no f16862 de recuperação (frame de 24,348 ms). A pausa de 1.709,627 ms permanece sem causa demonstrada; esta rodada não implementou correção do jogo.

Esta é a primeira medição do lote WPR. Rec1 foi falha técnica de preparação, sem Game ou recording, conforme a [emenda prospectiva](D:/geteco/game/evidence/stalls-1709-20261005/recovery-wpr-plan.md). Os dados deste documento são extraídos do [bruto renderizado](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-wpr-rec2/stall1709-wpr-rec2.json), com [JSON causal](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-causal-audit.json) e [analisador reproduzível](D:/geteco/game/evidence/stalls-1709-20261005/analyze_wpr_rec2_causal.py). A cobertura e os estados contínuos ETL são auditados separadamente pelo agente nativo; status saved não os comprova.

## Métricas e fases

Percentis e frequências usam todos os frames, sem descartar loading ou primeira passagem. Gameplay, loading e cauda estão separados. O diagnóstico com WPR não é comparação antes/depois ou aprovação global de FPS.

| Fase | Frames | s | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 | /s | >66,7 | /s |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Gameplay | 16657 | 120,014 | 5,603 | 12,988 | 14,624 | 83,432 | 9 | 0,074992 | 3 | 0,024997 |
| Primeira passagem | 5876 | 30,014 | 4,028 | 9,082 | 11,223 | 83,432 | 6 | 0,200 | 3 | 0,100 |
| Retorno | 3998 | 29,996 | 5,850 | 13,375 | 15,121 | 40,810 | 2 | 0,067 | 0 | 0 |
| Eventos | 3454 | 30,005 | 10,254 | 13,107 | 14,537 | 30,933 | 0 | 0 | 0 | 0 |
| Recuperação | 3329 | 29,999 | 10,351 | 13,489 | 15,360 | 57,256 | 1 | 0,033 | 0 | 0 |
| Loading | 602 | 25,283 | 2,493 | 77,918 | 299,973 | 7933,544 | 62 | 2,452 | 42 | 1,661 |
| Cauda | 212 | 3,004 | 11,769 | 18,225 | 114,673 | 121,552 | 8 | 2,663 | 6 | 1,997 |

Valores completos e sem arredondamento estão na [análise canônica](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-analysis.json). A física continua em 60 Hz/cap 3; população solicitada 40, diretores e sistemas normais, qualidade Mobile 1920×1080/MSAA enum 1, seed e percurso são as mesmas condições nominais dos diagnósticos anteriores. A carga efetivamente alcançada e a posição na recuperação diferem materialmente, como detalhado no adendo abaixo; não constituem controle equivalente do estado de 3 estrelas/4 unidades da pausa histórica. O OpenUsage permaneceu ativo normal; não houve CLI própria programada ou suspensão de threads por NativePoints nesta etapa.

## Linha do tempo dos positivos menores

Os tempos abaixo vêm de markers reais no intervalo. `processEnd` precede os callbacks físicos destes intervalos; não produzir um residual negativo pela ordem inversa. CPU é contador quantizado, com quantum observado de 15,625 ms; zero incremento não prova zero execução. Draw é wall do caminho de desenho, não GPU exclusiva. Não somar pais/filhos de WORK.

| Frame / fase | READY +s bruto | Frame ms | Maior trecho observado | Wall ms | CPU principal contabilizada no trecho ms |
|---|---:|---:|---|---:|---:|
| 651 primeira passagem | 0,588084 | 83,432 | pre_draw→post_draw | 56,355 | 0 |
| 1284 primeira passagem | 3,341312 | 76,585 | pre_draw→post_draw | 57,976 | 0 |
| 8307 retorno | 40,260108 | 40,810 | processEnd→pre_draw | 19,773 | 15,625 |
| 16889 recuperação | 116,843081 | 57,256 | process_frame anterior→processEnd | 39,172 | 15,625 |
| 17284 cauda | 120,283385 | 114,673 | post_draw→primeiro callback físico | 80,150 | 15,625 |
| 17285 cauda | 120,398058 | 121,552 | post_draw→primeiro callback físico | 93,984 | 93,750 |
| 17299 cauda | 120,666411 | 105,158 | post_draw→primeiro callback físico | 83,090 | 78,125 |
| 17384 cauda | 121,618739 | 112,176 | post_draw→primeiro callback físico | 89,522 | 0 |
| 17385 cauda | 121,730915 | 117,392 | post_draw→primeiro callback físico | 92,583 | 93,750 |
| 17399 cauda | 122,004658 | 114,956 | post_draw→primeiro callback físico | 91,959 | 78,125 |

Os seis picos de cauda concentram 80–94 ms **antes** do primeiro callback físico. Seus draws custam 3,788–5,138 ms; os três callbacks custam juntos aproximadamente 14–24 ms, e o trecho após o último físico é 0,907–2,287 ms. Isso é uma localização distinta do gap histórico pós-callback. Há alternância entre CPU pequena e proporcional no trecho anterior à física; não são prova de uma mesma API, espera, solver, frame limiter, GC ou contenção externa. O ETL deve decidir o estado/stack desse trecho antes de qualquer mudança.

Nenhum WORK ≥1 ms cruza esses seis intervalos por timestamp. No f17285 há zero criação/liberação de nós e nenhum entity event; posição `(66, 0.090104, 125.728)`, 28 pessoas, 40 veículos, 0 unidades/estrelas, 18 chunks e filas zeradas. Na cauda a carga muda normalmente: o evento route_end registrou 27/40/0 e 17.230 nós; o end registrou 30/44/0 e 17.724 nós. Não descrever essa cauda como população fixa nem atribuir sua latência apenas à contagem.

O máximo de recuperação f16889 cria 243 nós e libera 123, sem entity event e sem WORK ≥1 ms no próprio intervalo. A maior duração está no bracket de processamento anterior ao draw, não no pós-física. Essa assinatura precisa do perfil para localizar serviço/processamento ou preempção; criação contemporânea sozinha não demonstra uma chamada causadora.

Na abertura, f602 inclui `urban.build` 17,562 ms dentro de `urban.physics` 17,568 ms, com dois ônibus e readies 5,049/3,866 ms. Não somar esses pais/filhos. O primeiro draw grande f651 tem 60 nós adicionados/16 liberados e um evento de CharacterBody3D, mas essa coincidência não prova compilação ou instância como causa dos 56,355 ms de draw. WPR dirigido à recuperação não cobre esses primeiros draws.

## Loading, get_rid e áudio preservados

Loading contém f0 7933,544 ms; f24 1079,616 ms; f270 1875,089 ms; f301 3940,767 ms; f302 2923,348 ms e f303 363,634 ms. Nos f24/f270/f301/f302, o trecho grande vem antes de processEnd. Não descartá-los como aquecimento: são positivos reais com atribuição nativa fora do escopo temporal deste WPR. F0 contém `capture.main_resource_load` 2915,800 ms e `startup.before_first_await` 4843,196 ms, envelopes distintos; spans inclusivos de seus filhos não são adicionados de novo.

O getter de material de sangue `ground_blood.material.get_rid` custa 19,478 ms, READY −0,992160 s, em loading. A preparação de áudio `contact_audio.pool_bus_probe_summary` foi retida abaixo de 25 ms em READY +20,679729 s e custa 1,208 ms, com sete APIs, sem drops e 471 µs de hooks medidos inclusivamente. `set_bus_send` ocupa 0,633 ms e limiter+ceiling 0,197 ms; o resumo não é somado aos filhos. Não reproduziu a pausa de áudio de 1,35 s de outra captura. Tampouco cruza os picos de cauda. Getter/resumo/probes continuam diagnósticos, não uma nova correção.

## Janela circular e perdas

Zero ring overflow, dropped_details, cause_samples_dropped, CPU inválida, tick mismatches e `trace.events_dropped` nos detalhes retidos. Todos os detalhes disponíveis dos prefixos START−3 s dos positivos selecionados foram preservados. Loading f0 não possui os 3 s anteriores ao início da própria coleta.

O detalhe pós3 s ainda omite o único frame que cruza o cutoff em quatro janelas: f1284 perde 2,457 ms; f8307 perde 11,998 ms; f9204 perde 4,759 ms; f10477 perde 0,798 ms de interseção detalhada. Os timings continuam no array bruto. A janela do máximo de recuperação f16889 não tem detalhe faltante. Não declarar todas as janelas estritamente completas com base apenas em drops=0.

As janelas dos seis picos de cauda têm zero detalhe faltante dentro do tempo efetivamente coletado, mas END+3 s ultrapassa o término finito: faltam entre 0,390 e 2,112 s de pós-contexto que nunca foram capturados. Isso é cauda truncada, não perda interna ou prova de que o problema já recuperou. Não prolongar automaticamente o jogo para preencher essas janelas.

## Custo dos observadores e contexto externo

StallLog: self máximo 1,458 ms, window_sort máximo 0,659 ms, writer máximo 0,253 ms e drops de writer 0. A coleta de contexto acumulou 1290,005 ms em 17.471 chamadas e Input 145,012 ms. Apenas nos intervalos retidos, observer wall soma 564,553 ms, capture 167,451 ms e sinal 34,135 ms. São scopes inclusivos e retenção parcial: não adicionar esses subconjuntos nem subtrair do frame time.

O [coletor externo v4](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-offline-process-cpu.json) cobriu READY −31,867086..+124,593410 s, com 314 amostras, custo de 3,174% de um core antes de escrita. Query wall p50/p95/p99/máximo = 15,181/25,763/51,349/109,847 ms. Esses custos são maiores que nos diagnósticos anteriores e qualificam a rodada; não provam que a consulta provocou uma pausa de jogo.

Dois ccusage tiveram CPU positiva somente em loading: PID95036 nos brackets −31,844775..−20,400832 s, 30.265,625 ms de CPU; PID89580 em −16,395223..−2,403933 s, 64.859,375 ms, máximo equivalente a 15,045 cores. Nenhuma CPU positiva desse nome foi observada no gameplay. Esse negativo não elimina disputa externa ou identifica o responsável pelo gap antigo; estes contadores em brackets de ~0,5 s não medem CPU exclusiva de um frame, Ready/Waiting, hard faults ou IRQ.

O [status próprio do helper WPR](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-wpr-rec2/native-cpu/status.json) confirma start/save/cleanup. Seus anchors de comando correspondem a READY +85,677114..+124,148292 s; essa é a janela do helper, não a fronteira de retenção ETL por CPU. O stop_reason foi measurement_finished: salvamento começou após FINISHED, não para explicar os tail frames anteriores.

Pelos anchors internos `helper_cpu_at_recording_start` e `helper_cpu_at_stop_request`, o helper contabilizou 3625,000 ms de CPU em 38471,178 ms wall, aproximadamente 9,423% de um core durante recording. Desde sua entrada até saída, o status contabiliza 34546,875 ms CPU/223500,553 ms wall, incluindo espera e preparação. Queries de identidade somam 27473,858 ms wall, máxima 130,901 ms em todo o helper; não é o custo de uma query necessariamente dentro dos picos. Esses são dados próprios preservados em status, sem inventar CPU final por consulta a um PID já encerrado. Custos de comandos WPR e kernel ETW são scopes adicionais/inclusivos e exigem sua própria interpretação.

## C# e fontes

Harbor compilou com 0 avisos/erros em 0,53 s; stdout confirma Godot 4.7.2 .NET `ed1daf0bf`, Vulkan/Mobile e RTX 4060 Laptop. Os 1.650 hashes capturados coincidem com D1; `source_changed=[]`. Cinco arquivos C#/router pertinentes conferem live=frozen=capture nesta auditoria. Não se copiou ou sobrescreveu fonte concorrente.

READY `router_native=false` e enabled=true é a instância global lazy nesse instante. Os três plans privados do terminal registram native_active=true, em 32,213/0,424/0,300 ms; 6.926 contextos retidos têm router global ativo e o end também é true. ClockAnchor READY/end e ThreadCpuProbe correspondem PID91212/TID93472. C# foi efetivamente exercitado, sem aprovação por fallback GDScript.

## Estado e discriminante restante

O positivo novo é uma família de cauda antes dos callbacks físicos, com CPU ora pequena, ora proporcional. Scheduling e stacks contínuos nesse envelope podem identificar uma API/espera/serviço ou apontar lacuna; não fazem a localização virar automaticamente a pausa histórica pós-física. O perfil atual não inclui hard faults/DiskIO/DPC/Interrupt, e a interpretação deve preservar esses limites.

Nenhum Game adicional é autorizado por este relatório. O coordenador decide o segundo motor permitido pelo plano após a auditoria de cobertura, perdas por CPU/LastDroppedTimes e continuidade do ETL. Uma rodada sem reprodução continua inconclusiva; nenhuma mudança de gameplay, cache, física ou ambiente será apresentada como correção da pausa de 1,7 s com estes dados isolados.

## Adendo: transição para custódia e carga realmente alcançada

A rota de ida/volta foi efetivamente percorrida antes dos eventos: `max_x=179,042984` e `return_min_x=107,991699`, dentro dos guards 175/112 do collector. Isso confirma esses dois segmentos, não a permanência no mesmo lugar/carga durante a recuperação. O campo `teleports_during_capture=0` é um literal do report, que descreve o procedimento do medidor; não é um contador de teleportes automáticos do gameplay. Nesta rodada os contextos registram uma mudança real de posição de 110,979 m.

| Marco rec2 | Engine µs | READY +s bruto | Posição x/z | Estrelas / unidades | Fato observado |
|---|---:|---:|---|---|---|
| Início de eventos, phase_changed | 95406575 | 60,000129 | 107,9917 / 23,00001 | 0 / 2 | Arsenal/godmode registrados em seguida; tiros normais do roteiro |
| Primeiro contexto retido com procura, f13187 | 118511297 | 83,104851 | 107,9917 / 23,00001 | 1 / 5 | Contextos retidos da fase event abrangem estrelas 0..1 |
| Início da recuperação, phase_changed | 125411463 | 90,005017 | 107,9917 / 23,00001 | 1 / 5 | stimuli_stopped três µs depois |
| f16860 | 151965984→151979509 | 116,559538→116,573063 | 107,9917 / 23,00001 | 1 / 5 | 17 chunks; pending passa a 1 |
| f16861 | 151979509→151995730 | 116,573063→116,589284 | 107,9917 / 23,00001 | 1 / 5 | 18 chunks; build_jobs=1, 50 nós criados |
| f16862 | 151995730→152020078 | 116,589284→116,613632 | 66,0000 / 125,7280 | 0 / 0 | 33 nós criados/520 liberados; saúde 100; mudança abrupta de posição |
| Cinco dispatch.unit_finished | 152005771→152005916 | 116,599325→116,599470 | mesmo intervalo f16862 | 0 / 0 | Encerramento explícito das cinco unidades registrado |
| f16863 | 152020078→152045238 | 116,613632→116,638792 | 66,0000 / 125,7280 | 0 / 0 | 10 nós criados; build_jobs volta a 0 |
| Máximo da recuperação, f16889 | 152249527→152306783 | 116,843081→116,900337 | 66,0000 / 125,7280 | 0 / 0 | 57,256 ms e criação/liberação 243/123, depois da transição |
| route_end | 155410298 | 120,003852 | 66,0000 / 125,7280 | 0 / 0 | Cauda inteira começa fora do local original |

Os contextos retidos da recuperação antes de f16862 mantêm 1 estrela e 5 unidades; depois, o jogador permanece no ponto da delegacia sem procura/unidades. Já `shader-cache-a1` começa recuperação em READY +90,003182 s com **3 estrelas/4 unidades** e mantém `(107,9917, −0,009058, 23,00001)` nos f15918/+97,393732 e f16083/+102,102540, com 29 pessoas/39 veículos/16 chunks. A diferença de procura/unidades precede a mudança de local da rec2; não é apenas um efeito do pós120 s ou do WPR.

A fonte congelada sustenta uma **inferência forte de prisão com retorno à custódia**, sem sinal explícito player_arrested retido: [Gameplay.arrest_player](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-project/gameplay/Gameplay.gd:1590) bloqueia input e emite player_arrested; god_mode só bloqueia dano em `_apply_player_damage`, não essa prisão. [FullSession._on_arrest](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-project/runtime/FullSession.gd:1878) aguarda a apresentação de 2,2 s e chama `_respawn`. O [ramo de custódia](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-project/runtime/FullSession.gd:1937) escolhe `harbor_police.return_position + UP*0,1`, prepara foco/colisão, aguarda três physics_frame, depois chama respawn/clear_wanted, dismiss_all e teleport.

O ponto corresponde exatamente ao catálogo editado: [PlaceCatalog](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-project/world/places/PlaceCatalog.gd:78) usa approach/return da delegacia, transformado por [WorldServiceBuildings](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-project/world/editing/WorldServiceBuildings.gd:44) e pelo registro fonte `building/Police` em [world_edits.json](D:/geteco/game/evidence/intermittent-stalls-20261004/stall1709-project/world/editing/world_edits.json). Posição `[66,120]`, rotação 0 e escala z `10/15,625` produzem retorno `(66, 0,1, 125,728)`; o contexto seguinte tem y=0,090104 após acomodação física. Stars/unidades zerados e os cinco unit_finished correspondem ao cleanup desse ramo. Nenhum Save pessoal foi lido ou alterado.

Não há evento nomeado de prisão/resgate ou timestamp do início da apresentação no report; por isso não atribuir a hora exata de arrest_player, duração da custódia ou custo indivisível a uma função sem span/stack. O foco/builder mudam antes de f16862 e a criação/liberação grande posterior é contexto compatível com a transição; não prova que streaming causa os picos 57–122 ms. A classificação nativa desses picos continua separada da pausa antiga. Também não se pode declarar que uma captura sem a carga de 3 estrelas/4 unidades refutou a assinatura histórica.

Uma segunda observação finita, se escolhida pelo coordenador, precisa verificar a carga e o local realmente alcançados durante +90..120 s e registrar as transições produtivas. Nominalmente repetir seed/tiros não garante a mesma resposta policial. Não bloquear prisão, injetar procura/população ou teletransportar o jogador para produzir uma aprovação; qualquer fixture discriminante diferente exigiria plano próprio e conclusão restrita.
