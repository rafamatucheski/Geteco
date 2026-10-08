# Parque Lume — 07/10/2026

Parque opcional em Harbor/cidade 1, no lote oeste centrado em `(-176, 0, 78)`, com acesso pela rua em `(-125, 0, 94)` e marcador **Parque Lume** no mapa. O conteúdo não depende de missão, não cobra entrada e não altera os bloqueios da campanha. Trabalho dividido entre dois agentes: atrações/geometria e cosméticos/persistência; integração e validação da sessão pelo agente principal.

## Conteúdo jogável

- Montanha-russa com carrinho, trilhos e apoios, embarque pela plataforma, velocidade acompanhando as rampas, câmera em perspectiva e olhar livre. A volta termina na estação; também é possível encerrar antes. Colisão, câmera, controles e HUD são restaurados, inclusive no resgate por morte.
- Casa **Umbra**, um interior independente em primeira pessoa: circuito contornando palco, móveis sólidos, fantasma mecânico de proximidade, três lanternas fixas e saída com indicador compacto. O fantasma não ataca; a visita não é obrigação da campanha.
- Seis segredos: Jaqueta Lume, Casaco Meia-noite, Óculos Estrela, Óculos Âmbar, Máscara Fantasma e Máscara Raposa. Quatro estão no parque e dois na casa. Coleta por proximidade e linha de visão, persistente e sem duplicação.
- Cabine de troca no parque. Roupas, óculos e máscaras podem ser combinados; acessórios acompanham o osso da cabeça do Dante. Saves anteriores sem a chave opcional continuam válidos.

O parque tem piso contínuo e limite de acesso aos trilhos. Somente a vegetação do lote e de sua ligação pedonal foi reservada; a malha viária permanece como estava. A geometria é preparada durante o carregamento, admitida por proximidade e liberada quando distante. Não há SubViewport novo nem NPC residente. A fachada usa apenas nomes próprios.

## Evidência funcional e física

Ambiente: Godot **4.7.2 .NET**, `Harbor.csproj` compilado com zero erros/avisos. Main renderizado com roteador C# verificado; saves de fixture isolados, sem escrita no progresso pessoal.

| Validação | Resultado | Evidência |
| --- | --- | --- |
| Geometria e colisão | **440/440**: apoio, cápsulas de jogador/NPC, paredes, móveis, cercas, degrau exclusivo da estação, porta, seis pickups e rota completa | [log](../../evidence/amusement-park-geometry-step-door-20261007.log), `tests/test_amusement_park_geometry.gd` |
| Recompensas e persistência | **43/43**: coleta única, obstrução, bloqueios de estado, combinação, remoção, reentrada, save real isolado e corrupção | `tests/test_amusement_park_rewards.gd` |
| Sessão produtiva renderizada | **56/56**: caminhada rua→parque→plataforma, cancelamento/pausa/volta completa, entrada/saída da casa, circuito, seis coletas, interface de troca, morte/resgate e descarregamento | [resultado](../../evidence/amusement-park-session-118032-6134516/result.json), [log](../../evidence/amusement-park-session-verified.log) |
| Teclado, controle e toque | **19/19**: AndroidControls/GameInput reais, multitouch independente, deadzone, modal/pausa, botão acionado por eventos reais de mouse/toque e dica de teclas no desktop | `tests/test_amusement_park_input.gd` |

Fotos reais da sessão: [entrada](../../evidence/amusement-park-session-118032-6134516/gate.png), [estação](../../evidence/amusement-park-session-118032-6134516/station.png), [casa](../../evidence/amusement-park-session-118032-6134516/house_entry.png), [guarda-roupa](../../evidence/amusement-park-session-118032-6134516/wardrobe.png).

## Desempenho renderizado

RTX 4060 Laptop, Mobile/Vulkan, 1920×1080, VSync ligado e limite normal de 144 FPS, clima seco. Alvo provisório: 60 FPS / 16,67 ms; aumento acima de 5% em p95/p99 exige investigação. Fixtures iniciais idênticas, C# ativo. Cada janela estável tem 30 s; leitura da imagem ocorre fora da amostra. Nenhum benchmark concorrente foi observado na auditoria do final: somente o processo console e seu filho de jogo. FPS limitado não mede a capacidade máxima nem substitui os percentis.

| Dia, cenário | FPS antes → final | p50 antes → final (ms) | p95 antes → final (ms) | p99 antes → final (ms) | Máximo final (ms) / frames >33,3 / >66,7 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Entrada | 143,94 → 144,01 | 6,601 → 6,835 | 11,777 → 11,144 | 14,745 → 13,754 | 21,190 / 0 / 0 |
| Vista geral | 143,96 → 143,99 | 6,328 → 6,333 | 10,504 → 10,117 | 13,418 → 12,850 | 17,392 / 0 / 0 |
| Passeio, novo cenário | 143,13 | 6,967 | 9,547 | 12,245 | 29,450 / 0 / 0 |
| Casa, novo cenário | 144,01 | 6,968 | 8,456 | 11,423 | 12,057 / 0 / 0 |

[Baseline e amostras](../../evidence/amusement-park-baseline-189940-6435239/report.json), [final e amostras](../../evidence/amusement-park-final-187008-6177175/report.json), [auditoria dos processos](../../evidence/amusement-park-final-processes.jsonl), [vista geral final](../../evidence/amusement-park-final-187008-6177175/overview.png), [casa final](../../evidence/amusement-park-final-187008-6177175/house.png).

Não houve regressão observada nas duas janelas externas estáveis diurnas. O passeio e o interior ficaram dentro do alvo nos percentis, mas os máximos de 21/29 ms mostram que nem todo quadro cumpriu 16,67 ms. Primeira visita medida separadamente por 8 s: máximo **168,492 → 160,755 ms**, dois frames >33,3 ms e um >66,7 ms em ambos; p99 **12,600 → 13,635 ms** (+8,21%). Há um travamento pontual de carregamento já presente no baseline; não atribuir melhora causal nem aprovar ausência de engasgo de primeira visita.

O final manteve os 41 arquivos monitorados estáveis. O baseline diurno anterior à instrumentação não registrou hashes. Os contadores de população/tráfego foram tomados somente ao terminar, já em local diferente no final (casa): não comprovam igualdade de carga ao longo de cada cenário. Não há tempos separados de CPU/GPU. Após a medição diurna foi acrescentado somente o retorno imediato do runtime durante pausa; os caminhos ativos medidos foram preservados.

Comparativo noturno seco, com a correção de pausa e fontes idênticas entre os dois processos, também estáveis dentro de cada execução:

| Noite, cenário | FPS antes → final | p50 antes → final (ms) | p95 antes → final (ms) | p99 antes → final (ms) | Máximo final (ms) / frames >33,3 / >66,7 |
| --- | ---: | ---: | ---: | ---: | ---: |
| Entrada | 144,02 → 144,00 | 6,956 → 6,653 | 11,567 → 11,810 | 13,911 → 13,992 | 19,711 / 0 / 0 |
| Vista geral | 143,68 → 143,85 | 6,628 → 6,095 | 10,100 → 10,256 | 12,910 → 13,102 | 14,253 / 0 / 0 |

[Baseline noturno](../../evidence/amusement-park-baseline-night-188628-6208266/report.json), [final noturno](../../evidence/amusement-park-final-night-165160-6198663/report.json), [processos antes](../../evidence/amusement-park-baseline-night-processes.jsonl) e [depois](../../evidence/amusement-park-final-night-processes.jsonl). Maior aumento estável: **2,10% no p95 da entrada**, abaixo do limiar de investigação. Contagens ao fim: população/tráfego **40/7 → 38/5**; a simulação ambiente não foi congelada. As amostras não isolam causalidade nem certificam carga máxima de trânsito. Primeira visita noturna: pico **169,466 → 170,640 ms**, um frame >66,7 ms em ambas. Nenhum motor concorrente registrado. Desempenho observado dentro do alvo nos percentis dos cenários medidos; a ressalva de carregamento permanece.

## Profundidade, iluminação e pausa

`tests/capture/capture_amusement_park_temporal.gd` passou **49/49** no Main/.NET: [relatório completo](../../evidence/amusement-park-temporal-181056-6007320/report.json). A saída fica oculta quando atrás da câmera e o indicador usa a projeção da câmera em primeira pessoa ao olhar para a porta. Pausa real de 0,3 s manteve relógio do parque, câmera e fantasma inalterados. A [descida](../../evidence/amusement-park-temporal-181056-6007320/coaster-descent.png) mostra trilhos e terreno próximo contínuos.

Oclusão verificada independentemente da física: alvo visível e o mesmo frame com somente o alvo oculto, câmera e iluminação fixas. Fantasma visível: **4.705 pixels** de diferença; máscara no corredor: **712**. Os dois alvos atrás da divisória: **zero pixels**. Fotos [fantasma visível](../../evidence/amusement-park-temporal-181056-6007320/depth-ghost-visible.png), [parede ocluindo](../../evidence/amusement-park-temporal-181056-6007320/depth-ghost-behind-wall.png), [segredo visível](../../evidence/amusement-park-temporal-181056-6007320/depth-secret-visible.png) e [segredo ocluído](../../evidence/amusement-park-temporal-181056-6007320/depth-secret-behind-wall.png). Dante oculto pela própria câmera e ausência de moradores tornam oclusão visual de atores não aplicável a esta sala; cápsulas físicas de jogador/NPC foram verificadas separadamente.

Sequências contínuas de noite seca: parque **757 frames / 29,987 s**, casa **786 frames / 29,990 s**, estático→movimento→estático, **zero lacunas no contador de renderização** e zero falhas de gravação. Três fontes locais no exterior e três no interior, sem duplicação, com estado registrado por segundo. Fonte estável durante a execução. Captura em 1280×720, imagens JPEG 480×270 e limite temporário de 30 FPS; readback/gravação reduzem a cadência, portanto essa sequência não mede desempenho.

[Análise dos 1.543 frames](../../evidence/amusement-park-temporal-181056-6007320/pixel-analysis.json): nos trechos parados, 348 pares da casa tiveram diferença central zero; 104 pares do parque tiveram diferença média máxima de 0,187/255, sem pixel acima de 32/255. Nos pares de maior variação inspecionados, as mudanças acompanharam giro/retorno da câmera externa aos 15,09 s e movimento lento no interior, sem apagão observado. A borda do halo/sombra no teto traseiro apresenta serrilhado estático visível; não foi classificada como flickering nem corrigida alterando a qualidade global.

A revisão de regiões estáticas e pares de frames não equivale à observação humana integral em reprodução contínua. A certificação temporal integral permanece pendente; não extrapolar para chuva, todas as horas do dia, todos os percursos ou Android físico. O checklist mantém explicitamente essa pendência.

## Acabamento dos acessórios

A captura frontal revelou interferência visual entre máscara de raposa e óculos estrela. O ajuste final rebaixou/reduziu a máscara e suas orelhas e aproximou os óculos do rosto (`z .125 → .085` no espaço de autoria). Mantidos os mesmos materiais e objetos estáticos, sem adicionar luzes, animação ou processamento por quadro. Não houve alteração de estado/persistência neste acabamento.

Prova dirigida com Dante e esqueleto reais, câmera/luz fixas, **14 retratos**: rosto livre, cada um dos dois óculos, cada uma das duas máscaras e duas combinações, nas vistas frontal e três quartos. Fotos finais: [Estrela + Raposa frontal](../../evidence/amusement-park-cosmetics-fit-190392/star-fox-front.png), [Estrela + Raposa lateral](../../evidence/amusement-park-cosmetics-fit-190392/star-fox-three-quarter.png), [Âmbar + Fantasma](../../evidence/amusement-park-cosmetics-fit-190392/amber-ghost-three-quarter.png). Olhos e óculos permanecem livres do topo da máscara e as hastes chegam à cabeça. Esta fixture isolada verifica encaixe visual, não desempenho nem integração da sessão; esses aspectos têm evidências próprias acima.

As capturas temporais do parque e os benchmarks antecedem somente esse reposicionamento dos cosméticos. Não foram repetidos porque geometria da área, luzes, física, percurso e ciclo de vida permaneceram iguais. Saves do usuário e alterações de outras sessões foram preservados; nenhum commit ou descarte de trabalho foi feito.
