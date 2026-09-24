# Oficina de armas da Ammu-Nation

Selecione uma arma comprada e use **PERSONALIZAR**. As categorias disponíveis dependem da arma; a prévia não altera o inventário nem cobra. **COMPRAR E INSTALAR** confirma a escolha. Peças compradas pertencem àquela arma e podem ser removidas e reinstaladas gratuitamente. O save guarda compras e instalações; o formato antigo de lanterna continua aceito.

| Modificação | Compatibilidade |
|---|---|
| Acabamentos: preto, areia, verde, cromado e madeira escura | Todas as 13 armas personalizáveis, incluindo armas brancas e lança-chamas |
| Lanterna, tecla G remapeável | Pistola, Magnum, SMG, escopeta, escopeta curta, AK-47, M4A1, rifle de caça e lança-chamas |
| Laser vermelho ou verde | As oito armas de fogo, sem lança-chamas |
| Silenciador e capacidade ampliada | Pistola, SMG, escopeta, AK-47, M4A1 e rifle de caça |
| Empunhadura | SMG, escopeta, AK-47 e M4A1 |
| Coronha | As anteriores e rifle de caça |
| Luneta 2× | Rifle de caça |

Bazuca, granada e punhos não têm personalização. A loja também disponibiliza o lança-chamas. As filiais usam a mesma oficina. Não foram alteradas colisões ou oclusões dos interiores.

O laser aparece ao mirar, termina no primeiro contato físico e não atravessa paredes. A luneta amplia a câmera e adianta a visão na direção da mira, somente fora dos interiores. Empunhadura e coronha reduzem recuo e dispersão. O silenciador reduz clarão e alcance audível, preservando a reação de pessoas próximas ou na trajetória. Capacidade ampliada custa 18% a mais no tempo de recarga; instalar não cria munição e remover devolve o excedente à reserva. A oficina suspende sua prévia 3D quando fechada e suspende a prévia antiga do catálogo enquanto aberta.

## Sons e bazuca

Pistola, Magnum e escopeta recebem cinco novas variações por arma, sem repetir a mesma consecutivamente. Os sons foram sintetizados originalmente pelo script `tools/build_weapon_audio_v2.py`, em 44,1 kHz mono, com pressão inicial, corpo e detalhes mecânicos diferentes. Há outras 30 variações para as seis armas compatíveis com silenciador. Os arquivos importados ficam em `audio/combat/arsenal_v2`; `metrics.json` registra pico/RMS e zero amostras saturadas nos arquivos fonte. Isso não certifica ausência de saturação na mixagem de muitos eventos simultâneos. A qualidade subjetiva do timbre ainda depende de escuta no equipamento do jogador; não houve avaliação auditiva humana nesta implementação.

A bazuca mantém dano e alcance. O foguete deixa fumaça em posições do mundo, com até 24 partículas desenhadas por rastro, no máximo 12 rastros. A saída produz um clarão curto e fumaça, limitados a oito eventos. A explosão combina luz breve, fogo, fumaça e detritos orientados pelo impacto. Nós temporários terminam após sua duração; não são criados nós por partícula a cada frame.

## Validação em 19/09/2026

- Oficina: 42 verificações renderizadas aprovadas, incluindo câmera real, laser contra parede, compra, munição, reação ao som, compatibilidade, prévia, suspensão dos viewports e save JSON.
- Lanterna: 24 verificações aprovadas nesta etapa.
- Garagem: 30 verificações aprovadas na execução final sem erros de script; armas continuam bloqueadas e Maciota/mecânico protegidos.
- Recarga manual: 15 verificações aprovadas. Reação da vizinhança: 10 aprovadas.
- Áudio importado e incidentes de explosão: zero falhas. Efeitos renderizados: zero falhas, capturas inspecionadas e descarte de rastros/clarão/explosão verificado.
- Capturas da oficina inspecionadas para pistola, Magnum, escopeta, AK-47, rifle, lança-chamas e faca. A inspeção motivou ajuste do apoio da coronha do rifle e aumento da prévia.
- Percurso completo pelas lojas: a nova execução encerrou com código 1 durante a carga da cidade, antes dos casos de percurso. Sem resultado atual; os 27 casos da etapa anterior não substituem esta validação. A causa do encerramento não foi isolada. Log: `ammunation-final.log`.

**Performance pendente, sem aprovação geral.** A tentativa de baseline anterior às alterações foi bloqueada por erros de compilação em arquivos da montanha alterados em paralelo. A tentativa de amostra A/B na cidade encerrou com código 1 antes de gerar CSV/JSON; emitiu erros de construção de modelos em `MountainStaticModelView.gd`. Não foi isolada a causa do encerramento. O diagnóstico `tests/measure_arsenal_customization.gd` compara acessórios desligados/instalados na cena real, com dez segundos de aquecimento e trinta de amostra; exige tiros efetivamente emitidos pelas seis armas. Ambos os lados já contêm os novos sons e efeitos da bazuca, portanto esse A/B não substitui baseline histórico dos efeitos.

Os avisos de certificado e diretório padrão de saves são do ambiente restrito; os testes usam saves isolados. O teste de incidentes de explosão também indicou recursos vivos no encerramento, portanto não há certificação geral de descarregamento sem vazamentos.

Evidências: `C:/Users/rafae/.codex/visualizations/2026/09/19/01a0bb59-dcd2-7151-9835-df98e996d9c4`, incluindo `workbench-final`, `workbench-batched-final`, `rocket`, `audio-imported-final.log`, `garage-arsenal-fixed.log`, `explosions-final.log` e `arsenal-ab-standard.log`. As últimas capturas confirmam os encaixes após considerar a união dos modelos por material; algumas capturas rápidas de troca de arma não registraram todo o fundo/texto da interface, por isso não certificam estabilidade visual em trocas rápidas.
