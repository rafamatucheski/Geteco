# Fragmentos 3D e reações de dor — 13/09/2026

Os desenhos planos de cabeça, tronco e pernas foram substituídos por fragmentos extraídos das malhas visíveis do personagem. Roupa, pele, cabelo, rosto, acessórios e calçado preservam os materiais originais. As articulações separadas recebem superfícies de fechamento discretas. Não é criado um boneco genérico com a mesma cor da vítima.

Quatro combinações distribuem cabeça, tronco, braços e pernas em quatro a seis corpos físicos, mantendo cada região uma única vez. Algumas combinações mantêm a cabeça ou um braço presos ao tronco. Direção, energia, elevação, rotação em três eixos e orientação final variam entre explosões. Há suporte para pedestres e socorristas articulados, motoristas e moradores com o rig da montanha. Os fragmentos continuam formando um único trabalho de coleta, independentemente da quantidade.

Na rua, cada vítima usa um atlas de 384×256 compartilhado por todos os fragmentos, com células de 128×128. O atlas atualiza até 30 vezes por segundo durante a queda, evita atualizações de animação fora da tela e guarda o último quadro depois do repouso. Não há viewport por membro. O limite preexistente de 16 conjuntos permanece. Nos interiores, as mesmas malhas compartilham o depth buffer da sala, com apoio calculado pelos limites da geometria, oclusão real, acompanhamento da física e limpeza ao descarregar.

O Dante agora pode reagir ao dano com uma das cinco gravações humanas curtas de `audio/reactions/hurt_*.wav`, de aproximadamente 0,23–0,31 segundo. Tiros em NPCs usam a mesma política. A chance é de 42% para dano abaixo de 25 e 65% a partir de 25; há intervalo mínimo de 1,8 segundo, bloqueio de sobreposição e limite de seis vozes simultâneas. Acertos totalmente absorvidos pelo colete, invulnerabilidade e mortes não iniciam gemidos adicionais. Uma voz de dor em andamento termina ao morrer. Sons de impacto, pânico e morte continuam separados. O banco evita repetir a mesma tomada consecutivamente.

## Evidências

Diretório: `D:/geteco/artifacts/remains-pain-revision/`.

| Verificação | Resultado |
| --- | --- |
| `test_fragment_models.gd` | Zero falhas na entrega: três combinações diferentes em dez vítimas, seis regiões representadas uma vez, reutilização de malhas/materiais, variação de trajetórias, atlas com tamanho limitado, repouso, suspensão do render, coleta de todos os fragmentos e descarregamento. Verifica também face/cabelo e escala de motoristas e moradores da montanha. `test_fragment_models-delivery.log`. |
| `test_person_weapon_effects.gd` | Zero falhas: fogo persistente e sua renovação, granada, bazuca por raio e por sobreposição, cobertura, sobreviventes, isolamento dos mundos físicos e limpeza. `test_person_weapon_effects-delivery.log`. |
| `test_person_effects_interior.gd` | Zero falhas renderizadas: fragmentos variáveis e fogo no viewport da sala, oclusão com controle positivo, corpo inteiro oculto e remoção das malhas. `interior-delivery.log`. |
| `test_pain_reactions.gd -- --record` | Zero falhas: entrada pelo tiro real no Dante e NPC, silêncio probabilístico, gravações reais, colete, invulnerabilidade, rajada sem sobreposição, intervalo e morte. `pain-verified.log`. |
| `test_character_reaction_audio.gd` | Zero falhas: preserva as cinco tomadas de cada banco e uma única voz de morte nos callbacks reais de pedestre, policial, paramédico e bombeiro. `test_character_reaction_audio-delivery.log`. |
| `test_garage_weapon_restrictions.gd` | Zero falhas e sem erros de script na execução final, em `garage-delivery.log`. Maciota e mecânico continuam invulneráveis; inventário, entrada, saída, save e bloqueio de armas preservados. A primeira execução encontrou autoloads de resgate em edição; a verificação final foi feita depois da correção dessas dependências. |

As expectativas antigas de exatamente quatro partes foram atualizadas porque o pedido passou a exigir variedade. Os testes mantêm a exigência de substituir o corpo inteiro, acrescentando cobertura da anatomia e da coleta com quantidade variável.

Prévias renderizadas isoladas: `original-character.png`, `fragments-airborne.png`, `fragments-settled-0.png`, `fragments-settled-1.png` e `fragments-settled-2.png`. Capturas dos interiores continuam em `D:/geteco/artifacts/person-weapon-effects/`. O teste de driver usa a cena nativa para evitar o ciclo de carregamento provocado pela instanciação direta do script.

`pain-preview.wav` contém três vozes emitidas pelo mixer SFX, sem a rajada artificial do teste. Duração medida: 5,739 s; pico por canal: 0,154; nenhuma amostra saturada. A ferramenta não disponibilizou escuta ao agente; a validação foi do banco existente, da emissão real e do sinal capturado, não uma nova avaliação auditiva humana.

## Desempenho: não aprovado

Foi mantido o checkpoint de HarborGame com dez impactos durante 30 segundos após dez segundos de aquecimento, em 1280×720, Mobile/Vulkan, RTX 4060 Laptop, Godot 4.7.2. Limite de 60 FPS, VSync desligado; saves exclusivos do teste. Meta: 16,67 ms, com investigação de aumentos acima de 5% nos percentis p95/p99.

| Amostra de 30 s | Antes | Depois | Confirmação depois |
| --- | ---: | ---: | ---: |
| Frames | 1157 | 1013 | 881 |
| Duração | 30,007 s | 30,025 s | 30,015 s |
| FPS médio | 38,56 | 33,74 | 29,35 |
| p50 | 24,353 ms | 27,846 ms | 28,488 ms |
| p95 | 38,960 ms | 45,797 ms | 70,560 ms |
| p99 | 55,409 ms | 128,408 ms | 125,965 ms |
| Máximo | 79,240 ms | 187,786 ms | 223,137 ms |
| Frames >33,3 / >66,7 ms | 182 / 9 | 224 / 21 | 308 / 50 |

A piora observada não foi resolvida nem deve ser apresentada como performance aprovada. Não há atribuição causal isolada: durante a tarefa mudaram autoloads e rotinas de resgate, e a população ativa ao fim das amostras passou de 69 para 74 e 79 pedestres. A última amostra ainda registrou acesso a metadado `medical_sequence` ausente em `NPCMedicalCare.gd:160`, fora dos arquivos desta revisão. A calibração final de tamanho do rig alternativo foi verificada funcionalmente; o benchmark tem alvos de pedestre articulado.

Registros e amostras brutas em `before/`, `after/` e `after-confirm/`. Esses resultados justificam investigação de desempenho em um estado estável do projeto; não certificam 60 FPS nem ausência de regressão. A validação funcional e visual acima não depende dessa certificação.
