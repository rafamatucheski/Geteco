# Orientação inicial dos veículos estacionados — 20/09/2026

Corrigida a montagem em `cars/traffic/TrafficVehicle.gd`: o modelo recebe a rotação global da carroceria e o sprite permanece alinhado à tela desde o primeiro render. Antes, a montagem usava uma orientação fixa do modelo e rotação local zero do sprite. Veículos estacionados desabilitam ambos os callbacks, portanto só corrigiam a pose ao voltar a atualizar, por exemplo durante o embarque. Não foram adicionados callbacks, viewports ou trabalho por quadro.

## Validação

- `tests/test_parked_vehicle_initial_heading.gd`: reproduziu oito falhas antes; passou nas 12 verificações depois, com renderização real. Cobriu police_cruiser, police_suv, american_flatbed e cargo_flatbed_truck, incluindo rotação herdada do pai e ausência de callbacks nos estacionados.
- `tests/test_vehicle_3d_presentation_contract.gd`: 21 verificações aprovadas, headless. Inclui apresentação adiada, dormir/acordar, veículo dirigido e colisão com fachada.
- Capturas da delegacia antes/depois confirmaram a correção de perspectiva da viatura estacionada. Capturas isoladas verificaram também os caminhões.

## Comparação renderizada

`tests/measure_patrol_parking_heading.gd` usa HarborGame real, jogador a pé na delegacia, saves de diagnóstico separados, semente fixa, dia e tempo seco. Aquecimento de 10 segundos seguido de 30 segundos de amostra. Godot 4.7.2, Mobile/Vulkan, RTX 4060 Laptop, 1280×720, limite de 60 FPS, VSync desligado, janela em foco em 100% das duas amostras. Meta provisória: 60 FPS / 16,67 ms; aumento superior a 5% de p95/p99 exigiria confirmação.

| Métrica | Antes | Depois |
|---|---:|---:|
| FPS médio | 56,71 | 59,88 |
| p50 (ms) | 16,701 | 16,664 |
| p95 (ms) | 23,296 | 17,900 |
| p99 (ms) | 42,065 | 22,104 |
| Máximo (ms) | 82,817 | 103,449 |
| Quadros >33,3 ms | 53 | 2 |
| Quadros >66,7 ms | 2 | 1 |

Sem regressão observada em p95/p99; não atribuir a melhora à alteração de orientação, pois há população dinâmica e trabalho concorrente no projeto. Persistiu um pico isolado de 103 ms: estes resultados não aprovam estabilidade absoluta a 60 FPS. Um editor Godot já estava aberto e foi preservado. Não foram separadas durações CPU/GPU.

Evidências (JSON, CSV com tempos por quadro, capturas e logs): `C:/Users/rafae/.codex/visualizations/2026/09/20/01a0bf40-93e7-7b60-acaf-93aab4b1dc58/`, subpastas `patrol-before`, `patrol-after`, `parked-before` e `parked-after`.

Limitações do ambiente: erro de compilação de áudio apareceu apenas na primeira execução headless, anterior à correção, e desapareceu nas execuções seguintes sem intervenção desta tarefa. As execuções renderizadas registraram aviso de acesso ao diretório padrão de saves; as amostras usaram seus próprios diretórios. Houve avisos de recursos ainda alocados ao encerrar o jogo e o teste de apresentação, sem falhas nas verificações funcionais.
