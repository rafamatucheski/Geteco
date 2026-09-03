# Edição livre da cidade

Abra o projeto pelo `editar-godot.bat`. Ele agora aponta para `game`, que é a
versão atual do projeto.

As ferramentas atuam na cidade atual aberta em `Main.tscn`; não existe mais
uma cidade-demo paralela. Selecione o distrito ou qualquer `Node2D` real na
árvore antes de inserir o item. Cada rua, cruzamento, faixa, prédio e poste
novo é um nó individual: selecione e use as ferramentas normais de mover,
rotacionar, escalar, duplicar ou apagar. As alterações ficam na cena ao salvar
(`Ctrl+S`).

O menu 2D ganha os botões `+ Rua`, `+ Cruzamento`, `+ Faixa`, `+ Prédio` e
`+ Poste`. Eles inserem nós permanentes na cena (ou dentro do `Node2D`
selecionado) e suportam desfazer/refazer.

Para uma rua:

- ajuste `length`, `road_width`, calçadas, faixas e tipo no Inspector;
- arraste/rotacione livremente no canvas;
- para conectá-la a dois cruzamentos, preencha `start_anchor` e `end_anchor`
  com os dois nós e ative `update_connection_now`. A rua calcula centro,
  comprimento e ângulo entre eles; depois, caso mova um cruzamento, ative a
  ação novamente para atualizar sem sobrescrever seus ajustes manuais.

Postes não são mais decoração presa à rua: são nós separados e arrastáveis.
Ao criar uma rua pela barra, ela já nasce sem postes automáticos por esse
motivo.
