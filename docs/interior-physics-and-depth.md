# Contrato obrigatório de interiores acessíveis

Este contrato vale para novos ambientes, prédios, veículos acessíveis, móveis e interações de entrada, e para os ambientes alterados. O chalé é a implementação de referência. Um ambiente legado não está aprovado apenas porque existe no projeto.

## Comportamento obrigatório

- Jogador e NPCs caminham no piso livre. Mesas, camas, sofás, balcões, caixas, banquetas, portas fechadas e suportes ocupam espaço físico.
- Pernas finas de um móvel não autorizam atravessar seu tampo. Reserve a área do objeto inteiro. Divida móveis em L em partes para preservar os corredores livres.
- Piso e tapete raso são transitáveis. Vigas, lustres e superfícies elevadas encobrem atores pela profundidade, sem criar paredes invisíveis no chão.
- Não altere `z_index`, transparência ou posição do sprite para fingir uma colisão. Não eleve o ator até o tampo nem o teletransporte por obstáculos para resolver um caminho.
- Sentar, deitar ou subir só é permitido em uma interação explicitamente implementada, com acesso livre, pose, apoio e saída validados. O movimento comum continua bloqueado.
- Spawn, retorno, restauração de save, NPC residente, pickup e aproximação de interação devem ficar em espaço livre, considerando a dimensão real do ator. Navegação e deslocamento usam as mesmas colisões; NPC não recebe permissão especial para atravessar cenário.

## Implementação de referência

1. Construa objetos físicos com uma identidade `interior_solid_id` nas malhas que determinam seu volume. Em `MountainCabin3D.gd`, cada grupo identifica um móvel. Não agrupe toda a sala em um único sólido. Um novo objeto precisa de classificação explícita e de cobertura de teste; um objeto sem identidade não recebe bloqueio automaticamente.
2. Use `world/shared/interiors/InteriorSolidProjection.gd` para obter a área de cada grupo a partir das próprias malhas e transformações e projetá-la no piso. A mesma câmera fixa e o mesmo sprite devem projetar cenário, colisão, spawn e interação. Câmeras criadas por streaming precisam do transform final e de interpolação desativada antes da projeção. Mudança de malha ou layout exige reconstruir os bloqueios antes de admitir atores.
3. Use `world/shared/interiors/InteriorActorPresentation.gd` para jogadores e NPCs em uma sala 3D projetada. O rig animado original é renderizado no mesmo SubViewport da sala, com profundidade real. O sprite externo fica oculto, o viewport individual fica suspenso e o ponto de apoio é a interseção do raio com o chão. Não copie rigs nem adicione passes por ator.
4. Chame `configure(actor, camera, display)` na entrada e `restore()` na saída, respawn e descarregamento. Não desative o processamento do adaptador enquanto o ator está na sala. A limpeza é idempotente; o adaptador também acompanha remoção do ator e da câmera. Máscaras de colisão devem continuar incluindo o cenário. A admissão verifica o corpo inteiro contra os sólidos, inclusive antes do primeiro tick físico, e recupera uma posição antiga inválida no `SpawnPoint`. Esse ponto precisa estar livre; a validação de NPCs deve comprovar que posições autoradas não dependem desse fallback.
5. `MountainInteriorManager.gd` integra o adaptador nos interiores projetados da montanha. `HarborInteriorBase.gd` integra NPCs residentes em salas que expõem `camera_3d` e `sprite_3d`. Outros gerenciadores precisam conectar explicitamente seu fluxo de jogador ao adaptador. O antigo `MountainInteriorActorScale.gd` só calibra sprites de ambientes legados; não satisfaz o contrato de profundidade.
6. Projete disparos/efeitos a partir da câmera da sala (`project_node`), e calibre a passada na projeção do piso (`pixels_per_rig_unit`). Restaure os contratos externos ao sair. Adaptações para outro tipo de NPC precisam preservar seu rig, animação, colisão, escala e ciclo de vida.

## Gate de entrega

Para cada ambiente novo ou alterado, acrescente casos verificáveis ao teste correspondente. Não marque um ambiente como aprovado por ele apenas usar a classe compartilhada.

- Inventário completo de móveis: verificar que cada objeto sólido visível tem cobertura física, incluindo props pequenos e partes adicionadas depois.
- Movimento varrido com o jogador e com NPC real contra as bordas e cantos, inclusive deslocamento grande que poderia atravessar uma parede. Verificar também caminhos válidos: os bloqueios não podem fechar corredores.
- Testar entrada, spawn, pickups, interação, saída, reentrada e recuperação/respawn usando os fluxos reais. Query de ponto isolada não prova que o corpo cabe.
- Renderizar ator antes, atrás e ao lado de móveis, portas, vigas e paredes. Teste de oclusão deve ter controle positivo: esconder o ator sempre não passa. Verificar movimento e origem de armas/efeitos, não só uma pose parada.
- Verificar NPC residente e visitante, duas pessoas na mesma sala, remoção do ator e descarregamento. Sala vazia e viewports individuais não devem continuar renderizando sem necessidade.
- Comparar performance na cena real, seguindo `performance-do-jogo`, e registrar lacunas. Headless não comprova profundidade nem FPS.

Comandos de referência (executável Godot do ambiente):

```text
godot --headless --path game --script res://tests/test_projected_interior_contract.gd
godot --path game --script res://tests/test_projected_interior_contract.gd
godot --headless --path game --script res://tests/test_mountain_cabin_scale.gd
godot --path game --script res://tests/measure_cabin_depth.gd -- cabin-after
```

`test_projected_interior_contract.gd` cobre os sólidos do chalé, movimento de jogador/NPC, restauração e oclusão renderizada com controle positivo. `test_mountain_cabin_scale.gd` cobre entrada, circulação, coleta, saída e respawn na cena MountainPass. Novos ambientes precisam dos próprios casos equivalentes. Aprovação de um caso não substitui a cobertura de outro.

Se qualquer caso de colisão, profundidade, spawn ou circulação falhar, corrija a causa antes da entrega. Não ignore assertions, não aumente tolerâncias para aprovar clipping e não declare garantia universal de ausência de bugs.
