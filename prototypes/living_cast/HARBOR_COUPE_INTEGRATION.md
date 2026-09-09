# Cupê no HarborPreview

O `PlayerCar` de `district/harbor_preview/HarborPreview.tscn` agora usa
`HarborCoupe.gd`, que herda PlayerCar sem alterar o controlador global.
O botão **Dirigir** seleciona esse carro; E conserva entrada/saída e garagem.

## Escala, movimento e visual

- Comprimento nominal 74 px, collider 72 × 31 px, bumper 74 × 33 px.
- Mantidos os parâmetros prévios do PlayerCar e o fator local 0,75 do Harbor:
  máximo 450 px/s, aceleração 900 px/s². Não são km/h reais.
- Modelo 3D renderizado em SubViewport 192 × 192, câmera inclinada fixa no
  mundo: laterais mudam conforme o carro vira; quatro rodas giram e as duas
  dianteiras esterçam. Atualização limitada a 30 Hz em movimento/próximo.
- Parado, imagem reaproveitada; dano/pintura pedem render único. Física e
  interação continuam 2D. Não aplicar a todo o trânsito sem medir escala.
- L mantém o liga/desliga original; K alterna alcance baixo/alto. Fachos são
  PointLight2D no mundo, não SpotLight3D presos dentro do SubViewport.
- Freio ilumina lanternas traseiras. Colisão 2D aciona deformação localizada
  do modelo e os efeitos/sons/detritos já existentes de PlayerCar.
- Portas ainda usam a animação 2D existente, não portas articuladas do modelo.
  O desprendimento 3D do laboratório não foi transplantado para o mundo 2D:
  aqui ficam os detritos do controlador existente. Não é simulação estrutural.

## Paint & Spray

Entre dirigindo na garagem Westgate usando a entrada existente, pare na
faixa central e escolha uma das oito cores no painel. O serviço leva 0,8 s,
mostra partículas de spray e restaura pintura/danos/faróis. Gratuito nesta
versão de avaliação. Não reescreve NPCs ou as cenas internas.

Somente carro parado, conduzido pelo jogador e dentro da faixa pode usar o
serviço; controles retornam ao término. Materiais de vidro/metal/pneus não
são tingidos. Cor preservada durante a sessão, ainda sem persistência nova
em save. O contrato `repair_and_repaint(Color)` também serve a GarageTrigger.

## Verificação

- `test_harbor_coupe.gd`: entrada/saída, movimento, rodas, escala, colisão
  física real com barreira 2D, deformação, farol unilateral, seleção de cor,
  limites de acesso, reparação e retorno de controles.
- `test_harbor_interiors.gd`: contratos gerais de interiores.
- `test_harbor_interiors_gameplay.gd`: trajeto real pela garagem e demais
  interiores. Falhas devem ser relatadas, não ocultadas.
- `test_harbor_coupe_baseline.gd`: mesmo teste longo, substituindo apenas o
  carro pelo PlayerCar original em memória, sem reverter arquivos.
- `capture_harbor_coupe.gd`: capturas no distrito/garagem e amostra A/B do
  custo de render, com câmera parada. Não substitui benchmark de direção e
  pior caso; não executar com outras suítes concorrentes para comparar FPS.

Ver `FROTA_PLANEJADA.md` para 56 propostas de carroceria, cores e contratos.
