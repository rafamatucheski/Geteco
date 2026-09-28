# Tanques e esmagamento — 28/09/2026

O tanque possui canhão utilizável por quem dirige e pela polícia, torre em 360°, elevação do cano, recuo, projétil varrido e explosão. Mira pelo mouse; botão esquerdo dispara. No controle, analógico direito mira e B/Círculo dispara, mantendo o gatilho direito para acelerar. A mira muda de cor durante os três segundos de recarga. A direção do veículo não altera a orientação escolhida pela mira.

O casco possui 3.000 pontos de vida e recebe 40% do dano de entrada. Sua massa de colisão é 30; a velocidade máxima é 13 m/s. O dano salvo é restaurado diretamente, evitando reaplicar a blindagem durante o carregamento. Reparos recuperam blindagem, pneus e casco esmagado.

O projétil viaja a 80 m/s por até 120 m: dano direto 180 e explosão de raio 5 m, até 100 de dano com queda pela distância. O alvo direto não recebe a explosão duas vezes. Paredes bloqueiam trajetória e dano radial; o próprio tanque, o atirador e entidades protegidas ficam excluídos. O tiro policial preserva seus aliados e limita o dano ao jogador a 55 direto/45 radial. Rendição interrompe disparos policiais e cancela projéteis policiais em voo; garagem, pausa e transições bloqueiam a arma. A autoria do jogador permanece mesmo que saia antes do impacto.

Onze WAVs originais substituem o som de caminhão/rifle: sete faixas diesel, partida, lagartas, disparo e impacto. As lagartas acompanham velocidade e ré independentemente do giro do motor. São recursos carregados e reutilizados; os mixers de NPC mantêm duas vozes por veículo. Detalhes em [audio/tank/README.md](../audio/tank/README.md).

## Colisão

Veículos com massa a partir de 3,0, incluindo os caminhões menores do catálogo, atravessam pessoas e derrubam postes sem perda percentual de velocidade, dano próprio ou tremor de câmera. Carros a partir de 22 m/s também conservam velocidade nesses impactos. Os limiares de contato continuam evitando atropelamento pelo simples encostar.

O tanque esmaga carros, SUVs e vans comuns a partir de 2,5 m/s. Caminhões, ônibus e veículos gigantes são excluídos por classe, massa e dimensões originais, inclusive quando possuem teto baixo. Os caminhões esmagadores mantêm a relação de massa mínima 2,5. Um carro a partir de 22 m/s consegue subir/esmagar outro quando tem pelo menos 20% mais massa e uma área maior que o alvo. Veículos equivalentes mantêm a colisão comum.

Ao esmagar, o alvo passa imediatamente para **destruído**: vida zero, motor inutilizado, lataria carbonizada, vidro destruído e uma única explosão com som/dano radial. O casco convexo achatado continua sólido, com bordas em rampa; `move_and_slide` sobe nele sem teleporte nem remover colisão entre os carros. A carcaça esmagada não usa o salto da explosão convencional. Gravidade e encaixe temporário de 4,5 cm produzem uma descida contínua. O fogo residual dura no máximo 11 segundos; garagem impede explosão e chamas. Recontato não repete explosão, e o veículo esmagador fica excluído do dano direto da detonação. A autoria é do motorista que provocou o esmagamento.

Paredes, tetos baixos, caminhões, ônibus, gigantes e alvos invulneráveis continuam bloqueando a passagem. Maciota e o mecânico permanecem protegidos inclusive por metadado em ancestral. `heavy_crush_ratio` é validado e salvo junto ao veículo selecionado e aos veículos da garagem. A restauração aplica o casco achatado antes da consulta de espaço e não repete explosão nem reinicia o fogo. Reparo restaura visual, colisor, altura e estado anterior do motor.

## Validação

Evidências da primeira implementação em `evidence/tank-control-20260928/`, sempre com `--no-save --skip-arrival` nos testes da sessão:

- Canhão: 41 checks; terrestre policial: 35 checks.
- Main com entrada/saída animada, input, mira, recarga, bloqueios e persistência: 31 checks.
- Esmagamento/atropelamento/postes/proteções: 46 checks; conservação de momento: 21; dano de colisão: 10.
- Áudio do tanque: 38 checks; migração de sons, áudio próximo e veículos de serviço também aprovados.
- Garagem: recompensas 47; restauração do motorista 26; transferência 11.

Os logs finais desses testes não apresentam erros de script. A primeira execução de Main/áudio encontrou um arquivo de motocross em alteração por outra sessão; foi preservado, e a validação final foi executada após sua correção. O teste antigo de áudio próximo esperava 25 frames para um fade temporal; o backup anterior reproduziu a mesma falha, e a fixture passou a aguardar seleção + fade em segundos, mantendo a assertion original.

Revisão de destruição automática: 72 checks de impactos e 42 de integração aprovados. `test_crush_explosion.gd` usa Main, ProductionWorld, Gameplay e os materiais reais para validar explosão única, autoria jogador/NPC, fallback, proteção, casco de suporte, reparo, garagem sem chamas e restauração silenciosa sob teto baixo. O caso legado (save de carro achatado ainda vivo) só destrói na próxima passagem, uma vez. Logs e novas imagens em `evidence/tank-crush-explosion-20260928/`. As 84 verificações da garagem e as 41 do canhão também passaram; recompensas da garagem ainda avisam sobre duas instâncias no encerramento da fixture.

`capture_tank_main.gd` usa o mapa Main renderizado, pista e colisão reais, com disparo/destruição e avanço do tanque sobre o carro achatado. A revisão visual confirmou `health=0`, `wrecked=true`, `exploded=true` e subida de 0,32 m sobre o casco queimado. As capturas registram avisos de textura/RID ao encerrar, distintos dos testes funcionais. Os PNGs e seus contadores momentâneos não são benchmark; carga, gravação de PNG e outras sessões interferem neles.

**Performance pendente:** não há comparação renderizada controlada antes/depois. Jogo/editor e testes de outras sessões continuaram ativos na mesma GPU; nenhum processo alheio foi encerrado. Meta provisória 60 FPS/16,67 ms em RTX 4060 Laptop, 1280×720, renderer Mobile; tolerância de investigação 5% em p95/p99. Scripts anteriores e áudio foram preservados em `before/` para o comparativo. O custo novo é limitado: até dois projéteis por canhão, física do canhão adormecida quando ocioso, consultas locais de colisão e sem nova luz. Esses limites não substituem medição. A qualidade perceptiva do mix também depende de audição na sessão do jogador.
