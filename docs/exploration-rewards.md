# Exploração e conquistas

Cada descoberta conhecida paga $50. Encontrar 3, 5 e 10 itens diferentes concede
bônus adicionais de $100, $200 e $500. Isso financia o equipamento e os serviços
já existentes no jogo. São dez itens catalogados, incluindo as evidências da
montanha; IDs antigos desconhecidos continuam salvos, mas não inflam metas.

As conquistas têm recompensas únicas de $50 a $400, definidas em
`AchievementCatalog.CASH_REWARDS`. Seus nomes, requisitos e valores aparecem
no menu de pausa antes do desbloqueio. A tela Colecionáveis mostra o próximo
marco e seu bônus. A antiga promessa de pista de carro a cada vinte itens foi
substituída por bônus alcançáveis; o campo legado de pistas continua no save.

`collectibles_found` e `unlocked_achievements` são os recibos persistidos. Repetir
coleta, reler evidência ou carregar um save não repete dinheiro ou áudio. Critérios
já cumpridos em saves antigos e no estado inicial são reconciliados sem prêmio
retroativo e sem notificação. Novas conquistas durante gameplay pagam uma vez.

Descoberta: 1,15 s. Conquista: 2,4 s. Mesmos instrumentos sintetizados da vinheta
original aprovada, com frases distintas. A conquista espera o som da descoberta;
vários desbloqueios entram em fila. O som de missão aprovado de 4 s não mudou.

Validação dirigida: `test_exploration_rewards.gd`, `test_achievement_startup.gd`,
`test_pause_collectibles_screen.gd`, `test_reward_audio.gd`. Evidências em
`D:/geteco/artifacts/exploration-rewards-0913`. Não houve certificação de FPS.
