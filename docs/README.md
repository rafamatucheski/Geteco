# docs/

## Aqui na raiz — documentação que continua valendo

- [ARCHITECTURE.md](ARCHITECTURE.md) — mapa técnico: cadeia de entrada, autoloads,
  física 2D com apresentação 3D, streaming entre regiões, cadeia de despacho de
  emergência e as pendências conhecidas. **Comece por aqui.**
- Documentos por sistema, sem data no nome: descrevem como uma parte do jogo funciona
  (`CITY_AMMUNATION.md`, `HARBOR_CITIZEN_ROUTINES.md`, `BANK_ROBBERY_PROTOTYPE.md`,
  `CLOTHING_AND_SERVICE_CAST.md`, `WEST_MEMORIAL_WORLD_EVENTS.md`,
  `CODEX_MOUNTAIN_PASS_ARCHITECTURE.md`, `MOUNTAIN_PASS_ASTRA_REFINEMENT.md`).

## `history/` — relatórios de sessão

Documentos com data no nome (`*_2026-09-08.md`) e briefings de sessão (`PROMPT_*.md`).
São registro do que foi feito e por quê numa data específica, não descrição do estado
atual. **Podem estar desatualizados** — servem para entender uma decisão passada, não
para saber como o código está hoje.

Ao ler um documento de `history/`, confira contra o código antes de agir: nomes de pasta
mudaram (`district/harbor_preview/` virou `world/harbor/` em 2026-09-09) e vários
comportamentos descritos ali já foram alterados.
