# Harbor: redução de draw calls e experimento de física

Estado final em 30/10/2026: trabalho encerrado por solicitação do usuário.
Nenhum experimento foi promovido a padrão. Jolt concluiu 36/36 sessões; a matriz
das fases 1–3 foi encerrada com 74/108 sessões completas, uma interrompida e
33 não iniciadas. A fase 4 não foi aplicada. A meta de redução de 70–80% não
foi demonstrada. Planos e pendências abaixo são histórico, sem continuação
automática. Consulte o [laudo final detalhado](D:/geteco/game/docs/laudo-geteco-drawcalls-jolt-20261030.md)
e a [análise parcial encerrada](D:/geteco/game/artifacts/codex-drawcalls/encerramento-20261030/partial-analysis.md).

## Ambiente e identidade

Godot 4.7.2 .NET, GDScript e C#, Forward+/Vulkan, RTX 4060 Laptop, i7-13650HX,
resolução efetiva 3440×1440, VSync e limite de FPS desligados. Todas as execuções
do motor passaram por `tools/run_godot_locked.sh`. Exports e saves de teste são
exclusivos de `artifacts/codex-drawcalls`; `builds/jogar` não foi usado.

O export inicial e o pacote instrumentado `ab-phases123` são distintos e foram
preservados. A/B usa desligado e ligado dentro do mesmo pacote. PCKs que têm
hardlinks nos ambientes isolados nunca devem receber uma nova exportação.
Identidades, horários, configurações e hashes dos resultados ficam nos manifests
da pasta de evidências. O export instrumentado salvou o PCK, mas seu lançador
ficou aberto no encerramento e atingiu o timeout: código 124 preservado no log.
O executável exportado completou posteriormente as cinco sessões diagnósticas
com código 0 e C# nativo confirmado; isso não muda o resultado do comando de export.

## Fase 0: linha de base

A coleta inicial terminou antes das alterações de otimização: 18 sessões,
três por rota em cada condição. A bancada antiga não gravava visível/sombra,
objetos, CPU de render e física durante a janela completa. Os registros de
travadas contêm alguns desses contadores, mas são amostras condicionadas a
quadros lentos; não servem como percentis da rota. A instrumentação posterior
passou a registrar esses dados para os dois lados do A/B.

| Condição | Rota | Draws globais¹ | GPU¹ ms | Frame p50 / p95 / p99 / máximo ms | >33 ms | >100 ms |
|---|---|---:|---:|---|---:|---:|
| Calma | Oeste | 1365 | 4,38 | 6,86 / 10,54 / 12,29 / 50,64 | 1 | 0 |
| Calma | Porto | 752 | 4,68 | 6,38 / 10,27 / 11,68 / 43,61 | 2 | 0 |
| Calma | Sobrados | 711 | 4,22 | 5,49 / 9,95 / 13,06 / 50,34 | 3 | 0 |
| Estresse | Oeste | 1843 | 6,01 | 12,56 / 16,77 / 19,46 / 174,67 | 5 | 1 |
| Estresse | Porto | 1021 | 6,14 | 11,32 / 16,23 / 18,58 / 66,67 | 14 | 0 |
| Estresse | Sobrados | 962 | 5,55 | 9,89 / 15,01 / 18,63 / 62,91 | 15 | 0 |

¹ Mediana do p50 das três sessões. Latências usam todos os intervalos brutos do
grupo; contagens de travadas são somadas. `>33` significa estritamente 33,0 ms,
recalculado dos dados brutos: o campo legado da bancada usava 33,3 ms.
Fonte: [baseline-final.md](../artifacts/codex-drawcalls/baseline-final.md).

O monitor `physics_ms` publica aproximadamente uma vez por segundo o maior
tempo de física daquele intervalo. A bancada lê o último valor a cada quadro:
seus percentis ponderam máximos periódicos e não medem cada passo físico.
CPU/GPU de render também têm a defasagem normal das consultas do renderizador.

Em 30/10, outra sessão Claude iniciou suítes de teste durante a coleta do Jolt.
A fila manteve apenas um Godot por vez, mas isso acrescentou esperas entre as
sessões. O usuário confirmou que as duas sessões devem continuar trabalhando.
Não se afirma máquina exclusiva ou ausência de carga de fundo; os tempos de
fila permanecem nos manifests e não entram nos intervalos de frame medidos.
Diferenças pequenas não bastam para atribuir ganho causal ao backend físico.

## Fases 1–3: implementação e limites

| Experimento | Padrão | Comportamento e limite |
|---|---|---|
| `GETECO_CAR_SHADOW_PROXY=1` | Desligado | Casco simples só no Body intacto de Aurora, Union e Classic. Rodas e acabamento preservam casters; portas, tuning e dano restauram imediatamente a sombra original. Exige pré-aquecimento real. |
| `GETECO_SUN_SPLITS=2` | Quatro cascatas | Usa o interruptor existente. Menos passadas podem reduzir resolução de sombra; a inspeção temporal continua obrigatória. |
| `GETECO_CAMERA_FAR=120` | Desligado | Encurta o volume ortográfico do Harbor respeitando chão, recuo e projeção final. O valor efetivo pode superar 120 m. Reflexões conservam o alcance anterior. |
| `GETECO_CAMERA_FAR=settings` | Desligado | Usa a preferência de distância como reserva depois do foco, com a mesma proteção geométrica. Não foi incluído na primeira matriz do candidato fixo de 120 m. |
| `GETECO_REVEAL_GUARD=1` | Desligado | Relaxa apenas escopos não interativos quando as instâncias reais do reveal estão desligadas. Diagnósticos continuam protegidos; não restaura lotes já publicados se uma futura produção passar a ligar reveal dinamicamente. |

A câmera ortográfica usa `near..far` para as cascatas; `directional_shadow_max_distance`
não limita esse volume no Godot 4.7.2. Por isso a preferência anterior não controlava
o alcance na câmera normal. Reduzir o far também pode cortar geometria, de modo
que o piso conservador e as capturas são parte do experimento.

O modelo atual de Aurora tem 7 malhas e 28 superfícies, das quais 14 no Body;
o levantamento antigo de 55 malhas não descreve a frota deste pacote. O ganho
do proxy deve ser medido sobre essa geometria atual. Faróis continuam usando
os sistemas existentes; `VehicleEquipment.gd` e `LightBudget.gd` não foram editados.

O censo com guard desligado/ligado nos quatro trechos medidos passou de 732 para
731 superfícies e de 458 para 457 superfícies de sombra. A única diferença foi
no trecho (1,1); isso é composição da árvore, não draw calls reais nem ganho de FPS.

### Diagnóstico de ativação

As cinco sessões do porto com estresse, N=1 por variante, terminaram. O leitor
de resultados precisou de reparos para chaves vazias válidas de JSON e agrupamento
de dicionários PowerShell. Os dados originais foram preservados e validados sem
repetir essas execuções. [Checkpoint](../artifacts/codex-drawcalls/checkpoint-diagnostic.md)
e [recibo de validação](../artifacts/codex-drawcalls/checkpoint5-data-validation.json).

Não extrapolar uma queda do p50 de draws para toda a rota: o JSON também conserva
as médias e faixas por sessão. A matriz de aceite terá rótulo novo, uma única
data local, controle comum e cinco candidatos, incluindo a combinação dos
interruptores: 108 sessões. Dados diagnósticos de outra data não serão reaproveitados.

## Validação funcional e visual

Os testes dirigidos passaram: proxy 92 checks, alcance 480 e guard 46. Os 16
testes de área passaram, incluindo portas, dano, vidro, sangue, tuning, câmera,
reflexões renderizadas e acessos fatiados. Frame-rules manteve suas contagens.

A primeira suíte central completa teve 25 passes e duas falhas. Foram corrigidas
cinco traduções ausentes no catálogo e o prazo do teste de entrada no veículo:
4 s era menor que a animação/abordagem mínima atual, de 4,04 s; o máximo autorado
é 7,09 s e o teste agora permite 8 s simulados, mantendo todas as assertions.
As repetições dirigidas passaram com 2459 e 51 checks. Não se apresenta a primeira
execução completa como inteiramente verde.

Em 30/10, após essas correções, a suíte central completa foi executada novamente
com compilação C# pela fila: **27 passaram, zero falhas**, exit 0.
O resultado está em `evidence/test-suite/core/20261030-041837/RESUMO.md` e o
console em `artifacts/codex-drawcalls/core-full-phases123-20261030.log`.
Frame-rules também passou, mantendo 87/64/68/12 nas quatro categorias.
Essa validação é das fases 1–3 no checkout corrente; não valida a fase 4 ainda
em staging nem substitui a medição no export congelado.

Capturas temporais foram concluídas com o mesmo PCK e bytes da DLL ExportRelease,
usando host editor .NET para a entrada de captura. Esse host e a gravação de imagens
não medem FPS release. Cada sequência preserva todos os quadros renderizados,
seus timestamps e poses; equivalência dos controles não garante tráfego idêntico.
Inspeção de imagens isoladas não aprova ausência de flickering.

O par de proxy foi capturado em quatro casos (dia/noite × OFF/ON), na revisão
`temporal-proxy/run-v3`: todos passaram, cada um com mais de 30 s intactos,
zero quadros omitidos e zero falhas de escrita. ON confirmou três proxies e
fallback síncrono em porta/dano, com reparo somente nos modelos elegíveis.
Os vídeos `drive.mp4` foram derivados dos timestamps reais, fora de benchmarks.
Uma revisão delimitada decodificou 3.587 JPEGs em nove ROIs autoradas e congeladas,
sem ajustar limiares depois do resultado. Não houve imagens inválidas nem
candidatos a pulso nos trechos estáticos cobertos. Os 32 candidatos a degrau
persistente coincidem com fechamento da porta, dano e reparo; os frames
anterior/início/fim examinados são consistentes com essas ações. A cobertura por
ROI soma 30,86–31,86 s, incluindo cerca de 10 s intactos e as ações posteriores.
O arco intacto de aproximadamente 20 s ficou fora do detector sem homografia;
inspeção pontual nesse arco não aprova estabilidade temporal. À noite somente a
Aurora emite o par de faróis nesta fixture. Dano apaga uma lâmpada que permanece
apagada após reparo em OFF e ON, sem atribuir esse comportamento ao proxy.
Não houve reprodução integral em tempo real dos MP4 nesta revisão, nem aprovação
global de iluminação. Máscaras, candidatos, imagens e cobertura estão no
[relatório próprio](../artifacts/codex-drawcalls/proxy-review-20261030-v1/README.md).

A bancada complementar de oclusão v2 registrou PASS nas verificações de pixels
e movimento dos dois lados, mas seu launcher devolveu código 1. A investigação
identificou `bash -e` encerrando o wrapper ao tentar terminar um follower já
encerrado; o código nativo não ficou confirmado. Os resultados v2 permanecem
falhos/preservados. A correção atingiu somente o launcher de teste. Na V3,
os dois recibos confirmam exit 0, 78/78 checks, zero FAIL/ERROR e hashes íntegros.
Cada lado contém 1.921 amostras móveis em cerca de 32 s: 104 cobertas sem vazamento
e 505 abertas sem apagão inesperado; as demais 1.312 não recebem essas assertions
de posições extremas. O console ainda registra 10 instâncias ObjectDB vazadas
no encerramento de cada execução; o aviso não aparece no engine.log separado.

A inspeção de quatro PNGs originais, também repetida pelo coordenador, mostra
diferença de silhueta no Union: a lateral ON fecha faixas finas da baseline numa
sombra contínua; a frente altera contorno/comprimento, mantendo o bloqueio
principal. Isso é compatível com a simplificação autorizada, sem afirmar
equivalência fina ou aprovação de fidelidade completa pelos 78 checks. Os pares
e regiões exatas estão no relatório próprio; os originais foram preservados.

A revisão de câmera/sombra abrange nove sequências secas e três de chuva,
cada uma com mais de 30 s úteis. Os 12 vídeos VFR preservam os 9.189 frames
originais; contagem e timestamps foram verificados, com erro máximo inferior
a 0,501 ms. As amostras inspecionadas não mostraram corte grosseiro exclusivo
de far120 ou splits2, e o piso calculado permaneceu dentro do far em todos os
frames. Isso não aprova qualidade fina nem estabilidade temporal completa.
As ROIs estáticas cobrem somente cerca de 3,9–4,9 s e apresentam 38 sinais
inconclusivos nas bordas de sombra/parapeito e na chuva. A máscara inicial do
parapeito incidia na água: seus 25 sinais foram invalidados para essa finalidade,
preservados e separados da passagem corrigida, sem mudar os limiares.
O par ponte/far120 tem uma lacuna de pareamento de 8,899 s; pan/rotação/zoom
ficam fora do detector. A chuva exercita reflexo de chão, mas não de fachada
(zero receptores nesse cenário). Não houve reprodução contínua observada dos
12 vídeos; não há aprovação visual para ligar os gates por padrão.
[Revisão, cobertura e vídeos](../artifacts/codex-drawcalls/camera-review-20261030-v1/REVIEW.md).

## Fase 4: fachadas

Somente propostas em staging; nenhuma mudança foi aplicada ao runtime. O piloto
4a usa páginas de dimensões exatas, BC7 com mipmaps e emissão colorida: 60 materiais
de 26 estilos, seis páginas, 63,1745 MiB. Não redimensiona nem recorta as pinturas.
A estimativa de 60 superfícies para 28 lotes por dono é estática, não medição.
As propostas incluem lotes por célula, fallback conservador no túnel, liberação
antes de preparar acessos, cancelamento do carregamento e retenção de recursos.
A revisão também encontrou uma consulta de globais de shader exclusiva do editor;
uma camada adicional declara o global em Project Settings e inicializa a noite
antes de carregar o shader. Tudo permanece em staging, sem validação no motor.
A meta de 80–90% dos draws das fachadas não foi demonstrada.

O pré-aquecimento exige uma alteração em `runtime/PaintedFacadePrewarm.gd`, arquivo
que já tinha edição de outra sessão. A proposta preserva essa edição e está
separada em `artifacts/codex-drawcalls/staging-facade/prewarm.proposed.patch`.
A autorização específica foi concedida pelo usuário para a fase 4, depois das
fases 1–3. O patch permanece em staging até essa etapa.

## Fase 5: Jolt

`project.godot` não foi alterado. Cada motor usa seu próprio `override.cfg`, com
PCK e DLL idênticos. Os probes confirmaram GodotPhysicsDirectSpaceState3D e
JoltPhysicsDirectSpaceState3D, versão .NET e chamada C# real.

| Teste | GodotPhysics | Jolt |
|---|---:|---:|
| Entrada de direção nativa | PASS | PASS, mas 8 erros de engine |
| Ragdoll | 2 falhas / 66 | 3 falhas / 66 |
| Contato/liberação | 4 falhas / 36 | 4 falhas / 36 |
| Impactos pesados | 22 falhas / 80 | 23 falhas / 80 |
| Freio de mão | 0 falhas / 3360 | 0 falhas / 3360 |

O controle é o pacote instrumentado com gates desligados, não uma suíte funcional
da baseline original. As falhas compartilhadas incluem fixtures e prazos divergentes
das regras atuais; a postura final de dois ragdolls permanece sem causa demonstrada.
Jolt acrescenta a violação do limite de deslocamento no caso da parede e a falha
de passagem física do carro rápido sobre o alvo esmagado. O teste da parede não
registra a trajetória completa, então não distingue atravessar de passar por cima.

[Comparação funcional detalhada](../artifacts/codex-drawcalls/jolt-functional-delta.md).
O A/B release terminou com 36/36 sessões válidas em 30/10 e conferência final de
identidade, código 0. No porto com estresse, FPS médio passou de 78,54 para 85,53
e p99 de 26,94 para 21,06 ms. No oeste com estresse, FPS ficou praticamente igual,
mas física reportada passou de 7,00 para 7,82 ms e p99 de 19,56 para 20,22 ms.
O ganho não foi uniforme. [Comparação consolidada](../artifacts/codex-drawcalls/jolt-release-20261030.md)
e [métricas completas](../artifacts/codex-drawcalls/matrix-evaluator/jolt_20261030_v1.md).
Nenhuma assertion foi afrouxada para aprovar Jolt; o padrão continua GodotPhysics.

O controle de oeste/estresse teve um pico de 1,03 s, mantido nos resultados.
O rastro próximo por duração contém incremento de pipeline e CPU da viewport de
986,59 ms na sondagem seguinte. No Jolt, um evento de 119 ms contém construção
de ragdoll de 102,982 ms. Essas observações não provam causa do backend nem
identidade com o frame medido. Os 36 logs foram vinculados sem ambiguidade;
os oito eventos de sessão acima de 100 ms não são somados aos cinco frames
medidos, pois cobrem janelas diferentes. [Análise das travadas](../artifacts/codex-drawcalls/jolt-stalls-20261030-v1/findings.md).

As quatro sondas funcionais V1 foram preservadas em cópias isoladas. O Crush V2,
com a leitura de metadado corrigida, confirmou assinatura inicial A/B idêntica e
integridade sem issues: GodotPhysics passou 8/8 checks sem ERROR; Jolt passou 7/8,
com a única ERROR correspondente à assertion original de passagem física.
A fonte Jolt permaneceu em Z=-3,648293 m por 106 dos 115 passos observados,
apesar da velocidade lógica de 25 m/s. A comparação dos 920 registros de cada
execução encontrou zero diferenças cinemáticas V1→V2 após excluir somente
`engine_usec` e `shape_instance_id`. É uma diferença reproduzível do projeto
entre backends, sem demonstração de um defeito interno específico do motor.
[Diagnóstico final Crush V2](../artifacts/codex-drawcalls/jolt-crush-v2-findings.md)
e [comparação estruturada](../artifacts/codex-drawcalls/jolt-crush-v2-comparison.json).

O Wall V1 permanece com par rejeitado: as 11 partes já começavam com translação
Z de aproximadamente 4,86 cm entre motores, além de pequenas diferenças de pose.
Não houve nova execução da parede. O menor Z isolado não distingue atravessar
de passar por cima e esse par não permite atribuição causal ao solver.
[Evidências e limites da V1](../artifacts/codex-drawcalls/jolt-deltas-v1-findings.md).

A primeira tentativa adicional de direção foi interrompida sem gerar relatório.
O StallLog confirma renderização e direção C# ativas até 342 s, mas o carro ficou
quase parado durante parte do percurso. A bancada só começava a contar a janela
de 30 s depois de concluir a volta de aquecimento; portanto não há amostra válida.
O complemento foi concluído em 30/10 com o argumento existente `--benchmark-cold`,
rótulo próprio e quatro janelas de 30 s, separado da matriz aquecida de 36 sessões.
Os quatro processos terminaram com código 0 e identidade final verificada.
No estresse, o frame médio foi 11,09 ms em GodotPhysics e 10,10 ms em Jolt;
no cenário calmo, 9,14 e 9,77 ms, respectivamente. Nenhum excedeu 100 ms.
Isso não isola ganho do backend: todos registraram quedas e recuperações, as
trajetórias diferiram e há somente uma sessão por motor/carga. O progresso da
rota inclui saltos de recuperação; não comprova direção contínua estável.
[Resultados e limites do DriveCold](../artifacts/codex-drawcalls/jolt-drivecold-20261030-summary.md).
O Esc recebido
pelo controle de computador não foi uma solicitação de cancelar o trabalho;
o usuário confirmou a continuação.

## Pendências de entrega

- Completar A/B release, comparação temporal e análise de travadas das fases 1–3.
- Aplicar a fase 4 somente depois dessa validação, com o prewarm já autorizado;
  gerar/importar páginas, testar acessos e medir desligado/ligado no mesmo pacote.
- Manter os limites da decisão sobre Jolt: matriz release e diagnóstico Crush V2
  concluídos; parede V1 sem par admitido e sem nova execução. A direção real
  complementar tem limitações de trajeto/recuperação.
- Registrar decisões por interruptor, números finais e commits por fase.
- Consolidar o plano posterior de fusão de peças já escrito em
  `artifacts/codex-drawcalls/phase1-plan.md`, sem alterar a frota nesta tarefa.

Não há commits desta tarefa até esta revisão. Evidências permanecem em
`artifacts/codex-drawcalls`; outros arquivos modificados no checkout não foram
descartados nem incorporados ao stage.
