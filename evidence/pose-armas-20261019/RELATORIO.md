# Pose de armas do Dante: falhas de test_melee_moveset e test_firearm_rig (19/10/2026)

## O que falhava

- `tests/test_melee_moveset.gd` 53/55: soqueira (golpe 1 "braço na frente do rosto" Left ×7,
  golpe 3 ×1) e taco (golpe 0 Right ×4, golpe 1 Right ×5).
- `tests/test_firearm_rig.gd` 190/192: recarga do RPG (arma 5,2 cm na pele no quadro 64;
  limite 3,5) e troca punhos → lança-chamas (4,5 cm no quadro 10; limite 4,0).

## Desde quando (medido em worktrees separados, sem trocar arquivos do checkout principal)

| commit | melee | firearm |
|---|---|---|
| 758f1a61 (12/10, antes da consolidação) | 55/55 | 192/192 |
| 5e7d0360 (12/10, "Consolida trabalho integrado…") | falha igual ao HEAD | falha só a troca punhos → lança-chamas (RPG passa) |
| 199d5d18 (antes da katana 7bb1a365) | falha igual ao HEAD | falha igual ao HEAD |

- A katana (7bb1a365) não tem relação: antes dela as falhas são as mesmas.
- Melee e troca do lança-chamas: 5e7d0360. Ele reescreveu `Actor._build_idle_pose`: o quadril
  parado passou da média da caminhada +0,012 para a altura de repouso. Medido parado:
  centro da cabeça y 1,599 → 1,571 m, ombro direito 1,383 → 1,355 m, `body_bob` +0,028 → 0.
- RPG: depois de 5e7d0360 e antes de 199d5d18. Por eliminação (não rodei a4634240^): o único
  commit no intervalo que muda a geometria do RPG é a4634240 (16/10), que trocou o cone do
  `LoadedRocket` por uma ogiva mais gorda (raio 5,6 cm por mais comprimento).

## Defeito real ou teste velho

Defeito real de pose. O jogo passa `combat_rig_info().body_bob` ao `WeaponRigPose` (quase todo
alvo de mão soma esse deslocamento); os testes chamam `update()` sem `rig`. Até 12/10 isso dava
aos testes 2,8 cm de folga por acaso (corpo mais alto que as mãos); desde 12/10, parado, teste
e jogo coincidem (`body_bob` 0). Os golpes de taco/machado não somam `body_offset`, então no
jogo o taco passou mesmo 2,8 cm mais perto do rosto em 12/10. Todos os quadros reprovados
estavam na borda da zona (punho 11,6–13 cm abaixo do centro da cabeça; limite 13).

Onde, medido (diagnóstico por quadro):
- soqueira, direto: na cadência de 0,34 s o soco sai antes de o jab voltar, e a esquerda ficava
  parada a meio caminho (−0,110, 1,402, −0,350) na frente do queixo o golpe inteiro;
  uppercut: o corpo desce 9 cm (dip 0,075) e a guarda esquerda parada encontrava a cabeça;
- taco: follow-through do forehand (t 0,42–0,43 s) e backhand da preparação ao contato
  (t 0,27–0,33 s), punho direito rente ao queixo;
- RPG: ogiva dentro do antebraço/punho ESQUERDO no encaixe e na volta ao tubo (palma no eixo
  do foguete; ponto mais fundo a 10–12 cm da palma);
- lança-chamas: antebraço esquerdo subindo por dentro do corpo da arma nos quadros 8–10 do
  saque (a arma aparecia a 0,6 do saque, antes de a mão de apoio chegar). Só aparece com o
  histórico do teste inteiro; isolado dá 0,9 cm.

## Correções

- `MeleeMoveset.PUNCHES`: na primeira chave de cada soco a outra mão volta à guarda (posição,
  giro e polo); no uppercut a guarda esquerda acompanha o agachamento (`GUARD_DIP`).
- `MeleeMoveset.SWINGS`: follow-through do forehand (t 0,47) e backhand até o contato
  (t 0,26 e 0,36) 2,5 cm mais baixos. O forehand é o mesmo do machado.
- `WeaponRigPose`: palma do RPG na lateral da ogiva voltada para o ombro esquerdo
  (`RPG_ROCKET_SIDE` 7 cm do eixo) do encaixe em diante; lança-chamas aparece a 0,95 do saque
  (`EQUIP_SHOW_BY_ID`).
- `tests/capture/capture_melee_filmstrip.gd`: `mode=switch`, `only=` com várias armas e `look=`.

## Verificação

- Checkout principal: `test_melee_moveset` 55/55, `test_firearm_rig` 192/192 (RPG recarga 3,2 cm
  no quadro 52; troca punhos → lança-chamas 1,3 cm). Fora os quatro itens, todas as folgas,
  velocidades articulares e alcances saíram idênticos aos de antes.
- `test_weapon_presentation_contract` 150/150.
- `test_weapon_locomotion` 320/323: as 3 falhas (soqueira correndo com o braço no rosto ×18;
  M4A1 mirando andando 4,2 cm e de lado 3,6 cm na pele) são idênticas com o código do HEAD —
  anteriores a esta mudança, não corrigidas aqui.
- Sonda numérica da recarga do RPG: até o encaixe (t ≤ 0,50) palma e foguete idênticos ao HEAD;
  depois, a palma fica 5–7 cm mais perto do corpo e o foguete termina no mesmo lugar do tubo.

Capturas (fora do Git, nesta pasta): `antes/` e `depois/` (corpo inteiro), `antes-zoom/` e
`depois-zoom/` (rosto e braços; mão de apoio):
- `melee_knuckles-bat_front.png`: linhas 1–4 soqueira (jab, direto, gancho, uppercut), 5–7 taco
  (forehand, backhand, diagonal). Antes, coluna 5 do forehand: o taco cruza na frente da barba;
  depois passa na altura do peito; no direto a mão esquerda volta para o lado.
- `reload_rpg_left.png`: depois, do encaixe em diante a palma fica na lateral da ogiva.
  A coluna 6 de `depois-zoom` mostra o foguete fora da palma: artefato de render da tira
  (a sonda mostra foguete = palma nesse quadro, igual ao HEAD).
- `switch_flamethrower_left.png`: antes a arma aparece (colunas 3–4) com o braço ainda subindo;
  depois só com a mão no apoio.

## Não verificado

- Jogo de verdade (Gameplay): parado, os socos de punhos/soqueira tocam os clipes da UAL; o
  golpe procedural ajustado aqui é o de andar (e o A/B `ab_punch_clip`). Não abri o jogo.
- `test_combat_flow` e `test_dante_combat_timing` (sessão inteira) não rodados.
- Desempenho: só constantes e um cálculo vetorial a mais por quadro de recarga do RPG; não medido.
