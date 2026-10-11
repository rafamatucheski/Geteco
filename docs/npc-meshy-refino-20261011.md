# Refino dos corpos Meshy — 11/10/2026

Entrega parcial das prioridades 1 e 2. Corrigidos pesos do terno masculino, alcance por braço e alinhamento dos membros. Nenhuma família nova foi migrada; nenhum crédito Meshy foi gasto e nenhum arquivo foi baixado.

## Mudanças de produção

- `assets/civilians/meshy/police/suit_m.glb`: remove influência de `ForeArm` no topo do paletó, recupera influência de `Hand` nos dedos e curva somente vértices ainda não curvados. Colapsa `Bone_002`/`Bone_004`, preservando os auxiliares dos pés e os pivôs dos ossos mantidos. Continua com **3.912 vértices, 4.146 triângulos e textura 1024**; passa de **26 para 24 ossos**. Geometria do corpo/roupa e textura preservadas; somente as posições/normais dos novos dedos curvados mudam.
- `assets/CivilianModel.gd`: medidas de cada braço, sem somar os 6 cm da palma procedural à distância entre cotovelo e osso `Hand` do GLB. O kit conserva sua extensão original.
- `assets/civilians/MeshyBodyRig.gd`: alinha a origem do braço à junta da IK mesmo quando a coluna distribui a inclinação por três ossos. Calcula origens em cache, evitando consultar duas vezes o esqueleto sujo por quadro.
- `gameplay/PoliceModel.gd`: ajusta a posição rígida da arma aos alcances reais de ambas as mãos, incluindo recarga. Limites locais ficam em cache; o limite do kit continua 594 mm.
- `tests/test_police_meshy_body.gd`: tolerância de punho reduzida de 200 para **30 mm**, com resultado em milímetros.

`MeshyBodyRig.correct_hand_reach = false` recupera a IK/alcance anteriores para diagnóstico na mesma sessão. Esse interruptor compara a correção de runtime usando o mesmo GLB revisado; não restaura a arte antiga. Os interruptores dos catálogos e `GETECO_NO_MESHY_BODIES=1` continuam disponíveis.

Os nós de compatibilidade e a geometria antiga escondida por `RigBodySwap` não foram removidos nesta entrega. O teste confirma um único corpo **visível**; não aprova a exigência de eliminar toda geometria escondida das futuras famílias.

## Evidências visuais e diagnóstico

Diretório local, fora do Git: `evidence/npc-meshy/refinement-20261011/`.

- `before/`, `original-weights/`, `shoulder-compare/`: situação inicial e candidatos de ombro que não resolveram a asa. Não foram integrados.
- `refined-candidate/`: orientação dirigida de punho experimental, rejeitada por deformar a mão; o código experimental foi desfeito manualmente.
- `refined-forearm-wrist/`: terno com ombro e dedos corrigidos, preservando o roll do antebraço existente.
- `final-smg/` e `final-m4/`: GLB final de 24 ossos, corpo inteiro e piso de referência, nas oito poses e três vistas. Incluem buscar/inserir/carregar durante recarga.
- `country-review/`: country masculino/feminino A e terno feminino, frente/costas/lado, repouso sem arma, caminhada, mira, recuo, três fases de recarga e corrida. O candidato country não mostrou ganho suficiente para substituir o original. Variantes country B têm diagnóstico de pesos, mas não foram capturadas nesta revisão.
- `pose-diagnostics/` e `shoulder-candidates/`: matrizes da pose real, candidatos descartados e validações offline. Backups `suit_m_original.glb` e `suit_m_26_bones.glb` preservam os estados anteriores.

A asa masculina tinha vértices do ombro com até 54% de peso em `ForeArm`; a ponta era arrastada aproximadamente 208 mm. Na mesma pose, a correção reduz esse arraste em 192,5 mm e o p95 de estiramento das arestas do lado Right de 1,992× para 1,090×. Há resíduo no outro ombro; isto não certifica todas as poses ou todos os corpos.

Os dedos do terno masculino tinham em média somente 26–27% de influência `Hand` na região distal. Após o reparo, essa média fica em aproximadamente 98,5–99,8%. Os vértices previamente curvados permanecem intactos; a marca de reparo impede aplicar a curva novamente.

Detalhes e comandos: [ombros](npc-meshy-ombros-diagnostico-20261011.md) e [mãos](npc-meshy-maos-diagnostico-20261011.md). Esses documentos distinguem validação offline da integração no motor, registrada aqui.

## Validação funcional

Godot **4.7.2 .NET**, C# compilado por `dotnet build Harbor.csproj` e pelos runners, APPDATA temporário isolado, `--no-save --skip-arrival`. Headless usado somente para contratos funcionais.

A suíte inicial executou 16 testes: **14 passaram**, um excedeu o prazo inicial e um teve erro de encerramento do motor. Passaram catálogo de pedestres, country, acessórios, mecânico, polícia, contatos, morte Mixamo, equipamento, combate policial, segurança do Maciota, guardas da garagem, regiões, direção nativa e admissão fria.

- `test_meshy_weapon_contact_phases`: 7 GLBs policiais × SMG/M4 × mira/recuo/recarga/corrida, 56 casos, máximo medido **0,00144 mm** no osso do punho, sob o limite de 30 mm. Corrida aquece até `_run_w >= 0,95` antes de amostrar. Compara a posição real do osso `Hand` com as âncoras da arma; na recarga, a mão de apoio segue o alvo da animação. Não mede distância de toda a superfície da palma ao guarda-mão.
- `test_meshy_limb_alignment`: joelhos/tornozelos contra as juntas públicas, em repouso, passo, sentado e queda; terno e patrulha. Antes do colapso, o terno falhava com até **397,995 mm** de erro. Após remover os helpers, todos os casos passaram; erro do tornozelo no caso de queda aproximadamente **1,962 mm**.
- Depois do GLB final, reexecutados e aprovados: alinhamento dos membros, contatos, polícia Meshy e morte Mixamo. Morte Mixamo: 17 verificações. As poses artificiais de queda do teste de alinhamento não substituem uma revisão de todas as mortes em gameplay.
- `test_bridge_approach_terrain`: contrato territorial passou, mas o runner inicial registrou vazamentos de RID de corpo/forma no encerramento. Os probes sem Meshy passaram o contrato e ainda emitiram avisos de ObjectDB; os mesmos vazamentos de RID não foram reproduzidos. A causa do encerramento permanece inconclusiva.
- `dispatch/test_dispatch_police`: o prazo inicial de 120 s era insuficiente para o roteiro completo. Probes com passo fixo e depois **execuções normais completas**, com prazo de 900 s, concluíram 7/7 grupos, 54 verificações e as mesmas **10 falhas com Meshy ligado/desligado**. Falham chegada/desembarque, estacionamento, partida/liberação e equipe esgotada. Portanto não atribuir essas falhas à troca do corpo; não foram corrigidas nesta entrega.

`Jogar.cmd` abriu o menu, iniciou um slot vazio no APPDATA temporário, carregou a chegada com chuva, permitiu pular a apresentação com Esc e caminhar com tecla física A. Capturas `jogar-slots.png`, `jogar-before-walk.png` e `jogar-after-physical-walk.png`. Foi preciso registrar a escala 100% somente no perfil temporário do editor: o Terrain3D acessava uma opção ausente nesse perfil limpo durante a importação headless. Nenhum plugin ou configuração pessoal foi alterado.

Logs: `suite.log`, `test_*-final.log`, `limbs-before-controlled.log`, `dispatch-*.log` e relatório do runner em `evidence/test-suite/`. Avisos e falhas não foram ocultados.

## Desempenho

RTX 4060 Laptop, Vulkan Mobile, janela 1280×720, VSync/limitador desativados somente no processo. Cada comparativo tem seis rodadas, 5 s de aquecimento + 30 s de amostra, ordens legacy/refined/refined/legacy/legacy/refined. São preservadas amostras brutas e percentis em milissegundos. Meta provisória: 16,67 ms; sinal de regressão acima de 5%.

| Estado do runtime, 24 policiais | p50 legacy → refined | p95 | p99 | Draw calls |
|---|---:|---:|---:|---:|
| Primeira correção, consultas ao esqueleto | 1,851 → 1,944 | 2,148 → 2,271 | 2,476 → 2,622 | 374 / 374 |
| Cache de origens, antes do cache de limites | 1,871 → 1,961 | 2,279 → 2,361 | 2,568 → 2,704 | 374 / 374 |
| Cache de origens e limites, GLB de 26 ossos | 1,813 → 1,824 | 2,081 → 2,038 | 2,454 → 2,310 | 374 / 374 |
| **Asset final, 24 ossos** | **1,820 → 1,848** | **2,016 → 2,037** | **2,211 → 2,254** | **374 / 374** |

Valores são medianas das três rodadas de cada condição, sem descartar as rodadas ruidosas. Na última linha: p50 +0,61%, p95 −2,07%, p99 −5,87%; máximos 8,309/6,975 ms e zero quadros acima de 33,3 ms. O ganho dessa otimização não certifica a migração Meshy versus kit nem resolve automaticamente a regressão histórica de polícia mencionada no relatório anterior. Essa amostra precede o colapso final de dois ossos; o resultado do asset final e do jogo real fica registrado ao final.

Dados: `perf-before/`, `perf-contact/`, `perf-contact-final/`, `perf-contact-cached/`. Não declarar performance global aprovada a partir destes palcos.

Tentativa em **Main real**: sessão pronta, caminhada física aprovada e roteador C# confirmado em log (`route_jit_prewarm native=true`). O cenário não trouxe nenhum policial Meshy à câmera no prazo de 20 + 60 s; o runner abortou antes de registrar rodadas. **Desempenho da resposta policial real permanece não medido**, sem substituir o despacho por atores artificiais. Log `perf-game-contact.log`. O benchmark invalida rodadas sem carga policial ou com contagens divergentes; não pode gerar aprovação vazia.

Comparativo final `perf-contact-24-bones/`: p50 **+1,54%**, p95 **+1,04%**, p99 **+1,94%**, abaixo do sinal de 5% neste palco. Máximos **7,022 → 6,663 ms**, zero quadros acima de 33,3/66,7 ms nas seis rodadas, 374 draw calls em ambas. **Sem regressão detectada para o custo desta correção nesse palco**; não é aprovação da migração Meshy versus kit nem do jogo real. Mantidas todas as amostras; não há mais repetição equivalente necessária para este cenário.

## Próximos modelos: sem gasto autorizado nesta tarefa

A próxima família da ordem solicitada é bombeiro. O macacão do mecânico tem mangas arregaçadas e não cobre a jaqueta/calça de proteção do bombeiro. Não foi feita uma substituição visualmente inadequada. Para prosseguir com essa família, o mínimo é **1 malha + 1 textura = 30 créditos**, conforme os custos informados no pedido.

Base comum dos prompts: `Realistic adult game crowd NPC, single character, full body, natural human proportions 1.76 m tall, strict symmetrical A-pose, arms straight about 25 degrees away from torso, palms facing thighs, fingers relaxed, legs straight slightly apart, feet flat, head facing forward, neutral expression. Clean low-poly-friendly silhouette, matte fabric, no props, no weapons, no tools, no text, no logos, no extra people.` Revisar os marcadores de ombro, cotovelo, punho, virilha e tornozelo antes de rigar.

| Modelo ausente | Complemento do prompt | Quantidade | Custo malha + textura |
|---|---|---:|---:|
| Bombeiro masculino | `Adult male firefighter, protective tan turnout jacket and trousers, reflective bands, red firefighter helmet, black heavy protective boots, sleeves fully covering arms.` | 1 + 1 | 30 |
| Paramédico masculino | `Adult male paramedic, pale gray medical shirt with pockets, navy trousers, black practical shoes, fully covered legs, no stretcher, no medical bag.` | 1 + 1 | 30 |
| Tático feminino | `Adult female tactical officer, medium build, gray tactical uniform, helmet, protective vest, knee pads and black boots, trousers, no skirt.` | 1 + 1 | 30 |
| Masculino magro | `Adult slim male civilian, visibly narrow shoulders and lean torso, plain neutral gray polo shirt, jeans and ordinary shoes.` | 1 + 1 | 30 |
| Idoso masculino | `Elderly male civilian, natural older face and gray hair, lean older build, plain neutral shirt, long trousers and comfortable shoes.` | 1 + 1 | 30 |
| Idosa feminina | `Elderly female civilian, natural older face and gray hair, plain neutral blouse, long trousers and comfortable shoes, no skirt.` | 1 + 1 | 30 |

Somente o bombeiro é a dependência imediata; os demais são inventário de lacunas, não pedido para gerar tudo agora. Se todos forem gerados, seriam 6 malhas + 6 texturas = 180 créditos. Nenhuma ação Meshy foi executada nesta entrega.

## Limites de escopo

Não migrados: bombeiro, paramédico, funerário, serviço/médico, Neco, caixas, guardas de banco/blindado, FortSoldier, guarda da garagem, Cobras e montanha. Não editados CobraModel nem SkatePose, que tinham trabalho concorrente. Não implementados polegar independente, LOD de acessórios, variação adicional de biotipo ou coordenador único de poses. Não certificadas todas as transições, oclusões, mortes, noite/chuva ou populações maiores. Os fallbacks existentes foram preservados; não atribuir a todos os catálogos a mesma política de substituição de biotipo.
