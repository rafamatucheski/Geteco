# Apresentação urbana: estações e rodoviária

Implementado, **ainda não validado**. Nesta rodada não foram executados Godot, testes, capturas ou benchmarks, conforme solicitação. Não representa migração do serviço de transporte público.

`runtime/UrbanTransitPresentation.gd` recebe `configure(controller)` antes ou depois de entrar na árvore. `_ready()` e `refresh()` toleram a inicialização parcial. `on_region_changed()` remove a apresentação anterior e carrega a região atual. A ProductionWorld integra esses pontos. Dentro de ambientes, o foco é `session.return_point`, preservando os exteriores próximos.

Foram copiados os seis destinos e a ordem de `world/harbor/urban_transit/UrbanTransit.gd:STOP_DEFS`. As ruas retas e larguras são de `HarborRoadLayout.gd`. A posição usa exatamente a faixa deslocada por `tangent.orthogonal()*width/4*direction`, de `UnifiedRoadNetwork2D`, seguida da fórmula original da estação: posição de faixa menos 90 pixels na direção de viagem e 60 pixels na perpendicular local. A orientação é passada ao modelo, que já a aplica à geometria; não existe uma segunda rotação do nó.

O terminal regional permanece em `(1700,1060)/16`, de `HarborGame.tscn:ArrivalStop`. O adaptador usa as fábricas entregues em `world/urban_detail`, sem editar seus arquivos. A calibração do piso é `(18/16,1,18*0.76822128/16)`: transforma os modelos preparados para a antiga projeção PPM18/FLOOR_Y no mesmo piso /16 usado pelo mapa, preservando as alturas. É aplicada ao conjunto visual e físico. Esta escala não equivale a reduzir o modelo métrico inteiro novamente por 16.

A leitura das fontes preserva o corredor do M00: o ônibus V2 continua em `(1700,1250)/16`, e a chegada a pé em `(1700,1130)/16`. A arquitetura não cria ônibus, passageiros, novos destinos, marcadores de ação ou controles concorrentes. O prédio principal e plataformas permanecem ao norte da origem; o desembarque segue ao sul. A guarita permanece no lado leste original. Esta verificação de coordenadas **não substitui** admissão física do casco e da cápsula no jogo renderizado.

Streaming próprio avalia somente sete definições a cada 0,25 s. Carrega a 105 m e descarrega a 135 m, com histerese; fora de Harbor remove os conjuntos. Não mantém SubViewports ou uma segunda cópia dentro de NativeRegion. A distância inclui folga para o maior terminal, mas custo de construção e transição ainda precisam de medição.

Pendências concretas: validar colisores sob calibração do piso, desembarque/rota M00, largura da rampa e portão das seis estações, oclusão e encontros com fachadas/mobiliário recém-integrados; inspecionar apresentação e comparar frame time/streaming na Main real. Operação de linha 510, horários, embarque, passageiros, circulação regional e lógica das cancelas não foram migrados neste lote. O modelo entregue pode conservar elementos de plataforma fechada; não há ação de embarque anunciada.
