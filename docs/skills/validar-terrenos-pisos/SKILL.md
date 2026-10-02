---
name: validar-terrenos-pisos
description: Criar, revisar e corrigir terrenos e pisos do Geteco/Godot quanto a forma, bordas, encaixe, texturas, mistura de materiais e coerência com áreas vizinhas. Usar em alterações de superfícies, margens, cobertura do solo e defeitos de acabamento. Não executar auditoria do jogo quando o pedido for apenas editar esta skill.
---

# Validar terrenos e pisos

Exija superfícies que pertençam ao lugar: forma convincente, materiais identificáveis, encontros bem acabados e detalhes apoiados no chão. Reprove recorte quadrado artificial, placa solta, colagem de texturas e terreno incompatível com o entorno. A aprovação depende de evidência observada; esta skill não garante ausência universal de defeitos.

## Escopo e preparação

- Leia AGENTS.md e preserve trabalho concorrente. Delimite região, superfícies, encontros e rotas afetadas. Auditoria não autoriza redesenhar o mapa; correção local não exige migrar todos os terrenos.
- Identifique versão do Godot, renderer, câmera de gameplay, resolução, qualidade e escala do mundo. Consulte documentação oficial da versão quando precisar confirmar recursos de materiais, shaders e importação.
- Carregue `performance-do-jogo` antes de implementar mudanças com custo em runtime e na comparação final; `testes-com-criterio` na validação de software. Localize pelo catálogo da sessão; se indisponíveis, informe e aplique os critérios pertinentes do projeto.
- Use `padrao-interiores` ao alterar pisos/apresentação/acessos interiores; `auditoria-viaria` se afetar ruas ou trânsito; `validar-iluminacao` ao alterar luzes/reflexos ou investigar cintilação; `guardiao-do-jogo` se afetar múltiplos sistemas ou ciclo de vida compartilhado. Dimensione a cobertura pelo impacto.
- Se o pedido for somente criar ou editar esta skill, verifique arquivos e referências. Não modifique o jogo nem execute auditoria ou benchmark.

## Inventário e intenção visual

Inspecione a cena renderizada, geometria, geração, materiais e recursos efetivamente usados em runtime. Arquivo de textura no disco não prova aplicação correta. Documentação antiga não comprova o estado atual.

Registre por trecho: cena/coordenadas, superfície principal, vizinhas, altura/inclinação, origem da geometria, materiais, colisão, limites de streaming e defeitos observados. Diferencie famílias de implementação e instâncias repetidas; uma mudança compartilhada pode afetar vários locais.

Estabeleça a intenção visual a partir do próprio lugar: urbano/rural, clima, umidade, desgaste, manutenção, uso, paleta e escala dos elementos próximos. Use áreas existentes bem resolvidas como referência quando disponíveis. Não imponha fotorrealismo a um jogo estilizado. Compare primeiro na câmera de gameplay e depois aproxime para diagnóstico.

## Forma, bordas e encaixe

| Inspeção | Exigir | Reprovar |
| --- | --- | --- |
| Silhueta natural | Curvas, larguras e recortes relacionados ao relevo, erosão ou vegetação. | Retângulo de chunk, escada de grid ou contorno de ferramenta visível em grama, terra, neve ou margem. |
| Superfície construída | Retas e ângulos intencionais, alinhados à estrutura e à função. | Placa quadrada isolada sem contexto, canto inacabado ou espessura indevida. |
| Perímetro completo | Acabamento nos lados, traseiras, cantos internos e externos. | Só a frente está resolvida; aparecem vãos, triângulos expostos ou material vazando. |
| Relevo | Altura contínua ou desnível explicado por degrau, meio-fio, talude ou contenção. | Fenda, pico, buraco, degrau acidental ou rampa sem apoio. |
| Contato com estruturas | Fundações e bases apoiadas; portas, soleiras e acessos preservados. | Construção flutua, terreno atravessa porta ou pavimento invade cômodo vizinho. |

“Nada quadrado” significa eliminar formas artificiais sem contexto. Não arredonde azulejos, calçadas ou quadras por obrigação. Ruído aleatório em toda borda não resolve composição: varie forma em escalas diferentes, preserve função e evite ondulação uniforme ou serrilhado.

## Texturas e leitura dos materiais

- Confirme carregamento/importação, atribuição à superfície correta e funcionamento no renderer ativo. Procure erros e fallbacks. Caminho válido sem material visível não aprova.
- Textura pode ser imagem, atlas ou resultado procedural intencional. Exija leitura de material na tela. Recurso ausente, textura de erro, fallback silencioso ou cor lisa provisória reprovam quando a intenção exige textura.
- Compare escala com jogador, pneus, portas e construções. Reprove pedras/grãos gigantes, tábuas desproporcionais e ladrilhos que mudam de tamanho sem razão.
- Inspecione UVs, orientação e densidade visual em planos, curvas e encostas. Reprove esticamento, compressão, espelhamento evidente, vazamento de atlas e direção incoerente de tábuas ou pavimentação.
- Observe repetição de perto e à distância. Combine variação ampla e detalhe local quando necessário; não substitua padrões repetidos por manchas ruidosas distribuídas igualmente.
- Confira brilho, rugosidade e relevo aparente. Terra não deve parecer plástico; pedra seca não deve parecer metal ou molhada sem contexto. Mapas adicionais são condicionais ao estilo, não obrigação de acrescentar complexidade.
- Verifique filtragem, mipmaps e aliasing em movimento. Escolha UVs, projeção ou mistura triplanar conforme o problema e o orçamento; não imponha shader caro como solução universal.
- Harmonize paleta, saturação, contraste, escala do detalhe e resposta à luz com as vizinhas. Não esconda incompatibilidade escurecendo a cena, borrando tudo ou removendo textura necessária.

## Encontros e mistura entre terrenos

Inspecione cada par existente e junções de três ou mais materiais. Defina encontro natural gradual ou construído nítido. Ambos precisam de acabamento; mistura não é sinônimo de borrar soleiras, juntas ou meios-fios.

| Encontro existente | Critérios específicos |
| --- | --- |
| Grama × terra | Cobertura irregular coerente com uso/umidade; solo entre tufos, sem retângulo ou faixa uniforme. |
| Terra/grama × asfalto | Acostamento, desgaste ou meio-fio plausível; sem halo colorido, tapete flutuante ou invasão da pista. |
| Calçada/piso × solo | Cota, espessura lateral, cantos e rampas bem conectados; nenhum plano suspenso. |
| Rocha × terra | Base apoiada, sedimento/vegetação onde cabível e mapeamento adequado em encostas. |
| Areia/solo × água | Margem acompanha relevo e nível da água; sem vãos, retângulos ou chão atravessando água por engano. |
| Neve × rocha/solo | Distribuição coerente com geografia e relevo existentes; sem corte arbitrário ou faixa uniforme. |
| Piso × piso/soleira | Direção, escala e juntas coerentes; mudança intencional sem desnível acidental. |
| Chunk × chunk | Continuidade de altura, normais, mapeamento, mistura e detalhes, inclusive após recarga. |

Nas transições suaves, examine máscaras/pesos, largura proporcional ao lugar e variação guiada pelo terreno. Inspecione juntas em T, cantos internos, faixas estreitas e encontros de várias camadas: halos, linhas escuras, ilhas inexplicáveis e mistura turva reprovam. Avalie continuidade de cor, relevo aparente e brilho quando usados, sem obrigar todos os canais à mesma técnica.

Evite planos coplanares e camadas sem controle. Pequeno deslocamento vertical pode ajudar um decal, mas não deve criar placa flutuante nem esconder erro de altura. Escolha geometria, máscara, material ou decal a partir da causa demonstrada.

## Detalhamento e colocação

- Distribua pedras, tufos, folhas, marcas, rachaduras e sujeira conforme ambiente e uso. Use agrupamentos e vazios com motivo; não preencha cada metro uniformemente.
- Apoie objetos na superfície efetiva, considerando footprint, altura, inclinação e orientação. Quando o centro não basta, confira os pontos de apoio. Reprove flutuação, enterramento excessivo e interseções com desníveis.
- Respeite reservas de ruas, trilhas, portas, saídas, atividades, água e construções. Considere o tamanho do objeto, não apenas sua origem; confirme exceções intencionais.
- Preserve legibilidade de caminhos, entradas e obstáculos. Detalhe não pode esconder perigo, bloquear passagem nem invadir indicadores funcionais.
- Prefira variação determinística por chunk. Retornar ao trecho não deve redistribuir decoração ou duplicar instâncias sem uma mecânica explícita.
- Diferencie decoração pequena de obstáculo sólido. Rochas grandes exigem física coerente; tufos não devem prender personagens. Não coloque colisão em todo detalhe por hábito.
- Não encubra emendas defeituosas com arbustos, névoa, sombras, pilhas de objetos ou enquadramento. Corrija a superfície primeiro.
- Comunique materiais e ambiente pela aparência; não acrescente textos decorativos explicativos.

## Fluxo de correção

1. Registre evidência inicial e critérios de aceitação. Sem acesso à cena, trate diagnóstico visual como hipótese.
2. Relacione o defeito à causa verificável: geometria, transform, máscara, UV, material, importação, geração, altura, colisão ou streaming. Não mude várias causas supostas de uma vez.
3. Resolva suporte e forma; depois encontros/materiais; por último os detalhes dependentes. Adapte a ordem quando a causa já estiver isolada.
4. Corrija recursos compartilhados quando apropriado, verificando instâncias afetadas. Não faça remendo que quebre vizinhos ou o retorno ao chunk.
5. Compare antes/depois no mesmo local, com câmera, luz e configuração equivalentes.
6. Valide proporcionalmente e encerre quando os critérios estiverem cobertos. Repetir exige alteração relevante ou hipótese concreta, não busca por uma passagem favorável.

## Validação real

Separe aprovação visual, física, temporal e de performance. Nenhuma substitui as demais.

**Visual:** percorra trecho e perímetro afetados na câmera de gameplay, aproximando, afastando e observando ângulos oblíquos disponíveis. Examine chão sob os pés, encostas e emendas. Close-up ajuda no diagnóstico, mas não é evidência única. Inclua condições de luz/clima existentes que alterem o resultado; não crie novos sistemas para preencher cobertura.

**Temporal:** registre vídeo ou sequência contínua com tempo identificável cruzando emendas e limites de LOD/culling/streaming pertinentes. Observe popping, z-fighting, cintilação e mudanças de textura/decoração. Screenshot isolado não comprova estabilidade. Dimensione duração pela rota e limites afetados; evidência com lacunas que impeçam detectar defeitos é inconclusiva.

**Física:** caminhe e, onde permitido, dirija sobre encontros, rampas e bordas acessíveis. Confira apoio, afundamento, queda pelo chão, degraus invisíveis e travamento de pés/rodas. Se altura ou colisão mudou, compare a referência visual e física, incluindo offsets e transforms. NPCs pertinentes também devem atravessar sem penetrar sólidos. Inspecione colisão e oclusão separadamente nos ambientes acessíveis.

**Ciclo de vida:** quando geração/streaming forem afetados, confira primeira visita, saída e retorno; restauração de save quando pertinente, sem sobrescrever saves do usuário. Reprove mudança de seed, costura, duplicação ou perda de colisão após recarga.

**Performance:** compare frame time antes/depois na cena real renderizada, com mesma máquina, rota, câmera, resolução, população e clima. Separe primeira visita de regime estável. Considere shaders, transparência, decals, draw calls, memória de texturas e geração/colisão conforme afetados. Registre duração, frames, p50/p95/p99 e picos conforme `performance-do-jogo`; não execute benchmarks concorrentes. Headless e teto de instâncias não comprovam FPS. Sem medição, desempenho fica pendente. Regressão confirmada ou queda reproduzível para 12–15 FPS bloqueia aprovação.

Reutilize testes existentes. Acrescente teste de contrato apenas quando proteger comportamento relevante, como continuidade de alturas, reservas por footprint ou estabilidade de seed. Procurar palavras no shader não testa mistura visual; build/importação não certificam aparência.

## Aprovação e relatório

Por trecho, registre **aprovado**, **reprovado**, **não executado** ou **não aplicável** separadamente para visual, física, temporal e performance. Justifique não aplicáveis. Inclua cena/coordenadas/rota, configuração, defeitos, causas comprovadas versus hipóteses, correções, evidências reais com caminhos/timestamps e pendências.

Bloqueiam aprovação: textura necessária ausente, recorte artificial sem contexto, emenda aparente, textura esticada/desproporcional, mistura incoerente, flutuação, sobreposição, buraco, acesso obstruído, desacordo físico relevante, instabilidade temporal e regressão confirmada. Não compense falha grave com nota média de beleza.

Sem cena real, declare revisão estática e visual pendente. Sem baseline, não aprove performance. A conclusão cobre apenas locais e condições verificados; uma amostra não certifica a cidade inteira. Criar esta skill não corrige nem certifica terrenos existentes.

## Pontos de partida no Geteco

Resolva os caminhos a partir da raiz do projeto e confirme existência no checkout atual; são pistas, não prova de integração:

- `world/regions/MountainTerrain3D.gd`, `world/regions/NativeRegion.gd`, `world/regions/NativeLake.gd`: relevo, integração e lagos.
- `world/regions/TerrainDressing3D.gd`: reservas, alturas e detalhes por chunk.
- `world/urban_detail/RuralGroundMaterial.gd`, `world/urban_detail/HarborUrbanSurface3D.gd`, `world/editing/WorldGroundFactory.gd`: materiais e superfícies.
- `docs/terrain-dressing-migration.md`, `docs/mountain-terrain-migration.md`: contratos e pendências; confronte com runtime atual.
- `docs/interior-physics-and-depth.md`: colisão e oclusão em ambientes acessíveis.

## Exemplos de aplicação

- “A grama está quadrada ao lado da estrada”: conferir contorno, reservas e acostamento no trecho; não redesenhar a malha viária.
- “Misture esses dois pisos”: distinguir transição natural de junta construída; preservar soleiras intencionais.
- “O terreno está lindo nesta foto”: examinar percurso/bordas e validações pertinentes; a foto não encerra a revisão.
- “Revise todos os terrenos”: inventariar famílias, regiões e encontros com implementações distintas; registrar cobertura e lacunas.
