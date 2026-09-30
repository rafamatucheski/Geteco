# Sonda de picos de quadro (streaming) — 29–30/09/2026

`tests/measure/probe_region_hitches.gd` atravessa o mundo (porto → costura → montanha, e de volta, 2 voltas)
teleportando o foco do jogador a ~25 m/s e registra todo quadro acima de 40 ms com posição, divisão
processo/física/render, custos etiquetados do jogo e (com `--per-script`) o tempo de cada `_process` por script.
Renderizado, 1280×720, sem outra instância Godot ativa. **Não reproduz combate, polícia nem chuva.**

Arquivos: `probe-<rótulo>.json` (`summary`, `spikes`, `costs`).

| Arquivo | O que mostra |
|---|---|
| `probe-off` / `probe-on` | Passe genérico da frota desligado/ligado (com cache). |
| `probe-abl_*` | Ablação: sem tráfego, sem população, sem os dois. Os picos continuam: é o mundo, não os agentes. |
| `probe-perscript` | Cada `_process` cronometrado: `EditableRegion` (construção/liberação de chunk) domina. |
| `probe-phases2` | Picos quase todos em scripts; desenho e GPU não pesam. |
| `probe-retire2`, `probe-seam*`, `probe-fin*` | Depois das correções (ver `docs/mudancas-20260929-30-claude.md`). |
| `probe-twolaps` | A 2ª volta tem tantos picos quanto a 1ª: custo por visita, não de primeira vez. |

Evolução (quadros acima de 40 ms / máximo): 36 / 1.403 ms → 25–29 / 123–160 ms.

Ainda aberto: parada rara de 0,7–1,4 s (≈1 rodada em 3), sem script lento. Com `--verbose` a saída do console
sozinha já causa paradas de 1,5 s, então essa opção não serve para caçá-la.
