# Alcance e perda de força das armas

Valores em unidades do mundo, independentes do zoom. Na referência 1280×720 com zoom 1,8, a largura visível é aproximadamente 711 unidades. O alcance começa no cano; golpes corpo a corpo usam a distância entre atores. Balas mantêm a velocidade anterior.

| Arma | Dano cheio até | Alcance máximo | Dano mínimo no limite |
|---|---:|---:|---:|
| Punhos | 30 | 46 | 65% |
| Soqueira | 32 | 48 | 65% |
| Faca | 28 | 40 | 65% |
| Taco | 42 | 62 | 65% |
| Machado | 44 | 66 | 65% |
| Pistola | 170 | 420 | 25% |
| Magnum | 230 | 550 | 35% |
| SMG | 140 | 380 | 20% |
| Escopeta | 85 | 280 | 15% por chumbo |
| Serrada | 60 | 200 | 10% por chumbo |
| AK-47 | 300 | 700 | 35% |
| M4A1 | 330 | 750 | 40% |
| Rifle de caça | 480 | 950 | 50% |
| Lança-chamas | 55 | 140 | 25% |

Interpolação linear entre as duas distâncias, arredondada para HP inteiro, com mínimo de 1 HP dentro do alcance e zero fora. Exemplo: pistola causa 16 HP até 170, 10 HP a 300 e 4 HP a 420. O disparo é interrompido exatamente no limite, inclusive quando um frame longo passaria dele. O tempo de vida de 2 segundos continua como limpeza de segurança.

Rebalanceamento de 14/09: dano-base da pistola 12→16, magnum 30→38, SMG 8→10, escopeta e serrada 6→8 por chumbo, AK 15→18 e M4 13→16. Lenhadores causam 28 por golpe, independentemente dos 52 do machado do jogador. Alcances, cadências e quantidade de projéteis permanecem iguais; alteração apenas de valores de dano, sem novos efeitos ou trabalho por frame. Não foi medido FPS nesta alteração.

A intensidade do impulso das balas acompanha a fração de dano restante. Sangue, áudio, reação à lesão e marca de contato recebem o dano reduzido. A dispersão original das escopetas continua funcionando junto da queda por distância.

RPG: voo máximo 650; mantém a carga de 95 HP, raio 140 e redução radial já existente até zero na borda. Ao esgotar o voo, explode como já fazia ao esgotar o tempo de vida. Granada: percurso máximo 320, raio 120, dano central de catálogo 80; conserva fusível, quique e redução radial. O jogador antes ignorava o catálogo e usava o padrão de 180 HP da cena. O alcance solicitado do arremesso agora é limitado a 60–320; obstáculos e atrito podem encurtar o percurso real. Explosivos não perdem carga por distância do lançador.

Lança-chamas: 3 HP de contato perto e 1 HP na ponta, sem contato danoso além de 140. A queimadura posterior conserva sua duração e dano próprios. Golpes na extremidade do alcance causam cerca de 65% do dano; animações e tempos de contato foram preservados.

Perfis aplicados ao jogador e aos disparadores de NPCs: polícia a pé, passageiros da viatura, gangsters, Cobras e zelador do cemitério. Danos-base específicos dos NPCs foram preservados. Golpes dos gangsters também usam queda por distância; o lenhador já limita seu contato a 44, dentro da faixa de dano cheio do machado.

## Validação

Godot 4.7.2. Execução headless de `tests/test_weapon_range.gd`: zero falhas. Exercita acertos reais próximos/distantes, todos os projéteis convencionais além do limite em um frame longo, primeiro sólido bloqueando o segundo alvo, dano monotônico, chama perto/longe/fora, limite de percurso da granada, integração real de disparo do jogador para cada arma e golpes reais na extremidade.

Regressões aprovadas: `test_shot_feedback.gd`, `test_person_weapon_effects.gd`, `test_knife_single_target.gd`, `test_melee_weapons_and_animations.gd`, `test_police_vehicle_combat.gd`, `test_garage_weapon_restrictions.gd`. Alguns runners existentes reportam recursos/RIDs pendentes ao encerrar (principalmente o de animações); suas assertions passaram. O novo teste de alcance encerrou sem esses avisos.

Logs: `D:/geteco/artifacts/weapon-range/`.

## Performance: inconclusiva

Risco: uma soma e limitação de distância por projétil/frame, com cálculo do dano apenas no contato; nenhum novo nó ou efeito por projétil. Alcances menores encerram projéteis mais cedo. Referência provisória: 60 FPS / 16,67 ms; sinal de investigação: aumento acima de 5% em p95/p99.

`tests/measure_weapon_range.gd`: HarborGame real, 1280×720, zoom 1,8, dia/tempo fixados, disparos SMG a cada 0,11 s, 300 frames de aquecimento e janela de 30 s, VSync desligado/sem limitador, RTX 4060 Laptop, Vulkan Mobile.

| Medida | Antes | Depois |
|---|---:|---:|
| Frames | 1966 | 1292 |
| FPS médio | 65,52 | 43,05 |
| p50 ms | 14,69 | 19,98 |
| p95 ms | 20,44 | 33,13 |
| p99 ms | 27,65 | 43,77 |
| Máximo ms | 259,59 | 361,07 |
| Frames >33,3 ms | 8 | 62 |
| Frames >66,7 ms | 5 | 7 |

As medições NÃO certificam desempenho nem estabelecem causalidade: outros processos Godot renderizados/headless e alterações simultâneas do mapa foram observados entre as coletas (incluindo medição de ruas e captura de ambulância). As condições de carga não ficaram constantes. Não foi encerrado nenhum processo de outra tarefa. É necessária nova comparação isolada quando essas tarefas terminarem; o orçamento não está aprovado. Dados brutos e captura estão em baseline.json/png e after.json/png na pasta de artefatos. A captura final foi inspecionada; a validação visual de combate próximo/distante em todas as armas permanece limitada aos contratos automatizados, não a uma sessão manual completa.
