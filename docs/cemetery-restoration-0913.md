# Restauração pontual do cemitério e vegetação — 13/09/2026

- A casa existente permanece em `Cemetery + (-235, -245)`, no canto noroeste. Sua presença foi reproduzida na abertura direta de HarborGame; o desaparecimento original não foi reproduzido. Acrescentado refresh do render estático ao entrar na tela. A colisão externa agora deriva da malha das paredes, preservando o footprint anterior. A porta existente continua registrada no gerenciador de interiores.
- Anselmo estava sujeito à suspensão de pedestres por distância enquanto caminhava no interior remoto. O residente agora usa `simulation_keep_alive`; a renderização continua limitada por proximidade. Corrigida também a saída matinal a partir de `home_evening` quando o relógio salta a noite. Morte persistente, sono, diálogo e hostilidade não foram removidos.
- Reutilizado MountainPine3D sem neve: 8 coníferas internas, 8 árvores no canteiro leste de Memorial e 12 no entorno do Neco. Renders são compartilhados por espécie e pai, sem viewport por árvore. Removidas as árvores pintadas sob Memorial North e os círculos vegetais do pátio. A casa, a passagem de serviço e a estrada do guincho têm áreas livres.

## Checks executados

APPDATA isolado em `D:/geteco/artifacts/cemetery-*-user` / `cemetery-check-user`; nenhum save do usuário usado.

- `tests/check_cemetery_restoration.gd -- checks`: passou. HarborGame real, percurso espontâneo de Anselmo com streaming, varredura das paredes com jogador e coveiro, portão, passagem de serviço, retorno, entrada e saída com Player real, árvores fora das ruas e colisão dos troncos. Log: `D:/geteco/artifacts/cemetery-checks-final.log`.
- `tests/check_cemetery_restoration.gd -- yard`: passou. Novos troncos do Neco bloqueiam Player; distância mínima de 100 px à linha central da estrada de acesso. Log: `D:/geteco/artifacts/cemetery-yard-checks.log`.
- `tests/test_cemetery_keeper_home.gd`: passou, incluindo proteção contra suspensão remota e regressões existentes de sono, intrusão, pista e morte persistente. Log: `D:/geteco/artifacts/cemetery-home-final.log`. Aviso preexistente de dois ObjectDB no encerramento.
- O primeiro check da passagem detectou um NPC visitante no início da varredura. O check de sólidos isola esse visitante temporariamente; o percurso real de Anselmo acima mantém todas as colisões normais. A primeira tentativa de saída antecipava a reativação da porta; o check passou após respeitar a transição.
- Capturas renderizadas inspecionadas: `D:/geteco/artifacts/verified-Cemetery.png` e `D:/geteco/artifacts/verified-ChopShopZone.png`.

## Checagem pontual de performance

Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, 1280×720, zoom .85, meio-dia, limite normal de 60 FPS, 90 frames de aquecimento e 30 segundos de amostragem por local. Meta provisória: 60 FPS / 16,67 ms; variação de p95/p99 acima de 5% exige investigação, não aprovação automática.

| Local | Antes FPS / p95 / p99 | Última amostra FPS / p95 / p99 |
|---|---|---|
| Cemitério | 58,13 / 20,64 / 27,27 ms | 50,07 / 26,14 / 29,35 ms |
| Neco | 59,98 / 18,40 / 21,58 ms | 59,55 / 19,95 / 24,06 ms |

Logs: `cemetery-before.log` e `cemetery-verified.log` em `D:/geteco/artifacts/`. Houve alteração externa de RenderQuality.gd durante o trabalho (inclusive correção da leitura de shadow_key), com erros de configuração de luz nos logs intermediários. Assim, o comparativo não isola estas mudanças. Performance **pendente**, especialmente no cemitério; não aprovada nem atribuída exclusivamente às árvores. Sem nova rodada ampla de diagnóstico, conforme escopo solicitado.

Não houve reconstrução do cemitério nem reforma do interior. A profundidade de todos os móveis do interior legado não foi certificada por estes checks. Gameplay e revisão visual final ficam com o usuário conforme combinado.
