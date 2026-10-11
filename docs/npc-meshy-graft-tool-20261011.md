# Reprodução do transplante das mãos do Dante — 11/10/2026

A ferramenta `tools/meshy_graft_dante_hands.py` reproduz o `suit_m` com mãos e formas de grip autoradas do Dante. O resultado instalado corresponde ao V11. A sessão principal revisou mãos, mangas e encaixe com M4/SMG, frente/lado/repouso, e corrigiu a escala/posição da arma no runtime. A aprovação é limitada a esses cenários; testes finais e comparação de performance pertencem ao relatório `npc-meshy-maos-dante-20261011.md`. Este documento descreve somente a geração e a verificação offline.

## Entrada preservada e comando

Use a cópia anterior ao transplante. O arquivo de produção final já tem duas superfícies/morphs e é recusado corretamente pelo gerador.

```powershell
python tools/meshy_graft_dante_hands.py evidence/npc-meshy/hands-review-20261011/suit_m_before.glb evidence/npc-meshy/hands-review-20261011/suit_m_reproduced.glb --donor assets/dante.glb --report evidence/npc-meshy/hands-review-20261011/suit_m_reproduced.json
```

As saídas precisam ser novas. A ferramenta recusa destino igual às entradas, destino existente, `--report` igual a entrada/saída ou existente, corpo com morphs/superfícies adicionais e marcador de transplante anterior. Não executa Godot e não usa rede, créditos ou downloads. Usa Python, NumPy, Pillow e utilitários já existentes de leitura GLB/transformações; não depende das experiências descartadas de curva de dedos.

| Arquivo | SHA256 |
|---|---|
| `suit_m_before.glb` | `2E1FB4457FE272E49E3D6B5D8693BB0605B21B116DA67BBD9B0E44FAB2D00E73` |
| V11 / produção instalada | `9615807B1BEA25C0DD4E6DA7DA5C46CD9D61DAD5FACB994DCF8074152F1CBFFF` |

Uma geração a partir da cópia preservada produziu GLB byte a byte idêntico ao V11 e ao arquivo instalado pela sessão principal.

## Geometria e articulação

O corpo é recortado somente perto das mãos: envelope de raio até 220 mm, axial acima de −40 mm e radial menor que 160 mm, em altura normalizada de 1,76 m. Triângulos que cruzam o plano de −40 mm são cortados geometricamente com interpolação de posição, normal e UV. Apagar essas faces inteiras havia aberto a manga até 199 mm antes do punho. Fora do envelope, as faces originais permanecem preservadas.

A borda real do recorte liga-se a um cuff de paletó, faixa branca e tampa anular. A borda/cuff usa `ForeArm`, sem peso `Hand` na superfície corporal. A ponte de pele parte do anel proximal de −40 mm em `ForeArm`, passa por um anel intermediário 50/50 `ForeArm`/`Hand` e termina na borda REAL da mão em `Hand`. Os dedos transplantados ficam rígidos em `Hand`; nenhum deformador artificial foi aplicado às falanges.

O Dante tinha geometria de camisa com peso parcial `Hand` até 16,94 mm além do osso do punho. O transplante recorta essa base no plano +20 mm, com interpolação de normais, UVs e deltas autorados. O recorte contínuo removeu os dentes que a seleção por faces e a tentativa de apenas pintar o tecido deixavam; não se retiram faces por cor nem sombras dos dedos.

A ponte regular antiga de raios 27/20 mm não cobria a seção real: a borda direita chegava a X −40,2/+36,3 mm e Z −37,3/+22,7 mm. O raio elíptico exigido chegava a 1,86 vezes o previsto, deixando até aproximadamente 17 mm descobertos. O V11 conecta as 80 arestas direitas e 86 esquerdas da borda real. Duplicar os vértices distais preserva posição/normal/pesos/todos os deltas exatamente, enquanto permite UV constante de pele na ponte; usar o UV da mão nesse trecho havia atravessado ilhas de tecido do atlas e criado faixas escuras. Essa duplicação não permite a costura abrir com o estado do morph.

As manchas antigas perto do gatilho persistiram com material de cor uniforme, mas desapareceram ao esconder a arma após resolver a pose: eram partes da arma menor atravessando a palma, não roupa nem buracos da mão. A sessão principal aplica a escala `WeaponRigPose.V1_TO_V2` ao equipamento dos corpos com perfil, incluindo pontos de contato e encaixe da coronha. Não houve alteração adicional da malha para mascarar esse atravessamento.

As mãos preservam `GripRight`/`GripLeft`, por uma transformação de similaridade. A escala é `1,03 × 0,95`, incluindo a escala do osso Hand aplicada pelo Actor. O ponto de palma é o ponto autorado `(0; 0,065; 0)` do Dante nessa escala, convertido para o quadro anatômico do NPC: aproximadamente `(0; 0,0636025; 0)` m.

O perfil `npc_hand_profile` fica nos extras do nó da malha, em ordem Right/Left. Inclui eixos de dedos/normal assinada, offset de palma e `weapon_frame` com três colunas. Essa base reproduz `Rx(−PI/2) × Ry(−PALM_ROLL) × inverse(DanteHandRest) × donor_frame`, com rolls Right 0,358 e Left −0,392. O runtime aplica a base cruzada da mão esquerda das armas longas. A textura das mãos recebe ajuste de cor offline, preservando detalhes; a ponte usa UV de pele validada no centro da palma.

## Custo e evidência

O resultado tem uma malha, duas superfícies, 24 ossos e 11.317 triângulos: 3.638 no corpo recortado, 364 no cuff novo e 7.315 nas mãos/ponte. São 4.033 vértices no corpo/cuff e 5.571 nas mãos/ponte. Os dedos continuam com a densidade do Dante. Não houve simplificação, troca de modelos externos ou certificação de performance nesta análise.

O shader usa culling. Foram verificados explicitamente produto da normal geométrica com a normal atribuída e ausência de degeneração: todas as 364 faces novas do cuff e 664 da ponte apontam para fora. A versão v5 tinha os tubos invertidos, mesmo com posições e pesos válidos; as capturas detectaram isso. Foram também verificados índices, contagens de acessores, morphs corporais zero e ausência de influência `Hand` no corpo. Os 80/86 pares de costura distal têm posição, normal, pesos agregados e todos os morphs exatamente iguais; todos os UVs da ponte são constantes por lado.

Evidência: `evidence/npc-meshy/hands-review-20261011/suit_m_dante_hands_v11_validation.json`. As capturas finais de produção ficam em `production-m4/` e `production-smg/`. As experiências rejeitadas permanecem separadas, e as ferramentas de restauração/curva descartadas estão em `offline-probes/`. A validação offline comprova reprodução e integridade dessas propriedades; aprovação visual e comparação de frame time pertencem às cenas renderizadas e cenários registrados pela sessão principal.
