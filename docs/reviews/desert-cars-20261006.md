# Carros do deserto — 6 de outubro de 2026

## Implementação

Três agentes dividiram carrocerias, adesivos e iluminação. Os cinco modelos civis agora têm proporções distintas: hatch inspirado no R5 Turbo, muscle inspirado no Challenger, sedã esportivo inspirado no Evo, picape e cupê inspirado no 350Z. São interpretações no estilo do jogo, sem mudança das dimensões físicas ou da mecânica original.

As três edições de corrida são Faísca RX (27), Coyote 440 Drag (44) e Mirage GT (08). Cada uma tem rodas, kit, adesivos laterais e cor de neon próprios. O catálogo de Digo e os rivais Lívia, Raul e Nadir usam as novas edições. Os cinco IDs antigos continuam válidos; compra e save aceitam os oito IDs.

Geometria estática agrupada por material, malhas reutilizadas, quatro pivôs de roda preservados. Adesivos acompanham as portas e sobrevivem à repintura. Neon usa uma luz curta sem sombra, fitas emissivas e projeção suave no piso, com apoio físico e fades de horário/distância. Nenhum SubViewport ou loop autônomo por carro foi adicionado.

## Correção dos tetos e vidros

O defeito após embarcar era o interior calculado a partir dos retrovisores, criando um forro largo que atravessava a carroceria. Havia também pintura atrás dos vidros e um deck atravessando a cabine. Os tetos centrais já eram pintados.

Agora cada modelo informa sua cabine ao sistema compartilhado. Retrovisores usam metal, janelas têm vãos reais e a cabine é oca; teto e pilares continuam opacos. Acabamentos e bancos ficam dentro da carroceria. O parâmetro opcional de piso dos bancos preserva os valores antigos dos demais veículos. Nenhuma colisão de condução foi removida.

Comparação renderizada com portas preparadas e interior montado:

- Antes: [Mirage GT](../../evidence/desert-car-styles-71132-5444136/desert_mirage_gt-roof-interior.png).
- Depois: [Mirage GT](../../evidence/desert-car-styles-123164-7281340/desert_mirage_gt-roof-interior.png), [Coyote](../../evidence/desert-car-styles-123164-7281340/desert_coyote_drag-roof-interior.png), [Faísca](../../evidence/desert-car-styles-123164-7281340/desert_faisca_rally-roof-interior.png), [Bison](../../evidence/desert-car-styles-123164-7281340/desert_bison-roof-interior.png).
- Jogo real após a corrida: [câmera normal](../../evidence/desert-drag-temporal-79632-45113896/01570.jpg).
- [Vídeo contínuo da corrida e retorno](../../evidence/desert-drag-temporal-79632-45113896/desert-gt-roof-fixed.mp4), com a cadência real da captura preservada e sem áudio.

## Verificação

Godot 4.7.2 .NET, C# compilado sem avisos/erros. Execuções coordenadas por `D:/geteco/artifacts/runtime-queue/Run-DesertCheck.ps1`; dados de save isolados.

- Cabines: 337 verificações, oito modelos; portas, teto, envelope geométrico, vidros, câmera baixa, restauração, repintura e isolamento de instâncias. Zero excesso medido nas laterais elevadas e no teto.
- Pose do motorista: 283 verificações nos oito carros do deserto; 1.642 nos 47 modelos anteriores. O vazamento da fixture antiga foi corrigido liberando o `Driving` que ela criava fora da árvore.
- Corrida real final com Mirage GT: 59 verificações; entrada física, largada queimada, cancelamento, pausa, 800 m, recompensa única, câmera/controles/HUD restaurados e destruição do rival sem vitória fabricada.
- Save/garagem: 32 verificações. Adesivos: 69 verificações, repetidas após os ajustes das cabines. Contratos de neon e frota também passaram durante a implementação.
- Captura final de iluminação: 1.633 quadros em 55,98 s, sem quadros renderizados pulados. Inclui dia, transição do entardecer, noite, corrida, pausa e retorno. A captura limita a execução a 30 FPS e escreve imagens; **não é benchmark**.
- Nos 951 quadros de largada/corrida/frenagem, a telemetria manteve o neon apoiado e ativo, sem desligamentos. A inspeção visual amostral confirmou o encaixe do teto antes e depois da corrida. Isso não equivale à inspeção humana do vídeo inteiro em velocidade normal: [telemetria e limites](../../evidence/desert-drag-temporal-79632-45113896/neon-review.json).

## Limites da evidência

O palco de modelos prova apresentação, não desempenho nem travessia. A corrida real cobre o Mirage GT na pista; não certifica toda a cidade, chuva ou todas as combinações de veículos e iluminação.

A comparação de performance com o início do trabalho é inconclusiva: outras sessões alteraram terreno, horizonte e sistemas de veículos entre as medições. A medição anterior do GT mostrou p95 de 5,37 ms à noite e 5,64 ms de dia, com picos isolados de 74–110 ms. Não atribuir esses picos aos carros sem investigação, nem declarar performance global aprovada.

A tentativa final, após ajustar as cabines, também ficou **inválida**: `DesertVehicleGround.gd` mudou durante a execução. Não houve sobreposição de instâncias do motor. Foram observados p95 de 5,86/5,99 ms e máximos de 85,18/114,14 ms em noite/dia, mas esses números não aprovam performance: [relatório com hashes e motivo de invalidação](../../evidence/desert-car-style-measure-16120-7171070/report.json). Nova comparação exige fontes estáveis antes/depois; repetir a mesma medição enquanto outras sessões alteram runtime não resolve a pendência.

A mesma integração concorrente deixou temporariamente incompatíveis a assinatura do helper de terreno e a chamada em `Vehicle.gd`. A primeira tentativa final dos adesivos foi interrompida por esse erro de compilação. Depois que a sessão responsável completou a chamada de três argumentos, o teste foi repetido e passou sem erros (`desert-car-roof-livery-final-2`). Não foi necessário editar ou descartar os arquivos dela.
