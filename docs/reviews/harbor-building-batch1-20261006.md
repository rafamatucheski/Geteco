# Harbor — prédios acessíveis, leva 1

## Entrega e cobertura

Customs House e Union Lofts: **2 fachadas, 2 interiores independentes, 8 plantas**, com térreo e três andares em cada prédio. As plantas acompanham as três linhas superiores de janelas das fachadas existentes. O catálogo completo de levas está em [harbor-interiores-por-levas.md](../harbor-interiores-por-levas.md).

Uma visita pela rua começa no térreo. As escadas usam a interação remapeável; pavimentos intermediários oferecem subir, descer ou voltar. A transição usa o token e o bloqueio de controle da sessão, admite o corpo inteiro no destino antes da troca e preserva o andar anterior quando o patamar está bloqueado. Só um pavimento fica carregado após a transição. O save registra o andar, e a carga fria nasce em um patamar livre, sem prometer posição exata dentro do cômodo.

As portas exteriores e saídas usam o marcador compacto compartilhado, sem legenda de entrada/saída. As escadas mantêm texto funcional. Não foram acrescentados moradores, funcionários permanentes, recompensas, diálogos ou missões.

## Validação funcional e visual

Godot **4.7.2 .NET**, `Harbor.csproj` compilado, renderer **Mobile**, RTX 4060 Laptop GPU. Todas as sessões de teste usam saves isolados em `evidence/`; nenhum slot pessoal foi substituído.

| Evidência | Resultado |
| --- | --- |
| `tests/test_harbor_building_interiors.gd` | 715 checks aprovados: oito pavimentos, jogador/NPC reais, varreduras, móveis, piso, corredores, patamares, descarregamento, máscaras de oclusão e controles positivos. |
| Revisão final do pavimento 3 residencial | 96 checks aprovados após afastar a mesa/cadeira da parede frontal. |
| `tests/test_harbor_building_session.gd` | 58 checks aprovados no Main renderizado: fachada, ação de entrada, caminhada, todos os andares, botões reais da escada, save, carga fria no terceiro andar, descida e retorno. Backend C# confirmado. |
| `tests/test_full_save.gd` | PASS: publicação, backup, recuperação e rejeição de estado inválido, sem falhas. |

Diretórios:

- `evidence/harbor-building-contract-173028-4880618`: checks e fotografias naturais/diagnósticas dos oito pavimentos.
- `evidence/harbor-building-contract-92016-4797772`: revisão final da mesa do último pavimento residencial.
- `evidence/harbor-building-session-180248-4978171`: sessão final, dois exteriores, oito pavimentos e save/carga fria.
- `evidence/harbor-access-before-playable-139340-4912037/scene.png`: exterior anterior do Customs House. Os interiores eram inexistentes; não há fotografia independente anterior do residencial.

Na primeira execução, o registro de andar foi rejeitado pelo preflight do SaveStore porque o JSON devolve números como `float`. A validação passou a aceitar os inteiros numéricos 0–3 e rejeitar frações, tipos inválidos e andares inexistentes. A cadeia real de gravação e recarga foi executada novamente depois da correção. As tentativas anteriores permanecem em `evidence/harbor-building-session-6892-5305054` e `evidence/harbor-building-session-153388-4978245`.

## Performance

Meta provisória: **60 FPS / 16,67 ms**; diferença acima de 5% em p95/p99 pede confirmação. Medições em 1920×1080, renderer Mobile, VSync desligado e sem limitador, conforme a configuração encontrada. As janelas medem intervalos reais entre frames durante pelo menos 30 segundos após aquecimento, separadas das capturas de imagem.

A primeira comparação não controlada teve p95 de 7,375 para 8,577 ms e p99 de 8,508 para 9,871 ms, com população/frota diferentes. Não foi usada como aprovação. Uma alteração concorrente em `MountainBridgeShore.gd` interrompeu a primeira medição dos interiores; os números dessa execução com erros de compilação foram descartados. A nova execução começou somente depois de o arquivo corrigido pela outra sessão passar no parser.

A comparação seguinte usou a mesma seed, posição, horário, save, câmera e configuração de tráfego. O baseline desativa exclusivamente os dois novos acessos por metadado de medição; não remove sistemas existentes. Hashes das dependências ficaram estáveis dentro de cada execução. Entre os dois processos, a única mudança nos arquivos rastreados foi a integração dos marcadores desta leva em `FullSession.gd`.

| Exterior Customs House | Sem a leva | Com a leva |
| --- | ---: | ---: |
| Frames / duração | 7.970 / 30,003 s | 7.630 / 30,000 s |
| FPS médio | 265,64 | 254,33 |
| p50 | 3,084 ms | 3,186 ms |
| p95 | 7,277 ms | 7,377 ms |
| p99 | 8,686 ms | 8,785 ms |
| Máximo | 21,172 ms | 22,799 ms |
| Frames acima de 33,3 / 66,7 ms | 0 / 0 | 0 / 0 |
| Pedestres / veículos ao final | 25 / 32 | 23 / 33 |

Delta de p95 **+1,37%**, p99 **+1,14%**: dentro da tolerância definida nesse cenário. Tráfego real continua dinâmico e o total final de entidades varia; esta comparação não isola CPU/GPU nem certifica toda a cidade. Evidências: `evidence/harbor-access-controlled-before-144684-4855679` e `evidence/harbor-access-controlled-after-94864-5065675`.

Os quatro primeiros pavimentos medidos em `evidence/harbor-floor-performance-97364-4916696` ficaram entre **834,83 e 1.026,75 FPS**, p95 **1,437–2,097 ms**, p99 **1,717–2,964 ms** e nenhum frame acima de 33,3 ms. São cenas interiores estáveis com um só pavimento ativo, não um comparativo contra um interior anterior inexistente. Admissão bloqueada também preservou sala e controle nos dois prédios.

Os quatro pavimentos adicionais foram medidos em `evidence/harbor-floor-performance-166584-4950939`, também por 30 segundos cada: **953,20–1.042,98 FPS**, p95 **1,410–1,707 ms**, p99 **1,677–3,137 ms**, máximo **19,712 ms** e nenhum frame acima de 33,3 ms. Os dois casos de patamar bloqueado passaram novamente com a implementação final, mantendo o pavimento anterior, a câmera e o controle. A revisão final dos marcadores exteriores está fotografada em `evidence/harbor-access-controlled-after-94864-5065675/scene.png`.

Conclusão restrita: desempenho estável dentro da meta nas oito plantas diurnas e variação p95/p99 dentro da tolerância no exterior medido. As salas são novas, portanto não existe um interior anterior equivalente para comparação. Picos da primeira criação/troca de andar não tiveram uma janela própria de instrumentação; as medições estáveis não certificam latência de primeira visita ou todos os cenários de carga.

## Pendências explícitas

- Cobertura temporal noturna e observação de iluminação em mais condições. Fotografias diurnas e máscaras de profundidade não comprovam ausência global de flickering.
- Fotografia anterior independente do exterior residencial não disponível.
- Restam 47 novos acessos no inventário-base e a revisão dos 11 acessos anteriores, além do censo complementar das construções fora de `harbor_buildings`.

Não contar os dois prédios como certificados integralmente enquanto houver critérios obrigatórios pendentes. Os testes desta leva não certificam os demais interiores nem alterações concorrentes na montanha, câmera, áudio ou terreno.
