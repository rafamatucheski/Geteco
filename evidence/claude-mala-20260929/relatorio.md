# Mala de mão: mira, tiro e movimento (29/09/2026)

Autor: Claude. Vídeo analisado: gravação de 15,7 s do usuário (mala na mão esquerda, pistola, andando, mirando e atirando).

## O que estava errado (vídeo + código)

1. **A mala subia com a mira.** A mala é pendurada no osso `LeftHand` (`BagVisual._hand_hang`, a cada quadro). Ao mirar,
   `WeaponRigPose` manda a mão esquerda para o apoio da pistola (empunhadura de duas mãos: `support` ≠ 0, `left_solve`) e a
   mala ia junto até o peito. A recarga (mão esquerda vai ao pente) e a guarda de soco faziam o mesmo.
2. **Andando, a mala cruzava o corpo.** Com a pistola baixa o braço esquerdo não era resolvido e seguia o clipe de caminhada
   (vaivém de ±30 cm à frente e ao través do corpo), levando a mala junto.
3. **Mala colada na mão**, sem inércia: posição rígida a partir da palma, sem balanço ao arrancar, parar ou virar.

Reproduzido em palco mínimo (Actor + mala + pistola): antes, `05-aim`, `06-aim-recoil`, `07-aim-walk`, `08-reload` e
`09-fists-guard` mostram a mala na altura do peito.

## Ideia: "uma mão ocupada"

- **A mão esquerda é da mala** (`gameplay/WeaponRigPose.gd`, `bag_carry`): braço quase reto ao lado da coxa, palma com os dedos
  fechados na alça (orientação escolhida entre 8 candidatas em captura), quase sem vaivém (a mala pesa) e um leve recuo na corrida.
  Nunca vai ao apoio da pistola, à munição nem ao soco.
- **Só a direita trabalha:** mira, tiro e recarga da pistola são de uma mão (o recuo triplicado com a mala, que já existia, faz
  sentido); com a mala o soco sai sempre da direita; soqueira esquerda não aparece.
- **Mala como pêndulo** (`systems/inventory/BagVisual.gd`): a alça acelera, o corpo da mala fica para trás e volta amortecido
  (frequência √(g/L), limite de 0,5, teleporte não balança). Parado, não balança.
- Armas de duas mãos continuam proibidas com a mala (regra que já existia).

## Verificação

- Palco: em todos os casos (mirar, atirar, recarregar, magnum, guarda de soco, faca) a palma da mala desloca < 8 cm do repouso e
  fica abaixo de 1 m; sem mala, mirar ainda sobe a mão de apoio (comportamento antigo preservado).
- Jogo de verdade (Main, porto, câmera do jogo): parado, andando, correndo, mirando, atirando, mirando andando — mala sempre junto
  da coxa; dados da pose em jogo: `left_solve=true left_grip=true support_locked=false left_weight=1.0`.
- Testes: `test_handbag_carry` (novo, 23), `test_handbag_visual`, `test_backpack_visual`, `test_inventory_field`,
  `test_weapon_presentation_contract` (152), `test_actor_locomotion_idle`, `test_dante_combat_timing`, `test_running_hands`,
  `test_dante_deformation`, `test_native_driving`, `cold/test_admission` passam.
- Falhas já existentes em HEAD limpo, sem relação: `test_combat_flow` (51 linhas) e `test_dante_animation_continuity` (backpedal).

## Não verificado / limites

- Visual em movimento contínuo: só quadros isolados. Não medi o balanço em curvas fechadas nem o cansaço da pose de uma mão em tiroteio longo.
- O braço com a mala está sempre estendido para baixo; uma variação "mala junto ao corpo" ao mirar (encolher o braço) não foi testada.
- Mala no chão/aberta (`set_open`) segue o caminho antigo (tween) e não foi alterada.
