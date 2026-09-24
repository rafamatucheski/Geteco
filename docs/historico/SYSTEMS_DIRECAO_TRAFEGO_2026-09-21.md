# Direção, tráfego e percurso — 21/09/2026

## Entrega

O protótipo continua independente do Geteco atual. Agora permite caminhar até o cupê dourado, entrar com F, dirigir, frear e sair. O carro utiliza o cupê original com quatro conjuntos de rodas animados, materiais próprios e luzes de freio; o mundo e os materiais estáticos da primeira versão foram preservados.

W acelera, S freia e engata ré, A/D esterçam e Espaço freia. A câmera segue o veículo e antecipa até seis metros na direção do movimento, mantendo giro e zoom manuais. F só permite sair praticamente parado; a saída testa cápsula completa, caminho até a lateral e piso. Não teletransporta o jogador através de uma parede para encontrar um ponto livre.

Seis carros circulam em duas rotas com curvas contínuas, em sentidos adequados nas duas faixas centrais. O avanço segue a posição física, sem teletransporte no fechamento da volta. Sensores a 10 Hz consideram espaço frontal e velocidade; os corpos também colidem fisicamente. O tráfego freia diante de pedestres e volta a andar quando a passagem fica livre.

O percurso de quatro paradas começa ao entrar no carro. Cada ponto exige o motorista dentro do veículo e velocidade abaixo de 0,5 m/s durante um segundo. Passar rápido, ir a pé ou parar fora da ordem não conta. A interface mostra distância, marcador no chão e seta quando o destino está fora da tela. R repete após concluir. O botão de voltar ao início recarrega a cena e restaura jogador, população, carro e tráfego.

## Verificações

- `validate_driving.gd`: 46 verificações sem falhas. Entrada distante recusada, entrada próxima, controles de aceleração e freio com eventos reais de teclado, saída em movimento recusada, porta alternativa, duas portas bloqueadas, colisão a 15 m/s contra objeto sólido sem atravessar ou subir, câmera e colisões restauradas ao sair.
- Os seis veículos percorreram aproximadamente 439 m cada em 80 s simulados e completaram voltas. Um NPC real interrompeu a passagem; o veículo parou antes dele e retomou após liberação.
- `validate_controls.gd`: 15 verificações sem falhas. Esterçamento, rodas, ré e limite de velocidade, pontos fora de ordem, passagem sem parar, visita a pé e reinício pelo botão real do menu enquanto dirigia.
- Regressão da primeira base: circulação dos 24 pedestres, colisões, spawns, câmera, pausa e variação de população continuam passando.
- `capture_driving.gd`: aproximação caminhando, entrada, aceleração, frenagem e saída verificadas na cena renderizada. Capturas `evidence/systems-enter.png`, `systems-driving.png`, `systems-exit.png` e `systems-overview.png`.

Os testes funcionais usam passo fixo acelerado, sem inferir FPS a partir deles. A execução renderizada e as medições abaixo são separadas.

## Desempenho antes/depois

Godot 4.7.2, Vulkan Mobile, RTX 4060 Laptop, 1280×720, MSAA 2×, VSync ligado, limite de 60 FPS. Cinco segundos de aquecimento e pelo menos trinta de amostra real por execução. Mesmo roteiro a pé e mesma população no comparativo; a versão nova mantém direção, atividade e tráfego ativos. A rota comandada é igual, mas colisões com tráfego podem alterar o progresso físico.

Critério: alvo de 60 FPS; aumento acima de 5% em p95/p99 requer confirmação, não aprovação automática. Os números abaixo não mostram esse aumento. O editor permaneceu aberto; nenhuma outra janela de jogo ou benchmark foi detectada nos inventários. O monitor foi corrigido para reconhecer o executável filho criado pelo próprio launcher de console; a tentativa anterior foi interrompida e não entrou no comparativo.

| Cenário | FPS médio | p50 (ms) | p95 (ms) | p99 (ms) | Máximo estável (ms) | Quadros >33,3 / >66,7 ms |
|---|---:|---:|---:|---:|---:|---:|
| Antes: a pé, 24 pedestres, 8 carros estacionados | 60,00 | 16,668 | 17,073 | 17,628 | 37,893 | 1 / 0 |
| Depois: a pé, 24 pedestres, carro dirigível + 6 em circulação | 60,00 | 16,668 | 17,010 | 17,440 | 37,964 | 1 / 0 |
| Dirigindo: 96 pedestres + 6 carros em circulação | 60,00 | 16,672 | 17,241 | 17,663 | 20,206 | 0 / 0 |

O cenário dirigindo usou o mesmo corpo, motor de movimento e colisões do jogador, com entradas automáticas de acelerador, volante e freio; percorreu 190,47 m, acompanhando uma rota existente do mapa. Essa amostra é uma referência inicial de direção, sem equivalente na versão anterior. As 96 pessoas estão distribuídas nos quarteirões, não simultaneamente enquadradas.

Estado: **sem regressão relevante no comparativo medido; média próxima de 60 FPS nos três cenários**. O quadro isolado de aproximadamente 38 ms ocorre tanto antes quanto depois; não é uma promessa de todos os frames em 16,67 ms. A janela inicial teve máximos de 286,84 ms antes, 40,08 ms depois e 87,39 ms dirigindo com 96 pessoas. A diferença inicial não é atribuída a uma correção de código: cache/aquecimento e ordem de execução podem influenciá-la. Construção síncrona da cena antes da coleta não está incluída.

Dados completos: `evidence/systems-before-isolated-population24.json`, `systems-after-isolated-population24.json`, `systems-driving-isolated-population96.json`, com os inventários `*-processes.json`. Foram registrados 32, 31 e 31 snapshots, sem concorrência externa além do editor. CPU e física constam nos JSONs; não houve perfil isolado de GPU.

## Limites desta etapa

Tráfego com rotas fixas, sem semáforos, planejamento de desvios ou mudanças de faixa. Veículos não atropelam nem aplicam dano: colisões bloqueiam passagem. O carro tem condução arcade em chão plano, sem suspensão ou áudio de motor. Oito carros vermelhos continuam sendo cenário estacionado; apenas o dourado aceita entrada. O percurso não grava progresso nem altera saves. Não foram acrescentados interiores, armas, missões do jogo atual ou carregamento regional.
