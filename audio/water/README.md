# Água em movimento

`flow.ogg` é um loop estéreo original de 26 segundos, gerado por
`tools/build_water_audio.py`: correnteza filtrada, variação lenta de intensidade
e pequenos borbulhos. A junção usa sobreposição de dois segundos. Não há downloads
ou síntese de PCM durante a partida.

O mar continua usando as gravações de `audio/living_city`, cujos créditos estão
no README e no SOURCES.json dessa pasta. O lago usa a segunda gravação em volume
mais baixo; riacho e fonte usam `flow.ogg`, com altura diferente na fonte.

`audio/WaterSoundscape.gd` mistura as fontes por distância ao contorno da água,
com fade, redução durante diálogos e silêncio em interiores. A camada é integrada
ao ouvinte já usado pelo HarborSoundscape, inclusive dentro de veículos.
Fontes distantes param de decodificar; regiões ocultas ou suspensas não ativam água.

O visual fica em `world/shared/nature/WaterPresentation.gd` e
`WaterSurface.gdshader`. Mar, lago, correnteza, espuma e fonte compartilham materiais
por perfil. Somente a água recebe o shader: navio, pontes, ilhas, pedras e terreno
mantêm os próprios materiais. O Waterfront deixou de redesenhar navio e guindastes
a cada 0,1 segundo para mover as ondas.

Validação: `--script res://tests/test_water_presentation.gd`; acrescente
`-- --capture` com renderização real para salvar imagens. Evidências em
`docs/measurements/water-0910`.
