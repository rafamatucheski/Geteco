# Geteco

Jogo de mundo aberto em 3D nativo no Godot 4.7: Harbor (cidade e porto) e Mountain
(serra, vilarejo e serraria), ligados por uma ponte com túnel, com direção, trânsito,
pedestres, combate, polícia, campanha, economia e save próprios.

Este repositório é o jogo principal. Ele nasceu como a "V2", uma migração da V1 para o
3D nativo, e foi promovido à raiz em 24/09/2026. A V1 está preservada no ramo
`v1-legado` e na tag `v1-final`.

## Abrir

- Dois cliques em **Jogar.cmd** para jogar; **Editar.cmd** abre o projeto no editor.
- Também é possível importar o `project.godot` no gerenciador do Godot e pressionar F5.
- Em outra instalação, use `Open.ps1 -GodotPath 'caminho/do/Godot.exe'` ou defina `GODOT_EXE`.
- O save fica em `user://GetecoV2` (a pasta de dados do projeto não mudou com a promoção).

## Controles

| Ação | Controle |
|---|---|
| Caminhar | WASD ou setas, em relação à câmera |
| Correr | Shift |
| Trocar arma (a pé) / sintonizar rádio (dirigindo) | Roda do mouse |
| Girar a câmera exterior | Z / C |
| Entrar, sair, conversar, coletar e avançar diálogo | E |
| Salvar / carregar checkpoint | F5 / F9, fora do carro e diálogos |
| Pausa, voltar ao início e sair | Esc |
| Entrar / sair do carro dourado | F, próximo da porta / com o carro parado |
| Acelerar / frear até engatar ré | W / S, dirigindo |
| Virar o volante | A / D, dirigindo |
| Frear | Espaço |
| Repetir percurso experimental | R, somente iniciado com --sandbox |
| Mostrar desempenho e população | F3 |
| Diminuir / aumentar população | [ / ], com o painel F3 aberto |

## Estrutura

| Pasta | Conteúdo |
|---|---|
| `runtime/`, `scripts/` | sessão, mundo de produção (população, trânsito, regiões), save, câmera, direção, veículo |
| `systems/`, `data/`, `migration/` | campanha, economia, catálogos, importação do save da V1 |
| `world/` | regiões em streaming (`world/regions/NativeRegion.gd`), cidade, lugares, ponte |
| `gameplay/`, `activities/` | combate, polícia e emergência, trânsito, física de rua, atividades |
| `audio/`, `ui/`, `cutscenes/`, `assets/` | som, interface, abertura e arte |
| `tests/` | testes funcionais (`test_*.gd`), `tests/measure/` (desempenho) e `tests/capture/` (capturas) |
| `tools/` | exportação de modelos e sons, bake de veículos, geração de evidências |
| `docs/` | documentação — comece por [docs/README.md](docs/README.md) |
| `evidence/` | relatórios de validação (só `.md`/`.json`/`.patch` no Git; imagens e vídeos ficam no disco) |

## Testes

```powershell
powershell -ExecutionPolicy Bypass -File tests/run_suite.ps1            # suíte completa
powershell -ExecutionPolicy Bypass -File tests/run_suite.ps1 -Filter regions
```

Cada teste é um script `SceneTree` que sai com 0 (passou) ou 1 (falhou), roda sem janela e
com `--no-save`. Medições de desempenho exigem renderização real e ficam em
`tests/measure/`. Convenções para agentes e desenvolvedores: [CLAUDE.md](CLAUDE.md) e
[AGENTS.md](AGENTS.md).
