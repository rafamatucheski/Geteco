# Chegada original em 3D nativo

> Atualização de 28/09/2026: a chegada de ônibus descrita no relatório histórico
> abaixo foi substituída pela chegada ao terminal de passageiros de Harbor.
> A CGI termina antes da viagem de ônibus; Dante desembarca fisicamente do barco.
> Ver [direção e implementação de Harbor](harbor-identidade-e-chegada.md).

Fontes: `world/harbor/campaign/HarborArrivalMission.gd`, `HarborStoryArrival.gd`, `MaciotaTourCar.gd`, `MaciotaM8SedanModel.gd`, `HarborArrivalStop.gd`, `HarborTransitBus.gd`, `systems/Localization.gd` e a CGI produtiva `cutscenes/opening/OpeningCutscene.tscn`/`v3`. O V1 permanece intocado.

## Sequência e recursos

1. A CGI original inteira aparece como `Control`, acima do mundo nativo pausado. Foram preservados os 28 planos, 16 imagens aprovadas distintas, legendas/timing, música, foley e vozes PT/EN. Os arquivos ativos foram copiados sem modificar o filme. `show_studio_intro=false`; a confirmação original de pulo continua funcional. Não se usam capturas do palco de autoria rejeitadas pelo AGENTS da CGI.
2. Dante sai do ônibus urbano original `route_city`, parado em `(1700,1250)/16`, e caminha com colisão até `(1700,1130)/16`. Apenas ao terminar recebe `harbor_arrival_seen`.
3. Na delegacia, o jogador se aproxima do balcão e ouve as cinco falas completas sobre Vicente. Recebe `harbor_police_briefed`, sai e aguarda os quatro segundos originais.
4. O telefone toca com o oscilador original. Atender mostra/reproduz as quatro falas completas; marca `harbor_arrival_call_complete` e direciona ao ferro-velho.
5. O encontro em `(-750,930)/16` conserva as três falas e o M8 original inteiro, com quatro portas, rodas e ocupantes. Maciota usa o modelo original V2 e um corpo físico deliberadamente sem saúde, `receive_damage` ou morte.
6. Dante e Maciota caminham até suas portas. Só então o jogador fica oculto como passageiro, com um ocupante original visível no veículo. O percurso usa o grafo dirigido das ruas, incluindo a via Westgate de 4.5 m autorizada especificamente para esse passeio; tráfego ambiente mantém o filtro de 5 m.
7. As quatro legendas/falas do passeio são preservadas. Cada uma espera distância percorrida, tempo e término do áudio anterior. O veículo usa movimento físico e sensores; não avança por obstáculos. A aproximação final é uma mudança suave de faixa até o acesso da garagem.
8. O desembarque testa espaço e varre o trajeto de saída dos dois atores. Uma saída bloqueada mantém o passageiro no veículo. Maciota caminha fisicamente até a porta e seu residente na garagem fica disponível.

Vinte gravações originalmente referidas nessas falas foram copiadas por hash de texto/personagem, com manifest isolado. O `ExpressiveVoice` original permanece responsável pelos idiomas/linhas sem gravação. Não se inventou dublagem.

## Contrato de integração

`Arrival.configure(session)`; depois `start_or_resume(loaded)`. `nearest_action()/perform(id)` precedem os serviços da sala, `on_location_changed()` acompanha entradas/saídas e `notify_maciota_met()` conclui após conversa real na garagem. `objective_text`, `target`, `active`, `controls_locked`, `riding` orientam a UI central. Enquanto `phase == opening`, o input deve ficar com a confirmação do filme; durante o passeio, encaminhar sair/cancelar para `cancel_ride()` antes do bloqueio comum de controles.

`snapshot()/restore_state()` e o validador estático preservam marcos originais, progresso da apresentação e índice de legenda. Pular/finalizar a CGI marca `opening_completed` somente depois do fade final; não repete a abertura ao continuar. Saves V2 anteriores à chegada continuam sem recomeçar a jornada. Um save feito durante o passeio restaura o checkpoint original no ferro-velho, com atores visíveis e colisões, assim como o adaptador V1. O encontro distante suspende a física do carro até o chão local estar carregado.

Este adapter não avança artificialmente nenhum dos nove beats de `CanonicalCampaign`. A integração desse ledger com a conclusão produtiva da abertura continua responsabilidade do runtime de campanha, não de chamadas arbitrárias do passeio.

## Validação

- `tests/test_arrival.gd`: 14 verificações de estado, marcos inválidos, 16 falas, identidade original, portas/ocupantes/rodas, imortalidade e rede viária.
- `tests/test_opening.gd`: todas as imagens/planos/stems, confirmação de pulo, fim efetivo, emissão única e checkpoint sem replay passaram. Encerramento instantâneo ainda reportou recursos de áudio retidos; não foi mascarado.
- `tests/test_arrival_flow.gd`: no `Main.tscn`, desembarque físico, delegacia com cinco falas, saída, quatro segundos, telefone com quatro falas, save válido e encontro suspenso até streaming passaram.
- `tests/test_arrival_drive.gd`: embarque por ambas as portas, 200.98 m nas ruas reais, chegada com saúde do carro intacta, saída com colisão e caminhada final de Maciota até a porta passaram. O último encerramento, após a caminhada final, foi limpo.

Logs em `evidence/arrival-tests.log`, `opening-tests.log`, `arrival-flow-tests.log`, `arrival-drive-tests.log`. Ensaios headless não aprovam FPS. O movimento das mãos/corpo no gesto de sentar não replica ainda as poses adicionais `VehicleBoardingPose`/`MaciotaBoardingPose` do V1; aproximação, portas, ocupação e saída já são físicas. A operação contínua de todas as filas/linhas de ônibus do terminal não faz parte deste adapter.

## Revisão renderizada e desempenho — 21/09/2026

Cena integrada `Main.tscn`, Godot 4.7.2, RTX 4060 Laptop, Vulkan Mobile, 1280×720, MSAA 1, VSync 1, limite 60 FPS, 24 pedestres e nove veículos ambientais solicitados. Mesma configuração do benchmark nativo anterior; salvo exclusivamente com `--no-save`. Inventários de processos registraram zero jogos concorrentes em 40 amostras da CGI e 47 do passeio final; o editor preexistente permaneceu aberto, como no baseline.

Cada medição separou cinco segundos de aquecimento de 30 segundos de intervalos reais entre frames (1801 frames). Capturas foram feitas fora da janela de medição. Após medir o passeio, o ensaio continuou até completar a viagem, restaurar Dante e ver Maciota caminhar até a porta.

| Cenário | FPS | p50 ms | p95 ms | p99 ms | Máximo ms | >33.3 ms / >66.7 ms |
|---|---:|---:|---:|---:|---:|---:|
| CGI original | 60.0023 | 16.666 | 16.906 | 17.173 | 17.758 | 0 / 0 |
| Passeio antes da correção de ciclo de vida | 60.0006 | 16.669 | 17.423 | 18.248 | 33.250 | 0 / 0 |
| Passeio após a correção | 60.0026 | 16.668 | 17.456 | 18.195 | 32.871 | 0 / 0 |

O primeiro passeio revelou erros repetidos em `ProductionWorld`: tentar `erase` de uma referência já liberada em array tipado de pedestres. A raiz corrigiu a remoção por índice inverso e acrescentou sua regressão de ciclo de vida. A evidência falha foi preservada em `arrival-tour.*`; somente o cenário afetado foi repetido em `arrival-tour-fixed.*`, com stderr vazio, viagem concluída e Maciota na garagem. Os percentis variaram menos de 1% entre essas duas rodadas comparáveis, sem regressão confirmada. A CGI também encerrou com stderr vazio.

No aquecimento da primeira rodada do passeio houve um frame de 37.764 ms; na rodada corrigida o máximo foi 22.711 ms, sem quadros acima de 33.3 ms. Na CGI o máximo de aquecimento foi 17.216 ms. A inicialização da fixture até o início do aquecimento levou 9.34 s para CGI e 10.08 s para passeio; isso inclui carregar a cena/população e preparar a interação, não apenas renderizar um frame. Esses tempos não foram ocultados na amostra estável.

O benchmark anterior `full-native-driving-isolated-population24.json` teve 60.0031 FPS, p95 17.527 ms e p99 18.176 ms. Serve como contexto da mesma máquina/configuração; a rota e o conteúdo são diferentes, portanto não prova um comparativo controlado contra o jogo anterior à migração. A aprovação de estabilidade fica limitada aos dois cenários medidos, com a configuração normal a 60 FPS; não afirma capacidade ilimitada nem identifica custo de GPU por subsistema.

Capturas inspecionadas:

- CGI: `arrival-cgi-measured.png`, `arrival-cgi-bus-gallery.png`, `arrival-cgi-terminal.png`. Arte ilustrada aprovada, composição, galeria no celular e botão de pulo preservados.
- Mundo: `arrival-cgi-disembarked.png`, `arrival-tour-meeting.png`, `arrival-tour-fixed-measured.png`, `arrival-tour-fixed-garage.png`. Ônibus original, M8, Maciota, pedestres, tráfego, legenda completa e chegada à garagem visíveis na cena real.

**Lacuna visual confirmada:** a região do desembarque ainda é um terreno amplo com o ônibus e a rua, sem a arquitetura/ambientação completa da rodoviária original. Portanto a apresentação da CGI e o funcionamento/desempenho do adapter foram validados, mas a paridade gráfica do terminal não foi declarada concluída. Essa geometria pertence ao mundo regional e não foi substituída por cenografia inventada neste adapter.

Fixture reproduzível: `tests/measure/arrival_measure.ps1 -Cgi` e `tests/measure/arrival_measure.ps1 -Label arrival-tour-fixed`. JSONs contêm todas as amostras, métricas e resultados físicos. Novas execuções devem usar outro identificador para preservar estas evidências.
