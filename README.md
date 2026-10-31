# Geteco

Jogo de mundo aberto em 3D nativo no Godot 4.7.2 .NET, com GDScript e C# (.NET 10). Versão
atual: **0.3.3** (alpha; aparece na marca d'água do canto da tela junto com o commit).

Este repositório é o jogo principal. Ele nasceu como a "V2", uma migração da V1 para o
3D nativo, e foi promovido à raiz em 24/09/2026. A V1 está preservada no ramo
`v1-legado` e na tag `v1-final`.

## O jogo hoje

- **Mundo em streaming:** Harbor (cidade e porto), Mountain (serra, vilarejo, serraria e abrigos)
  e a Estrada do Sal (deserto, salinas, Motel Oásis, cavernas), ligados por ponte com túnel e
  rodovia; chuva com poças, noite com fases da lua, mar com ondas, lagos e ursos na serra.
- **Veículos:** carros com tração por eixo (AWD, FWD, RWD, 4x4), esportivos, muscle cars e
  lowriders com hidráulica, motos, ônibus; roubo de carro e entrada/saída com mocap; rádio.
- **Trânsito e rua:** semáforos com fases, pedestres e moradores com rotina.
- **Combate:** armas com variantes, silenciador e som estéreo; corpo a corpo com espada e
  escudo do gelo (Cabana do Cavaleiro); reações de dor e queda com mocap.
- **Polícia e emergência:** perseguição de carro, reforços até seis estrelas, helicóptero,
  bombeiros com hidrante, Bay Medical e delegacia.
- **Campanha e atividades:** histórias do Harbor e de Vicente, diário (J), fretes, guincho,
  carro-forte, corrida Descida da Meia Noite, bares com dardos e bilhar, academia Ferro Velho
  (força e fôlego), lojas e mais de 25 interiores com porta física.
- **Save próprio** com recuperação de slot danificado e importação do save da V1.

O que mudou em cada versão está no [CHANGELOG.md](CHANGELOG.md) e no board
`docs/painel-geteco.html`.

## Abrir

- Dois cliques em **Jogar.cmd** para jogar; **Editar.cmd** abre o editor .NET. Ambos compilam os scripts C# antes de abrir.
- Também é possível importar o `project.godot` no gerenciador do **Godot .NET (mono)** e pressionar F5. Use o SDK .NET 10 para compilar `Harbor.csproj`.
- Em outra instalação, use `Open.ps1 -GodotPath 'caminho/do/Godot_mono.exe'` ou defina `GODOT_EXE`.
- O save fica em `user://GetecoV2` (a pasta de dados do projeto não mudou com a promoção).

## Controles

| Ação | Controle |
|---|---|
| Caminhar | WASD ou setas, em relação à câmera |
| Correr | Shift |
| Pular a pé | Espaço; A no Xbox / X no PlayStation |
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

```bash
tools/run_core_suite.sh        # contratos (~2 min), antes de commitar
tools/run_core_suite.sh full   # inclui a verificação estrutural
powershell -ExecutionPolicy Bypass -File tests/run_suite.ps1 -Filter regions  # um filtro, no Windows
```

Godot roda sempre pela fila `tools/run_godot_locked.sh`, um por vez; o guia completo
(desempenho, medição em release, regras de código) está em
[docs/HOW-TO-DEVELOP.md](docs/HOW-TO-DEVELOP.md).

Cada teste é um script `SceneTree` que sai com 0 (passou) ou 1 (falhou), roda sem janela e
com `--no-save`. Medições de desempenho exigem renderização real e ficam em
`tests/measure/`. O CI (`.github/workflows/ci.yml`) compila o C# e roda os contratos rápidos
de `tools/run_core_suite.sh` em headless a cada push e pull request. Convenções para agentes e desenvolvedores: [CLAUDE.md](CLAUDE.md) e
[AGENTS.md](AGENTS.md).
