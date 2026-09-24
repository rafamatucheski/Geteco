# Reações civis V1 → V2

Módulo novo e exclusivo: `gameplay/civilian_reactions/` (`CivilianReactionDirector`, `CivilianDanger`,
`CivilianReactionPresenter`). Teste: `tests/test_civilian_reactions.gd` (sessão de produção real, `--no-save`).

**Estado: conectado uma única vez na sessão produtiva.** `ProductionWorld` instancia o diretor depois de `Gameplay` e `configure(world, gameplay)` conecta o sinal existente `weapon_fired`.

## Separação por responsabilidade

| Etapa | Onde |
|---|---|
| Perceber | `report_gunfire`, `report_explosion`, `report_assault`, `report_horn`, varredura de ciclo de vida e buzina 4 Hz; tiro entra sozinho por `Gameplay.weapon_fired` |
| Decidir | `CivilianDanger` (memória ≤4 ameaças, vida 12 s, dedupe 1 m, candidatos com raio de mundo/veículo, penalidade na linha de tiro) |
| Mover | só ganchos públicos de `Actor`: `controlled_automatically`, `automatic_direction`, `speed` |
| Apresentar | `CivilianReactionPresenter`: grito (`panic_0..2.wav` do V1, ≤3 vozes, 4 s por civil) e balão Label3D (textos do V1) |
| Retomar | `_release`: devolve controle/velocidade e reengata `waypoint` no ponto mais próximo da rota |

## Comparação por reação

| Reação | V1 | V2 (este módulo) | Diferença/limite |
|---|---|---|---|
| Tiro | `hear_gunfire` no raio 240 px (80 silenciado); panic 9–12 s; grito; "TIROS! CORRE!" | raio 40 m (13 m silenciado), panic 9–12 s, grito, mesmo balão | **Conversão px→m assumida** (não medida). Silenciador vem de `Gameplay.weapon_data(weapon_id).suppressed`, cujo acessório real é `suppressor` |
| Fuga | replan 2 Hz, candidatos 150/72/36 px em ângulos, raio, penalidade de linha | idem em metros (12/6/3), raio contra camadas 1+4, replan 0,5 s, detecção de travamento (1 s <0,5 m descarta direção) | Não enxerga outros civis como obstáculo (só mundo e veículos) |
| Rajada | remember dedupe | dedupe 1 m renova sem reiniciar; grito com cooldown | — |
| Explosão | (V1 chama panic via caminhos próprios) | `report_explosion`, raio 55 m | **Nada chama ainda**: `Gameplay.explode` precisa chamar o contrato |
| Buzina | **não é pânico**: quem está à frente do veículo dá passo ao ombro livre por 4,5 s; sem ombro livre não faz nada | idem (9 m à frente, meia-largura 2,4 m, raio de parede) | Detecção por subida de `horn_audio.playing` nos veículos do grupo `drivable` |
| Agressão (melee/fogo) | `panic()` ao ser ferido | `report_assault(person, source)` exige origem real | Sem metadado confiável, a queda de vida não inventa o jogador como agressor |
| Atropelo | derruba/incapacita, **não foge** | nenhuma autoria é inferida por proximidade | O desmaio segue com `Actor`; integração futura deve entregar a fonte real |
| Morte/removido | — | estado solto no quadro seguinte, sem tocar no objeto | — |
| Retomada | recover 2–4 s a 0,75 da velocidade, rejoin da rota | idem 2–4 s a 3,5 m/s, waypoint mais próximo | Civil sem rota fica parado |
| Distância | — | >110 m do jogador solta o civil | — |

## Distinções preservadas
Só reage `CharacterBody3D` com `gameplay_role == "civilian"`, fora do grupo `v1_routine_actor`, sem `interior_actor`/`reaction_exempt`,
vivo e **não** controlado por outro sistema no alerta. Polícia, Cobras, atores de rotina V1 e missões ficam de fora.
Maciota e mecânico: o módulo não causa dano nem morte; não estão em `world.people`.

## Evidência (execução real, Godot 4.7.2, Vulkan, `--no-save`)
`tests/test_civilian_reactions.gd`: **35 casos, 0 falhas**, sem erros de script. Cobre: instância produtiva única, tiro real normal/silenciado sem duplicação, continuidade cidade–serra, raio de audição, fuga
(10 → 17,5 m em 1,5 s), rajada de 300 tiros sem reiniciar nem empilhar (1 ameaça, mesmo nº de reatores), parede larga, alvo removido,
morte, suspensão por distância (velocidade restaurada), recuperação e retomada da rota, distinção (controlado/rotina/papel),
buzina (passo lateral, sem ombro livre, retoma em 4,5 s), agressão por dano, explosão, `reset_region`, referências limpas.

## O que NÃO foi provado
- **Aparência da fuga**: o modelo civil só tem flag `walking`; correr a 5 m/s usa a mesma animação de andar. Sem pose de susto/corrida.
- Balão e grito foram criados, mas não vistos/ouvidos numa partida; o teste só confere existência/limites.
- O caso "parede" foi contornado pelo civil (fugiu pela ponta), então a rota de **travamento** (`stuck_replans`) ficou em 0 — não foi exercitada.
- Sem teste de multidão/performance; MAX_REACTORS=24 e varredura a 4 Hz não foram medidos.
- Se outro sistema assumir `controlled_automatically` *depois* do pânico, o módulo não distingue de si mesmo.
- Explosão ainda foi exercitada pelo contrato `report_explosion`; `Gameplay.explode` não publica um sinal próprio.

## Conexão atual e contratos restantes
1. **ProductionWorld:** conexão concluída com a assinatura real `configure(world, gameplay)`. `reset_population()` ocorre só no descarregamento por viagem rápida; mudança lógica de `region_id` não apaga uma reação ativa.
2. **Gameplay** (dono do combate): tiro já entra pelo sinal real existente. Para explosões, o contrato mínimo pendente é publicar uma vez `{origin, radius, source}` a partir de `explode(...)` para `report_explosion`; nenhuma origem foi inferida nesta frente.
3. **routines_v1** (time de vida urbana): atores de rotina V1 não reagem por este módulo. Se quiserem, expor
   `pause_for_reaction()` / `resume_from_reaction()` e o diretor passa a chamá-los; hoje não há esse contrato.
