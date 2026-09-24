# Maciota — candidato Meshy

Primeira geração solicitada em 22/09/2026. Modelo para avaliação, ainda sem substituir o NPC em gameplay.

## Referências do projeto

- `characters/JagerNPC.gd`: identidade, traje, acessórios e proporções do personagem atual.
- `geteco_v2/assets/maciota/MaciotaModel.gd`: extração visual correspondente na versão 3D.
- `audio/mission_voices/maciota-human-recording-brief.md`: adulto, dono de oficina, carismático, confiante e acolhedor.

Traje roxo #6c3483, lapelas pretas, pele morena #a87858, rosto fino e cavanhaque, fedora roxo com faixa de onça, óculos escuros de armação dourada, corrente de ouro, sapatos roxos e bengala dourada com joia púrpura. Proporções humanas naturais.

## Geração

Arquivo principal: `maciota-animated.glb`, com textura PBR 2K, esqueleto e três animações no mesmo arquivo. Pode ser importado pelo Godot. `MaciotaCane.tscn` preserva a bengala original como acessório separado, com origem na empunhadura; ainda não está presa à mão do novo rig.

Animações Meshy: `Idle` (0), `Stylish_Walk_inplace` (675) e `Talk_with_Left_Hand_on_Hip` (309).

Requisições e identificadores de tarefas estão persistidos ao lado do modelo. Não reenviar POST ao retomar uma tarefa existente.

| Etapa | Créditos |
|---|---:|
| Primeira geometria, descartada visualmente por omitir acessórios | 20 |
| Segunda geometria, com acessórios | 20 |
| Textura da segunda geometria | 10 |
| Rig da pose fechada, recusado na estimativa de pose | 0 |
| Conversão da imagem texturizada para pose A | 30 |
| Rig da pose A | 5 |
| Três animações | 9 |
| Total das solicitações desta tarefa | 94 |

A consulta de saldo após a exportação retornou 1.336 créditos, acima dos 1.250 vistos após a conversão para pose A. Não atribuir essa variação às gerações: a causa não foi investigada. O custo acima usa as etapas solicitadas, não a diferença entre saldos.

A credencial fica somente em `.secrets/meshy.env`, ignorada pelo Git e pelo Godot. Nunca copiar a chave para scripts, manifests ou documentação.

## Validação e limites

GLB carregado e renderizado em projeto temporário isolado no Godot 4.7.2, OpenGL Compatibility, RTX 4060 Laptop. Uma malha, 15.524 triângulos, 24 ossos, altura deformada de 1,85 m. Três clips enumerados, aplicados e capturados em `review-animated-*.png`; dados em `review-animated.json`. A medição usa a malha deformada pelo esqueleto: a AABB estática importada do rig dá uma escala enganosa. Não aplicar escala 100 ao modelo.

O resultado é um candidato estilizado, mais caricato que as proporções naturais solicitadas. O chapéu ficou muito escuro, os sapatos marrons e o tecido mais brilhante que o padrão original. A pose A removeu a bengala; o acessório separado usa a geometria e paleta originais do projeto. Esses desvios não foram corrigidos gastando novas gerações.

As animações estão no arquivo, mas não estão ligadas à máquina de estados do NPC. Não houve substituição do personagem ativo nem validação de FPS em gameplay. A integração futura deve preservar invulnerabilidade, gestos, embarque, colisões e restrições de armas da garagem, com os testes obrigatórios e medição de performance do projeto. Os clips de conversa e caminhada ainda exigem ajuste da mão/bengala, contato com o chão e transições no jogo; capturas isoladas não certificam esses comportamentos.
