# Acesso físico e profundidade dos tubos urbanos

A malha existente passa a determinar os sólidos por `interior_solid_id` e `InteriorSolidProjection`: vidro e base laterais, extremidade fechada, corrimãos da rampa, bancos, totem, leitor e bilheteria. O acesso público fica na rampa; o portão junto ao ônibus abre quando ele está parado com as portas abertas. O fechamento consulta o corpo completo dos ocupantes.

`UrbanStationActorPresentation` reutiliza o rig original de jogador, passageiros e visitantes no viewport da estação. Mantém o tamanho físico externo, acompanha a altura da rampa, projeta a origem da arma e restaura o rig ao sair ou descarregar. Posições antigas que intersectem móveis ou paredes retornam ao ponto livre de acesso. Estações vazias não renderizam continuamente.

O embarque (inclusive E) exige a abertura correta. O desembarque procura espaço dentro da plataforma e permanece bloqueado quando ela está ocupada, sem devolver o jogador diretamente à calçada. A fila ocupa quatro posições a partir do fundo, embarca quem está mais perto da abertura e deixa excedentes aguardando fora. Os pontos de espera não se sobrepõem.

## Evidências

- `tests/test_tube_access.gd`: jogador e NPC real, quatro orientações, varreduras contra paredes/cantos/corrimãos/portão e bancos; caminhos pela rampa, circulação, saída, recuperação, dois atores, fechamento seguro e descarregamento. Aprovado headless e renderizado. O teste renderizado usa oclusão com controle positivo, além de capturas da geometria real. Logs: `D:/geteco/artifacts/tube-contract-final.log` e `tube-gate-final.log`; imagens em `D:/geteco/artifacts/tube-access/depth/`.
- `tests/test_urban_station_3d.gd`: projeção, geometria, orientações e afastamento de sinais. Aprovado; `D:/geteco/artifacts/tube-geometry-final.log`.
- `tests/test_tube_boarding_flow.gd`: HarborGame, ônibus real parado, embarque por E, recusa pelos lados, plataforma ocupada, desembarque, caminhada pela rampa, reentrada e NPC entrando/saindo. Aprovado; `D:/geteco/artifacts/tube-boarding-final.log`.
- `tests/test_urban_transit.gd`, versão final: alcançou as seis estações, com 15 embarques e 5 desembarques reais. Falhou em completar uma volta e recolher toda a frota à noite; ônibus permaneceram bloqueados em cruzamentos e o teste terminou por timeout. Log: `D:/geteco/artifacts/tube-service-final.log`. O circuito completo permanece reprovado; esses resultados não certificam o trânsito urbano.

## Performance: pendente

Meta: 60 FPS / 16,67 ms; aumentos acima de 5% em p95/p99 exigem confirmação. Baseline renderizada de 30 s em HarborGame, 1280×720, Mobile, RTX 4060 Laptop, limite de 60: 50,72 FPS, p50 17,83 ms, p95 28,97 ms, p99 36,76 ms, máximo 305,41 ms; 29 quadros acima de 33,3 ms e 4 acima de 66,7 ms. A base já não cumpria a meta.

O comparativo posterior foi interrompido quando outras execuções renderizadas e benchmarks passaram a concorrer por CPU/GPU. Também houve alterações paralelas da cena durante a tarefa (o inventário de iluminação mudou). Não há pós comparável nem aprovação de performance. `tests/measure_tube_access.gd` conserva o cenário para a medição; baseline em `D:/geteco/artifacts/tube-access/before/`.
