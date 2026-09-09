# Judder de movimento e hitches de frame — medições de 2026-09-09

Contexto: o jogo estava em ~64 FPS médios e o movimento do carro ainda parecia
vibrar para frente e para trás. Instrumentos criados nesta investigação:

- `tests/measure_motion_judder_isolated.gd` — mede o mecanismo do judder isolado da
  rota do jogo (determinístico e reprodutível).
- `tests/diagnose_frame_judder.gd` — a mesma medição na rota real, mais frame-time.
- `tests/diagnose_frame_hitches.gd` — atribui os picos de 40–110 ms a uma causa.

Cada arquivo carrega no cabeçalho os números que produziu. Os commits
`6e4256b`, `4eaf47c` e `a62798f` têm o raciocínio completo.

## Correções aplicadas

`project.godot`: `run/max_fps=60`, `physics/common/physics_interpolation=true`,
`physics/common/physics_jitter_fix=0.0`. **O Godot reescreve `project.godot` a cada
`--import` e descarta comentários**, por isso a justificativa vive em
`SettingsManager.apply_display_settings()` e no histórico do git, não lá.

Mais `reset_physics_interpolation()` nos teleportes (`VehicleMotionSafety`,
`DynamicCamera.handoff`, `Player._respawn_at_hospital`, `PlayerCar` entrar/sair,
`HarborInteriorManager`, `RegionTravel`) e `PHYSICS_INTERPOLATION_MODE_OFF` no ator
durante `VehicleBoarding`, que é movido em `_process` e não pela física.

## Falhas de teste pré-existentes — NÃO causadas pela interpolação de física

Este é o registro mais importante deste diretório: quem ligar ou desligar
interpolação de física vai encontrar estes testes vermelhos e pode culpar a
configuração errada. Foram verificados rodando cada um duas vezes, com
`physics/common/physics_interpolation=false` via `override.cfg` e com o padrão
atual do projeto:

| teste | resultado | verificação |
| --- | --- | --- |
| `test_harbor_interiors_gameplay` | `failures=66` | 60 mensagens de falha **idênticas** com interpolação ligada e desligada (diff vazio) |
| `test_harbor_gateway` | `failures=6` | idêntico nas duas configurações |
| `test_harbor_bridge` | `failures=2` | idêntico nas duas configurações |
| `test_garage_real_circulation` | 1 falha (portão sul) | idêntico nas duas configurações |
| `test_harbor_real_flow_10steps` | sai com **exit 0** apesar de 13 `GAMEPLAY_TEST_FAILURE` no log | o teste não propaga as falhas para o código de saída — não confie no exit code dele |

Cuidado ao medir: rodar estes testes em paralelo com medições de performance
inflou as falhas de `test_harbor_interiors_gameplay` de 66 para 69, porque ele usa
timeouts em segundos e compete por GPU. Rode um por vez.

`test_garage_real_circulation` valida a garagem de `prototypes/`, não a de
produção (`world/harbor/interiors/HarborGarageInterior.gd`), apesar do nome
"real_circulation".

## Direção de otimização

A GPU está ociosa: 1,4 ms de render GPU num orçamento de 16,7 ms, igual nos frames
rápidos e nos hitches. Culling de luzes, batching e SubViewports mexem na parte que
não é o gargalo — esta base é limitada por CPU. Os hitches são frames que
instanciam (Δnós 19,2x, Δobjetos 14,9x, +1,49 MB de memória de vídeo, recursos
606x). Qual subsistema faz esses spawns continua não identificado.
