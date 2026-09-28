# Garagem na prévia do editor

O worker inclui a fachada original na posição usada por ProductionWorld e MaciotaPlace. Não instancia o interior nem altera regras ou transições do jogo.

`test_world_editor_garage_preview.gd`: 7 verificações aprovadas em execução renderizada. Captura: `world-editor-garage.png`. Verificados presença, posição, detalhes, dimensões, snapshot passivo e preservação do mundo salvo.

Comparação da prévia ociosa: RTX 4060 Laptop, Mobile, 1440×900, VSync e limite 60 FPS, 8 s de aquecimento e 30 s medidos.

| Métrica | Antes | Depois |
|---|---:|---:|
| FPS | 59,94 | 60,00 |
| p95 (ms) | 16,688 | 16,687 |
| p99 (ms) | 16,726 | 16,737 |
| Máximo (ms) | 62,238 | 17,483 |
| Frames >33,3 ms | 1 | 0 |

Sem regressão observada neste cenário do editor. Não certifica performance de gameplay. Amostras em `world-editor-live-garage-before.json` e `world-editor-live-garage-after.json`. Avisos de texturas no encerramento presentes nas duas execuções.
