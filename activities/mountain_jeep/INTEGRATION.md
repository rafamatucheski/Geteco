# Trilha dos Pinheiros — módulo isolado

Criado exclusivamente em arquivos novos durante o trabalho concorrente de missões. Não altera a campanha, o relógio nem o acesso ao mapa 2. A integração em arquivos compartilhados pertence ao agente principal; este arquivo não afirma que os ganchos já foram aplicados.

## Pontos de integração

Controller: `res://activities/mountain_jeep/MountainJeepController.gd`. Recebe `configure(session)` e expõe `nearest_action` (id `mountain_jeep`), `perform`, `snapshot`, `cancel_attempt`, `save_block_reason`, `objective` e `target_position`. `active` indica tentativa em andamento. Usa `mountain_activities.can_start(self)` quando presente. O agregador grava o snapshot integral em `world_state.mountain_jeep`.

`MountainJeepProgress.validate_snapshot(value)` e `validate_wallet(value,economy_snapshot)` aceitam Variant e recusam dados malformados. O formato inclui o único jipe fornecido, em `vehicle`; não adicionar outra key de veículo. A conta paga R$ 700 na primeira conclusão, com recibo `mountain_jeep_first_finish_v1`. Repetições registram tempo/recorde e não repetem o prêmio. Tentativas ativas não são serializadas e bloqueiam save.

Ganchos necessários em `world/regions/NativeRegion.gd`:

```gdscript
const MOUNTAIN_JEEP := preload("res://world/mountain_jeep/MountainJeepCourse.gd")
const MOUNTAIN_JEEP_SCENERY := preload("res://world/mountain_jeep/MountainJeepScenery.gd")
```

Em `_revise_mountain_routes`, imediatamente depois de obter `walkways`:

```gdscript
walkways.append_array(MOUNTAIN_JEEP.paths(main))
```

Depois de `route_geometry.configure(roads + walkways)`, registrar a decoração:

```gdscript
for record in MOUNTAIN_JEEP.records():
    _record(record.position, record)
```

Ampliar somente o filtro final de árvores dessa função, mantendo a geração determinística anterior:

```gdscript
return record.kind != "tree" or (not route_geometry.contains(record.position,3.0)
    and not MOUNTAIN_JEEP.is_reserved(Vector2(record.position.x,record.position.z),3.0))
```

Em `_dressing_reserved`, antes de consultar árvores:

```gdscript
if MOUNTAIN_JEEP.is_reserved(point,radius): return true
```

No `match` que constrói registros:

```gdscript
"mountain_jeep_scenery": MOUNTAIN_JEEP_SCENERY.build(chunk,record)
```

Não registrar a trilha em `roads`: permanece fora do grafo de tráfego civil, mas sua largura útil, apoio e colisão aceitam o jipe. Os caminhos entram em `terrain_roads` por `roads + walkways`. A máscara de terra existente compõe o corredor sobre neve sem empilhar pisos transparentes. `_record_path` usar `surface: footpath` não elimina essa máscara, pois MountainTerrain3D recebe os dados originais de `walkways`.

## Geometria e ciclo de vida

Circuito de aproximadamente 300 m, largura de 5,8 m, corredor separado do lago do avião, caverna e esqui. Acesso de 8 m ligado por projeção à estrada real, largada no ponto original `(5970,-2030)`, jipe ao lado e chegada do circuito com doze metros de desaceleração até o retorno. Checkpoints a cada 28 m, com cruzamento no sentido correto e passagem física entre as balizas.

Duas cristas suaves de 38/46 m, com alturas 1,4/1,7 m e inclinação longitudinal máxima analítica de aproximadamente 11,6%. A largura extra forma taludes até o terreno plano reservado. Malha e colisão usam os mesmos triângulos; as faces superiores seguem a convenção horária do terreno Godot. Balizas apoiadas nas cristas compensam a altura do talude lateral. Sem árvores, pedras decorativas ou grama dentro do corredor reservado. Sem luzes novas, timers ou processamento nos elementos estáticos.

Cada crista pertence ao chunk que contém seu centro e ocupa menos de 64 m; a retenção normal de dois chunks deve cobrir as extremidades. Essa análise estática não comprova suporte durante streaming, portanto validar acesso pelos dois sentidos, saída/retorno e estacionamento na borda de chunk é obrigatório.

O controlador cria um `Vehicle.gd` real `desert_jeep_4x4` com ID fixo `mountain_trail_jeep_01` depois de verificar o corpo inteiro pelo controlador de produção. Nunca troca, teletransporta ou remove o veículo pessoal. O jogador entra/sai pelo `Driving.gd` normal. É um jipe fornecido para a atividade e disponível no mundo aberto; estado de dano, posição, pintura e equipamento persistem. Também admite outro veículo do mesmo arquétipo. Um jipe destruído precisa ser reparado ou substituído por outro do jogador.

Antes de criar, o módulo adota o veículo de mesma identidade já restaurado por ProductionWorld. `race_owned` conserva seu apoio enquanto vivo na região. `tree_exiting` captura estado antes do descarregamento normal; o snapshot restaura perto da posição salva somente quando a região e o piso estão disponíveis. Cancelar mantém o veículo real e não altera travas de controle.

Quando não existe corpo para adotar, o snapshot dedicado tem precedência sobre `starting_vehicle()`: ele pode ter sido atualizado no descarregamento depois do último save do carro selecionado. O registro de seleção só é fallback quando `vehicle` está vazio. Assim estacionar ou danificar o jipe e depois descarregar a região não restaura uma posição/saúde antigas.

## Validação preparada, execução pendente

O parser gdtoolkit foi executado com sucesso nos oito scripts GDScript deste módulo. Uma checagem analítica independente mediu a polilinha de controle em 297,98 m e inclinações máximas de 11,57/11,61%. Isso não é execução Godot nem aprovação de física ou performance.

- `tests/test_mountain_jeep_progress.gd`: percurso contínuo no modelo puro, sentido/largura/ordem dos gates, veículo errado, troca, saída, teleporte, largada queimada, timeout, recorde, repetição, JSON e recibos.
- `tests/test_mountain_jeep_course.gd`: conexão com estrada real, retorno, reservas de terreno, distância das áreas narrativas, limite de inclinação, criação de cristas/balizas com colisão.
- `tests/test_mountain_jeep_integration.gd`: cena Main/.NET real, fornecimento/adoção de um único jipe, apoio do corpo, embarque/saída normais, cancelamento pelo token real de transição, pausa, bloqueio de save e SaveStore isolado com recarga. Exige `--no-save` e a integração aplicada. O posicionamento de fixture na largada não comprova direção pela trilha.

Nenhum teste Godot, build, benchmark ou captura foi executado pelo subagente, por coordenação explícita com o processo externo já ativo. Executar somente depois que o agente principal liberar a fila exclusiva. Antes dos testes, compilar Harbor.csproj; usar exclusivamente Godot 4.7.2 .NET `_console.exe`.

Pendentes: volta completa dirigindo com física, calibração do limite de 110 s, revisão visual/temporal de neve-terra-talude, atravessar cristas/limites de chunk, colisão/oclusão de balizas, morte/prisão/troca de região reais e comparação renderizada p50/p95/p99/picos antes/depois. Alvo provisório 60 FPS/16,67 ms; regressão >5% nos percentis exige confirmação finita. Não há aprovação visual, física, temporal ou de performance.
