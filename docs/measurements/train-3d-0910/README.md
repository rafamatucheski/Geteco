# Trem 3D — primeira etapa, 10/09/2026

Implementação na ferrovia atual do porto. A extensão da rota às montanhas e ao
próximo mapa permanece como próxima etapa; o percurso atual não foi alterado.

## Comportamento

- Locomotiva e seis vagões de geometria 3D: contêineres, tanque, carga mineral e
  madeira. Cada peça segue sua própria tangente do trilho. A câmera ortográfica
  permanece fixa, preservando a perspectiva e a iluminação ao virar.
- Sete SubViewports de 256 × 256, atualizados quando a orientação muda e a peça
  está perto da câmera. Peças subterrâneas não atualizam a imagem.
- Motor diesel, emendas dos trilhos em cada vagão, ressonância do viaduto,
  rangido nas curvas e buzina ao sair do túnel. Loops PCM são compartilhados
  dentro da composição e usam o barramento SFX quando disponível. As rodas
  silenciam quando o trem para; peças enterradas silenciam separadamente.
- Abertura suave e localizada no viaduto e nos vagões sobre o jogador.
  O carro dirigido recebe uma abertura maior. Interiores e trechos ao nível
  do chão não acionam o efeito. Pilares e colisões permanecem físicos.
- A aparência do tabuleiro recebeu borda e corrimão para reforçar sua espessura.

## Validação

Godot 4.7.2. Capturas da cena HarborGame com Vulkan / Forward+ na RTX 4060.

- `tests/test_harbor_train_3d.gd`: `HARBOR_TRAIN_3D failures=0`.
  Verifica articulação e orientação da geometria, posições dos emissores de
  áudio, transparência para pedestre/carro, exclusão de interiores e rampas,
  entrada individual das peças no túnel, buzina e parada. Verifica também
  amostras PCM não silenciosas, sem saturação e reutilização dos recursos.
- `tests/rail_crossing_escape_audit.gd`: `failures=0`.
- `tools/check_references.py`: nenhuma referência quebrada nova na conferência final.
- Revisão visual: composição completa, curva, pedestre sob o trem, carro sob o
  trem e entrada no túnel. Capturas feitas com a simulação congelada e poses
  controladas; não constituem teste de condução ou medição de desempenho.

A suíte geral não está toda verde:

- `test_harbor_safety.gd`: duas falhas em "Road crossing requires explicit rail
  elevation clearance". Reproduzidas também numa cópia temporária que usava
  HarborRailLine e HarborTrain do HEAD anterior, com o restante da pasta atual.
  Ambas as execuções informaram seis cruzamentos separados por altura,
  nenhuma passagem de nível e zero erros no relatório RoadSafety.
- `rail_level_crossing_runtime_test.gd`: o cenário legado observou conflito
  com `BoroughTraffic_11` (um veículo; antecedência da cancela de 4,533 s).
  Esse teste observa o trem legado, cuja lógica de movimento não foi alterada.
  O conflito de tráfego legado não foi corrigido nesta etapa.
- O ambiente compartilhado também registrou mensagens de InputMap na carga,
  transformações de YellowCabModel fora da árvore e avisos de objetos no
  encerramento. Não se afirma uma carga global sem erros.

## Evidências

- [Composição completa](train-overview.png)
- [Articulação na curva](train-curve.png)
- [Pedestre visível sob o trem](train-underpass-person.png)
- [Carro visível sob o trem](train-underpass-car.png)
- [Entrada no túnel](train-tunnel.png)

Reprodução das capturas: executar `tests/capture_harbor_train_3d.gd` com
renderização real. O script salva as imagens nesta pasta.
