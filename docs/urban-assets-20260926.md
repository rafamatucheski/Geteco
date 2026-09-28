# Biblioteca de prédios, casas e galpões

20 novos presets em dez famílias, disponíveis em Mundo → biblioteca → Prédios. A seleção de modelo nas propriedades inclui todas as famílias. Largura, profundidade, altura, cor e rotação continuam editáveis. São exteriores sólidos sem interiores ou serviços novos. O documento oficial do mapa não foi editado nesta tarefa.

| Família | Preset menor (L × P × A, m) | Preset maior (L × P × A, m) |
|---|---|---|
| Torre escalonada | 14 × 12 × 22 | 18 × 16 × 32 |
| Torres gêmeas | 18 × 14 × 24 | 24 × 18 × 36 |
| Residencial com varandas | 16 × 10 × 12 | 24 × 12 × 20 |
| Torre art déco | 10 × 12 × 20 | 14 × 14 × 30 |
| Prédio estreito | 6 × 9 × 12 | 8 × 12 × 18 |
| Torre de vidro com base comercial | 18 × 16 × 26 | 26 × 22 × 38 |
| Casa com telhado inclinado | 7 × 9 × 4,8 | 11 × 12 × 6 |
| Sobrado geminado | 10 × 10 × 7 | 16 × 12 × 9 |
| Galpão com sheds | 14 × 18 × 6 | 24 × 30 × 9 |
| Galpão com docas | 16 × 14 × 7 | 30 × 22 × 10 |

Os modelos têm janelas frontais, traseiras e laterais. Detalhes repetidos usam MultiMesh por material, sem luzes ou callbacks por frame. Cada volume principal possui colisão própria; os telhados inclinados usam prismas convexos. Os vãos entre torres e os recuos superiores não recebem colisões de caixas envolventes. Fachadas não recebem textos decorativos.

## Validação

- `tests/test_urban_asset_library.gd`: **209 checks aprovados com renderização**, Godot 4.7.2 Mobile / RTX 4060 Laptop. Cobre os 20 presets, gravação e leitura de documento isolado, dimensões e rotação na região produtiva, janelas nas quatro faces, limite de batches, ausência de processamento/luzes, consultas físicas, movimento de cápsula bloqueado pelas fachadas, vãos livres e descarregamento/reconstrução de chunks.
- O teste exige renderização: o backend dummy headless não fornece as transformações de MultiMesh usadas para verificar as janelas. O runner `tests/run_suite.ps1` o executa renderizado. A primeira etapa de colisão/persistência passou em 189 checks headless; a verificação adicional de janelas foi validada no renderer real, sem retirar assertions.
- `tests/test_world_editor_assets.gd`: **29/30**, tanto headless quanto renderizado. Pendência: Ctrl+S com texto ainda sendo digitado em um SpinBox não aplicou 57; permaneceu 53. Foco e visibilidade do campo foram confirmados. Salvamento pelo botão, busca, copiar/colar e os demais checks passaram. O editor tem mudanças concorrentes; a integração desta tarefa nele alterou somente as opções de modelo, preservando as demais alterações.
- Capturas reais revistas: `evidence/urban-assets-20260926/catalog.png` e `lowrise-catalog.png`. Dez miniaturas geradas em `addons/geteco_world_editor/thumbnails/`. A revisão corrigiu uma peça que encobria janelas laterais na torre de vidro, a orientação das faces dos telhados e suas normais.
- Os avisos de liberação de texturas ao encerrar também apareceram na base existente. Não se declara ausência de vazamentos.

## Desempenho: inconclusivo

As amostras em `evidence/urban-assets-20260926/{before,after,lowrise-before,lowrise-after}/report.json` preservam dados brutos, aquecimento e p50/p95/p99. **Não são aprovação de performance ou prova de regressão.** Uma primeira medição ficou aberta após falhar na gravação restrita e concorreu com os comparativos; também foi identificado um teste de veículos de outra sessão. O processo remanescente desta tarefa foi identificado por PID/script e encerrado; processos alheios foram preservados.

Configuração pretendida: Main real, seed 26092026, população solicitada 8, 1280×720, Mobile, VSync, limite 60, câmera fixa idêntica, 8 s de aquecimento e 30 s medidos por cenário diurno/noturno com chuva. As amostras ficaram próximas de 30 FPS, abaixo da meta de 60; os percentis não devem ser interpretados causalmente devido à concorrência. A ausência de regressão e a meta de frame time permanecem **pendentes** de ambiente disponível sem medições concorrentes.

Reprodução, em processos sequenciais e com `--no-save`:

```text
Godot --path D:/geteco/game --script res://tests/measure/measure_urban_assets.gd -- --no-save --population=8 --variant=clean-before
Godot --path D:/geteco/game --script res://tests/measure/measure_urban_assets.gd -- --no-save --population=8 --variant=clean-after --with-new
```

Para casas/galpões, acrescentar `--lowrise` a ambos e usar outros nomes de variante. Confirmar ausência de processos de medição concorrentes antes de começar. A comparação usa documentos isolados em memória e não grava o mapa oficial ou o save do jogador.
