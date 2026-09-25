# Ammu-Nation — travamento de entrada/reentrada (Claude, 25/09/2026)

Estado: **reentrada corrigida no cenário medido; primeira entrada depende de
integração no carregamento (patch abaixo) e ainda tem um quadro residual de
60 ms de causa não identificada. FPS não certificado.** Sem commit.

## Causa demonstrada

Probe de CPU com renderer real (Vulkan/Mobile, `tests/test_claude_ammo_perf_probe.gd`)
e atribuição por linha de `room()` (cópia instrumentada em memória):

1. **Armas expostas remontadas a cada visita.** `item()` chamava `ARSENAL.build` +
   agrupamento WeaponFinish para as 12 armas, o colete e as granadas em toda
   entrada. Os caches existentes cobriam só caixas/chanfros/materiais (~2,5 ms). As
   armas custavam ~60–80 ms por visita.
2. **Variante de shader do vidro descartada e recompilada.** O vidro precisa de
   material exclusivo por sala. Ao liberar a sala anterior, a variante transparente
   perdia a última referência e a atribuição do novo material custava ~19–20 ms em
   **toda** visita. No micro-teste, qualquer material novo custa ~19 ms enquanto
   nenhum material vivo com RID retém a variante; com a variante retida, 0,015 ms.
3. Descartado: a inclusão na árvore custa ~0,5 ms para 643 nós. Montar dentro ou
   fora da árvore não é o problema.

## Correção (só `assets/regions/source/guns/ammunation/AmmunationArt.gd`)

- `item()`: na primeira montagem de cada id, o resultado já agrupado vira um
  `PackedScene` (limite 32 ids). As visitas seguintes instanciam e reaproveitam os
  nós. Malhas e materiais ficam compartilhados, como nos caches anteriores. O
  `PackedScene` guarda só recursos: nenhum nó ou instância de render fica viva fora
  da árvore (0 avisos/vazamentos na saída). A boca da arma (`weapon_muzzle`) é
  preservada.
- Vidro: `_glass_template` estático com `get_rid()` retém a variante. Cada sala
  recebe `duplicate()` exclusivo; o teste confirma o isolamento entre salas.
- `prewarm()`: monta e descarta uma sala de cada variante e devolve os ms. Deixa
  modelos e variantes prontos. Custo medido: 97,9–102,8 ms uma vez; depois 7,4 ms.
  Memória estática do processo após aquecer: ~133 MB (valor do processo inteiro,
  não o delta; o delta não foi isolado).

Geometria, transformações, materiais, vidro, Vance/pivôs, peças móveis e
personalização: idênticos ao snapshot anterior (teste `art_cache` com `--legacy`).
Não foram alterados fades, resolução, população, objetos ou limite de FPS.

## Integração proposta (arquivo do Codex, não aplicada)

`runtime/ProductionWorld.gd`, em `_prewarm_regions()`, logo após
`VehicleDamage.gd._char(false)` (sob a cortina de carregamento):

```gdscript
	# Ammu-Nation: modelos das armas expostas e variantes de shader (vidro) sem
	# pagar ~70 ms na primeira entrada. Medido 25/09: ~100 ms uma vez no load.
	preload("res://assets/regions/source/guns/ammunation/AmmunationArt.gd").prewarm()
```

Contrato: estático, síncrono, idempotente. Chamadas repetidas custam só a
montagem leve (~7 ms). Sem essa linha, só a reentrada melhora.

## Medição renderizada (Main real)

Ambiente: Godot 4.7.2, Mobile/Vulkan, RTX 4060 Laptop, 2560×1440, MSAA 2x, VSync,
limite 60, seed 21092026, clima limpo 09:07, população 40, `--no-save`, script
`tests/measure/video_phase4_ammunation.gd` (C: `tests/test_claude_ammo_perf_main.gd`,
que chama `prewarm()` antes da Main). **Nenhum outro Godot em execução** (conferido
antes de cada rodada; editor e jogo do usuário estavam fechados). As rodadas foram
sequenciais, uma de cada, sem repetição: a variação entre rodadas não foi medida.
A "antes" restaurou temporariamente o snapshot do meu arquivo, que depois voltou
com o hash conferido.

| ms | A antes | B depois | C depois + prewarm |
|---|---:|---:|---:|
| 1ª entrada máx | 142,0 | 139,1 | **60,3** |
| 1ª entrada p50/p95/p99 | 16,60/18,44/21,90 | 16,67/17,37/17,89 | 16,68/18,31/20,36 |
| 1ª entrada >33,3 / >66,7 | 1 / 1 | 1 / 1 | 1 / 0 |
| arte na 1ª entrada | 72,4 | 63,3 | **3,6** |
| reentrada máx | 118,8 | **32,9** | **30,8** |
| reentrada >33,3 / >66,7 | 1 / 1 | 0 / 0 | 0 / 0 |
| arte na reentrada | 66,3 | **3,8** | 3,4 |
| saída máx | 83,8 | 19,0 | 17,7 |
| interior 30 s p50/p95/p99 | 16,66/17,73/18,68 | 16,71/17,64/18,73 | 16,81/17,88/18,42 |
| interior 30 s máx, >33,3 | 20,5, 0 | 23,7, 0 | 22,3, 0 |

Dados brutos: `evidence/claude-ammo-performance-20260925/claude-{before,after,prewarm}.json`
e `main-*.log`. Fotos: `claude-*-first-inside.png` e `claude-*-steady-inside.png`,
abertas e comparadas (antes × prewarm idênticas, exceto a pose do jogador).

- O pico da saída (83,8 → ~18 ms) também caiu. Hipótese, não provada: liberar a sala
  deixou de descartar variantes/recursos.
- **Pendente:** 1 quadro de 60 ms na primeira entrada com prewarm. GPU ~3 ms, render
  CPU ~0,45 ms, arte 3,6 ms, nativo 10,9 ms: o custo está fora da arte e não foi
  identificado. Candidatos a verificar pelo Codex: primeira construção de
  catálogo/entrada/NPC em FullSession/NativePlace, ou compilação de pipeline no
  primeiro desenho.
- **Hipótese rejeitada:** desenhar a sala num SubViewport antes da Main
  (`claude-renderwarm.*`) piorou (máx 183,9 ms, 11 quadros >66,7 ms e 1086 ms no
  aquecimento). O código foi removido.

## Testes

Todos com exit 0. Os headless validam comportamento, não FPS.
- `test_video_phase4_art_cache.gd --legacy=<snapshot>`: 29/29. Sala Harbor/Mountain
  idêntica ao snapshot; vidro independente; acabamento/recolor não contaminam;
  caches limitados. Recursos distintos: malhas 192→163, materiais 150→124 (armas
  repetidas compartilham).
- `test_video_phase4_weapon_batch.gd`: 144/144.
- `test_video_phase4_workbench.gd -- --no-save`: 59/59 (a prévia usa `item()`).
- `test_claude_arsenal_ui_parts.gd`: 172 combinações, 774 checks.
- `test_claude_ammo_perf_probe.gd` (renderizado): 643/614 e 665/635 nós/malhas
  preservados; montagem por visita ~85 ms → ~3 ms; 0 avisos.

## Arquivos

- Alterado: `assets/regions/source/guns/ammunation/AmmunationArt.gd`.
- Novos: `tests/test_claude_ammo_perf_probe.gd`, `tests/test_claude_ammo_perf_main.gd`,
  `docs/claude-ammo-performance-20260925.md`, evidências em
  `evidence/claude-ammo-performance-20260925/` (snapshots `.gd.txt`, hashes, logs,
  JSON, PNG).
- Não tocados: ArsenalWeapon3D, WeaponFinish3D, arquivos do Codex, catálogo/bancada.

## Limites

Uma rodada por condição; população dinâmica real (não fixa). Não medidos: chuva/noite,
Mountain renderizada, UI do catálogo aberta, combate. A meta de 60 FPS/16,67 ms **não**
é declarada aprovada: a primeira entrada ainda tem um quadro de 60 ms e a
integração do prewarm está pendente.
