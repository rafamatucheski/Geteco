# Migração da apresentação de combate V1 → V2 — 2026-09-21

## Resultado e limites da rodada

A apresentação produtiva foi portada para as 16 armas do catálogo. A pistola foi usada como referência completa antes da extensão para o restante do arsenal. Dano, cadência, munição e o caminho do cheat (`FullSession → Gameplay.handle_arsenal_input`) foram preservados; nenhum evento visual ou de animação aplica dano novamente.

Esta rodada não altera `FullSession`, HUD, menus, `CameraRig`, economia, mapa, `Vehicle` ou áudio do mundo. Som ouvido e benchmark final permanecem propositalmente separados das aprovações funcionais e visuais.

## Cadeia produtiva rastreada

| Etapa | Fonte V1 | Destino V2 | Adaptação feita |
|---|---|---|---|
| Modelo e materiais | `guns/WeaponCatalog.gd`, `scripts/player/ArsenalWeapon3D.gd`, `scripts/player/WeaponPresentation3D.gd`, `guns/WeaponAttachmentVisuals.gd` | `gameplay/WeaponCatalog.gd`, `gameplay/ArsenalWeapon3D.gd`, `gameplay/WeaponPresentation3D.gd`, `gameplay/WeaponAttachmentVisuals.gd` | Catálogo, geometrias, cores, acessórios e escalas originais reaproveitados no rig 3D real. |
| Empunhadura e IK | `characters/PlayerCombatPose.gd`, `scripts/player/MeshyDanteRig.gd` | `gameplay/WeaponPoseData.gd`, `gameplay/WeaponRigPose.gd`, `scripts/Actor.gd` | Apoio bilateral por IK de dois ossos, palmas ancoradas nos pontos reais da arma e orientação própria por família. Erro medido de contato pronto/ação: 0–5 mm. |
| Postura e movimento corporal | `characters/PlayerCombatPose.gd`, `scripts/player/MeshyMeleePose.gd`, clipes de `dante.glb` | `gameplay/WeaponRigPose.gd`, `scripts/Actor.gd`, `gameplay/Gameplay.gd` | Tronco, braços, locomoção e clipes de golpe separados do transform da arma e dos efeitos. Mirar não reduz a velocidade. |
| Disparo e recuo | `characters/Player.gd`, `guns/combat/WeaponEffects.gd` | `gameplay/Gameplay.gd`, `gameplay/WeaponRigPose.gd` | Origem no cano real, recuo por arma, ferrolho/cilindro/bomba e pose de apoio preservados sem duplicar o evento de dano. |
| Recarga | `guns/combat/WeaponReload.gd`, bancos `assets/gameplay/audio/reload/` | `gameplay/Gameplay.gd`, `gameplay/WeaponRigPose.gd`, `gameplay/CombatAudio.gd` | Movimento da arma e mãos por progresso; duração respeita o banco original, mínimo V1 de 0,5 s. |
| Clarão e gases | `guns/combat/WeaponEffects.gd` | `gameplay/CombatEffects.gd`, `gameplay/Gameplay.gd` | Clarão orientado pelo cano, partículas e backblast do RPG; não é esfera genérica. |
| Trajetória/traço | `guns/Bullet.gd`, `guns/combat/WeaponEffects.gd` | `gameplay/CombatEffects.gd`, `gameplay/Projectile.gd` | Traço curto que viaja na trajetória, em vez de risco instantâneo de ponta a ponta; foguete e granada continuam projéteis físicos. |
| Cápsula | `guns/combat/WeaponEffects.gd` | `gameplay/Gameplay.gd` | Ejeção nasce na arma, com direção e impulso lateral próprios. |
| Impacto/explosão/chama | `guns/combat/WeaponEffects.gd`, `guns/Bullet.gd`, efeitos procedurais V1 | `gameplay/CombatEffects.gd`, `gameplay/Projectile.gd`, `gameplay/Gameplay.gd` | Impacto por material; explosão composta; lança-chamas com núcleo, línguas conectadas, fumaça e partículas, sem cone/linha contínua. Pools fixos evitam alocação por disparo. |
| Som | `audio/combat/CombatAudioBank.gd`, `ProceduralAudio.gd`, `audio/combat/KnifeAudio.gd`, `audio/combat/BatAudio.gd`, WAVs originais | `gameplay/CombatAudio.gd`, `gameplay/Gameplay.gd`, `gameplay/Projectile.gd` | Fórmulas e WAVs originais. WAVs agora entram por `ResourceLoader` como `AudioStream` importado, válido no editor e no PCK. |

## Inventário produtivo completo

As colunas “pronto/ação” referem-se aos atlas V1 e V2 capturados com a mesma câmera ortográfica, o mesmo enquadramento de célula e os mesmos estados. A diferença de altura aparente do personagem decorre do rig GLB V2, não de uma câmera especial para favorecer a comparação.

| Arma | Fonte V1 principal | Partes reaproveitadas | Adaptação ao V2 | Comparação visual | Pendência específica |
|---|---|---|---|---|---|
| Punhos | `PlayerCombatPose`, `MeshyMeleePose` | Clipes, fase e som procedural | Guarda neutra, jab, tronco e retorno à locomoção | Pronto/ação V1×V2 e câmera real | Escuta subjetiva do contato |
| Soqueira | `PlayerCombatPose`, `ArsenalWeapon3D` | Modelo, material, jab e som de punho | Modelo preso à palma; guarda mais alta | Pronto/ação V1×V2 | Escuta subjetiva do contato |
| Faca | `MeshyMeleePose`, `ArsenalWeapon3D`, `KnifeAudio` | Modelo, três variações de contato e golpe no ar | Escala GLB, empunhadura invertida e estocada | Pronto/ação V1×V2 e câmera real | Escuta subjetiva dos quatro sons |
| Taco | `MeshyMeleePose`, `ArsenalWeapon3D`, `BatAudio` | Modelo, carga/contato/recuperação e som | Porte no ombro e pegada bilateral | Pronto/ação V1×V2 e câmera real | Escuta subjetiva de ar e impacto |
| Machado | `MeshyMeleePose`, `ArsenalWeapon3D`, trilha do golpe | Modelo, ataque em arco e áudio de lâmina | Porte no ombro, pegada bilateral e arco no rig | Pronto/ação V1×V2 e câmera real | Escuta subjetiva do contato |
| Pistola 9 mm | Cadeia completa de `Player`, `PlayerCombatPose`, `WeaponEffects` e `CombatAudioBank` | Modelo, stats, WAVs, clarão, cápsula e traço | Mira com duas mãos, cano real, recuo, ferrolho e recarga | Atlas próximo de 5 estados, pronto/ação e câmera real | Escuta subjetiva; benchmark final |
| Magnum | Mesma cadeia da pistola + apresentação do revólver | Modelo, stats, WAVs, clarão, cápsula | Mira alta com duas mãos, recuo forte e cilindro | Pronto/ação V1×V2 | Escuta subjetiva; benchmark final |
| SMG | `PlayerCombatPose`, `WeaponEffects`, catálogo/áudio | Modelo, stats, WAVs, clarão, cápsula | Coronhada no peito, mão de apoio e automático | Pronto/ação V1×V2 | Escuta subjetiva; benchmark final |
| Escopeta pump | Cadeia de rifle + bomba/recarga V1 | Modelo, stats, WAVs, múltiplos chumbos | Ombro, mão na bomba, recuo e ciclo da telha | Pronto/ação V1×V2 e câmera real | Escuta subjetiva do tiro/ciclo; benchmark final |
| Cano serrado | Cadeia de pistola pesada/escopeta | Modelo, stats, WAVs e dispersão | Porte alto de duas mãos e recuo curto forte | Pronto/ação V1×V2 | Escuta subjetiva; benchmark final |
| AK-47 | Cadeia de rifle V1 | Modelo, stats, WAVs, clarão, cápsula | Ombro, empunhadura de apoio, automático e recarga | Pronto/ação V1×V2 | Escuta subjetiva; benchmark final |
| M4A1 | Cadeia de rifle V1 | Modelo, stats, WAVs, acessórios e efeitos | Ombro, apoio frontal, automático e recarga | Pronto/ação V1×V2 | Escuta subjetiva; benchmark final |
| Fuzil de caça | Cadeia de rifle + customização de luneta | Modelo, stats, WAVs, luneta 2× e efeitos | Ombro alto, ferrolho/recuo e contrato de luneta | Pronto/ação V1×V2 | Escuta subjetiva; benchmark final; UI aplica retícula/zoom |
| RPG-7 | Projétil/explosão e apresentação V1 | Modelo, stats, WAVs, foguete e fumaça | Apoio no ombro, foguete orientado, motor, backblast e explosão composta | Pronto/ação V1×V2 e câmera real | Escuta subjetiva; benchmark final |
| Lança-chamas | Apresentação e gerador procedural V1 | Modelo, stats, fórmula de áudio e identidade de chama | Porte pesado no quadril; núcleo, línguas móveis conectadas, fumaça e partículas | Pronto/ação V1×V2 e câmera real | Escuta subjetiva; benchmark final |
| Granada | Modelo, arremesso, ricochete e explosão V1 | Modelo, stats, pino/sopro, projétil e explosão | Arremesso sobre o ombro, giro físico e som de quique | Pronto/ação V1×V2 e câmera real | Escuta subjetiva; benchmark final |

## Evidência

- Pistola V1 próxima: `artifacts/combat-parity/pistol-v1-close.png`.
- Pistola V2 próxima: `geteco_v2/evidence/combat/pistol-v2-close.png`.
- Atlas V1: `artifacts/combat-parity/arsenal-v1/arsenal-v1-ready.png` e `arsenal-v1-action.png`.
- Atlas V2: `geteco_v2/evidence/combat/arsenal/arsenal-ready.png` e `arsenal-action.png`.
- Câmera real de jogo: `geteco_v2/evidence/combat/migration-2026-09-21/`, cobrindo pistola parada/mirando/acerto/morte, escopeta, quatro golpes, lança-chamas, RPG, granada e recuo em movimento.
- PCK usado para validar recursos importados: `geteco_v2/evidence/export/GetecoV2-current.pck`.

## Contrato entregue à interface — mira e luneta

A interface e a câmera não devem inferir a luneta pela arma nem ler estado de entrada diretamente.

| API de `Gameplay` | Semântica | Frequência/latência |
|---|---|---|
| `aiming: bool` | Corpo/arma estão na camada de mira: `aim`, `fire`, lanterna ou retenção curta pós-disparo, desde que o combate esteja permitido. | Atualizado na física; leitura vê o último passo (até ~1/60 s). |
| `aim_active: bool` | Botão de mira apertado com arma que admite mira; exclui punhos, faca, machado, soqueira, taco e granada. | Atualizado na física. |
| `scope_active() -> bool` | Luneta instalada **e** `aim` pressionado **e** combate/jogo livre permitido **e** fora de interior isolado. Soltar, trocar arma, morrer, entrar em veículo/garagem/transição ou bloquear entrada desliga no passo atual. | Consultar a cada atualização visual. |
| `scope_part() -> String` | Identificador instalado, hoje `scope_2x`, ou `none`. Permite escolher fator e arte sem duplicar regras de compatibilidade. | Consultar quando `scope_active()` mudar. |

Responsabilidade da interface/câmera: retícula, máscara, zoom e suavização. Responsabilidade do combate: verdade de ativação, peça instalada, rumo corporal e origem física do disparo. Não existe aplicação de dano por evento de retícula/animação.

## Validação executada

| Área | Resultado | Observação |
|---|---|---|
| Contrato de apresentação | **148/148** | 16 modelos, poses finitas, contato das mãos pronto/ação, recursos de áudio e bancos de recarga. |
| Fluxo de combate | **67/67** | Mouse, controle, parado/movimento, recarga, troca, golpes, morte, interrupções, garagem, velocidade ao mirar e cheat pelo caminho de `FullSession`. |
| Gameplay/regressão | **208/208** | Dano, munição, recarga, troca, projéteis e geometrias existentes. |
| Proteção da garagem | **0 falhas** | Armas bloqueadas; Maciota e mecânico permanecem imortais; restauração de save coberta. |
| Editor/PCK | **148/148 nos dois** | Cada WAV é um `AudioStream` importado com duração real; o PCK foi lido como pacote principal. |
| Exportação executável | **Bloqueada pelo ambiente** | Templates oficiais Windows do Godot 4.7.2 não estão instalados. O PCK foi produzido e validado; não se declara `.exe` aprovado. |

## Declarações independentes

- **Funcional: APROVADO.** Fluxos e regressões acima passaram; os eventos de apresentação não duplicam dano.
- **Visualmente fiel: APROVADO para o escopo de combate desta rodada.** A pistola passou pela referência próxima completa; as 16 armas foram comparadas em pronto/ação; os efeitos e ações selecionados foram verificados na câmera real. Isso não aprova mudanças de câmera/HUD, que ficaram fora do escopo.
- **Som conferido: PENDENTE.** Carregamento, duração, seleção e execução técnica foram validados no editor e no PCK, mas não houve escuta humana em dispositivo de áudio. Portanto o som não está subjetivamente aprovado.
- **Desempenho medido: PENDENTE.** Há baseline anterior de 30 s, mas ele registra possibilidade de outro editor aberto e não é usado como “depois”. A medição final deve ocorrer em janela exclusiva, na cena real e nos cenários afetados; até isso acontecer não há aprovação de performance.

