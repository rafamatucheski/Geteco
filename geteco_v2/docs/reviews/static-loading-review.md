# Revisão estática — carregamento e recursos do Geteco V2

Data da releitura final: 2026-09-21.

## Escopo e método

Foi conferida por leitura a cadeia `project.godot` (`run/main_scene`) → `ui/MainMenu.tscn` / `ui/MainMenu.gd` → novo jogo, continuar ou carregar → `Main.tscn` → `scripts/World.gd` → `runtime/ProductionWorld.gd`. Também foram conferidos os carregadores alcançados na montagem inicial do mundo, a abertura inicial, a frota, os catálogos JSON e a criação de interiores.

Os caminhos `res://` literais dos arquivos de produção foram confrontados com a árvore atual do V2, inclusive com comparação de caixa. Os caminhos dinâmicos foram conferidos pelos respectivos catálogos e chamadores. Não foram usados relatórios anteriores como prova.

Não foram executados Godot, parser/compilador GDScript, testes, benchmarks, importação, exportação ou commits. Nenhum `.import` ou `.uid` foi gerado. Portanto, este documento não afirma que o projeto compila, exporta ou funciona.

## Achados

### [P1] O projeto depende de JSON lido com `FileAccess`, mas não possui configuração de exportação que demonstre a inclusão desses arquivos

1. **Prioridade e impacto no jogador:** P1. Uma exportação feita com as opções padrão ou com seleção de cenas pode abrir o menu e falhar ao montar o mundo. O caso mais direto impede novo jogo e carregamento porque a região inicial depende de `OriginalWorldData.json`. Outros JSON afetam frota, moradores, lagos, pintura e diálogos.
2. **Arquivo, função e linha conferida:** `geteco_v2/runtime/ProductionWorld.gd`, `build()`, linhas 60–62; `geteco_v2/world/regions/NativeRegion.gd`, `_ready()` e `_prepare()`, linhas 42–47 e 53–88; `geteco_v2/runtime/FleetCatalog.gd`, `all()`, linhas 3–7; `geteco_v2/world/places/OriginalResidents.gd`, `for_place()`, linhas 2–5. Também foi conferida a ausência de `geteco_v2/export_presets.cfg` na raiz atual do projeto.
3. **Evidência e caminho de chamada:** `project.godot:14` abre `MainMenu.tscn`; `MainMenu._start()` troca para `Main.tscn` nas linhas 115–131; `World._ready()` cria `ProductionWorld` nas linhas 29–35; `ProductionWorld.build()` monta a região ativa e atualiza seus consumidores nas linhas 60–62, passando por `_mount_region()` nas linhas 144–153. A adição chama `NativeRegion._ready()`, que lê `res://world/regions/OriginalWorldData.json` por `FileAccess` e entrega o resultado diretamente a `_prepare()`. `_prepare()` acessa `source_data.harbor_roads` ou `source_data.mountain_control_points` sem um fallback. Foram localizados ainda `assets/fleet/catalog.json`, `world/places/OriginalResidentData.json`, `world/regions/OriginalLakeData.json`, `runtime/VehiclePaintSources.json` e os JSON de diálogo como dados de runtime. Nenhum deles possui `.import`. A documentação oficial do Godot alerta que JSON não é recurso e precisa de filtro de arquivos não-recurso ou de modo *Keep File*: <https://docs.godotengine.org/en/stable/classes/class_fileaccess.html> e <https://docs.godotengine.org/en/latest/tutorials/export/exporting_projects.html>.
4. **Classificação:** **risco**. A dependência e a ausência do preset são demonstráveis por leitura; a falha de uma exportação específica não foi medida nem reproduzida.
5. **Correção sugerida, sem aplicar:** versionar um preset de exportação que inclua explicitamente os JSON de runtime (ou migrar esses dados para recursos carregáveis pelo `ResourceLoader`), e adicionar verificação de existência, parse e esquema antes de usar o resultado. A falha deve produzir uma mensagem controlada, sem prosseguir com `source_data` inválido.
6. **Validação necessária:** gerar uma exportação limpa fora da árvore do editor; inspecionar o PCK/manifesto para os seis JSON de runtime; iniciar novo jogo em Harbor; carregar save em Harbor e Mountain; aproximar-se dos dois lagos; entrar em um interior com moradores; instanciar pelo menos um veículo assado; acionar um diálogo original. Registrar separadamente descoberta de testes e resultado; esta revisão não executou esses cenários.

### [P1] Falha de uma cena assada da frota retorna `null`, mas o veículo a desreferencia imediatamente

1. **Prioridade e impacto no jogador:** P1. Se uma cena `.scn` listada no catálogo faltar, estiver corrompida ou não entrar no pacote exportado, a criação do carro do jogador pode interromper a montagem do mundo. O mesmo caminho atende tráfego e veículos restaurados.
2. **Arquivo, função e linha conferida:** `geteco_v2/runtime/FleetCatalog.gd`, `create()`, linhas 10–14; `geteco_v2/scripts/Vehicle.gd`, `_ready()`, linhas 55–81; `geteco_v2/scripts/Driving.gd`, `_ready()`, linhas 14–19; `geteco_v2/runtime/ProductionWorld.gd`, `build()`, linhas 75–80.
3. **Evidência e caminho de chamada:** `ProductionWorld.build()` adiciona `Driving`; `Driving._ready()` cria `Vehicle`, define o arquétipo salvo ou `sport_coupe` e o adiciona ao mundo. `Vehicle._ready()` obtém uma especificação do JSON e chama `FleetCatalog.create()`. `create()` verifica o `PackedScene` e retorna `null` quando `load(definition.scene)` falha, mas `Vehicle._ready()` executa `visual.name = "Coupe"` e `add_child(visual)` sem validar `visual`. Todas as 49 cenas enumeradas no `assets/fleet/catalog.json` estavam presentes na releitura, portanto não há recurso ausente atual demonstrado. Entretanto, esses caminhos são descobertos em JSON em tempo de execução, e não por dependência estática da cena principal.
4. **Classificação:** **risco**. O contrato inconsistente (`create()` pode retornar `null`; chamador exige `Node3D`) é demonstrável. Não se confirmou falha dos arquivos atuais nem erro de compilação.
5. **Correção sugerida, sem aplicar:** fazer `Vehicle._ready()` tratar retorno nulo antes de acessar o visual, com fallback seguro ou abortamento controlado; validar `definition.scene` e o tipo carregado; tornar as cenas da frota dependências explícitas do pacote de exportação.
6. **Validação necessária:** teste de integração que percorra todas as entradas do catálogo e confirme `PackedScene` + instanciação; teste dirigido com uma entrada ausente/inválida para comprovar a degradação controlada; repetir na exportação limpa, não apenas no editor.

### [P2] Um `.tmp` de save abandonado torna o slot simultaneamente impossível de carregar e impossível de reutilizar

1. **Prioridade e impacto no jogador:** P2. Depois de interrupção durante salvamento, um slot que contenha apenas `slot_N.json.tmp` fica permanentemente bloqueado pela interface. Se isso ocorrer em vários slots, o jogador pode ficar sem espaço para iniciar um novo jogo mesmo sem saves válidos.
2. **Arquivo, função e linha conferida:** `geteco_v2/runtime/SessionLaunch.gd`, `list_slots()` e `prepare()`, linhas 13–32 e 41–48; `geteco_v2/ui/MainMenu.gd`, `_show_slots()`, linhas 70–89; `geteco_v2/runtime/SaveStore.gd`, `load_into()` e `save()`, linhas 14–21 e 22–49.
3. **Evidência e caminho de chamada:** `list_slots()` só valida o arquivo principal e `.bak` (linhas 17–21), mas inclui `.tmp` no booleano `exists` (linha 22). No menu, novo jogo desabilita todo slot com `row.exists`, enquanto carregar desabilita todo slot sem `row.valid` (linhas 79–87). `prepare()` repete os mesmos bloqueios. `SaveStore.load_into()` nunca tenta recuperar `.tmp`; `save()` cria o temporário antes da renomeação final. Portanto, no estado concreto “só existe `.tmp`”, não há ação disponível para carregar, recuperar ou reutilizar o slot.
4. **Classificação:** **defeito por leitura**.
5. **Correção sugerida, sem aplicar:** definir uma política explícita para temporários: validar e promover um `.tmp` íntegro quando não houver principal/backup, ou preservar o temporário como diagnóstico mas permitir ao jogador criar no slot mediante fluxo seguro e confirmação. Não apagar automaticamente dados sem verificar conteúdo.
6. **Validação necessária:** em diretório `user://` isolado, cobrir os estados: somente `.tmp` válido, somente `.tmp` inválido, principal + `.tmp`, backup + `.tmp` e nenhum arquivo. Confirmar rótulo, habilitação dos botões, recuperação e preservação do original sem tocar saves pessoais.

### [P3] O atalho de inicialização por flags abandona o resultado da troca de cena

1. **Prioridade e impacto no jogador:** P3. As flags `--sandbox`, `--slice`, `--no-save` e `--skip-arrival` ignoram o fluxo normal do menu; se `Main.tscn` não puder ser carregada, não há restauração do menu nem mensagem de erro. O impacto se concentra em execuções de desenvolvimento/diagnóstico e em qualquer distribuição que exponha essas flags.
2. **Arquivo, função e linha conferida:** `geteco_v2/ui/MainMenu.gd`, `_ready()`, linhas 19–27. Para contraste, `_start()` verifica o `Error` de `change_scene_to_file()` nas linhas 115–131.
3. **Evidência e caminho de chamada:** ao encontrar uma das flags, `_ready()` usa `change_scene_to_file.call_deferred("res://Main.tscn")` e retorna. Diferentemente do fluxo de novo jogo/carregar, o resultado da operação diferida não é observado e nenhum callback implementa tratamento de falha.
4. **Classificação:** **risco**. `Main.tscn` existe na árvore atual; não foi provocada falha de carregamento.
5. **Correção sugerida, sem aplicar:** encaminhar o atalho para uma função diferida que execute `change_scene_to_file()`, capture o `Error` e mantenha/restaure o menu com diagnóstico visível.
6. **Validação necessária:** iniciar cada flag em ambiente isolado, confirmar a transição e simular um alvo indisponível por fixture controlada para verificar o caminho de erro. Não alterar nem remover a cena real para esse teste.

## Itens conferidos que não viraram achado

- `project.godot:14` aponta para `res://ui/MainMenu.tscn`; o recurso, seu script, `Main.tscn`, `scripts/World.gd` e os autoloads declarados existem com a mesma caixa na árvore atual.
- Não foi encontrado `res://../` nem preload literal de produção que escape da raiz do V2.
- Os `model_class` que apontam para `res://prototypes/...`, `res://cars/...` e `res://world/harbor/...` em `data/catalogs/VehicleCatalog.gd` e `assets/fleet/catalog.json` referem-se a metadados de origem. O runtime usa `definition.scene` em `assets/fleet/*.scn`; os chamadores de produção não carregam `model_class`. Por isso, esses caminhos ausentes no V2 não foram reportados como dependência ativa.
- Os caminhos literais e dinâmicos da abertura, dos interiores catalogados e dos bancos de áudio examinados existem atualmente. A ausência de checagem em pontos como `NativePlace._ready()` e `opening_controller._ready()` permanece endurecimento desejável, mas foi absorvida pelos riscos de empacotamento e não duplicada como defeito atual.
- O trecho `WorldAudio.gd:81–82` infere `AudioStreamWAV` antes de receber `duplicate()`. Sem parser/compilação não foi possível estabelecer incompatibilidade; o ponto não foi elevado a erro de tipagem confirmado.

## Lacunas e entrega para outras equipes

- **Equipe de build/exportação:** receber o achado P1 de JSON e a inclusão explícita das cenas assadas.
- **Equipe de runtime/frota:** receber o tratamento de retorno nulo de `FleetCatalog.create()`.
- **Equipe de saves/menu:** receber o estado abandonado `.tmp` e o tratamento do atalho por flags.
- Uma releitura final das linhas citadas foi feita após a gravação e as referências foram atualizadas para a versão então presente. Como outras sessões podem continuar editando o repositório, a equipe que corrigir deve reconferir os mesmos chamadores no momento da alteração.
- Não houve compilação nem execução; erros de parser, comportamento real do export e resultado dos cenários acima continuam pendentes.
