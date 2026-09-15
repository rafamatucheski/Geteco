# Soqueiras duplas do Dante Meshy — 14/09/2026

O Dante Meshy equipa uma soqueira em cada mão. A peça esquerda acompanha a palma, é reutilizada ao reequipar e desaparece imediatamente ao trocar de arma ou guardar o armamento. O alinhamento das duas peças acompanha a fileira dos dedos.

`MeshyKnucklePose.gd` define quatro golpes alternados: jab esquerdo, direto direito, gancho esquerdo e golpe ascendente direito. A mão oposta permanece em guarda. Dano, alcance e cadência de gameplay foram preservados.

O GLB derivado contém os morphs adicionais `FistRight` e `FistLeft`, gerados por `tools/prepare_meshy_dante.py`. Eles fecham os dedos e recolhem as pontas na palma; os morphs anteriores de empunhadura continuam disponíveis para as demais armas. O GLB fonte permanece preservado.

## Validação

- `test_meshy_knuckles.gd`: quatro variantes, 360 quadros, zero falhas; inclui caminhada, corrida, alinhamento das peças, alcance das palmas, morphs, troca de arma e reutilização da peça esquerda.
- `check_meshy_clearance.py`: 360 poses sem invasão das mangas no núcleo convexo do tronco acima da tolerância de 3 mm. Essa medição não certifica colisão entre todas as superfícies do personagem.
- Testes de poses de combate e restrições da garagem: zero falhas. Revisão das poses Meshy das 15 armas também passou.
- Revisão visual: quatro golpes e aproximações das mãos em três ângulos. Vídeo em `artifacts/meshy-knuckles-0914/soqueiras-duplas.mp4`.

A importação do asset funciona; a importação global do editor ainda aponta erros preexistentes em `LandmarksV2.tscn` e `CarjackedDriver.tscn`.

## Desempenho

Comparação com `measure_meshy_knuckles.gd`, cenário real HarborGame, downtown, 1280×720, Mobile, RTX 4060 Laptop, sem limite de FPS/VSync; amostra de 30 segundos após aquecimento, executada sem captura de vídeo simultânea. Relatórios em `artifacts/meshy-knuckles-0914/before` e `after`.

Baseline: 54,72 FPS; p95 24,786 ms; p99 28,066 ms. A meta de 60 FPS já não era atendida antes da alteração.

Depois: 55,34 FPS; p95 25,208 ms (+1,70%); p99 28,674 ms (+2,17%). A comparação não apresentou regressão acima do limite de 5% adotado para p95/p99. O maior quadro isolado passou de 77,252 para 97,028 ms, com dois quadros acima de 66 ms em ambas as amostras. São amostras locais de 30 segundos; não constituem certificação de 60 FPS nem eliminam os picos preexistentes.
