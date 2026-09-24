# Migração V1 → V2 · som e ambiência

## Conexão produtiva conferida

O V2 ativo instancia `Main.tscn`, cujo `scripts/World.gd` cria `runtime/ProductionWorld.gd`. Ao concluir a admissão inicial, `ProductionWorld.build()` chama `_audio()`, instancia `audio/WorldAudio.gd`, atribui `world` e o adiciona à árvore. A implementação desta rodada está, portanto, nessa cadeia real; nenhuma cena de demonstração foi tratada como integração.

No V1 produtivo, `project.godot` abre `ui/MainMenu.tscn`, `ui/MainMenu.gd` seleciona `world/harbor/HarborGame.tscn`, e `HarborGame.gd` instancia `HarborSoundscape.gd`. A serra entra por `HarborGame → ContinuousWorld → MountainPass`; `MountainPass` instancia `IceStormManager`, que usa `SnowWindAudio`. Esses foram os pontos de comparação, não cenas legadas isoladas.

## Fontes V1 consultadas

- `world/harbor/HarborGame.gd`, `HarborSoundscape.gd`, `HarborLivingQuarter.gd`, `HarborDockCrew.gd`, `HarborSouthPortLayout.gd` e `HarborAudioBank.gd`.
- `audio/living_city/LivingCityAudio.gd`, `audio/regional/RegionalSoundscape.gd`, `RegionalAudio.gd`, `SnowWindAudio.gd`, `audio/WaterSoundscape.gd`.
- `audio/footsteps/FootstepSurfaceResolver.gd`, `FootstepAudioBank.gd` e as gravações originais em `audio/footsteps`.
- `characters/Player.gd` para confirmar o disparo real de passos no V1.
- `world/mountain_pass/MountainPass.gd` e `IceStormManager.gd` para a cadeia produtiva da serra.
- `activities/Activities.gd`, `Motorsport.gd`, `runtime/MissionWorld.gd` e `audio/rewards/RewardAudioBank.gd` para os estados reais das atividades já migradas.

## Implementação no V2

- Cidade, costa, porto sul, áreas naturais, serra e interiores têm alvos separados, com transição suave. Leitos inaudíveis param; não ficam decodificando fora do contexto.
- Ambiência exterior é silenciada ao entrar em uma sala. Maciota e a garagem do chefe recebem a oficina original; o esgoto recebe a água original. Outros interiores permanecem intencionalmente sem um leito inventado.
- A serra preserva o vento já conectado por `runtime/Weather.gd`; o novo perfil acrescenta apenas natureza diurna/noturna, evitando duplicar a camada meteorológica.
- Um único emissor 3D reutilizável agenda gaivotas, buzina de navio, pássaros, cão, oficina e sucata somente nos contextos V1 correspondentes e nas proximidades.
- Passos distinguem interiores de piso frio, madeira e concreto; estrada asfaltada, terra, jardins/cemitério, neve, convés/passarela/trilho metálicos e piso molhado. A água continua usando `WaterSteps` e `OriginalWaterStep`, que já preservavam o comportamento V1.
- Como o acervo V1 não contém gravações separadas de terra e neve, esses dois perfis reutilizam o passo macio original de grama com pitch discreto. Nenhum PCM novo foi sintetizado.
- O bridge de atividades observa `Activities.motorsport`, as descidas de ski e a corrida da campanha sem assumir autoridade sobre suas regras. Ele toca os cues V1 copiados de largada, checkpoint, início e conclusão em duas vozes limitadas.

## Arquivos desta entrega

- `audio/WorldAudio.gd`
- `audio/v1_ambience/V1AudioCatalog.gd`
- `audio/v1_ambience/SurfaceResolver3D.gd`
- `audio/v1_ambience/AmbienceProfile.gd`
- `audio/v1_ambience/ActivityAudioBridge.gd`
- `audio/v1_ambience/activity/{countdown,checkpoint,complete,mission_start}.wav`
- `docs/AUDIO_AMBIENCE_MIGRATION.md`

Nenhum arquivo de combate, áudio de arma ou arquivo mantido pelo Claude foi alterado.

## Integrações ainda necessárias

- Quando atividades de carga/guincho expuserem eventos públicos de engate, descarga e entrega, o integrador deve encaminhá-los para um método público do bridge (ou acrescentar sinais próprios). Nesta rodada, apenas estados públicos de corrida oferecem transições inequívocas; inferir efeitos de carga por polling criaria falsos positivos.
- Se novos pisos forem adicionados, o integrador deve marcar o `StaticBody3D`/pai com identidade de superfície ou registrar a estrada em `NativeRegion.roads`; hoje o resolver usa os colliders e registros reais já existentes. Uma futura propriedade `footstep_surface` no collider pode substituir os aliases por nome sem alterar `WorldAudio`.
- Se o sistema de interiores passar a publicar um perfil acústico por lugar, encaminhar `state.place_id` e o perfil a `AmbienceProfile.targets`; não se deve adicionar leitos genéricos a salas sem fonte V1 correspondente.

## Validação pendente

Por instrução desta rodada, Godot, testes, benchmarks e commits **não foram executados**. A inspeção estática confirma caminhos, símbolos e a cadeia de instanciação, mas não valida comportamento audível, colisão, mixagem nem performance.

Na rodada autorizada de validação, verificar no jogo renderizado:

1. cidade → costa → porto sul → serra e retorno, incluindo transições sem vazamento de leitos;
2. entrada/saída de Maciota, garagem do chefe, esgoto, pisos frios e chalés;
3. passos sobre estrada, jardim, cemitério/caminho, terra, neve, convés e chuva;
4. corrida livre, descida de ski e corrida da campanha, garantindo um cue por transição;
5. pausa, diálogo, viagem de região, respawn e descarregamento da cena;
6. comparativo de frame time antes/depois na cena real, mesma rota e condições, cobrindo cidade, porto, serra e interiores. Sem essa medição, desempenho permanece **não medido**.
