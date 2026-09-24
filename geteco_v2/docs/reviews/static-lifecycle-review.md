# Revisão estática — ciclo de vida e transições do Geteco V2

Data da leitura: 2026-09-21  
Escopo: novo jogo/carregamento, entrada e saída de interiores, troca de região, morte/reaparecimento e retorno ao menu. A revisão de despacho e ultrapassagem ficou limitada aos pontos externos de integração; não houve inspeção interna desses subsistemas.

## Método e limites

- Foram conferidos os chamadores de produção a partir de `project.godot`, `MainMenu`, `ProductionWorld`, `FullSession`, `Arrival`, `PauseMenu`, `Driving`, `GameState` e `PlaceCatalog`.
- Relatórios e testes existentes foram usados somente para entender contratos; não foram tratados como prova de execução atual.
- Não foram executados Godot, testes, benchmarks, importação, compilação nem commits. Portanto, este documento não declara que o projeto compila ou funciona.
- Nenhum save pessoal, credencial ou dado externo foi lido.
- As classificações abaixo significam: **defeito por leitura** quando o caminho contraditório é determinado diretamente pelo código; **risco** quando a abertura é demonstrável, mas o efeito final depende de temporização/semântica de runtime ainda não executada; **hipótese** quando falta confirmação adicional.

## Resumo prioritário

| ID | Prioridade | Classificação | Impacto principal | Equipe indicada |
|---|---|---|---|---|
| LIFE-01 | P1 — alta | Defeito por leitura | Duas entradas a pé podem coexistir e deixar sala/NPCs órfãos ou duplicados | Sessão e interiores V2 |
| LIFE-02 | P1 — alta | Defeito por leitura | O jogador pode desembarcar durante a transferência de garagem e terminar com ocupação/câmera incoerentes | Veículos + transições de interiores |
| LIFE-03 | P1 — alta | Defeito por leitura | Um save aceito pode combinar região e interior incompatíveis e restaurar/retornar em coordenadas de outro mapa | Save/schema e migração |
| LIFE-04 | P2 — média | Risco | Pausa permite salvar, carregar ou voltar ao menu durante corrotinas bloqueadas da chegada | Chegada/cutscene + UI de pausa |

## Achados

### LIFE-01 — Entrada a pé não tem exclusão mútua e usa estado compartilhado após `await`

1. **Prioridade e impacto no jogador:** P1 — alta. Uma segunda interação durante a admissão pode criar mais de um interior, sobrescrever `room`, instalar NPCs duas vezes e deixar o primeiro nó de sala anexado ao mundo sem proprietário. O resultado possível é duplicação de atores/colisões, câmera ligada à sala errada e crescimento de objetos até recarregar a cena.
2. **Arquivo, função e linha conferida:**
   - `geteco_v2/runtime/FullSession.gd`, `interact`, linhas 579–595.
   - `geteco_v2/runtime/FullSession.gd`, `enter_place`, linhas 405–466.
3. **Evidência e caminho de chamada:** `FullSession._input` encaminha `interact` para `interact()`; o ramo `enter` grava `access_id`, chama `enter_place(action.place)` sem aguardar o resultado e retorna `true`. `enter_place` só rejeita veículo ocupado ou `state.place_id` não vazio nas linhas 405–406. Em seguida trava apenas o ator, escreve no campo compartilhado `room`, adiciona a sala ao `world` e aguarda dois `physics_frame` nas linhas 416–435. `state.place_id` só muda na linha 446. Logo, enquanto a primeira chamada está suspensa, uma segunda chamada ainda passa pelo mesmo predicado, substitui `room` e adiciona outra sala. Ambas retomam usando o último valor do campo `room`; não há serial/token de geração nem revalidação depois do `await`.
4. **Classificação:** defeito por leitura. A janela e a mutação concorrente do mesmo campo são explícitas; a revisão não mede quão fácil é produzir dois eventos dentro dela.
5. **Correção sugerida, sem aplicar:** criar um estado único de transição de lugar antes de qualquer mutação, rejeitar novas interações/carregamento/menu enquanto ele estiver ativo, manter `next_room` local até a admissão física ser concluída e revalidar sessão, saúde, região e destino após cada `await`. Limpar somente o nó criado pela tentativa correspondente em qualquer saída antecipada.
6. **Validação necessária:** em uma cena renderizada real, injetar duas interações de entrada em quadros consecutivos e também `F9`/pausa durante a janela. Verificar exatamente uma sala anexada, uma coleção de NPCs, `state.place_id`, `room`, câmera, colisão, retorno e autosave coerentes; repetir com Maciota e um interior criado por `PlaceCatalog`.

### LIFE-02 — A transferência de garagem trava o carro, mas o controlador de desembarque continua aceitando `F`

1. **Prioridade e impacto no jogador:** P1 — alta. Durante entrada ou saída com veículo, o jogador pode sair do carro antes da admissão terminar. A transferência continua sem confirmar que o carro ainda está ocupado e pode finalizar com o personagem a pé, `Driving.occupied == false`, estado de interior alterado e câmera seguindo o carro/âncora incorretamente.
2. **Arquivo, função e linha conferida:**
   - `geteco_v2/runtime/FullSession.gd`, `transfer_garage_vehicle`, linhas 50–122.
   - `geteco_v2/scripts/Driving.gd`, `_unhandled_input`, linhas 32–34; `interact`, linhas 58–77.
3. **Evidência e caminho de chamada:** a transferência valida ocupação somente antes de marcar `vehicle_transition_busy` (linhas 50–57), trava `car.input_locked`, zera movimento e aguarda três `physics_frame` (linhas 58–78). Ela não trava `world.player.input_locked` e não revalida `world.driving.occupied`/`world.driving.car` ao retomar. Paralelamente, `Driving._unhandled_input` continua chamando `interact()` para `exit_vehicle`; `Driving.interact` não consulta `vehicle_transition_busy` nem `car.input_locked`, e quando `occupied` é verdadeiro chama `leave()`. Na saída da garagem, a transferência ainda atribui `world.camera.target = car` nas linhas 101–111 mesmo que o desembarque concorrente já tenha tornado o jogador pedestre.
4. **Classificação:** defeito por leitura. Os dois consumidores de entrada não compartilham o bloqueio e a pós-condição não é revalidada.
5. **Correção sugerida, sem aplicar:** fazer `Driving` consultar um bloqueio de transição pertencente à sessão (ou bloquear também o ator e consumir `vehicle_interact`/`exit_vehicle`), e validar novamente ocupação, carro, lugar e geração da tentativa depois do `await`. Em cancelamento, restaurar atomicamente todos os locks, câmera e estado de ocupação.
6. **Validação necessária:** iniciar entrada e saída veicular em Maciota e na garagem do chefe e enviar `exit_vehicle` em cada um dos três quadros de espera. Ao concluir ou cancelar, conferir ocupação, visibilidade e colisão do jogador, `car.controlled`, locks, câmera, `state.place_id`, metadados do carro e possibilidade de nova transição. Incluir morte e retorno ao menu durante a mesma janela.

### LIFE-03 — O validador de save aceita pares incompatíveis de `region_id` e `place_id`

1. **Prioridade e impacto no jogador:** P1 — alta. Um save estruturalmente aceito pode restaurar um interior de Harbor enquanto a região ativa é Mountain (ou o inverso). Ao sair, `return_point` vem da definição do outro mapa, fazendo streaming e teleporte para coordenadas que não pertencem à região carregada.
2. **Arquivo, função e linha conferida:**
   - `geteco_v2/runtime/GameState.gd`, `restore_snapshot`, linhas 43–97.
   - `geteco_v2/runtime/FullSession.gd`, `restore_location`, linhas 327–367; `enter_place`, linhas 405–466; `leave_place`, linhas 468–490.
   - `geteco_v2/world/places/PlaceCatalog.gd`, `definitions`, linhas 9–39 e montagem das definições nas linhas 40–66.
3. **Evidência e caminho de chamada:** `restore_snapshot` valida que a região é `harbor` ou `mountain` e que `place_id` é apenas uma string com até 128 caracteres; não confere a propriedade `region` da definição do lugar. Depois de aceitar o snapshot, `restore_location` considera válido qualquer ID existente no catálogo e chama `enter_place(place, false)`. `enter_place` também não confere `definition.region == state.region_id`, usa o `return_position` catalogado e grava o par incompatível. `leave_place` então foca a região ativa e teleporta para esse `return_point`. O catálogo demonstra que os lugares carregam região explícita e coordenadas diferentes para Harbor e Mountain.
4. **Classificação:** defeito por leitura. A fronteira de validação aceita uma combinação que o fluxo normal de acesso não produz, mas o carregamento trata como válida e a consome.
5. **Correção sugerida, sem aplicar:** validar `place_id` contra uma tabela explícita de lugares permitidos para `region_id`, incluindo a regra especial de Maciota; rejeitar ou migrar de forma segura pares incompatíveis antes de modificar o estado. Como defesa adicional, `enter_place` deve recusar definição de outra região e `restore_location` deve cair em um checkpoint exterior conhecido sem autosalvar sobre o original inválido.
6. **Validação necessária:** construir snapshots sintéticos (sem usar saves pessoais) para `mountain + harbor_bank`, `harbor + mountain_cabin`, `mountain + maciota`, lugar inexistente e pares válidos. Verificar rejeição/preservação do arquivo incompatível, fallback explícito, nenhuma sala criada e nenhum teleporte para coordenadas de outra região; cobrir também backup e retorno ao menu.

### LIFE-04 — Sequências assíncronas da chegada não entram no bloqueio de pausa/save/load/menu

1. **Prioridade e impacto no jogador:** P2 — média. Durante desembarque e embarque guiado, o menu de pausa pode expor salvar, carregar e voltar ao menu enquanto a chegada mantém o jogador oculto ou com física desativada e há corrotinas suspensas. Isso permite interromper a sequência em estado transitório e cria risco de continuação/callback após descarregamento ou de retomada em fase anterior.
2. **Arquivo, função e linha conferida:**
   - `geteco_v2/runtime/Arrival.gd`, `_lock`, linhas 109–111; `_begin_disembark`, linhas 113–147; `_board`, linhas 223–257.
   - `geteco_v2/runtime/FullSession.gd`, `_input`, linhas 623–656; `save_game`, linhas 941–970; `load_game`, linhas 971–981; `return_to_main_menu`, linhas 982–996.
   - `geteco_v2/ui/PauseMenu.gd`, `pause_game`, linhas 52–68.
   - `geteco_v2/scripts/PauseInput.gd`, `_unhandled_input`, linhas 4–10.
3. **Evidência e caminho de chamada:** `Arrival` marca `controls_locked`, desativa física/visibilidade do jogador e aguarda frames/caminhadas; `_board` ainda aguarda um timer na linha 238 antes de ocultar atores e assumir a câmera. `FullSession._input` simplesmente retorna quando `arrival.controls_locked` é verdadeiro, sem marcar o evento como tratado. `PauseInput` bloqueia somente `arrival.phase == "opening"`, portanto o evento de pausa alcança o menu em `disembark` e `tour_boarding`. O cálculo `in_transit` do `PauseMenu` não inclui `arrival.controls_locked`; as guardas de `save_game`, `load_game` e `return_to_main_menu` também não incluem esse estado. A linha 238 não faz uma checagem de geração/validade após o timer. Não foi executado o runtime para afirmar se o engine cancela toda continuação ao liberar a cena; esse efeito permanece como risco, não como erro confirmado.
4. **Classificação:** risco. A disponibilidade indevida das ações é demonstrável por leitura; o comportamento exato da corrotina após troca de cena precisa de execução dirigida.
5. **Correção sugerida, sem aplicar:** representar a chegada bloqueada no mesmo contrato central de transição usado por pausa/save/load/menu; consumir `pause_game` quando a sequência não puder ser pausada ou implementar pausa/cancelamento explícito. Adicionar token de geração e checagens de validade após todo `await`, especialmente o timer de embarque, restaurando física, visibilidade, colisão, câmera e locks em cancelamento/`_exit_tree`.
6. **Validação necessária:** pausar em cada `await` de `disembark` e `tour_boarding`; confirmar quais ações devem estar desabilitadas. Exercitar carregar e voltar ao menu nesses pontos sob monitoramento de erros, assegurar ausência de callback no mundo antigo e iniciar nova sessão verificando jogador visível, física/colisão, câmera, fase da chegada e pausa restauradas. Não tratar simples ausência de crash como cobertura suficiente.

## Fluxos conferidos sem achado consolidado

- A troca de região usa `travel_busy`, bloqueia entrada em `FullSession._input`, preserva a região de origem até a admissão física do destino e restaura pausa/input no ramo explícito de falha. Não foi feita medição nem execução para validar seus efeitos reais.
- Morte e reaparecimento limpam sala, NPCs de serviço, transporte de passageiro, perseguição externa e estado de câmera no caminho nominal. Foram vistas sincronizações posteriores por processo em `Arrival`, `Robberies` e `GarageRewards`, mas sem execução não se afirma ausência de corridas em combinações raras.
- O retorno ao menu restaura `SceneTree.paused` em falha de troca de cena e força estado não pausado antes da troca bem-sucedida. O risco consolidado é a falta de inclusão das transições de chegada e a pé nas guardas, não uma falha geral dessa restauração.
- Conexões de sinais inspecionadas pertencem majoritariamente a nós da mesma cena e tendem a ser removidas com suas fontes/alvos; não foi encontrado, por leitura, um caso atual de conexão duplicada no caminho nominal que justificasse achado separado.

## Lacunas deliberadas

- Nenhuma afirmação de erro de compilação, execução bem-sucedida, FPS ou desempenho aprovado.
- Nenhum teste, benchmark, Godot, importação ou exportação foi executado; os cenários acima são prescrições de validação futura.
- Sem inspeção interna dos algoritmos de despacho e ultrapassagem; somente chamadas externas de liberação/sincronização foram consideradas.
- A semântica exata de cancelamento de corrotinas GDScript quando a cena é substituída deve ser confirmada no executável e versão usados pelo projeto.
