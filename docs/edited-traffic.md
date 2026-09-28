# Trânsito após edição das ruas — 26/09/2026

O arquivo salvo tinha ruas cujo asfalto encostava, mas as linhas centrais já não se encontravam. O grafo aceitava somente cruzamentos geométricos precisos; surgiam fins de rua falsos, restringindo as rotas possíveis. Exemplos encontrados: Market Street / Quay Boulevard (~1 m), Medical Garden Lane / Warehouse Way (~1,27 m), Northbank Civic Avenue / Island Esplanade (~30 cm) e Northbank Neighborhood Street / Island Esplanade (~23 cm).

`WorldRoadJoins.resolve()` corrige essas pequenas diferenças ao reconstruir ruas editadas, antes de gerar tanto a superfície quanto o grafo. A ponta precisa estar dentro da meia largura da rua de destino, com limite de 3 m. Continuação entre extremidades usa um ponto estável; pistas paralelas lado a lado, caminhos estreitos e vias em alturas diferentes não são conectados. Sobreposição de linhas praticamente coincidentes usa tolerância de 10 cm. São duas passagens limitadas, somente na construção, sem novo processamento por frame.

O documento oficial não foi regravado: as correções são aplicadas à representação carregada do mapa. Ruas realmente separadas continuam separadas. A mudança não permite atravessar prédios/objetos nem garante circulação em qualquer curva arbitrária. É necessário iniciar nova execução para reconstruir as vias e as rotas.

## Validação

- `test_edited_road_joins.gd`: 16 verificações aprovadas, com casos sintéticos de segurança e seis junções do mapa salvo. O trecho que audita o mapa atual é diagnóstico dessa versão do documento, não um contrato que proíbe futuras alterações do usuário.
- `test_edited_traffic_drive.gd`: 8 verificações aprovadas na cena Main com carros físicos. Um sedan atravessou Market Street → Quay Boulevard e Medical Garden Lane → Warehouse Way, sem bloqueador ao final dos percursos. Execução sem tráfego ambiente para isolar a passagem física, simulação acelerada sem alterar o passo físico.
- `test_world_editor_roads.gd`: 19 verificações aprovadas, preservando caminhos de pedestres e reconstrução das vias.
- Hash do mapa preservado nos testes e medições: `1e39478c32ec7fcb1774330b6fb21d1becc0099023f809ac411f82cd5296aeb8`.

## Desempenho

Main renderizada com tráfego normal, câmera (110,95), tamanho 90, Godot 4.7.2 Mobile/Vulkan, RTX 4060 Laptop, 1280×720, limite 144 FPS. Mesma semente, clima, mapa e câmera; 8 s de aquecimento e 30 s medidos. Meta provisória 60 FPS; sinal de confirmação acima de 5% em p95/p99.

| Amostra | FPS | p50 ms | p95 ms | p99 ms | Máximo ms | >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Antes | 107,21 | 9,749 | 14,921 | 16,771 | 25,810 | 0 / 0 |
| Depois, primeira amostra | 99,08 | 9,753 | 15,121 | 30,772 | 73,665 | 22 / 1 |
| Confirmação equivalente | 109,80 | 9,538 | 13,164 | 14,523 | 23,609 | 0 / 0 |

Na primeira amostra posterior houve um grupo de travadas entre 18,38 e 19,82 s da janela medida. A amostra foi preservada; foi feita uma única confirmação equivalente para investigar intermitência. Não foi atribuída causa às travadas com base apenas no intervalo entre frames.

A confirmação não reproduziu as travadas e não apresentou regressão em p95/p99 contra a base. O comportamento funcional passou; a causa da oscilação permanece não isolada, portanto não se certifica estabilidade geral de FPS nem se atribui ganho causal à correção.

Evidências: `evidence/edited-traffic/{before,after,after-confirm}/performance.json`, com amostras brutas, aquecimento, configuração e hash. Capturas `world.png` nas mesmas pastas. Avisos de liberação de texturas no encerramento também ocorreram antes da correção.
