---
name: validar-iluminacao
description: Validar qualidade visual e estabilidade temporal da iluminação no Geteco/Godot, investigar flickering e popping em faróis, lanternas, postes, luzes da cidade, sombras e reflexos. Aplicar ao criar ou alterar iluminação e ao revisar defeitos visuais relacionados, junto da validação de performance. Não executar auditoria do jogo quando o pedido for apenas editar esta skill.
---

# Validar iluminação

Exija iluminação legível, coerente e temporalmente estável na cena real. Nenhum flickering involuntário observado pode ser aprovado. A conclusão vale para cenários, duração e configurações efetivamente examinados; não prometa ausência universal de defeitos.

## Preparação

- Leia AGENTS.md e preserve alterações concorrentes. Delimite os sistemas afetados: correção localizada não autoriza reformar toda a cidade.
- Carregue `testes-com-criterio` para validação e `performance-do-jogo` antes de mudanças de runtime e na comparação final. Localize pelo catálogo da sessão; se indisponíveis, informe e aplique os critérios abaixo e do projeto. Interiores também seguem `padrao-interiores` e os contratos locais quando alterados.
- Confirme versão do Godot, renderer efetivamente usado, GPU/driver, resolução, qualidade, antialiasing, VSync e limite de FPS. Consulte documentação oficial da versão antes de assumir limites de luzes, recursos ou propriedades. Não troque o renderer para contornar defeitos sem autorização de escopo.
- Registre reprodução e baseline antes de editar: mapa/posição, rota, câmera, veículo, horário, clima, tráfego e save de teste. Não sobrescreva saves do usuário.
- Separe luminária/material emissivo, fonte, feixe, sombra e reflexo. Conte fontes instanciadas e ativas, sobreposição por objeto/região, alcance, máscaras e duplicações. Brilho da lente não comprova iluminação da pista.

## Matriz visual

Em auditoria geral, cubra todas as famílias existentes e regiões com implementações distintas. Em alteração localizada, cubra o trecho afetado e suas interações. Marque recursos ausentes como não aplicáveis, com justificativa; não implemente funcionalidades novas para preencher a matriz.

| Família | Cenários |
| --- | --- |
| Carros do jogador e tráfego | Faróis, lanternas, freio, ré, setas e emergência quando existentes; parado e em movimento, curvas, frenagem, diferentes perfis de veículos e vários carros cruzando seus fachos. |
| Cidade e postes | Rua isolada e cruzamento denso, fachadas/emissivos, luzes fixas e móveis sobre os mesmos objetos, objetos grandes atravessando várias áreas iluminadas. |
| Câmera e distância | Câmera parada, movimento lento e rápido, rotação/zoom disponíveis; aproximar, afastar e oscilar nos limites de ativação, LOD, culling e streaming; ida e volta pela mesma rota. |
| Ambiente | Dia, crepúsculo, noite e transição do ciclo; seco e chuva/reflexos quando presentes; túneis, pontes e interiores afetados, incluindo entradas e saídas. |
| Ciclo de vida | Primeira visita, descarregamento e retorno à região, spawn/despawn de veículos e restauração de save quando a alteração tocar esses fluxos. |

Verifique alinhamento dos faróis com o carro, continuidade do feixe na pista, alcance útil, cor, simetria quando prevista, transição sem saltos, exposição e ausência de estouro que esconda detalhes. Examine vazamento através de sólidos, sombras instáveis, manchas retangulares, cortes e reflexos piscando. Não introduza textos decorativos para explicar efeitos visuais.

## Evidência temporal

- Observe o jogo renderizado na câmera de gameplay, mantendo tráfego, clima e streaming pertinentes. Headless verifica lógica, não estabilidade visual nem GPU. Preview isolado e screenshot ajudam a investigar, mas não certificam o resultado integrado.
- Defina antes uma janela finita por cenário crítico: comece com pelo menos 30 segundos, incluindo trechos estáticos, movimento e travessia dos limites suspeitos. Amplie somente para completar a rota ou investigar hipótese concreta. Não repita até obter uma passagem limpa.
- Guarde vídeo ou sequência contínua de frames com timestamps e cadência suficiente para capturar defeitos de um frame. Capturas esparsas não comprovam estabilidade. Registre perda de frames na gravação; se comprometer a observação, a evidência é inconclusiva. Inspecione em velocidade normal e quadro a quadro nos eventos suspeitos.
- Correlacione eventos com estado das luzes, transformações, câmera, entrada/saída de região e contagem de fontes quando necessário. Instrumentação temporária deve ter custo controlado e não permanecer como logging por frame em produção.
- Em análise automatizada, use regiões de interesse e compensação de movimento quando cabível. Diferenças de pixels não bastam: câmera, chuva, tráfego e sombras móveis produzem variações legítimas. Um pico é candidato a inspeção, não diagnóstico automático.
- Setas e giroflex são piscadas intencionais somente quando vinculadas ao estado e à cadência esperados. Não aceite apagões ou saltos de fontes vizinhas sincronizados com esses efeitos. Não classifique piscada desconhecida como intencional sem evidência.

## Diagnóstico sem mascarar

Trate as causas abaixo como hipóteses, não conclusões. Isole uma variável por vez e restaure as variantes de diagnóstico antes da validação final.

- Luz alternando perto de limite: examine histerese, distância, visibilidade, ordenação/prioridade e estado de ativação. Verifique seleção estável quando muitas fontes competem, conforme limites documentados do renderer.
- Farol tremendo em movimento: compare atualização de física e render, interpolação, hierarquia de transforms e acompanhamento da câmera. Confirme a causa antes de trocar o modo de atualização.
- Superfície cintilando: investigue geometria coplanar, z-fighting, normais, material especular, mipmaps/aliasing, emissivos e transparências. Nem toda cintilação vem da fonte luminosa.
- Sombra ou reflexo piscando: isole sombras, reflexos, exposição e efeitos temporais; investigue estabilidade e precisão conforme os recursos do renderer.
- Mudança de região: procure criação duplicada, descarte antecipado, estado perdido e transições sem continuidade.

Desabilitar um subsistema temporariamente ajuda a isolar a causa. Não aprove solução que esconda o defeito apagando luzes necessárias, removendo sombras essenciais, escurecendo a cena, saturando o brilho ou reduzindo globalmente a qualidade. Corrija dentro do escopo autorizado e valide a configuração final.

## Performance e aprovação

- Compare antes/depois na mesma máquina, cena, rota, clima, população, câmera e configuração. Separe aquecimento do regime estável e registre travamentos de primeira visita. Não execute benchmarks concorrentes. Considere o custo da captura e mantenha o método comparável.
- Siga o orçamento do projeto e a skill de performance. Registre duração, número de frames, FPS por frames/tempo, frame time p50/p95/p99, máximo e frames acima de 33,3 e 66,7 ms; CPU/GPU separadamente quando disponíveis.
- Sem meta definida, explicite 60 FPS / 16,67 ms como alvo provisório no hardware medido. Defina tolerância antes do teste; aumento superior a 5% em p95/p99 pede confirmação finita equivalente, considerando ruído. Não flexibilize critérios após a falha.
- Aprove somente com estabilidade temporal observada, qualidade visual preservada, comportamento funcional correto e desempenho dentro do orçamento, sem regressão confirmada. Flickering involuntário, queda reproduzível para 12–15 FPS ou falha relevante bloqueiam aprovação. Ausência de execução renderizada ou de baseline comparável deixa a respectiva validação pendente.
- Reporte por cenário: aprovado, reprovado, não executado ou não aplicável; duração/configuração, caminhos das evidências e timestamps dos defeitos, comparação de métricas, causa comprovada versus hipótese e pendências. Uma cena aprovada não certifica as demais.

## Pontos de partida no Geteco

Confirme os caminhos no checkout atual. Consulte `gameplay/VehicleLightProfiles.gd`, `world/city_look/CityLocalLighting.gd` e `world/mountain_detail/MountainRoadLamp3D.gd`. Reaproveite conforme o escopo:

- Contratos: `tests/test_traffic_headlights.gd`, `tests/test_city_local_lighting.gd`, `tests/test_weather_lighting_parity.gd`.
- Inspeção: `tests/capture/capture_traffic_headlights.gd`, `tests/capture/capture_lighting_glitches.gd`, `tests/capture/capture_camera_lighting_parity.gd`. Confira a cadência: adapte somente se necessário para evidência temporal.
- Medição: `tests/measure/measure_traffic_headlights.gd`, `tests/measure/measure_outdoor_lighting.gd` e infraestrutura de `tests/measure/`.

Se o pedido for somente criar/editar a skill, valide arquivos e referências; não execute auditoria nem altere o runtime. Informe que a criação da skill não certifica a iluminação atual.
