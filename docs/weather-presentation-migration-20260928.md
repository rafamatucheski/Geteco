# Clima e atmosfera V1 → V2 — 28/09/2026

## Escopo

Complemento de `regional-atmosphere-migration.md`: recupera as lacunas de
apresentação do clima, preservando as paletas regionais,
as fases da lua e os ajustes atuais da câmera 3D. Não certifica migração integral
de todos os cenários da V1, nem altera interiores, colisões, combate ou inventário.

## Implementação

- O dia volta aos 1.440 segundos (24 minutos) usados pelas cenas produtivas
  `HarborGame` e `MountainPass` da V1; os 180 segundos do manager eram apenas seu
  padrão, sobrescrito pelas cenas. A V2 estava em 600 segundos. A progressão lunar
  existente permanece em oito dias de jogo, agora aproximadamente 192 minutos.

- `audio/weather/WeatherAudioMixer.gd` recuperado de `v1-legado`: três camadas
  originais de chuva, dois trovões, transição de intensidade, filtro de abrigo e
  redução de volume durante diálogos. O bus privado envia ao controle Ambiente;
  é removido ao encerrar a sessão. Interiores silenciam chuva e trovões; o vento
  da montanha mantém o abafamento já existente.
- Chuva leve usa intensidade 0,14–0,30; tempestade usa 1,0. A seleção
  natural usa 42% limpo, 28% nublado, 22% garoa e 8% tempestade, em
  intervalos de 90–180 segundos. A tempestade fecha o céu e o horizonte em
  cinza-escuro e reduz a luz direta, preservando luz ambiente e leitura próxima.
  Usa iluminação e névoa existentes, com transição regional para Mountain.
  A intensidade é salva no dicionário do mundo; saves
  anteriores usam 0,22. IDs de clima não mudaram.
- Clarão duplo de 0,57 s e trovão com atraso de 0,8–3,2 s, a cada 14–26 s de
  tempestade exterior. Usa a luz direcional e ambiente existentes, com intensidade
  moderada para preservar leitura. Entrar em abrigo, mudar de região ou encerrar
  tempestade cancela efeitos pendentes. Não cria luzes adicionais.
- Gotas afiladas com textura original procedural da V1; neve arredondada e granizo
  com contorno de gelo. Texturas pequenas, compartilhadas e produzidas uma vez.
- Estilhaços locais de granizo com vida de 0,28 s, conforme a V1. Pool de 120 peças
  em um MultiMesh, sem sombras, colisões ou dano. Até quatro raios a cada 100 ms,
  somente durante granizo, colocam impactos em sólidos reais e rejeitam telhados
  acima do jogador. Teleportes e abrigos limpam as peças.
- Névoa local móvel complementa a névoa de profundidade: 16 partículas suaves,
  seguindo cor e densidade da paleta regional. Não usa cópia de tela, volumetria,
  luz nova ou SubViewport. Não pretende reproduzir pixel a pixel a composição 2D.

## Validação

**Código final:** `test_weather_migration.gd` passou em **37 checks** renderizados
(incluindo cinco capturas), e `test_weather_atmosphere_integration.gd` passou em
**24 checks**. Logs `clock-verified.log` e `boundary-integration.log`; capturas em
`clock-verified/`. Dia de 24 minutos e virada do calendário lunar foram verificados.
Não houve erro de script nessas duas execuções finais; o encerramento renderizado
mantém o aviso de texturas já presente no baseline. Hashes em `source-final.sha256`.

O teste integrado `tests/test_weather_migration.gd` passou em 30 verificações
headless e em 35 com renderização/capturas, incluindo contraste de intensidades,
áudio, atraso do trovão, restauração de luz, diálogo, garagem, túnel, granizo sobre
colisão real e limpeza do bus. Capturas em `evidence/weather-migration-20260928/visual`.
Os 35 checks incluem cinco gravações de imagem; não são 35 comportamentos distintos.

O teste legado de fronteira inicialmente falhou em quatro expectativas: seus
pontos em x≈456 ainda exigiam neve, enquanto o contrato atual de `WorldConnection3D`
inicia o clima montanhoso somente após a margem leste da ponte. A fixture passou
a verificar chuva sem neve nos dois lados da fronteira lógica e a coexistência
chuva/neve na faixa climática descoberta, antes do túnel. Asserções de mistura,
persistência e abrigo foram mantidas; não se alterou o mapa para fazer o teste passar.

Regressões executadas: `test_regional_atmosphere.gd` (25 checks, zero falhas),
`test_weather_lighting_parity.gd` (PASS), `test_camera_rig.gd` (PASS). Os quatro
módulos novos também passaram em `--check-only`. Logs no mesmo diretório de
evidências. A câmera não foi editada neste lote.

A execução renderizada revelou um aviso de interpolação do MultiMesh, corrigido
desativando interpolação física somente nos efeitos animados por quadro. A revisão
também aumentou a largura/opacidade das gotas para preservar leitura com a textura
afilada e adicionou liberação explícita do cache de texturas no fim da sessão.

A execução de 35 checks registrou erro externo ao clima na validação do mapa
editado (`road/dock_street`, número de faixas por sentido), portanto não é uma
certificação de saúde global do projeto. A medição seguinte também encontrou
erros de tipagem em arquivos de ruas/passarela em edição concorrente; os arquivos
foram corrigidos pela outra sessão e as regressões acima puderam ser executadas.

## Desempenho e limites

Meta: 60 FPS / 16,67 ms. Aumento superior a 5% em p95/p99 exige confirmação
dirigida. `tests/measure/measure_weather_migration.gd` utiliza Main real, 1280×720,
Mobile, população 24, seed fixa, save desativado, oito segundos de aquecimento e
30 segundos de intervalos reais entre frames por cenário. Não isola tempo de GPU.

O baseline inicial foi contaminado por processos de outras sessões, incluindo
outra medição renderizada iniciada durante a execução. Registrou 14,06 FPS na
chuva, 18,04 na tempestade e 29,92 na neve; não é comparação causal válida.
Evidência preservada em `evidence/weather-migration-20260928/baseline`.

A opção `--ab-weather` troca somente a instância de clima do processo de medição
entre a cópia anterior preservada e o código migrado, mantendo a mesma cidade
carregada. Nunca restaura ou sobrescreve arquivos do projeto. Todas as amostras,
inclusive desfavoráveis, foram preservadas.

Rodada A/B (`paired`), RTX 4060 Laptop, Godot 4.7.2, Mobile, 1280×720, VSync
desligado, limite efetivo de 144 FPS vindo das configurações existentes:

| Cenário | FPS antes/depois | p95 ms antes/depois | p99 ms antes/depois |
|---|---:|---:|---:|
| Garoa | 28,93 / 10,93 | 42,64 / 182,28 | 65,41 / 209,15 |
| Tempestade noturna | 15,66 / 28,49 | 148,22 / 48,62 | 199,56 / 63,24 |
| Neve/granizo | 19,60 / 29,90 | 132,51 / 36,00 | 156,97 / 41,42 |

Esses números **não aprovam performance**: houve jogos/testes concorrentes durante
a rodada, e a direção da diferença mudou entre cenários. Não foi demonstrado ganho
nem isolada regressão causada pelos efeitos. A rodada precede os refinamentos
finais de gota, processamento ocioso, interpolação e limpeza de texturas.

O aviso de liberação de `ImageTexture`/dois RIDs no encerramento também está no
`baseline.err`, anterior à migração. A limpeza global do renderizador não está
certificada por este trabalho.

A tentativa final (`final.log`/`final.err`) foi interrompida ao identificar os
erros de compilação externos; não produziu comparação válida. A meta de 60 FPS
continua sem comprovação. Falta um comparativo renderizado do código final com o
projeto estável e sem outras sessões consumindo CPU/GPU. Não se ampliou o escopo
para corrigir ou sobrescrever o trabalho concorrente de ruas, passarela ou editor.
