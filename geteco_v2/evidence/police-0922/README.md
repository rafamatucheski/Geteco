# Policiais e disparos — 22/09/2026

Correção implementada; performance final **pendente por escolha do usuário**. Não se declara fidelidade integral nem estabilidade universal.

## Causa e alteração

`PoliceAgent._ready` fixava ombros em X negativo (-1,25/-1,1 rad), embora os braços pendam em -Y e a frente do modelo seja -Z. As mãos iam para +Z, atrás do corpo. A arma herdava também a rotação do antebraço, sem compensação. Nenhuma atualização de mira ou recarga corrigia essa pose.

`PoliceModel` agora resolve os dois segmentos com os comprimentos e o polo de cotovelo de `characters/PlayerCombatPose.gd` da V1. A empunhadura acompanha a mão; a orientação do cano é independente do antebraço. Há porte, mira, recuo, busca de carregador, inserção, manejo e retorno à mira. Os perfis já existentes de `PoliceAppearance.gd` são utilizados para altura, pele e volume do uniforme, sem escala não uniforme nos ossos. Clarão de 50 ms no cano real, também apagado ao morrer.

`Gameplay.police_shoot` deixou de desenhar uma linha e descontar vida imediatamente. Agora registra uma bala em voo; cada passo de física consulta o segmento percorrido e resolve um único contato. Parede, esquina e carro interrompem a trajetória. A consulta entre corpo e cano impede nascer do outro lado de uma parede fina. Dano, impacto visual e áudio de contato acontecem na colisão; alvo móvel pode escapar. Dano usa a proteção central de Maciota/mecânico. Rodadas são descartadas na troca de região. Limite de 128 balas físicas; visuais usam o pool existente de 32 traçantes, com identidade de slot para não mover um efeito reutilizado.

Cadência, rajadas, capacidade do pente, dano nominal, alcance de ataque, perseguição e tempo de aquisição de mira não foram alterados. `Actor.gd`, `WeaponRigPose.gd`, `WeaponPoseData.gd`, `PoliceAppearance.gd` e iluminação global não foram editados por esta frente.

## V1 verificada em código e em cena

Fontes: `police/PoliceOfficer.gd` → `_shoot_at_target` → `_fire_single_bullet` → `guns/Bullet.tscn`/`guns/Bullet.gd`, `guns/combat/ShotQuery.gd`, `characters/pedestrians/NPCCombatRig.gd` e `characters/PlayerCombatPose.gd`.

| Propriedade | V1 efetivamente usada | V2 anterior | V2 corrigida |
|---|---|---|---|
| Origem | Rua: corpo + direção × 22 px; interior: cano projetado | Corpo + 1,1 m | Cano da geometria real, protegido por consulta corpo–cano |
| Trajetória | Bala com consulta varrida por passo | Linha imediata até o suspeito | Bala 3D com consulta varrida por passo |
| Velocidade | 880 px/s regular/detetive; 1200 táticos | Sem viagem física | 55/75 m/s, conversão ÷16 |
| Dispersão | ±0,13 rad regular/detetive; ±0,10 táticos | Ausente | Mesmos limites |
| Dano | Somente no contato, com queda por distância | Direto após visibilidade | Somente no contato, mesma função de queda |
| Clarão | Esfera emissiva por 0,05 s | Mesh existia, não era ativado pelo tiro | Esfera no ponto devolvido pelo construtor da arma |
| Rastro | Cauda compacta viajando atrás da frente de colisão | Segmento até o alvo | Cauda compacta acompanhando a bala |
| Som policial | Pistola para patrulha; SMG nos demais tipos | Som do catálogo da arma, incluindo M4 | Família policial da V1; pitch 0,95–1,05 |
| Recarga sonora | Take ajustado à duração da recarga | Take sem ajuste de duração | Pitch = duração do take / duração da recarga |

Diferenças ainda explícitas: V1 é 2D com atores renderizados em SubViewport; V2 é física 3D. O ponto de origem exterior foi melhorado para o cano real, não copiado como deslocamento de 22 px. Os três takes de pistola e SMG da V2 são idênticos por SHA-256 aos três correspondentes da V1 (`audio-comparison.json`); V1 tem cinco takes e randomizador sem repetição, V2 mantém três e sorteio simples. Impactos usam a apresentação e o mixer 3D existentes da V2. Essas diferenças impedem chamar a entrega de cópia audiovisual integral.

## Evidências

- Referência obrigatória examinada: `C:/Users/rafae/AppData/Local/Packages/Microsoft.ScreenSketch_8wekyb3d8bbwe/TempState/Recordings/20260922-1328-56.2777156.mp4` (38,63 s). Quadros extraídos em `reference-*.jpg`.
- [Comparativo em vídeo](v2-before_v1_v2-after.mp4): esquerda = V2 original; centro = V1 real; direita = V2 corrigida. Sequências capturadas, sem áudio, montadas a 10 quadros/s. Trechos curtos repetem; isto não mede velocidade de execução ou FPS.
- `before/frame-*.png`: captura antes das edições na Main real.
- `v1/frame-*.png`: HarborGame real, patrulheiros. `v1-tiers/frame-*.png`: os cinco tipos, selecionados pela propriedade real `response_tier_level`.
- `final-video/frame-*.jpg`: Main real, oito orientações, mira/disparo, recarga e retorno ao porte. Atores posicionados pelo harness; não é uma gravação de perseguição espontânea. Algumas orientações ficam parcialmente ocluídas pelo cenário, complementadas pelas verificações geométricas.
- Capturas V1 usam diretório temporário de saves; V2 usa `--no-save --skip-arrival --population=8 --seed=7`.

## Validação

Motor: Godot 4.7.2. V2 renderizada em Mobile, RTX 4060 Laptop, 1280×720. Não foram removidas nem relaxadas assertions.

| Execução | Resultado |
|---|---|
| `tests/test_police_ballistics_0922.gd` | 107 checks, zero falhas: origem, atraso, dano único, alvo móvel, parede, esquina em L, carro, veículo ocupado, proteção, parede entre corpo e cano, recarga/perseguição, dez perfis × oito direções, clarão apagado ao morrer |
| `tests/test_police_combat_closure.gd` | 30 checks, zero falhas |
| `tests/test_police_crime_contract.gd` | 10 checks, zero falhas |
| V1 `tests/test_garage_weapon_restrictions.gd` | Zero falhas; entrada, save, saída, bloqueios e ausência de rotinas de dano/morte dos essenciais |
| V2 `tests/test_combat_flow.gd`, primeira execução renderizada | 65/67: falhas ao recuar mirando (2,24 m/s e fase divergente). Garagem, save e proteção passaram |
| V2 `tests/test_police_combat_flow_0922.gd` | Mesmas 67 assertions do teste anterior, com diagnóstico adicional: 67/67; recuo 3,50 m/s, fase 0,22 igual à esperada |

A execução diagnóstica não prova estabilidade da falha inicial: não houve correção de locomoção nesta frente. A amostra final registrou somente contato com `SlabCollision` nesse trecho. Não se atribui a causa inicial a Actor ou aos policiais sem evidência adicional. Há avisos/erros de recursos vazados ao encerrar V1 e alguns testes isolados V2; o código de saída e as assertions passaram, mas o encerramento não foi limpo.

Logs próprios: `test_police_ballistics_0922.log`, `test_police_combat_closure.log`, `test_police_crime_contract.log`, `combat-flow-diagnostic.log`. Não houve patch de integração do Dante recebido. Foi detectada e preservada instrumentação concorrente de `find_path` em `Gameplay.gd`; os blocos policiais foram editados localmente.

## Performance — pendente

Meta provisória: 60 FPS / 16,67 ms, tolerância de investigação de +5% em p95/p99, não critério ajustado após o resultado.

| Amostra exploratória | Duração / frames | FPS médio | p50 / p95 / p99 ms | Máximo | >33,3 / >66,7 ms |
|---|---|---|---|---|---|
| Original, com PNG durante a janela | 30,014 s / 1683 | 56,07 | 16,66 / 17,417 / 19,411 | 189,284 | 12 / 12 |
| Caminho original reconstruído no harness, sem capturas | 30,015 s / 1801 | 60,00 | 16,673 / 17,23 / 17,979 | 29,292 | 0 / 0 |

A primeira amostra está contaminada pelo custo de salvar PNG. A segunda mantém explicitamente o tiro e a pose anteriores no harness; não é um checkout original isolado. Não existe amostra final comparável: outras frentes executaram Godot e alteraram arquivos durante o trabalho. O usuário escolheu **deixar a performance pendente**. Números nos diretórios `*-video` são de captura e não são benchmarks. Não há aprovação de desempenho nem inferência de regressão a partir dessas capturas.

Reprodução futura, sem outras execuções de teste/captura: `--path geteco_v2 --script res://tests/capture_police_0922.gd -- --no-save --skip-arrival --population=8 --seed=7 --baseline output=res://evidence/police-0922/baseline-novo`; em seguida, mesma chamada sem `--baseline`, com outra saída. Não usar `--record` para medição. O harness aquece por 8 s e guarda 30 s de amostras brutas, resolução, GPU, renderer, VSync e limitador.
