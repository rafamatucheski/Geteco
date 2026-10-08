# Entorno do avião na montanha — 07/10/2026

Reforma local do lago secreto, em `(5450,-1150)` nas coordenadas originais. O aro plano escuro, o acampamento/ilha pintados e os blocos de carga foram substituídos por superfícies e objetos compatíveis com a montanha. Nenhum lugar ou interior novo.

`NativeLake` mantém os polígonos originais de água e das cinco exclusões secas. `CargoLakeSurface` gera margem com relevo baixo, apoios secos, água aberta e gelo fraturado. O material de solo usa a receita efetiva de Mountain: cores `source_color`, ruído no espaço do mundo, normal, rugosidade, brilho, trilhas e neve. As bordas do acampamento e da ilha se misturam com a água ou o terreno que existem por baixo, com largura irregular. Não foram alterados o terreno global, o lago alpino ou a câmera do avião.

`CargoLakeDressing` reúne sete batches estáticos e 12 sólidos: cargas com tábuas/ferragens/lona, bancos, rochas, três pedras de passagem distintas, bote com remo/passarela e vestígios do acidente. Os apoios correspondem aos volumes visíveis. Fonte de calor, fogueira, pinheiro, recompensas e classificação de água foram preservados. As novas apresentações não têm atualização por frame nem novas luzes.

## Visual, física e ciclo de vida

Godot **4.7.2 .NET**, `Harbor.csproj` compilado com zero erros/avisos, Main real e roteador C# ativo. Dados exclusivos com `--no-save`; nenhum save pessoal foi sobrescrito.

- **38/38**: caminhada no acampamento e margens, rampa/carga do avião, apoios de terreno e das três pedras, domínios de água/seco, NPC visitante, saída de streaming e retorno sem duplicar geometria/colisores. [Log](../../evidence/cargo-lake-session-final.log), [resultado](../../evidence/cargo-plane-lake-final-review-10708/checks.json).
- **80/80** na regressão da fogueira: identidade/posição térmica, geometria, ausência de luz exterior extra, apresentação e limpeza. [Log](../../evidence/cargo-lake-heat-regression.log).
- A primeira montagem foi rejeitada visualmente: o aro preto havia virado uma faixa branca e os materiais estavam excessivamente lisos. Foi corrigido o uso de cores lineares no lugar de `source_color`, e aplicada a receita completa do chão vizinho. A primeira fixture também tentou entrar diagonalmente pela parede do avião; a rota foi alinhada à rampa, sem alterar os sólidos nem afrouxar assertions.

Fotografias reais equivalentes: [antes — vista geral](../../evidence/cargo-plane-lake-before-148232/airframe-closed.png), [depois — vista geral](../../evidence/cargo-plane-lake-after-82424/airframe-closed.png), [antes — acampamento](../../evidence/cargo-plane-lake-before-148232/camp-ground.png), [depois — acampamento](../../evidence/cargo-plane-lake-after-82424/camp-ground.png).

## Evidência temporal

MovieWriter no Main real: **60,0167 s**, sendo aproximadamente 30 s de dia e 30 s de noite, cada fase com dez segundos estáticos e vinte caminhando. Saída **1920×1080 / 60 quadros por segundo de simulação**, conforme override `movie` existente. [AVI contínuo](../../evidence/cargo-lake-temporal-fixed-20261007.avi), [timeline](../../evidence/cargo-plane-lake-temporal-45720/temporal.json), [inspeção](../../evidence/cargo-plane-lake-temporal-45720/inspection.json).

Foram decodificados todos os **4.359 quadros** do arquivo; os **3.601 quadros** do trecho acompanhado são contíguos e nenhum está ausente. O restante contém preparação/encerramento. Triagem por diferença de pixels no centro da imagem não encontrou candidato a flash de um quadro. Essa triagem não certifica sozinha estabilidade: câmera, fogo e atores produzem diferenças legítimas.

Foram revistas amostras de dia/noite e quadros consecutivos dos maiores eventos, em torno de 20,48 s e 23,88 s. Eles correspondem à subida/descida suave da câmera na proximidade do avião, confirmadas pela timeline. Não foi observada piscada involuntária, retorno de aro uniforme, vazamento de superfície ou desaparecimento de objetos nessas inspeções. A troca dia/noite aos 30 s e a desmontagem no final são cortes intencionais. [Dia](../../evidence/cargo-plane-lake-temporal-45720/review/sequence-02s.png), [noite](../../evidence/cargo-plane-lake-temporal-45720/review/sequence-32s.png), [evento de aproximação](../../evidence/cargo-plane-lake-temporal-45720/review/event-1985.png), [evento de afastamento](../../evidence/cargo-plane-lake-temporal-45720/review/event-2189.png).

Não houve revisão humana de todos os quadros em velocidade normal. A conclusão temporal se limita à sequência, triagem e janelas visualmente examinadas. O custo de leitura/encoding do MovieWriter reduz a velocidade real de gravação; os contadores de FPS presentes no vídeo não são benchmark do gameplay.

## Frame time do gameplay renderizado

RTX 4060 Laptop, Mobile/Vulkan, 1280×720, VSync ativo, limite efetivo 144 FPS e MSAA com valor runtime 2. Mesmo horário `.45`, clima limpo, seed, rota e parâmetros de população. Cinco segundos de aquecimento e 30 segundos de intervalos reais por versão, sem outro benchmark renderizado concorrente. Meta provisória: 60 FPS/16,67 ms; aumento superior a 5% em p95/p99 exigiria confirmação finita.

| Métrica | Antes | Depois |
| --- | ---: | ---: |
| Quadros/duração | 4.300 / 30,0074 s | 4.306 / 30,0061 s |
| FPS médio por quadros/tempo | 143,30 | 143,50 |
| p50 | 6,966 ms | 6,978 ms |
| p95 | 10,906 ms | 10,840 ms |
| p99 | 14,076 ms | 13,689 ms |
| Máximo | 39,049 ms | 37,260 ms |
| Quadros >33,3 / >66,7 ms | 1 / 0 | 1 / 0 |
| Caminhada medida | 84,04 m | 83,87 m |

p95 -0,61%; p99 -2,75%. **Sem regressão observada nessa amostra.** População de pedestres permaneceu em 40; o tráfego nativo variou de três para cinco carros no fim das amostras. Portanto, não chamar o resultado de comparação com população idêntica e rigidamente controlada. Os parâmetros de gameplay e a população esperada foram preservados; não foram removidos atores para melhorar FPS.

[Amostras antes](../../evidence/cargo-plane-lake-before-148232/report.json) e [depois](../../evidence/cargo-plane-lake-after-82424/report.json) incluem intervalos brutos, CPU/física, hardware, configuração e fingerprints. Os arquivos acompanhados permaneceram estáveis dentro da execução final. O aquecimento final teve p95 9,944 ms, p99 12,823 ms e máximo 36,404 ms. Custo isolado de GPU, construção do lago e primeira viagem completa cidade→avião não foi instrumentado separadamente. As fotos e o MovieWriter ficaram fora da janela de FPS.

Visual e funcionamento local aprovados nos casos descritos. Regime estável medido sem regressão observada; comparação estrita com tráfego fixado, outras condições meteorológicas e cobertura global da montanha não foram certificadas.
