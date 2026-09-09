# world/ — as regiões jogáveis

Esta é a árvore viva do jogo. Antes de 2026-09-09 estava espalhada dentro de `district/`,
com o jogo principal chamado `harbor_preview` — nome que sugeria protótipo e enganava
quem chegava.

| pasta | o que é |
|---|---|
| `harbor/` | **O jogo principal.** `HarborGame.tscn` (herdada de `HarborPreview.tscn`) é o que o menu carrega. Contém a campanha (`campaign/`), os interiores (`interiors/`), a gangue das Cobras (`cobras/`), os eventos de mundo (`events/`) e a arte do distrito (`art/`) |
| `mountain_pass/` | Segunda região. Não é uma cena separada carregada por troca: `harbor/ContinuousWorld.gd` a mantém na mesma árvore, dormente, e acorda quando o jogador se aproxima da emenda |
| `shared/` | Infraestrutura usada pelas duas regiões |

## `shared/`

| pasta | responsabilidade |
|---|---|
| `roads/` | Malha viária: `UnifiedRoadNetwork2D`, junções, semáforos, segurança de travessia e o `EmergencyLaneRouter` que planeja rota de veículo de emergência sobre o grafo de faixas |
| `pedestrians/` | Agentes de calçada com rota autorada |
| `emergency/` | Depósitos de serviço: `EmergencyDepotDirector` (classe base de despacho), marcadores de depósito, portões, pátio de veículos e a fábrica de tráfego moderno |
| `nature/`, `rail/` | Vegetação e ferrovia |

## Regiões dormentes, não descarregadas

`ContinuousWorld.gd` não faz troca de cena entre porto e montanha. Ele mantém as duas na
mesma árvore e desliga a que está longe: `process_mode = PROCESS_MODE_DISABLED` e
`visible = false`. Tráfego ambiente a mais de 3.400 px do jogador também tem o
processamento desligado, preservando instância e estado em vez de respawnar.

Consequência prática: uma região distante **não simula nem renderiza**, mas continua
ocupando memória. Ver [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md) para os números.
