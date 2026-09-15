# Entradas da rodovia e do pátio

As duas conexões do circuito regional e a entrada do pátio do abrigo têm
bocas asfaltadas com bordas curvas. `MountainRoadJunctions` deriva essas
superfícies das curvas reais de circulação, com alargamento suave perto da
rodovia. O asfalto continua preto e as faixas centrais permanecem contínuas.

As linhas brancas laterais são recortadas nos polígonos de abertura. Neve e
acostamento dão lugar ao asfalto nesses trechos. As defensas usam a mesma
abertura expandida em 9 px, e seus segmentos físicos seguem cada segmento
desenhado, sem cordas longas que atravessem as curvas.

Na entrada do ônibus, a defensa existente foi prolongada até um retorno
curvo fora da pista, com poste terminal e refletor perto de `(6954, -1617)`.
O prolongamento acompanha o acostamento, abre 12 px para fora e usa um raio
de 16 px na ponta. Desenho, segmentos físicos e poste compartilham o mesmo
traçado. A captura `06_terminal_defensa.png` mostra o acabamento final.

O pátio acompanha a borda da rodovia; a neve compactada só começa no offset
140 da curva de acesso, chegando à opacidade total no offset 180. O mirante
foi recuado 8 px ao norte, com piso, desenho e guarda-corpo físico juntos,
para liberar também as bordas da faixa de 62 px. Rotas dos veículos intactas.

Validação: `test_mountain_geodata.gd -- --production --dressing --mouths`
passou em 34.384 movimentos de carros/ônibus, cobrindo a largura útil das
três bocas nos dois sentidos. Nenhum contato, nenhuma defensa sobre as
aberturas. Também passaram 15 rotas de pedestres, 83 elementos decorativos,
vagas e todo o acesso regional. Registro:
`D:/geteco/artifacts/rodoviaria-3d-0910/mountain-access-mouths-final.log`.

Capturas Forward+: `D:/geteco/artifacts/neve-detalhada-0910/02_abrigo_detalhado.png`
e `05_juncoes.png`, geradas por `capture_mountain_winter_dressing.gd`.

## Validação do serviço em movimento

`test_harbor_mountain_coach.gd` sem `--geometry-only` executa o mesmo ônibus
de Harbor à serra e de volta, com tráfego e semáforos ativos. Confere a
identidade do veículo, os desembarques, as compras de roupas de inverno,
descansos e o início automático da viagem seguinte após a parada em Harbor.
A aceleração da fixture mantém subpassos físicos de 1/60 s, verificados
durante a execução. A fixture não reposiciona o veículo nem limpa tráfego.

A validação prolongada expôs um conflito entre a reserva da junção e a
parada da faixa de pedestres: um veículo já comprometido podia receber
ordem de parar no vermelho da própria junção, impedindo a liberação da
reserva. `JunctionTrafficController.can_clear_crossing` agora identifica
o proprietário comprometido da mesma junção e veículos que já estão
fisicamente saindo dela pela pista canônica. Para estes últimos, exige
centro da junção atrás, faixa adiante, direção de afastamento e casco ainda
no envelope de saída, inclusive quando a reserva já foi liberada.
`RoadCrossingArea2D` permite terminar a travessia, mantendo o veto quando há pedestre
presente ou com autorização para atravessar. A regressão
`test_committed_junction_crossing.gd` cobre o movimento real, a liberação
da reserva e os casos que devem continuar parando (43 verificações).

O registro de pedestres da faixa inclui os passeios para solicitar o sinal.
O veto aos veículos agora usa `has_pedestrian_on_roadway`: colisões reais
dos pedestres contra a faixa sobre o asfalto, com margem de 1 px e
transformações completas. Pessoas esperando no passeio continuam gerando
demanda; pedestres sobre a pista ou com fase autorizada continuam parando
os veículos. Isso evita prender a fila de saída da Union Avenue apenas
porque moradores aguardam na calçada.

A varredura regional aplica também `HarborGatewayWorks.update_actor_layer`
ao corpo de teste em cada pose e usa as exceções de colisão publicadas por
esse contrato. Assim, as defensas da passagem inferior não são confundidas
com obstáculos no tabuleiro superior; obstáculos do mesmo piso continuam
incluídos na consulta. Verificação separada:
`D:/geteco/artifacts/rodoviaria-3d-0910/regional-height-aware-geodata.log`.

Resultado final com todas as correções carregadas: execução integral
concluída com código 0 e `failures=0`. O mesmo ônibus percorreu
38.885,98 px, completou Harbor → vila → Harbor, cumpriu a parada e iniciou
automaticamente outra saída (`round_trips=1`, `departures=3`). Manifesto:
5 de 5 desembarques, 3 viajantes já agasalhados, 2 compras de roupas e
5 descansos concluídos. Maior deslocamento na transição entre pistas:
0,00109 px. Registro definitivo:
`D:/geteco/artifacts/rodoviaria-3d-0910/regional-live-roundtrip-final.log`.

A fila que travava a Union também passou em reprodução com os veículos
reais e toda a população ativa (`test_harbor_junction_exit_queue.gd`).
