# Veículos — terceira leva, 24/09/2026

## Resultado e limite

Foram reproduzidos e corrigidos dois defeitos no roubo de um carro que sofreu uma batida. **A queda para baixo do terreno observada entre 02:21 e 02:23 no vídeo não foi reproduzida; sua causa permanece aberta.** Os quadros são compatíveis com queda vertical: a rua sobe no enquadramento, o carro aparece como silhueta e termina no vazio com velocímetro 00. Isso não demonstra por si só a causa física.

O caminho de morte em FullSession que mantinha vida cheia foi comunicado ao agente principal, responsável pela correção e teste separados. Não foi alterado nesta frente.

## Causa demonstrada e correção

- Uma colisão real deixa impulso em `crash_slide/crash_spin`, separado de `velocity/horizontal_velocity`. Zerar apenas a velocidade de direção deixava o cupê deslizar **3,227 m** durante a apresentação que mantinha porta e assento fixos, embora o velocímetro marcasse zero. `Vehicle.stop_boarding_motion` agora encerra também esse impulso residual e seu temporizador durante a transferência.
- A batida suspende `traffic` e guarda `crash_was_traffic`. O roubo verificava apenas `traffic`, portanto não retirava a propriedade de trânsito; a recuperação do impacto podia reativar a IA durante o embarque. Isso ocorreu no frame 72 do caso de recuperação, ainda com a apresentação ativa. `Driving._begin_entry` reconhece também essa origem temporariamente suspensa e remove a retomada pendente, a propriedade ambiente e ejeta o motorista pelo mesmo fluxo normal.

São alterações pontuais nesses dois métodos. Alterações anteriores dos mesmos arquivos foram preservadas. Não foram alterados terreno, gravidade, limites de FPS, comportamento geral de colisão nem o sistema de impacto.

## Evidência funcional

`tests/test_video_phase3_vehicle.gd` carrega Main real, com pavimento/streaming e física dos veículos ativos, sem saves, tráfego aleatório ou DispatchController. O preparo posiciona os carros na faixa do Westgate junto ao Maciota; os trechos observados usam a interação normal e a apresentação completa. O caminho de polícia legado de Gameplay permanece ativo; não se trata de uma cena vazia de toda reação ao crime.

Casos: cupê parado; sedan a 7 m/s; cupê imediatamente após colisão real; cupê 1,2 s após a colisão. Cada caso inclui embarque e desembarque. Um impacto adicional contra o cupê já ocupado prova que a correção não desativa a física: o novo impacto continua empurrando e danificando o veículo.

- Antes: **67 verificações, 3 falhas**, guardadas em [JSON](phase3-vehicle-before.json) e [log](phase3-vehicle-before.log).
- Depois: **78 verificações, 0 falhas**, guardadas em [JSON](phase3-vehicle-after.json) e [log](phase3-vehicle-after.log).
- Regressão preexistente `tests/test_vehicle_body_transitions.gd`: **21 verificações passaram, exit 0**, cobrindo reversão, interrupção por morte e remoção; [log](phase3-vehicle-body-regression.log). Esse harness emitiu no encerramento aviso de 4 instâncias ObjectDB / 1 recurso ainda retidos. O novo teste de 78 verificações e a captura não emitiram esse aviso; não foi alterado o teardown do teste preexistente nesta frente.
- Integração adicional das garagens, executada sequencialmente com `--no-save --no-traffic --population=0`: `test_garage_driver_restore.gd` **26 checks, exit 0**, [log](phase3-garage-driver-restore.log); `test_garage_vehicle_transfer.gd` **11 checks, exit 0**, [log](phase3-garage-vehicle-transfer.log). Cobrem motorista restaurado, admissão do casco, restrição de armas, câmera e transferências Maciota/garagem do chefe. O segundo harness emitiu no encerramento aviso de 18 instâncias ObjectDB / 5 recursos retidos.
- Erro de âncora no cupê recém atingido: 3,227 m → 0.
- Nos quatro casos finais, nenhum frame observado perdeu contato real com o piso; altura do carro entre 0,000145 e 0,000942 m; maior deslocamento entre passos de física de 0,11613 m no roubo em movimento.
- Sem IA retomada, teleporte detectado, resíduo de deslocamento vertical do personagem ou portas substitutas visíveis após fechar.

Comando:

```powershell
& 'D:/Downloads Chrome/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe' --headless --path 'D:/geteco/game' --log-file 'D:/geteco/game/evidence/video-review-20260924/phase3-vehicle-after.log' --script res://tests/test_video_phase3_vehicle.gd -- --no-save --no-traffic --no-dispatch --population=0 --report=phase3-vehicle-after.json
```

Não cobre toda a rota do vídeo, todos os modelos, impactos novos durante a animação, restauração de todos os saves nem travessia de regiões. O resultado não permite encerrar o achado original de queda abaixo do mapa.

## Validação renderizada e performance

A captura usa `tests/capture/video_phase3_vehicle.gd`, herdando o mesmo cenário e mantendo física/câmera reais, para sedan em movimento e cupê recém atingido. Os arquivos `phase3-vehicle-captures.json` e `phase3-vehicle-render-physics.json` registram imagens, coordenadas e verificações da execução renderizada.

Render concluído, processo 25492 encerrado: **47 verificações, 0 falhas**, stderr vazio; oito PNGs de 2560×1440, Godot 4.7.2 / Mobile / RTX 4060 Laptop. A janela reporta 3440×1440 e o viewport capturado 2560×1440. As oito imagens foram abertas e inspecionadas: carro sobre o asfalto, Dante de pé ao final, portas fechadas sem folhas substitutas extras, minimapa visível nos quatro estados de cada carro. Os cacos no asfalto ao lado do cupê vêm da colisão real. Uma resposta policial legada aparece durante esse segundo caso, sem falhas das verificações.

| Fluxo | Entrada inicial | Sentado | Saída inicial | Em pé |
|---|---|---|---|---|
| Sedan em movimento | [PNG](phase3-vehicle-moving_sedan-entry-020.png) | [PNG](phase3-vehicle-moving_sedan-entry-179.png) | [PNG](phase3-vehicle-moving_sedan-exit-020.png) | [PNG](phase3-vehicle-moving_sedan-exit-159.png) |
| Cupê após impacto | [PNG](phase3-vehicle-fresh_impact_coupe-entry-020.png) | [PNG](phase3-vehicle-fresh_impact_coupe-entry-179.png) | [PNG](phase3-vehicle-fresh_impact_coupe-exit-020.png) | [PNG](phase3-vehicle-fresh_impact_coupe-exit-159.png) |

**Performance não medida.** O jogo do usuário continuou aberto; os testes e as capturas não são baseline comparável nem aprovação de FPS. O novo trabalho ocorre no embarque/desembarque, sem novo loop por frame.
