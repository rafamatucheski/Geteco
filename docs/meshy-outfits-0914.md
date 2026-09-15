# Trajes e integração completa do Dante Meshy — 14/09/2026

O Dante Meshy virou padrão do gameplay em 14/09, mas só o traje clássico usava o
modelo importado, e vários estados ainda dependiam das malhas antigas. Esta
revisão fecha essas lacunas.

## O que estava faltando

| Situação | Antes desta revisão |
| --- | --- |
| Outros 9 trajes da loja e o conjunto de ski | Voltavam ao boneco procedural antigo |
| Entrar/sair de carro (cabine) | **Dante invisível**: `VehicleCabinOccupant` duplica as âncoras do Player, e as malhas copiadas vinham ocultas (sonda: 0 malhas visíveis; 92 no rig antigo) |
| Pilotar moto | **Piloto invisível**, exceto o capacete (`DanteMotorcycleRider` faz a mesma duplicação) |
| Embarque, esqui, morte | O Meshy congelava no último quadro de caminhada; quem se movia era o corpo antigo, oculto |
| Flash vermelho de dano | Pintava a jaqueta antiga, oculta |
| Prévia da loja de roupas | Mostrava o boneco antigo |

## Como os trajes vestem o corpo novo

O Meshy entrega **uma textura assada única**: jaqueta, henley, jeans e botas não
são materiais separados. Há três caminhos:

1. **Recolorir regiões da textura** (implementado). Cobre todos os trajes agora,
   com custo de um material.
2. **Gerar cada traje no Meshy** (retexture/novo modelo com o mesmo esqueleto).
   É a melhor qualidade e troca a silhueta, mas depende de gerar e aprovar cada
   modelo. `MeshyAnchorRetarget`/`MeshyDantePuppet` e `MeshyDanteRig` aceitam
   qualquer GLB com os mesmos nomes de ossos, então dá para trocar traje a traje
   depois, começando pelos que mais sofrem com a silhueta (abaixo).
3. Roupas 3D separadas por cima do corpo: descartado, porque exige skinning
   próprio por peça e tende a atravessar a malha nas poses de arma.

### Máscara de regiões

`tools/build_meshy_outfit_mask.py` gera `dante_outfit_regions.png` (R = região,
G = zona do corpo) e `scripts/player/MeshyDanteRegionStats.gd`. Reconstrução, na
raiz do repositório:

```bash
python tools/build_meshy_outfit_mask.py assets/characters/meshy_dante/dante_grip.glb assets/characters/meshy_dante/dante_outfit_regions.png scripts/player/MeshyDanteRegionStats.gd
```

Regenerar o `dante_grip.glb` (novo modelo do Meshy) exige rodar de novo este
gerador e reimportar: a máscara é indexada pelas UVs do modelo.

A classificação cruza o osso dominante de cada triângulo com a cor, porque as
ilhas UV do Meshy misturam peças (henley, cinto e jeans são contíguos no atlas).
No quadril, barra da jaqueta e jeans têm o mesmo azul escuro: ali a decisão é
por peça conectada. `dante_outfit_regions_preview.png` mostra textura, regiões e
zonas lado a lado para revisão. Regiões: pele, cabelo/barba, jaqueta, camisa,
calça, cinto, bota. Zonas: tronco, braço, antebraço, mão, coxa, canela, pé.

### Shader e catálogo

`meshy_dante_outfit.gdshader` multiplica a cor nova pela luminância local
relativa à média da região, conservando dobras e sombras pintadas. `pattern`
controla quanto do padrão original fica: 1,0 no lenhador (xadrez vermelho a
partir do xadrez azul), 0,08–0,2 em terno e parka. Zonas pintam pele (regata,
manga curta, bermuda) ou luva. Estampas procedurais: floral (havaiana) e
camuflagem. O clássico passa pelo shader sem recolorir, só com o flash de dano.

`MeshyDanteAppearance.gd` guarda as cores por traje e os acessórios presos a
ossos por `BoneAttachment3D`, escritos no espaço de repouso do modelo:

| Traje | Roupa | Acessórios |
| --- | --- | --- |
| Terno | preto liso, camisa branca, sapato escuro | gravata, relógio |
| Parka ártica | parka azul lisa, luvas | gorro, gola de pele |
| Ski | jaqueta vermelha, luvas | capacete/óculos do `PlayerSkiController` |
| Sobretudo | cinza chumbo, luvas de couro | cachecol |
| Pistoleiro | colete de couro, mangas creme | chapéu, bandana |
| Sobrevivente | couro escuro, luvas | óculos anti-poeira, ombreira |
| Lenhador | flanela vermelha (xadrez mantido) | gorro, suspensórios |
| Camuflado | camuflagem procedural, luvas | capacete tático, colete |
| Havaiana | estampa floral, peito e antebraço à mostra, bermuda | óculos, colar |
| Regata | regata preta, braços à mostra, bermuda, tênis branco | boné virado, óculos |

As cores do camuflado seguem a descrição da loja (verde-oliva e marrom), não os
campos `jacket_color`/`pants_color` do `OutfitCatalog`, que estão azul e verde
vivos e só servem ao construtor antigo.

### Limites conhecidos

- **A silhueta é a do modelo.** Regata e bermuda pintam pele sobre o volume da
  manga e da perna; o sobretudo não ganha barra longa; a havaiana não fica mais
  solta. De longe, na câmera do jogo, lê bem; em close, não. São os candidatos
  a um modelo próprio do Meshy.
- Cabelo pode atravessar gorro/boné em algumas poses de cabeça; os chapéus foram
  calibrados na pose de repouso e na revisão frontal/traseira.
- A borda da bermuda segue a fronteira de peso entre coxa e canela, que é
  irregular.

## Retarget das âncoras antigas

`MeshyAnchorRetarget.gd` orienta o esqueleto do Meshy pelas âncoras que o resto
do jogo já anima (`TorsoNode`, `HeadNode`, braços, pernas, `Foot`). Copia
direções de segmento e a descida da pelve, não comprimentos, para não esticar
o modelo. Usos:

- `MeshyDanteRig` entra nesse modo em embarque (meta `meshy_anchor_pose`, posta
  por `VehicleBoarding`), esqui, morte e sempre que a física do Player para de
  chamar `prepare_pose`. Na caminhada a pé, continua usando os clipes e o IK de
  armas do Codex.
- `MeshyDantePuppet.gd` é o Dante Meshy para cópias de âncoras: cabine de
  veículo, piloto de moto e prévia da loja (`DantePreviewRig.use_meshy`, ligado
  só em `CharacterPreview3D`; abertura e renders de montanha seguem com o rig
  antigo).

## Validação

Godot 4.7.2, Vulkan, RTX 4060 Laptop, renderizado.

- `tests/test_meshy_outfits.gd`: 0 falhas. Cobre os 11 trajes (material,
  recoloração, acessórios visíveis, pose finita, modo âncora com física parada),
  flash de dano acendendo e apagando, embarque abaixando a pelve do Meshy, cópia
  de âncoras visível (cabine), piloto de moto com Meshy e capacete, prévia da loja
  com um único Dante Meshy e sem boneco antigo visível. Imagens em
  `docs/measurements/meshy-outfits-0914/` (`outfits.png` frente/costas,
  `boarding.png`).
- `test_meshy_dante.gd`: 0 falhas. A checagem "outros trajes mantêm o rig
  original" foi trocada pelo contrato novo.
- `test_meshy_knuckles.gd`, `test_meshy_grenade_release.gd`,
  `test_garage_weapon_restrictions.gd`, `test_clothing_preview.gd`: 0 falhas.
- `tools/check_references.py`: 0 quebras novas.
- `test_vehicle_boarding_animation.gd`, execução real: entrada, motorista dentro
  da carroceria, cabeça abaixo do teto e oclusão da cabine fechada da Monaliza
  (lado esquerdo) sem falhas. Captura em
  `D:/geteco/artifacts/vehicle-exit-0914/monaliza_L_49.png` mostra o Dante Meshy
  na porta. O teste depois trava na saída (`_door_landing` sem ponto livre → a
  transição se libera). **Isso é anterior a esta revisão**: repete igual com o
  Meshy desligado e com o Meshy ligado sem o boneco da cabine.

Resultados que não são desta revisão, registrados para quem vier depois
(atualizado mais tarde no mesmo dia; ver `docs/recuperacao-e-pendencias-codex-0914.md`):

- `test_player_combat_pose.gd`: 126 falhas com o Meshy padrão; 0 com
  `use_meshy_dante = false`; 126 também com o modo âncora desligado. O teste mede
  o rig antigo; agora fixa `use_meshy_dante = false` e passa com 0 falhas.
- `test_dante_motorcycle_helmet.gd`: `Player.ensure_motorcycle_helmet` tinha
  sumido do Player (o capacete estava desligado no jogo). Restaurado do backup do
  Codex de 12/09; o teste fixa o rig antigo e passa com 0 falhas. O encaixe do
  capacete sobre o cabelo do Meshy não foi medido.
- Os erros de parse do `UrbanBus.gd` eram consequência de um `git checkout` do
  Antigravity que apagou a lógica de faixa do `TrafficVehicle.gd`; o arquivo foi
  recuperado e mesclado. `test_menu_flow_integration` (atualizado para a
  transição do menu e a abertura de 86 s) e `test_dante_gameplay_integration`
  (ações `move_*`, embarque animado) passam.
- `test_player_render_visibility.gd`: o Player visível usa `UPDATE_WHEN_VISIBLE`;
  o teste passou a exigir "não desativado" e passa.
- `test_mountain_ski_3d_and_loop.gd`: o teste ajustava um relógio falso em vez do
  que o `MountainSkiSchedule` lê; corrigido, passa.
- `test_vehicle_boarding_animation.gd`: passa (0 falhas) depois da recuperação do
  `TrafficVehicle.gd` e da correção do roubo sem vão para o motorista.
- Passaram: `test_projected_interior_contract` (17 grupos, 136 aproximações),
  `test_opening_cutscene_runtime`, `test_pedestrian_life_routines`,
  `test_pedestrian_render_lod`, `test_real_player_instance`,
  `test_mountain_ski_transitions`, `test_clothing_shops`,
  `profile_load_time_0909` (exit 0).
- `test_character_fall_animation`: passou na repetição (a primeira execução
  pegou `ContactShadow.gd` no meio de uma edição de outra sessão). Cobre a queda
  dos NPCs, não a morte do Dante.

Não medido: aparência em partida real na cidade, clipping de acessórios em todas
as poses de arma, o esqui e a queda de morte renderizados em jogo, custo de
performance do shader e do retarget (nenhuma medição de FPS/frame foi feita
nesta revisão).
