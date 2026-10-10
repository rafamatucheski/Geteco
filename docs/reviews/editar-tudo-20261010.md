# Editor de mundo: editar tudo e "Jogar aqui" — validação (10/10/2026)

Pedido: poder editar absolutamente tudo (fio de luz, poste, pedra, coisas de missão) no editor 2D/3D e ter um botão que põe Dante no ponto e joga só aquele pedaço. Descrição de uso e limites: [world-editor.md](../world-editor.md).

## O que foi medido

Todos os testes abaixo rodaram com Godot 4.7.2 .NET, Mobile/RTX 4060 Laptop, em cima da árvore de trabalho compartilhada com outras sessões (que estavam editando scripts ao mesmo tempo).

| Teste | Resultado | O que cobre |
|---|---|---|
| `tests/test_world_units.gd -- --no-save` (headless) | **50 verificações, 0 falhas** | prévia → documento → jogo (sem prévia) para peça de chunk (cacto do deserto, pedra da montanha), poste do deserto, terraço do Harbor; mover/girar/esticar/elevar/excluir; cópia (deserto e Harbor), mãe excluída mantém a cópia; mobiliário em lote (posição, exclusão, cópia na lista de colocações); Vértice como lugar da sessão |
| `tests/test_world_editor_units_3d.gd` (janela) | **20 verificações, 0 falhas** | editor real no deserto: poste destravado e indexado, clique seleciona o poste (não o fio na frente), arraste grava, reconstrução mostra o poste movido, excluir/restaurar o fio, peça automática chega ao mapa e é editável, Duplicar pela interface |
| `tests/test_world_editor_units_3d_harbor.gd` (janela) | **12 verificações, 0 falhas** | editor real no Harbor: poste de calçada, hidrante e terraço são peças indexadas; clique + arraste do poste; **botão "Jogar aqui" abre o jogo e ele continua vivo após 25 s** |
| `tests/test_play_here.gd` | 6 verificações cada (montanha, deserto, Vértice) e 4 (Harbor), 0 falhas | o jogo real abre na região pedida, Dante perto do ponto e no chão (não no telhado), `no_save`, peça editada ainda não salva já está no lugar novo |

Capturas (ficam no disco, fora do Git): `evidence/editor-units/desert-units.png` (editor com a peça selecionada e os campos novos), `harbor-units.png`, `play-here-desert.png` (jogo real com Dante, o cacto 2,5× maior ao lado do poste e os fios).

Regressão do editor (`tests/test_world_editor*.gd`, bateria de 27 arquivos rodada com todos os ganchos prontos; depois dela mudaram só o texto de ajuda do painel, o campo `play_pid` e os dois testes de proteção, que foram reexecutados): todos passam **exceto**
- `test_world_editor.gd`: 2 verificações de árvore da montanha ("Mountain forest edit reaches rendered object", "Moved mountain tree rests on terrain"). Falham também com `GETECO_WORLD_UNITS_OFF=1` (interruptor que desliga todos os ganchos novos), então não vêm dos ganchos de peças; **a causa não foi isolada** (suspeita: mudanças de outras sessões no zoológico/terreno da montanha, não verificada).
- `test_world_editor_props.gd`: erro de script antes de qualquer verificação (`FACTORY.SIZES` não tem `desert_cactus`), anterior a esta entrega e fora dela.

Testes que **afirmavam a proteção antiga** e foram atualizados de propósito (o pedido é justamente o contrário): `test_world_editor_pieces.gd` (3), `test_world_editor_piece_shapes.gd` (1), `test_world_editor_desert.gd` (1), `test_world_editor_service_controls.gd` (1, agora cobre os dois modos de Colocação livre) e `test_world_editor.gd` (1, idem).

Verificação mínima do `CLAUDE.md`: `test_bridge_approach_terrain.gd` PASS; `test_native_driving.gd -- --no-save` PASS; `cold/test_admission.gd` 11 verificações sem falha; **`test_regions.gd` não completou**: para em `tests/test_regions.gd:24` com "Invalid access to property or key 'model' on a base object of type 'Node3D (HarborBuildingPlace.gd)'", arquivo que outra sessão está alterando.

## O que NÃO foi medido

- **Desempenho em jogo.** Nenhum FPS/percentil de quadro foi medido. Sem edições, os caminhos novos saem na primeira linha (nenhuma peça é criada, nenhum nó muda de pai); o único custo permanente é um `Engine.get_meta` por registro construído e uma checagem por chunk. Só há medida de tempo de construção da prévia headless (deserto 8,3 s com os ganchos × 9,5 s com `GETECO_WORLD_UNITS_OFF=1`; Harbor 2,4 × 3,7 s; montanha 1,7 × 5,1 s) e com a máquina carregada por outras sessões: diferença dentro do ruído, não é medida de regressão.
- **Cobertura individual dos lugares da sessão.** O mecanismo (observar a árvore e aplicar em 3/90/400 quadros) foi exercitado no jogo com o Vértice; Posto do Tonico, Torque, portão norte, descida, saída do forte e conexão usam o mesmo código mas não foram testados um a um.
- **Colisão e gameplay das peças movidas.** Foi checado que a posição final do grupo (malhas e corpos estáticos) mudou; não foi dirigido/andado contra cada tipo de peça movida, nem verificado que gatilhos de missão continuam coerentes depois de mover o visual (a interface avisa nos equipamentos conhecidos).
- **Troca de chunk de peças automáticas** (além do vizinho): é limite documentado, não testado.
- O botão foi exercitado pela chamada `_play_here()` do editor real; não houve clique manual em janela.

## Segunda parte: correções e restrições removidas

- `test_world_editor.gd` (árvore da montanha): o foco agora só garante o chão e os registros do chunk saem fatiados; o teste passou a completar o chunk da árvore. 46/46.
- `test_world_editor_props.gd`: `WorldPropFactory.SIZES` ganhou `desert_cactus` e `desert_rock`. 93/93.
- `test_regions.gd`: `HarborBuildingPlace` embrulha o cômodo em `floor_room`; o teste lê `model`/`solid_bodies` de lá. `REGIONS PASS failures=0`.
- Restrições removidas (ver world-editor.md): travas de prédio, exclusão de serviço e bueiro, limites numéricos, vias e luzes do deserto, peça movida a qualquer distância.
- `tests/test_world_units.gd`: 62 verificações, 0 falhas (inclui peça 400 m longe com só o destino carregado, via/luz do deserto, validações novas). Bateria `test_world_editor*` (28 arquivos) sem falha depois de atualizar 4 testes que afirmavam limites antigos (garagem, escala 4, piso de 65 m, handles de local protegido) e 2 sobre exclusão (bueiro, prédio de serviço).
- Não medido: gameplay com via do deserto editada (tráfego/rotas), prédio de serviço excluído em partida real, desempenho.
