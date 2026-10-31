# Forte da Serra: expansão e recompensa narrativa (31/10/2026)

Card "Expansão do forte e recompensa narrativa". Continua `docs/fort-operation-plan.md`.

**O que existe de verdade hoje:** ante-sala, sala de operações (com a mesa de comando) e
elevador. **Alojamento, arsenal e comando são propostas**: a regra, os soldados, o save e
as recompensas estão no código, mas as salas **não têm geometria** e não devem ser
contadas como áreas existentes.

## Fluxo da operação

1. **Sala de operações** (existe): combate atual. Pegar o saque abre a expansão
   (`FortExpansionState.unlock`, fase `desk`).
2. **Mesa de comando** (existe, jogável agora): com a sala limpa, "Revistar mesa de
   comando" entrega o memorando ("Ninguém desce sem o V."). Fase passa a `barracks`.
3. **Alojamento** (proposta): entrada furtiva. Duas sentinelas dormindo e um operador de
   rádio. Barulho, dano ou o rádio acordam todo mundo. Limpar **sem alarme** paga bônus.
4. **Arsenal** (proposta): escudeiro + fuzileiro + atirador. Saque único de arma especial
   (fuzil de caça com 40 balas; quem já tem leva só as balas) + 120 balas de M4.
5. **Comando** (proposta): líder, escudeiro, operador de rádio e atirador. O cofre tem a
   revelação; abrir o cofre **desliga o rádio do forte**: dali em diante o alarme acende,
   mas ninguém responde (sem reforços, sem chamada de rádio).
6. Fim: fase `complete`, a linha do forte sai do diário.

A ordem é obrigatória (save forjado que pula fases é recusado no load).

## As três áreas

| Área | Função de gameplay | Recompensa |
|---|---|---|
| Alojamento | Furtividade: sentinelas dormindo (`sleeping`), operador de rádio a abater antes de 6 s em combate. Alarme = perde o bônus. | R$ 2.500 ("Alojamento do forte") + R$ 1.500 se silencioso ("Entrada silenciosa"); pista: escala de 1998 |
| Arsenal | Saque de arma especial uma vez + munição; combate contra escudo e luneta | Fuzil de caça + 40 balas (ou só as balas), 120 balas de M4; pista: livro de saída para o setor 7 |
| Comando | Cofre com a revelação; corta reforços | R$ 12.000 ("Cofre do comando"); três pistas (abaixo) |

Dinheiro sai por `Economy.grant_reward(recibo, valor, rótulo)`: o rótulo aparece no aviso
central do HUD. Recibos: `mountain_fort_<área>_cash|_quiet|_weapon|_weapon_ammo|_ammo_m4a1`.

## Tipos novos de soldado (mesma malha `PoliceModel` ARMY e mesma IA)

Só parâmetros em `FortSoldier.ROLE_PARAMS`; a arma visível continua a M4 (malha e material
já pré-aquecidos, nada compila no jogo).

- **Atirador** (`marksman`): 80 de vida, vê a 34 m, tiro único de 16 de dano a cada
  1,6–2,2 s, perde pouca precisão com a distância, segura posição.
- **Escudeiro** (`shield`): 120 de vida, segura 80% do dano **de frente** (cone ~100°),
  alcance curto (12 m), avança devagar (65%). Resposta: flanquear.
- **Operador de rádio** (`radioman`): 80 de vida, recua para longe. Se ficar **6 s vivo em
  combate**, chama reforço: sem alarme, dispara o alarme; com alarme, traz uma onda extra
  (fuzileiro + flanqueador), uma vez por visita. Abatido ou com o rádio do comando
  cortado, não chama.
- **Sentinela dormindo** (`sleeping` no spec): não vê até ouvir barulho, levar dano ou ser
  alertado pelo rádio.

## Revelação sobre Vicente (cânone)

Avança **quem** (Vicente assinou o lacre), **onde** (setor 7, este forte) e **o que
saiu** (lanternas, cal, lacre de chumbo), sem dizer **por quê**. Nada confirma origem
sobrenatural; toda pista admite leitura mundana (contaminação, obra, acidente) e outra
estranha.

- Memorando da mesa: "Ninguém desce sem o V."
- Escala do alojamento: nome de Vicente riscado, "transferido" escrito e apagado.
- Livro do arsenal: saída de material para o setor 7 assinada por V.
- Ordem de lacre: assinada por Vicente; o motivo foi cortado com tesoura.
- Fita citada: "Setor 7, última ronda, V." A fita não está lá ("enviada para a cidade").
- Crachá de Vicente: foto arranhada; número de cofre que não é do forte (gancho futuro).

## Código

- `gameplay/urban_v1/fort/FortExpansionState.gd`: fases, recibos, recompensas, pistas,
  esquadrões por sala, linha do diário, `RadioCall`. Estado em
  `world_state.mountain_fort_expansion` (validado no load pelo `GameState`).
- `FortSoldier.gd`: `ROLE_PARAMS`, `sleeping`, `shield_block`.
- `FortOperation.gd`: mesa de comando, `complete_expansion_area`,
  `spawn_expansion_squad(área, pontos)`, rádio (`_update_radios`, `radio_called`), alarme
  sem reforço quando o rádio foi cortado.
- `JournalArcs.gd`: linha do forte no diário.
- Teste: `tests/test_fort_expansion.gd`.

## Precisa de arte/geometria nova (pendente)

- As três salas: paredes, portas entre elas, iluminação (via `LightBudget`), coberturas
  (`HALL_COVERS` por sala), extensão do `ROOM_BOUNDS`/grade A* e da câmera de
  acompanhamento, admissão física do lugar. Dá para fazer com as caixas/cilindros do
  `MountainFort.gd`, mas sem Godot nesta sessão não dava para conferir enquadramento,
  navegação nem custo de quadro; ficou de fora de propósito.
- Beliches e armários (alojamento), prateleiras e caixa da arma especial (arsenal), cofre e
  console de rádio (comando).
- Escudo visível do escudeiro e fuzil com luneta do atirador (hoje todos mostram a M4 para
  não criar material novo sem pré-aquecimento).
- Som de rádio chamando e de alarme.
- Fita cassete tocável no Arquivo de Vicente (só citada por enquanto).
