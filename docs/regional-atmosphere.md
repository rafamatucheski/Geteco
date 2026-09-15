# Atmosfera regional — porto e serra

A ponte entre porto e serra agora mistura progressivamente o tratamento de cor,
a névoa e a exposição ao vento frio. Na subida, o perfil da floresta dá lugar ao
da neve. A iluminação continua acompanhando o relógio do mundo: selecionar a
serra não coloca mais o gerenciador de dia/noite em modo de interior.

## Direção visual e configuração

Os recursos em `world/shared/atmosphere/profiles/` definem sombras, áreas claras,
cor e quantidade de névoa, saturação, contraste e vento. Porto, floresta e neve
estão integrados ao trajeto existente. Deserto e costa têm perfis para os IDs de
bioma já existentes; esta mudança não cria uma região de deserto jogável.

- Porto: sombras discretamente azuladas, contraste industrial e maresia.
- Floresta: verdes contidos e névoa úmida.
- Neve: sombras azuis, neve clara de dia e névoa mais presente no cume.
- Deserto: áreas claras quentes, sombras mais frias e poeira ocre.
- Costa: cores um pouco mais vivas e névoa marítima leve.

### Cemitério

O lote do cemitério recebe sombras frias, saturação 14% menor, névoa adicional
discreta (0,035) e deriva do ar mais lenta. A cor da névoa acompanha o horário;
ela não clareia artificialmente a noite. Os tons das áreas claras permanecem
iguais para conservar as luminárias quentes existentes.

O controlador encontra o nó pelo grupo `cemetery`, mantém uma referência e usa
`to_local()` com o `LOT_SIZE` real. O perfil tem peso integral no centro e borda
suavizada antes/depois dos muros. Não depende da posição absoluta do lote na
cidade. O peso zera na montanha; interiores continuam suspendendo o compositor.
A mistura é calculada a 10 Hz e usa o shader existente. Não acrescenta luzes,
partículas, viewports, colisores ou alterações de geometria.

Revisão: `D:/geteco/artifacts/cemetery-atmosphere/review.html`.

### Resort e refúgios — configuração

O entorno do Cume Branco recebe uma variação local: áreas claras 7% mais quentes
no canal vermelho, azul reduzido em 6%, e saturação até 0,07 maior. As sombras,
névoa e nevasca continuam seguindo a serra. `resort_weight()` usa uma elipse
centrada em (7190, -2730), com escalas de 470 × 290 e borda suavizada; fora dela
o perfil da neve é preservado. O peso é multiplicado pela presença na montanha.
O mesmo passe existente aplica a mistura, avaliada a 10 Hz, sem luz ou viewport
adicional.

No chalé, o preenchimento frio passa de 0,70 para 0,48 e o ambiente ganha um tom
de madeira levemente mais quente. No lodge, o preenchimento genérico externo
dá lugar a uma luz fria de 0,48 e ambiente quente de 0,55. São ajustes nas fontes
existentes, feitos uma vez durante a construção. Jogador e residentes continuam
sob as mesmas luzes e profundidade 3D. Os interiores não recebem névoa externa.

Revisão antes/depois: `D:/geteco/artifacts/resort-atmosphere/review.html`.
Medições e limitações: `D:/geteco/artifacts/resort-atmosphere/performance.md`.

`AtmosphereProfile.sample()` varia esses controles com horário e cobertura de
nuvens. À noite a própria cor da névoa escurece. No entardecer, a modulação
compartilhada preserva a luminosidade do horário, e o compositor trata sombras
e áreas claras separadamente para não pintar toda a neve de laranja.

`AtmospherePalette` mistura porto/floresta ao longo dos 1.800 pontos de mundo
entre x=6.700 e x=8.500 na aproximação da ponte. Uma faixa norte impede que o
bairro leste seja confundido com a serra. Na montanha, a transição floresta/neve
acompanha y local de 250 até -1.700. A fronteira de streaming em x=7.300 não
dispara uma troca de filtro. Há suavização temporal de 1/3 s aproximadamente.

## Integração com o renderizador híbrido

`RegionalAtmosphere` aplica um único shader à composição do mundo, incluindo as
imagens dos modelos 3D, depois do desenho do cenário e antes do HUD. Isso conserva
os caches dos modelos e não acrescenta luzes, viewports ou materiais por pessoa.
Não é uma alteração da iluminação direcional gravada nos modelos em cache.

O passe usa uma cópia explícita da tela, uma leitura da imagem e duas leituras
de uma pequena textura de ruído reutilizada. O ruído acompanha coordenadas do
mundo, inclusive zoom e transformação da câmera. A região próxima ao personagem
tem menos névoa para conservar a leitura de obstáculos e da pista.

Essa névoa de primeiro plano é uma aproximação para a câmera superior; distância
do jogador é uma máscara de legibilidade, não profundidade 3D. O vale distante
tem seu próprio material atmosférico na camada de parallax, abaixo do terreno
sólido. Não há fog volumétrica nem inferência de profundidade a partir da cor.

A camada do efeito é 1. Relógio, HUD, menus e minimapa são desenhados depois.
Interiores suspendem o passe e a cópia de tela; túneis suspendem a névoa externa.
Não foram alterados geometria, colisões, spawns ou adaptação de atores em salas.

## Horário, clima e ciclo de vida

- O relógio e a atualização do estado noturno continuam dentro dos interiores;
  a modulação da sala continua branca, preservando suas luzes próprias.
- Chuva e respingos diminuem na aproximação da serra. O ID do clima da cidade é
  preservado, e a chuva reaparece ao retornar ao porto.
- A intensidade da nevasca existente participa do perfil. O mixer de vento
  existente recebe o peso geográfico; não se cria um segundo sistema de áudio.
- Uma cena avulsa da serra recebe um gerenciador de horário. A serra carregada
  pelo mundo contínuo usa o gerenciador do porto, sem duplicação.
- Perfis são avaliados até dez vezes por segundo; parâmetros são suavizados por
  frame. O efeito acompanha a pausa do gerenciador e é removido com a cena.

## Validação

Comandos usam o Godot 4.7.2 disponível no ambiente, com `--path D:/geteco/game`.

- `tests/test_weather_atmosphere_cycle.gd`: ciclo de cores, garoa, clima explícito
  e estados secos, zero falhas.
- `tests/test_weather_audio_mixer.gd`: chuva, mudanças rápidas de estado,
  abafamento e limpeza do mixer, zero falhas.
- `tests/test_regional_atmosphere.gd`: perfis, fronteiras geográficas, relógio em
  interior, ausência de passe duplicado, pausa e pixels renderizados.
- `tests/test_continuous_world.gd`: ida e volta dirigindo pela fronteira real,
  integridade do veículo, continuidade do mundo e atmosfera, zero falhas.
- `tests/test_mountain_cabin_scale.gd`, renderizado: entrada, circulação,
  bloqueios, coleta, saída, reentrada, recuperação e restauração, zero falhas.
- `tests/visual/capture_regional_atmosphere.gd`: porto, ponte, floresta, cume de
  dia/entardecer/noite, nevasca e túnel; confere a suspensão da névoa no túnel.

Evidências: `D:/geteco/artifacts/regional-atmosphere/`.
A galeria `review.html` reúne oito capturas finais; os JSONs `review/*-inventory`
registram luzes e modos dos viewports. No cume noturno, havia 700 PointLight2D
instanciadas, 659 habilitadas, 57 visíveis na árvore e 11 com retângulo de alcance
sobrepondo a câmera. A contagem inclui todo o mundo residente. Dos 496 SubViewports,
273 estavam em modo de atualização diferente de desativado; isso não significa
que todos tenham desenhado naquele frame. O novo efeito não cria essas fontes
nem esses viewports.
As cenas completas ainda emitem avisos de recursos no encerramento, também
observados antes desta mudança. O teste isolado da atmosfera encerra sem esses
avisos. Foi removida uma declaração duplicada de classe/base em `ui/MenuAudio.gd`
que impedia carregar os scripts dos menus antes das medições.

## Performance

O ensaio `tests/measure_regional_atmosphere.gd` usa HarborGame completo, com NPCs,
tráfego e streaming. A câmera segue um percurso controlado; ele não substitui o
teste de direção física. Cada cenário tem 30 s, com aquecimento separado, primeira
visita e repetição da ponte. CSVs guardam tempos reais entre frames, posição,
tempo de CPU e draw calls; JSONs incluem percentis, máximo, frames lentos,
resolução, GPU, versão, VSync e limitador. Saves vão para a pasta da evidência.

Alvo provisório: 60 FPS / 16,67 ms. Variação acima de 5% em p95 ou p99 exige uma
confirmação finita, não alteração da tolerância. As primeiras medições na pasta
`before/` e `after/` são exploratórias: houve mudanças externas no cenário e HUD
durante as execuções. O comparativo controlado usa `frozen-game/`, uma cópia
independente, com apenas os seis arquivos de integração alternados entre antes
e depois. O resultado final das medições é registrado junto das evidências.

**Estado final: performance não certificada.** Na retomada de 14/09/2026, porto e
primeira travessia tiveram p95 de 30,89→31,69 ms e 32,91→30,92 ms; p95/p99 não
pioraram mais de 5% nesses trechos. A execução terminou normalmente, mas outro
benchmark apareceu aos 145,59 s, durante a repetição da ponte. Essa repetição e
a neve continuam inconclusivas, mesmo com números próximos da base. Não houve
nova tentativa equivalente após a recorrência. A base já estava abaixo da meta
de 60 FPS. Deserto e costa têm perfis preparados, sem validação como regiões
jogáveis nesta entrega. O relatório
completo está em `D:/geteco/artifacts/regional-atmosphere/performance.md`, com
CSVs, percentis, manifests da cópia congelada e evidência dos processos externos.
