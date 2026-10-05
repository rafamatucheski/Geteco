# Helper WPR com consulta de identidade limitada

Foi preparada uma candidata privada que reduz o custo de `Get-Identity`, sem modificar o jogo, a versão anterior do helper ou a coleta ETW. [Candidata](D:/geteco/game/evidence/intermittent-stalls-20261004/continuation-native/capture_stall_native_cpu_window_1024_query_limited.ps1), SHA `dd62f1f3e37c83fc8c84bae907a2e4d71e8b355d8e73b21d44cf395322138254`. Baseline SHA `4a9e900b…` permanece byte a byte intacto. [Manifesto](D:/geteco/game/evidence/stalls-1709-20261005/query-limited-helper-manifest.json), [diff](D:/geteco/game/evidence/stalls-1709-20261005/query-limited-helper.diff), [inverse](D:/geteco/game/evidence/stalls-1709-20261005/query-limited-helper.inverse.diff) e backup exato preservam a revisão.

Na rec2, os anchors próprios do helper mostraram 3625 ms de CPU/38471,178 ms wall durante recording, 9,423% de um core, além de 27,474 s wall de queries de identidade em todo o helper. O gap antigo de 1,7 s foi capturado sem esse helper. O ajuste abaixo é do **observador** e não será apresentado como correção daquela causa.

## Mudança e preservação dos guards

Cada consulta abre um handle novo com `PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE` (`0x00101000`); verifica liveness por `WaitForSingleObject(handle,0)`, PID por `GetProcessId`, nascimento por Creation FILETIME de `GetProcessTimes` e caminho Win32 por `QueryFullProcessImageNameW(flags=0)`; revalida liveness no mesmo handle e fecha em finally. Falha de API, processo sinalizado ou PID divergente retorna null, recusando a identidade. Não há cache de PID/nascimento/caminho, enumeração de módulos, leitura de memória, suspensão ou direito de controle do processo.

`GetProcessTimes` e `GetProcessId` aceitam query limitada; FILETIME preserva a precisão de 100 ns, sem afrouxar o comparador de nascimento existente. [GetProcessTimes, Microsoft](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocesstimes), [GetProcessId](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getprocessid). Flags 0 de QueryFullProcessImageNameW produzem o formato Win32 usado pelos guards atuais. [Documentação da API](https://learn.microsoft.com/pt-br/windows/win32/api/winbase/nf-winbase-queryfullprocessimagenamew). O wait com timeout 0 exige SYNCHRONIZE e retorna imediatamente, sem suspender a thread. [WaitForSingleObject](https://learn.microsoft.com/en-us/windows/win32/api/synchapi/nf-synchapi-waitforsingleobject).

As chamadas externas `Identity-Matches`, parent/child por Toolhelp, wrapper/native path/birth, Godot 4.7.2 .NET, READY/FINISHED/ClockAnchor, instância GUID, perfil SHA `31441e4b…`, 1 GiB Memory, StartMode/delay/capture, timeout 300 s, salvamento e cleanup permanecem iguais. A inversão virtual apenas das declarações/método C# de identidade e de Get-Identity reconstruiu exatamente o SHA baseline. Nenhum arquivo de runtime ou guard de gameplay mudou.

## Única verificação funcional/custo

[Preflight preservada](D:/geteco/game/evidence/stalls-1709-20261005/query-limited-identity-preflight.json), Windows PowerShell **5.1.26100.9444**, exit 0, 1233,747 ms wall. Parser de ambos os helpers passou; Add-Type compilou exatamente a declaração C# candidata nesse host. Executou 50 pares old/new somente para o PID próprio, conferindo PID, birth FILETIME e caminho iguais em todos. Um único child próprio `cmd /d /c exit 0`, mantido por handle para impedir reuso do PID, foi recusado pelos dois caminhos depois de sair. ValidateOnly passou para Ready85/Capture40/perfil esperado, sem comando WPR ou lookup de processo.

| Custo de 50 consultas próprias, inclusive despacho | Old | Query limited |
|---|---:|---:|
| Wall somado ms | 553,8314 | 22,1086 |
| Wall primeira/máxima chamada ms | 32,3004 | 11,1482 |
| Mediana reportada ms | 10,6993 | 0,2111 |
| CPU contabilizada somada ms | 593,750 | 31,250 |
| Wall da recusa do PID próprio encerrado ms | 10,9735 | 0,0675 |

Redução local observada: 96,008% no wall somado e 94,737% no CPU contabilizado. A primeira consulta foi retida, incluindo JIT/despacho inicial; não descartada como aquecimento. CPU é quantizada e o teste alterna old→new em 50 pares no mesmo processo. É um diagnóstico pequeno de API/guard, sem estimativa automática do custo futuro do helper em gameplay ou do overhead ETW/kernel. Acesso de administrador ao wrapper/native Godot ainda deverá passar os mesmos guards da coleta real; a preflight não iniciou esse motor.

A primeira impressão de console continha campos null porque Select-Object projetou propriedades de OrderedDictionary; o JSON escrito continha todos os resultados PASS. Somente a projeção final da fixture foi corrigida, sem repetir as 50 consultas ou modificar a candidata. O recibo original está preservado. Nenhum Game, UAC, workload, consulta de processo alheio ou mudança de prioridade foi executado nesta validação.

Estado: candidata revisável e compatível com PowerShell 5.1; menor custo comprovado apenas nas consultas próprias dirigidas. Não altera ou resolve a assinatura de 1,7 s. O coordenador decide se a utiliza na segunda captura finita depois do review nativo da rec2; nenhum motor extra é implícito nesta entrega.
