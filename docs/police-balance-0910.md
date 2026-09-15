# Ajuste de sensibilidade policial — 10/09/2026

O jogador recebia pontos por mortes e atropelamentos de civis e policiais
causados por NPCs. Os caminhos de dano agora respeitam a autoria recebida do
projétil ou veículo. Explosões de veículos propagam a autoria do dano que
iniciou a combustão, inclusive depois de o motorista sair.

## Regras

| Estrelas | Pontos mínimos | Espera inicial | Intervalo de despacho |
| --- | ---: | ---: | ---: |
| 1 | 12 | 6 s | 18 s |
| 2 | 30 | 3 s | 14 s |
| 3 | 60 | 1 s | 10 s |
| 4 | 100 | 1 s | 8 s |
| 5 | 160 | 1 s | 6 s |
| 6 | 240 | 1 s | 4 s |

- Um atropelamento não fatal atribuído ao jogador vale 6 pontos. Uma ocorrência
  isolada fica sem estrelas e expira após 12 segundos sem novos relatos.
- Ocorrências repetidas dentro dessa janela acumulam. Patrulhas a pé também
  respeitam o mínimo necessário para iniciar perseguição.
- Morte de civil ou denúncia concluída de roubo de carro vale 20 pontos.
  A denúncia usa o prazo do gerenciador, sem despachar uma viatura extra de imediato.
- Furto de viatura mantém pelo menos duas estrelas e despacho urgente. O próximo
  reforço respeita o intervalo normal, eliminando o segundo despacho após 0,2 s.
- Ao perder estrelas, os pontos também diminuem; uma ocorrência leve não restaura
  imediatamente o nível anterior. A API de mínimo de estrelas preserva eventos
  de missão, e a restauração de saves normaliza pontos sem apagar estrelas salvas.
- O limite continua em uma viatura por estrela, até quatro simultâneas.

## Verificação

`tests/test_police_sensitivity.gd` cobre tolerância, expiração, reincidência,
tempos de resposta, redução de estrelas, saves antigos, autoria de vítimas civis
e policiais, patrulha a pé e explosões dos três tipos de veículo.

Regressões relacionadas: `test_police_car_alarm_theft.gd`,
`test_police_fair_arrest.gd`, `test_vehicle_crash_and_explosion.gd` e
`test_harbor_police_multi_dispatch.gd`. Execução headless no Godot 4.7.2.
