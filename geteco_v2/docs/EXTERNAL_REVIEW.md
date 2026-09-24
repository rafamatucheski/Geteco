# Revisão dos módulos externos — 21/09/2026

Primeira revisão da cópia disponível durante o trabalho concorrente. Não representa uma entrega final confirmada pelos autores. Nenhum arquivo dentro dos módulos externos foi editado nesta revisão; ambos continuam desligados da Main. Correções posteriores podem invalidar os apontamentos, que devem ser conferidos novamente antes da integração.

## Execução real do integrador

Godot 4.7.2, projeto Geteco V2. Importação headless não registrou erros, mas isso não comprovou compilação dos scripts ainda não referenciados pela Main.

- Urban: `tests/urban_detail/test_urban_building_factory.gd` terminou com código 1 e erros de compilação. [Log completo](../evidence/external-urban-factory.log).
- Dispatch: `tests/dispatch/test_dispatch_rules.gd` terminou com código 0 e imprimiu `checks=27 failures=0`, **apesar de SCRIPT ERROR**. Resultado reprovado. [Log completo](../evidence/external-dispatch-rules.log).
- Não foram executados os testes dependentes nem benchmarks desses módulos enquanto a compilação está quebrada. Nenhum FPS ou aspecto visual deles foi aprovado.

## Antigravity — urban_detail

1. Corrigir chamadas inexistentes `UrbanMaterials.metal_dark()` e `brick_dark()`, além das inferências sem tipo em `u_mat`, `u_door_mat`, `wx`, `hx`, `bx` e variáveis derivadas. O log mostra os arquivos e linhas afetados; corrigir a API compartilhada e todos os consumidores.
2. Em `UrbanBuildingFactory`, hospital, loja de armas, residências e casa do cemitério recebem ajustes de portas, materiais, nomes e geração de colisão antes de entrarem na árvore. Os modelos constroem as malhas em `_ready()`: nessa ordem, a busca de malhas retorna vazia. Separar criação da finalização após `add_child`, de maneira síncrona e explícita, para não entregar fachadas sem colisão nem portas bloqueadas. Conferir fisicamente acessos e sólidos depois da montagem real.
3. Validar o contrato com os dados reais de `NativeRegion`, incluindo unidades, formato e posições, em vez de presumir que o teste da fábrica equivale à Main.
4. Materiais compartilhados reduzem duplicação de recursos, mas não unem automaticamente os draw calls de MeshInstance3D distintos. Remover essa alegação de desempenho do handoff; comprovar custo na cena integrada antes/depois.
5. `UrbanSignage.gd:10` associa `NorthFrontage1` a Foundry Flats, mas a fábrica usa esse ID para Ammu-Nation. Usar o nome próprio do estabelecimento conforme o catálogo ao corrigir a finalização do modelo.
6. `UrbanLShapedBlock.gd:29` chama a cobertura retangular completa da base, incluindo o pátio sudoeste. Mesmo com piso sem colisor, o telhado pode ocultar o jogador no pátio; preservar também a forma em L na cobertura e verificar oclusão separadamente.
7. `UrbanServiceBuilding.gd:175` produz vão de 7,875 m e fundo de 1,2 m; a fonte usa 110 px = 6,875 m e fundo de 40 px = 2,5 m. Reconciliar os sólidos da oficina e testar o casco inteiro do veículo.
8. `UrbanTransitStation3D.gd:49–53`: o ponto de embarque não incorpora `orientation_angle`, apesar de a geometria girar. Aplicar a mesma transformação e verificar aproximação em estação rotacionada.
9. Os testes de acesso usam amostras pontuais de cápsula, não percurso completo nem casco do carro. A vitrine visual não registra janela de frame times na Main. O inventário de 61 registros inclui Maciota, que retorna null: não declarar 61 modelos novos construídos.
10. `UrbanShopfrontBuilding.gd:64`: a porta recuada fica dentro do bloco opaco `ShopBody`, sem recortar o vão. Abrir o volume da entrada, preservando paredes laterais e fundo, e verificar visibilidade e aproximação com cápsula no cenário renderizado.

## Claude — dispatch

1. `DispatchRules.gd:97`: a inferência de `goal` falha por operação com valor sem tipo definido. Tipar o resultado e conferir as demais operações com arrays. A chamada subsequente a `stop_radius` falha porque o script não compilou.
2. O teste de regras continua e imprime sucesso após abortar `_rules()` por erro. O runner precisa reprovar SCRIPT ERROR/compilação e verificar que todos os grupos e quantidades esperadas realmente terminaram. Código de saída zero, sozinho, não serve.
3. `DispatchUnit._police_working` retorna a `enroute` quando a dupla morre, e `_police_parked` cria nova dupla sem consumir novo orçamento. Guardar a composição/orçamento já utilizado; cobrir morte de toda a equipe e retorno ao alvo.
4. A suspensão esconde e congela policiais/socorristas, mas mantém colisões. Suspender também participação física e validar cápsulas ao retomar, não somente o casco do carro.
5. `set_enabled(false)` restaura o relógio de emergência, mas não desfaz a alteração artificial de `Gameplay.deployed`. Preferir controle explícito e único do despacho na integração; desligar o módulo deve devolver o comportamento legado sem zerar arbitrariamente a procura.
6. `dismiss_all()` não recolhe os destroços registrados em `wrecks`, e a saída do controlador não recolhe carros que são filhos de `world`. Cobrir troca de região, desligamento e destruição do controlador, sem deixar objetos órfãos.
7. Revalidar o papel do socorrista durante `working`: paciente que morre durante atendimento médico deve gerar fluxo de legista, sem paramédico remover o corpo por `EmergencyManager.complete()`.
8. `test_dispatch_emergency.gd:102` pode consultar `crew_seen` já liberado após embarque. Capturar a evidência antes da liberação ou verificar `is_instance_valid`, conforme a intenção do teste.
9. `measure_dispatch.gd` e comandos de benchmark precisam exigir `--no-save`, pular Arrival e fixar cenário/carga. Não medir filme, save pessoal ou estado variável como referência de despacho.

## Responsabilidade da integração

Após a correção dos módulos: executar testes dirigidos com inspeção dos logs; conectar um único responsável por polícia e emergências; preservar as regras de armas da garagem; integrar as fachadas sem duplicar prédios ou bloquear acessos; medir a Main renderizada em cenários comparáveis. As aprovações de performance do restante do V2 não se estendem automaticamente a estes módulos.
