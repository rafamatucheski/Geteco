# Geodata exterior

`ProceduralBuilding.get_solid_rects()` define os volumes locais que geram
`BuildingSolid`, com camada física 1 e grupos `building_geodata` e
`building_blocker`. As subclasses mantêm os recortes próprios: pátio em L,
entrada de serviço do hospital e fachadas. Parques ficam abertos; arcadas
autorizadas mantêm passagem no térreo, mas não liberam o volume fechado.
O porto sul registra seus cinco prédios 3D no mesmo contrato.

`WorldPerimeter.gd`, integrado em `HarborPreview` e herdado por `HarborGame`,
une os terrenos e acessos existentes. O contorno resultante gera muro físico
e visual, enquanto os polígonos externos recebem o oceano animado existente.
A união preserva os canais internos e remove as emendas entre regiões.
As curvas são simplificadas com erro máximo de 0,5 pixel: 288 segmentos físicos,
sem reconstrução por frame. O terreno da montanha corresponde à extensão real
da floresta, incluindo sua parte sul anteriormente sobreposta pela água sólida.

A cada 0,2 segundo, somente o jogador ou seu veículo controlado é verificado.
Posições fora do terreno ou dentro de geodata de prédio retornam à última
posição válida, zerando a velocidade; sem histórico, usa-se o spawn de
Breakwater. Interiores mantêm suas coordenadas e colisões independentes.
Ao ampliar o mapa, acrescente o terreno/acesso ao contrato de contornos;
não abra apenas um buraco na colisão da água.

## Validação em 12/09/2026

- `tests/test_world_geodata.gd`: aprovado; 288 bordas, quatro direções de
  movimento rápido, recuperação, prédios, parques, arcada, pátio em L e
  ausência de água sólida sobre a floresta sul.
- `tests/test_world_geodata_integration.gd`: aprovado; 59 volumes de prédios
  com os corpos reais de Player/PlayerCar, além de conexões da ilha, montanha
  e passarela do porto sul. Execução renderizada anterior também conferiu
  visualmente as costas oeste, norte e sudeste.
- `tests/test_harbor_entrances.gd`: aprovado; nove portas, sete vínculos com
  interiores e embarque/desembarque. O teste foi atualizado para as ações
  atuais `move_*` e para aguardar a animação real de embarque.

Evidências: `D:/geteco/artifacts/world-geodata/`, incluindo logs finais e
`west_coast.png`, `north_coast.png`, `south_port.png`.

Performance **não aprovada/não comparada**. Alvo provisório: 60 FPS / 16,67 ms;
regressão superior a 5% em p95/p99 exige investigação. A tentativa inicial na
HarborGame renderizada (Godot 4.7.2 Mobile, RTX 4060 Laptop, 1920×1080,
VSync e limitador desativados no processo) encontrou erros de compilação em
arquivos sob edição concorrente. A tentativa seguinte também continha erro
de compilação e usava ações antigas de movimento: percorreu zero pixels,
portanto os 7,7 FPS registrados não constituem benchmark de condução válido.
Outras execuções Godot estavam abertas; não foram encerradas. É necessário
comparativo renderizado antes/depois em ambiente estável para certificar FPS.
