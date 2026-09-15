# Empunhaduras e efeitos — 13/09/2026

O rig de produção usa apoio nas duas mãos para pistola e escopeta serrada, palmas fechadas em torno dos cabos, pulsos orientados conforme cabo vertical ou apoio longitudinal e cotovelos voltados para baixo. Fuzis e escopeta giram o tronco para apoiar a coronha junto ao ombro. O taco fica elevado em guarda, com as mãos juntas no cabo, e percorre um arco no golpe. O rifle de caça usa o apoio dianteiro de madeira.

O RPG recebeu cabo de apoio, ogiva voltada para a frente e apresentação de tubo descarregado após o disparo. O projétil tem uma chama presa à traseira desde a primeira renderização, que acompanha suas mudanças de direção. O lança-chamas recebeu cabo dianteiro, válvula, suporte do reservatório e bico com ignitor. A emissão entra no mundo já na posição do bico; línguas de fogo sobrepostas e partículas formam o fluxo, e a cauda termina gradualmente. As curvas e texturas são compartilhadas. O clarão do bico usa a luz existente do jogador, sem empilhar uma luz por pacote de fogo.

As proporções e materiais continuam os do Dante estilizado do jogo. As referências reais orientam postura e contato, sem pretensão de equivalência fotográfica.

Referências visuais consultadas:

- [RPG apoiado no ombro, imagem de treinamento publicada pelo NDU](https://ndupress.ndu.edu/Media/News/News-Article-View/Article/1913099/ground-combat-overmatch-through-control-of-the-atmospheric-littoral/).
- [Registro de lança-chamas portáteis do Imperial War Museums](https://film.iwmcollections.org.uk/record/37925).
- [Exemplos fotográficos de empunhadura de pistola](https://www.policemag.com/articles/perfecting-your-handgun-grip).
- [API de polígonos texturizados do Godot 4.7](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-method-draw-colored-polygon).

## Verificações

- `test_player_combat_pose.gd`: 16 armas; contato da mão com o cabo, apoio, alinhamento, recuperação de recuo, mudança de postura e integração com o ataque real.
- `test_dante_weapon_clearance.gd`: 2.592 amostras, cobrindo repouso, caminhada, corrida, mira, disparo e recarga durante corrida; nenhuma interseção detectada com tronco, cabeça ou pernas.
- `test_manual_weapon_reload.gd`: recarga, reserva parcial, bloqueios de controle e atualização de munição; zero falhas.
- `test_melee_weapons_and_animations.gd`: golpes, catálogo, integração e rig de NPCs; zero assertions falhas. O teste legado relata recursos/RIDs remanescentes ao encerrar; esse encerramento não está certificado como livre de vazamentos.
- `test_dante_natural_gait.gd`: contato com o piso e oposição de braços/pernas; zero falhas.
- `test_weapon_effects_realism.gd`, renderizado: emissão no bico real, chama na traseira do foguete em quatro direções, tubo descarregado, alcance visual e encerramento dos pacotes de fogo; zero falhas.

Capturas dos 16 equipamentos, comparação de fontes e logs estão em `D:/geteco/artifacts/weapon-realism-0913/`. As capturas próximas e o vídeo são prévias isoladas do Player de produção. A medição abaixo usa HarborGame integrado, com NPCs, tráfego e resposta policial. Os ambientes e suas colisões não foram modificados ou certificados por este trabalho.

Prévia geral: `after/arsenal.png`. Animação de 28 segundos: `armas-em-movimento.mp4`, com transições, mira, recuo, recarga e corrida de pistola, escopeta, rifle, RPG, lança-chamas, taco e machado. Capturas dos disparos reais: `effects/rocket-launch.png` e `effects/flamethrower-stream.png`.

## Performance

Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, 1280×720, mesmo checkpoint diurno e sequência de disparos, 10 segundos de aquecimento e 30 segundos medidos. Saves redirecionados às pastas de evidências. Comparação principal com VSync/limitador desligados apenas nos processos de medição. Orçamento de referência: 16,67 ms; aumento de p95/p99 acima de 5% exigiria investigação.

| Métrica | Antes | Depois |
|---|---:|---:|
| Frames / duração | 1.855 / 30,017 s | 2.025 / 30,012 s |
| FPS médio | 61,80 | 67,47 |
| p50 | 15,639 ms | 14,308 ms |
| p95 | 23,089 ms | 20,948 ms |
| p99 | 30,265 ms | 28,436 ms |
| Máximo | 86,060 ms | 207,030 ms |
| Frames acima de 33,3 ms | 10 | 8 |
| Frames acima de 66,7 ms | 4 | 2 |

Não houve piora de p95/p99 na amostra, mas há travadas pontuais e o orçamento absoluto não foi atingido. Isso não certifica 60 FPS estáveis. O tráfego e a população evoluem durante a execução; a medição demonstra o comportamento observado, não isola causalmente cada alteração. Uma pequena alteração concorrente na fase do balanço dos braços em `Player.gd` foi preservada e não pertence a esta correção.

Dados brutos e configuração efetiva: `baseline/driving.csv`, `baseline/driving.json`, `performance-after/driving.csv` e `performance-after/driving.json` na pasta de evidências.

Execução adicional com o limite normal de 60 FPS: 1.677 frames em 30,008 s, média 55,88 FPS, p50 16,883 ms, p95 25,996 ms, p99 32,973 ms, máximo 83,993 ms, 15 frames acima de 33,3 ms e 2 acima de 66,7 ms. A configuração efetiva de VSync reportada pelo processo foi 0. Houve quatro viaturas policiais no pico, versus duas no comparativo sem limite. Evidências em `performance-normal/`; o cenário continua pendente em relação ao alvo de 60 FPS estáveis.
