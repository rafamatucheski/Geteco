# Postes e semáforos — 14/09/2026

Postes de iluminação e semáforos cedem a impactos veiculares a partir de 35 px/s na normal do contato. Postes e sinais legados exigiam 70 px/s; os sinais 3D atuais eram indestrutíveis. Caminhar continua encontrando uma base sólida enquanto o objeto está em pé.

O sinal 3D cai com modelo privado, lentes apagadas e base física desativada. A queda usa uma imagem maior para acomodar a extensão horizontal sem recortar o modelo, e termina abaixo dos veículos. A restauração recupera a colisão e o estado atual do controlador. O cache dos vizinhos não é alterado.

O posicionamento considera outros postes e semáforos, inclusive durante a construção no mesmo frame, com 40 px entre bases para reservar braços e caixas. Sinais procuram uma posição apoiada nos polígonos reais de calçada e livre de sólidos. A iluminação automática aplica a mesma separação; postes autorados conflitantes são reposicionados fora das pistas, acessos reservados e colisões estáticas. O registro de restauração acompanha a nova posição, impedindo retorno ao conflito original.

Validação em Godot 4.7.2:

- `test_street_lamp_impact.gd`: passou, incluindo contato físico a 40 px/s, queda, reparo, separação de duplicatas e posição preservada no registro de renovação.
- `test_fixed_traffic_signals.gd`: passou com renderização real; batida com veículo de produção, dano do carro, queda, ancoragem da base, isolamento do vizinho, lentes apagadas, reparo e limite 34/35 px/s.
- `test_street_lamp_fallen_depth.gd`: passou com Vulkan Mobile na RTX 4060 Laptop; carro encobre o poste caído dos dois lados, mantendo os destroços descobertos visíveis. Evidência: `D:/geteco/artifacts/post-lamp-depth-final.log`.
- `test_road_post_spacing.gd`: HarborGame com 460 objetos e porto + montanha com 502; 125.751 pares na cena conjunta, zero conflitos de espaçamento e zero bases intersectando outros corpos estáticos. A iluminação manteve zero lacunas nas 2.841 amostras do porto e 342 da montanha.

Evidências em `D:/geteco/artifacts/post-spacing-solids-final.log`, `post-lamp-final.log`, `post-signal-rendered-final.log` e `post-signal-fallen.png`. A execução integrada reportou recursos pendentes no encerramento; isso não foi atribuído nem corrigido por esta mudança. Os testes isolados finais de impacto e sinal terminaram sem esses erros.

A primeira carga integrada foi invalidada por erros transitórios em arquivos de áudio/ferrovia alterados simultaneamente; a carga usada nos resultados ocorreu depois de essas dependências serem corrigidas. Não há comparativo controlado de FPS: havia outros processos Godot ativos. As buscas de posicionamento acontecem na construção, sem uma varredura permanente por frame; o sinal só ganha renderização privada durante a queda. A meta provisória de 60 FPS / 16,67 ms continua sem certificação nesta tarefa. Os resultados cobrem as cenas e estados descritos, não garantem ausência universal de clipping em qualquer estado do mundo.
