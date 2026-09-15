# Materiais e decoração da serra

O fundo alpino, os pátios dos abrigos e o piso da vila usam superfícies
granuladas em vez de preenchimentos lisos: neve, neve compactada, cascalho,
pedra, terra e solo florestal. O acesso regional usa o mesmo asfalto preto da
rodovia, com grão discreto e suas extremidades desenhadas abaixo da pista;
a estrada principal preserva suas cores e sinalização com detalhe superficial.
O mirante recebeu piso de pedra. Pisos e neve dos telhados da vila usam
texturas com normais e projeção triplanar em materiais 3D.

`MountainGroundMaterials.gd` gera sete pares de texturas de 256 × 256 px,
incluindo normais e mipmaps, com sementes fixas. Os recursos ficam em cache
e são compartilhados. O shader 2D ancora as texturas ao mundo, sem movimento
relativo à câmera. A geração isolada dos sete pares levou cerca de 1,7 s
na máquina de desenvolvimento; não ocorre a cada quadro.

`MountainWinterDressing.gd` distribui grupos de pinheiros, rochas com neve,
troncos cortados e galhos nas três paradas, na vila e em três trechos da
estrada superior. Os modelos têm ramos assimétricos, anéis nos cortes da
madeira, manchas baixas de neve e agulhas no chão. São meshes 3D reais,
agrupados em seis viewports estáticos; a vila reutiliza seu viewport.

As silhuetas projetadas dos objetos sólidos geram geodata. A distribuição
rejeita sobreposições com construções, bancos, moradores, vagas, estrada,
ferrovia e corredores de circulação. Galhos e agulhas são detalhes baixos
transitáveis. Não foram alteradas rotas ou rotinas dos veículos/passageiros.

## Verificação

- `test_mountain_geodata.gd -- --production --dressing`: cenário completo,
  meshes e contratos dos quatro tipos, 15 rotas de pedestres, acesso/vaga do
  carro e varredura do casco de 120 × 34 px no acesso real do ônibus.
- `test_mountain_bench_rest.gd`: ciclo físico, reserva, animação e liberação.
- `test_mountain_transit_village.gd`: desembarque, compras, bancos e chalés.
- `capture_mountain_winter_dressing.gd`: quatro vistas em Forward+, carregando
  Harbor e a região contínua. Arquivos em
  `D:/geteco/artifacts/neve-detalhada-0910/`.

Resultado final: 83 elementos instalados (20 pinheiros, 24 rochas, 2 troncos
e 37 grupos de galhos), 15 rotas livres, nenhuma obstrução do acesso SUV
ou do casco do ônibus. O teste da vila completou sete desembarques, três
compras e sete descansos, com todos os passageiros nos chalés. O teste dos
bancos também passou. A captura Forward+ terminou sem erros e a auditoria
final de geodata encerrou sem recursos pendentes. Logs:
`D:/geteco/artifacts/rodoviaria-3d-0910/mountain-dressing-*-final.log`.
