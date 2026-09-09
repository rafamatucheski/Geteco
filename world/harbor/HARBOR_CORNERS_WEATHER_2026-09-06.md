# Quinas e indicador de clima — integração isolada

Sem commits. Não foram editados HUD, diálogos, CGI, Player, tráfego, relógio,
WeatherManager, save/settings ou decoração de terceiros.

## Produção

- HarborRoadNetwork.gd: sete encontros ortogonais de duas ruas recebem curva
  exterior e concordância interior em todas as camadas de material. Calçada
  mantém a margem de 42px; contorno usa os mesmos polígonos da pintura.
  IDs, pontos dos providers, faixas, conexões e máscaras físicas permanecem
  intactos. Cobra, rodovia Mapa2, junções T/X e passagens elevadas não recebem
  essa substituição. Não é uma reautoria de todas as curvas da cidade.
- HarborWeatherReadout.gd: ícones vetoriais/horário 24h, leitura a 4Hz do
  WeatherManager existente; não altera hora, clima, chuva ou som. É indicador,
  não um segundo sistema climático. Sem processamento de input.
- HarborGame.tscn: instancia esse adaptador. Ele acrescenta sua própria linha
  ao HUD em RootMargin/TopRightPanel, abaixo das estrelas, sem editar HUD.tscn.
  Oculto na abertura/pausa. Se a equipe de UI renomear esse container, ajustar
  o adaptador junto; na ausência do container, o indicador permanece oculto.

## Validação

9 testes distintos aprovados:
test_harbor_rounded_corners (7 cantos, 161 amostras),
test_harbor_weather_readout (estados, relógio, ausência de mutação/input,
abertura/pausa e layout em 1280x720/1920x1080), test_harbor_road_edges,
test_harbor_road_contract, test_harbor_district, test_harbor_alleys,
test_harbor_landscape, test_harbor_safety, test_harbor_campaign_flow.

Capturas com renderização real conferidas:
D:/geteco/harbor-rounded-corner.png
D:/geteco/harbor-weather-1280.png
D:/geteco/harbor-weather-1920.png

Os testes renderizados no sandbox reportam a restrição já conhecida de escrita
no diretório de saves e de certificados Windows; estes testes não gravam slots.
Sem erros de script/parsing/asserção. Nenhum benchmark de FPS nesta rodada.
Teste do distrito inclui 2391 amostras viárias, 46 acessos e saída dirigindo
da garagem; não se declara perseguição policial completa validada aqui.
