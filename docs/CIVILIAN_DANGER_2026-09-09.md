# Reação civil a disparos

O pânico anterior escolhia um destino cotidiano, apenas aumentava a velocidade e expirava após cinco segundos sem renovação. Agora Bullet comunica os disparos reais de qualquer atirador aos civis próximos, inclusive tiros da polícia. A notificação acontece após a configuração do projétil, no primeiro passo de física, limitada a uma por atirador a cada 200 ms.

PedestrianDanger mantém até quatro origens/linhas de tiro. A fuga seleciona trajetos locais livres de prédios e veículos com margem lateral; evita atravessar as linhas de tiro conhecidas e favorece posições protegidas. Reavalia em intervalos de aproximadamente meio segundo, com verificação curta de obstáculos durante o movimento. Quando já protegido e afastado, o civil espera no abrigo. Não depende apenas de nível de procurado ou da presença de um policial.

Disparos novos renovam o medo por 9–12 segundos. Civis interrompem paradas e visitas; depois de silêncio, voltam à rotina com alguns segundos de caminhada mais lenta. Civis Cobra usam o mesmo comportamento; guardas armados preservam sua lógica de combate. WinterResident e residentes de eventos também interrompem diálogo e deslocamento de rotina para reagir ao perigo; o contador de histórias não continua falando durante a fuga.

## Verificação executada

- test_civilian_gunfire_response.gd: passou com Vulkan. Tiro produzido por PoliceOfficer real, presença policial sem pânico, interrupção de parada/diálogo, fuga física afastada do atirador e da linha de tiro, renovação do medo, destino sem atravessar parede, permanência atrás de cobertura e recuperação após silêncio. Polícia posicionada como fixture e disparo iniciado pelo teste.
- test_harbor_civilian_danger.gd: passou no HarborGame com população real e Vulkan. Quatro civis próximos assustados, três com deslocamento superior a 45 pixels em três segundos. Não foi demonstrada fuga longa para todos os quatro. Captura estática não constitui evidência de animação contínua. Um aviso ObjectDB no encerramento.
- test_police_vehicle_stop_live.gd: passou com Vulkan após integração da reação civil: retirada do motorista parado, prisão sem novo ataque, cancelamento quando o veículo se move, interação impedida por parede e pedestre sem empurrar viatura. Um aviso ObjectDB no encerramento.
- test_police_fair_arrest.gd: passou; quatro avisos ObjectDB no encerramento.
- git diff --check passou.

## Limites

A fuga é planejamento local com colisões, não um navegador global de interiores ou garantia de saída de qualquer labirinto. O teste do bairro não mede performance de perseguição prolongada. Ambulâncias, enterro, streaming por região e coreografia visual do Antigravity não são concluídos por esta mudança. Nenhum arquivo da pasta de protótipos do Antigravity foi alterado.
