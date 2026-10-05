Rec3 concluiu a segunda e última rodada prevista. **Nenhum frame de gameplay ≥250 ms, nenhum pico de cauda >33,3 ms e nenhuma reprodução do alvo histórico de 1,7 s.** Não houve correção no jogo; a mudança foi somente o guard de identidade do observador WPR. A redução de seu custo foi medida, mas a ausência da assinatura de cauda em uma rodada não demonstra sua eliminação.

Evidências: [síntese JSON](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-native-summary.json), [cobertura/perda por CPU](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-native-coverage.json), [scheduler v2](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-scheduler-analysis-v2.json), [header mínimo](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-native-header.json), [análise canônica](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec3-analysis.md) e [rec2 nativa](D:/geteco/game/evidence/stalls-1709-20261005/wpr-rec2-native-summary.md).

Helper QUERY_LIMITED `DD62F1F3…`, perfil `31441E4B…`, instância `GetecoAudit-55188cf7f48e4fd7a3c80dae6e217890`, helper PID 88476, Godot nativo PID 101116/main TID 97080. Controle Ready+85 s/Capture40, buffers 1 GiB, keywords, guards de parent/birth/path e cleanup permaneceram iguais. O stop foi causado por `measurement_finished`; save/cleanup passou, falha nula, instância voltou ao baseline. ETL original **607.125.504 B** preservado.

O header FileOnly confirma **QPC 10.000.000 Hz**, session UTC 12:33:38,5044875–12:34:18,1098808. Não foram exportados outros payloads de header, comandos ou ambiente. O decoder de cobertura passou: 20 CPUs, **34.519 transições** e **38.255 samples da main**, zero EventsLost/erro de payload/decode. Seu export não tem o cap de um milhão do export global detalhado; nenhum JSON global de stacks foi necessário nesta rodada.

Dois LastDroppedTimes versão 2 mostram todos os 20 timestamps zero, sem indicação de evicção circular do prefixo. Main CSwitch/Ready cobre **READY+85,491807–124,189231 s**. Pares de âncora Godot/QPC de loading/início/fim passaram; 10.092 probes existentes de processor number da main entre +85,8 e +123 s ficaram dentro dos ranges CSwitch correspondentes. Inícios tardios de CPUs pouco ativos não foram automaticamente classificados como perda. A semântica v2 validada em rec2 produziu **zero anomalias de pareamento CSwitch**. Não se assume estado antes/depois do range efetivo.

| Frame de recuperação | Parede | Scheduled running | Ready | Waiting |
|---|---:|---:|---:|---:|
| 13694 | 35,262 ms | 31,579 ms | 0,467 ms | 3,216 ms |
| 13695 | 33,417 ms | 28,061 ms | 0,706 ms | 4,650 ms |
| 14340 | 26,305 ms | 25,858 ms | 0,105 ms | 0,342 ms |
| 14341 | 29,823 ms | 29,343 ms | 0,090 ms | 0,391 ms |
| 14342 | 26,799 ms | 26,530 ms | 0,039 ms | 0,230 ms |
| 15611 | 40,514 ms | 34,431 ms | 0,733 ms | 5,350 ms |

Essas seis partições cobertas não têm Unknown ou boundary não coberto. Scheduled running é residência entre In→Out no mesmo CPU, incluindo ISR/DPC não separados; não é execução exclusiva de callback. No f15611, process_frame→process_callbacks_end mede 20,396 ms: residência 14,597 ms, Ready 0,701 ms, Waiting 5,098 ms. O gap post_draw→primeiro físico é só 0,129 ms. Assim, o maior frame de recuperação desta rodada não reproduz o gap de 80–94 ms visto na cauda rec2 nem o gap pós-último callback de 1,7 s.

| Custo próprio do aparato | Rec2 antigo | Rec3 QUERY_LIMITED |
|---|---:|---:|
| CPU do helper durante gravação | 3.625,000 ms | 609,375 ms |
| Parede do bracket | 38.469,753 ms | 38.535,787 ms |
| % de um núcleo | 9,423% | **1,581%** |
| Consultas de identidade | 1.843 | 2.201 |
| Parede agregada das consultas | 27.473,858 ms | **301,309 ms** |
| Máxima consulta | 130,901 ms | **17,927 ms** |

A preflight própria do novo guard já havia conferido identidades iguais e recusa de PID encerrado; a rodada real confirma custo menor com os mesmos campos de identidade. Os números vêm de âncoras/custos embutidos enquanto o helper estava vivo; não dependem de consulta externa depois da saída. Não medem todo o overhead kernel de ETW e não devem ser somados/subtraídos para corrigir FPS.

O gameplay canônico ficou p50/p95/p99 **6,198/14,026/15,735 ms**, máximo 94,667 ms; não há aprovação global: p95 rec2 era 12,988 ms. Rec2 teve prisão/respawn antes da cauda; rec3 manteve 3 estrelas/4 unidades perto de +97/+102 s e ao fim. Essa diferença de estado limita a comparação dos tailpicos. A assinatura de input demonstrada na rec2 permanece separada e pendente; não foi feita nova atribuição por símbolos/stacks em rec3 nem alteração de SDL, DirectInput, Bluetooth ou suporte a controles.

O lote terminou com dois negativos para o alvo. Os dados nativos agora cobrem e distinguem residência, Ready e Waiting nos picos efetivamente capturados; não identificam a causa do frame histórico ausente nem comprovam que ele foi resolvido. Nenhum terceiro jogo, UAC ou trace foi iniciado.
