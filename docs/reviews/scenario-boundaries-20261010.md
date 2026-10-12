# Limites da montanha e do deserto — 10/10/2026

Escopo: lateral neve/areia e fim do mapa do deserto, conforme reprodução relatada pelo usuário. Não é auditoria global das cidades.

## Causa e correção

O retângulo do deserto termina em x=440, z=-1950 e z=-373,5. A classificação regional usa esse retângulo e, fora dele, classifica cidade ou montanha sem exigir uma ligação física. Os afloramentos espaçados não vedavam todo o perímetro; a abertura sul reservava 156 metros, apesar de haver uma única ponte. A montanha usa células inteiras de 64 metros, cuja borda oeste não coincide com o retângulo de areia.

`world/regions/ScenarioBoundary3D.gd` acrescenta escarpas contínuas com malha visível e colisão feita dos mesmos triângulos. Elas são construídas no estágio das superfícies, antes da decoração fatiada, e acompanham o descarregamento do chunk. Não acrescentam processamento por frame, gatilhos de viagem ou mudanças de saúde.

- Deserto: perímetro oeste, leste, norte e sul; abertura de 28 metros para a ponte existente.
- Norte do deserto: proteção permanente atrás do terminal em z=-1945. A missão continua abrindo a passagem até o terminal, sem liberar um mapa ainda inexistente.
- Montanha: borda oeste e limite sul, dentro do território lógico. A linha da ponte e suas células de água permanecem com a estrutura e margens existentes.

As alterações anteriores de outras sessões em `NativeRegion.gd` e `DesertRegion.gd` foram preservadas; esta tarefa acrescentou uma chamada em cada arquivo.

## Evidências e limites

Godot 4.7.2 .NET console; `dotnet build Harbor.csproj --no-restore`: aprovado, zero erros/avisos.

`tests/test_scenario_boundaries.gd`: 45 verificações aprovadas. Inclui seis alturas longitudinais da lateral neve/areia, bordas oeste/norte/sul do deserto, limite entre chunks, varreduras de cápsula iniciadas fora de sólidos, tentativa de saltar a proteção do terminal, abertura da ponte e igualdade entre faces visíveis e colisão. Diagnóstico inicial encontrou nove falhas nos pontos do perímetro de areia. As primeiras fixtures de cápsula estavam dentro de sólidos existentes; foram corrigidas para usar o piso real e verificar espaço livre antes do movimento.

`tests/test_desert_session.gd`: 14 verificações aprovadas em Main com backend C# ativo, dirigindo pela ponte, desembarcando e gravando/lendo checkpoint isolado. A primeira invocação usou `--no-save`, que suprimiu a gravação exigida pelo teste; a invocação correta usa somente o caminho de checkpoint exclusivo criado pelo próprio teste. Saves pessoais não foram usados.

Logs: `evidence/scenario-limits-20261010/bridge-session.log` e `capture-final.log`. Captura isolada: `evidence/scenario-boundaries-52792/snow-sand.png`, Mobile/Vulkan, RTX 4060 Laptop. Essa captura não certifica apresentação na câmera de gameplay ou FPS.

**Funcionamento local:** aprovado para os contratos exercitados. Não foram percorridos todos os metros do perímetro em Main, nem todas as combinações de veículos, combate e save/load nesses limites.

**Sessão integrada atual:** pendente. Após a passagem do teste de sessão, uma alteração concorrente introduziu erro de inferência em `gameplay/TrafficEscape.gd:30` (`var offset := car.route.get_closest_offset(...)`), propagando falha de compilação a Vehicle, Gameplay e SessionLaunch. O teste de colisão continuou executando, mas o log da captura registra esse erro no autoload. Esse arquivo não foi editado nesta tarefa.

**Performance e apresentação integrada:** não aprovadas. Havia benchmarks/testes renderizados de outras sessões durante a investigação; não foi obtida comparação antes/depois de frame time em Main. Não há medição suficiente para declarar ausência de regressão. Retomar com compilação de gameplay resolvida, máquina sem outros testes renderizados, rota em ambos os lados da lateral e terminal norte, pelo menos 30 segundos por cenário e métricas p50/p95/p99, máximo e hitches.
