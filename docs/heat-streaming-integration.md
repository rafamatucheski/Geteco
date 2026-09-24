# Fontes de calor e detalhes da montanha

Implementação de 21/09/2026, **não validada**: por instrução do usuário, nenhum Godot, teste, captura ou benchmark foi executado nesta etapa.

As fontes originais de `HeatPresentation` continuam sendo o padrão. A integração de `mountain_detail` omite suas reconstruções alternativas de fogueira e braseiro; não acrescenta outra luz ou outro conjunto de corpos no mesmo lugar.

O protocolo `native_heat_source` permite reaproveitar uma fonte original pertencente ao mapa: grupo `native_heat_source`, metadado opcional de mesmo nome contendo o ID de `OriginalHeatSources`, posição coincidente com a fonte original. Marcadores antigos sem ID continuam reconhecidos pela posição. `native_heat_has_solids=true` declara que o provider já possui os sólidos necessários; `native_heat_has_effects=true` declara efeitos completos; `native_heat_flame_offset` ajusta a posição das chamas quando faltam. Não marque um simples Marker3D como dono de sólidos.

`HeatPresentation` nunca reparenta nem apaga o provider. Seu wrapper próprio acrescenta somente o que falta. Com provider presente, não recria o braseiro/toras; sem provider, utiliza a geometria original existente. O ID de instância permite detectar chegada, descarregamento e substituição durante streaming, inclusive quando uma fonte fallback já estava ativa. A troca desativa imediatamente os sólidos do wrapper antigo antes de instalar o novo.

A reconciliação visual ocorre no intervalo existente de 0,25 s. `ColdSurvival.prepare_collision_at()` força a reconciliação local antes de admitir jogador ou carro e rejeita a admissão no mesmo frame físico em que novos sólidos foram instalados. O marcador antigo do lago não declara corpos e portanto recebe o sólido da fogueira, sem repetir as pedras ou toras do cenário.

Pendentes: parser, aproximação e descarregamento das fontes, fallback→provider→fallback, ausência de duplicações, colisões de jogador/carro e comparação renderizada de performance. O documento descreve implementação, não aprovação desses comportamentos.
