# Diary (Protótipo de Diário) — Issue #30

Autoload (singleton) que guarda as páginas de um diário/livro navegável e decide quando ele está
aberto ou fechado. Qualquer script do projeto pode adicionar conteúdo chamando
`Diary.add_page(...)`, sem precisar conhecer a UI nem esperar o diário estar aberto.

Script: `res://scripts/singletons/Diary.gd`
UI (instanciada sob demanda): `res://scripts/ui/DiaryOverlay.gd` + `res://scenes/ui/DiaryOverlay.tscn`

> ⚠️ **Não confundir com o `InsightJournal`.** Aquele autoload (`scripts/singletons/InsightJournal.gd`)
> é apelidado de "diário" só nos comentários internos dele, e cuida de outra coisa: quais insights o
> jogador já leu, sem UI própria. Este `Diary` é a peça de UI navegável (livro com páginas) pedida
> na issue #30 — os dois sistemas não têm relação hoje (ver "Como escalar" mais abaixo se um dia
> fizer sentido ligar os dois).

## Configuração inicial

Já registrado no `project.godot` deste PR:

1. `Diary` no Autoload, apontando para `res://scripts/singletons/Diary.gd`.
2. Ação de input `diary_toggle` (tecla **J**, ou botão **Y** no controle).

Se precisar refazer manualmente: **Project > Project Settings > Autoload**, path apontando pro
script, Node Name exatamente `Diary`. Não adicione `class_name Diary` — o nome do Autoload já cria
a referência global (mesma regra do AudioManager, ver `docs/AudioManager.md`).

## Como o jogador interage

- **J** (ou botão **Y** no controle) abre e fecha o diário — funciona em qualquer cena de gameplay,
  sem precisar instanciar nada à mão.
- Com o diário aberto: as teclas de movimento **esquerda/direita** (ou o D-pad/analógico
  correspondente) folheiam as páginas; não voltam ao início ao passar da última nem da primeira.
- **Esc** fecha o diário (mesmo padrão do menu de pausa e da tela de diálogo).
- Por padrão, abrir o diário pausa o jogo (`Diary.pause_game_on_open`) — ver "Como escalar" para
  desligar isso.

## API pública

| Membro | Descrição |
|---|---|
| `add_page(text_key, title_key = "", format_args = []) -> int` | Adiciona uma página ao final e devolve o índice dela. Não muda a página que o jogador está lendo. |
| `insert_page(index, text_key, title_key = "", format_args = [])` | Insere numa posição específica, empurrando as seguintes. |
| `remove_page(index)` | Remove a página do índice (silencioso se o índice for inválido). |
| `clear()` | Esvazia o diário inteiro. |
| `get_page_count() -> int` | Número de páginas atuais. |
| `get_page(index) -> Diary.DiaryPage` | Devolve a página (ou `null` se o índice for inválido). |
| `get_current_page_index() -> int` | Índice da página sendo exibida. |
| `next_page()` / `previous_page()` | Navega uma página (não dá a volta nas pontas). |
| `go_to_page(index)` | Vai direto para uma página, com clamp nos limites. |
| `open_diary()` / `close_diary()` / `toggle_diary()` | Abre, fecha ou alterna a UI. |
| `is_open() -> bool` | Se o diário está aberto agora. |
| `pages_changed` (signal) | Lista de páginas mudou (adição, remoção, limpar). |
| `current_page_changed(index)` (signal) | A página exibida mudou. |
| `diary_opened` / `diary_closed` (signal) | O diário abriu ou fechou. |

### `text_key` e `title_key` são chaves de tradução, nunca texto pronto

Segue a regra do `GUIDELINE_PROGRAMACAO.md` ("Strings e Localização"): nenhum texto exibido ao
jogador pode estar hardcoded. `title_key` vazio (`""`) significa página sem título.

```gdscript
# Errado — texto pronto direto no código:
Diary.add_page("Encontrei uma pista sobre o poço.")

# Certo — chave do translations.csv:
Diary.add_page(&"DIARY_CLUE_WELL_TEXT", &"DIARY_CLUE_WELL_TITLE")
```

`format_args` existe pro mesmo caso que o `DYNAMIC_EXAMPLE` do CSV já cobre (texto com uma parte
variável, tipo nome de NPC ou quantidade):

```gdscript
# CSV: DIARY_MET_NPC_TEXT,"I met %s today.","Conheci %s hoje."
Diary.add_page(&"DIARY_MET_NPC_TEXT", &"", [tr(HeadRegistry.get_display_name_key(head_id))])
```

## Quando usar

- Qualquer sistema que precise registrar algo que o jogador vai querer reler depois (pista,
  anotação de missão, entrada de lore) e que caiba num texto com título opcional.
- Conteúdo que nasce em momentos diferentes e de sistemas diferentes — é exatamente pra isso que a
  API é "chamar uma função de qualquer lugar", em vez de a UI conhecer o conteúdo de antemão.

## Quando não usar

- Conteúdo com layout próprio (imagem, mapa, formulário) — o protótipo só desenha título + texto.
  Nesse caso, ou estende `Diary.DiaryPage`/`DiaryOverlay`, ou é melhor uma tela própria (como a
  `PlaceholderDialogueScreen`).
- Estado que precisa ser consultado por lógica de jogo (ex: "o jogador já leu isso?", flags que
  abrem porta) — isso é o `InsightJournal`, não este sistema. `Diary` não sabe nada sobre "lido"
  nem persiste nada por enquanto (ver "Como escalar").

## Prós e contras de ser um Autoload

**Prós**
- Qualquer script chama `Diary.add_page(...)` sem precisar de referência nem saber se a UI existe.
- Sobrevive a trocas de cena — o diário não esvazia ao trocar de tela, igual ao `InsightJournal`.
- UI instanciada sob demanda (só na primeira vez que a tecla é apertada): enquanto ninguém abre o
  diário, ele não custa nada além do array de páginas em memória.
- Tecla funciona em qualquer cena de gameplay sem precisar instanciar `DiaryOverlay.tscn` à mão
  (diferente do `PauseMenu`, que precisa ser colocado em cada cena).

**Contras**
- Estado global: nada impede um sistema de adicionar página em duplicidade ou no momento errado —
  não há deduplicação nem validação de conteúdo hoje.
- `_overlay` nunca é destruído depois de criado (mesma armadilha documentada no `AudioManager.md`):
  não é um problema sério aqui (é só um punhado de `Label`/`Button`), mas vale saber.
- Sem persistência: fechar e reabrir o jogo apaga as páginas adicionadas em runtime (ver "Como
  escalar").

## Como escalar

- **Persistência:** seguir o mesmo padrão do `InsightJournal` (`to_dict()`/`from_dict()` +
  `SaveManager.save_game()`/`load_game()`, gravando dentro do slot ativo). Hoje o `Diary` guarda
  `title_key`/`text_key`/`format_args` por página — dá pra serializar isso direto, sem precisar de
  `StringName -> String` na volta do JSON pros `format_args` que forem número.
- **Categorias/capítulos:** hoje é uma lista única. Pra separar em seções (ex: "Missões",
  "Personagens"), o caminho mais simples é adicionar um campo `category: StringName` em
  `DiaryPage` e a `DiaryOverlay` filtrar por aba, no mesmo espírito da coluna de seções do
  `DebugMenuOverlay`.
- **Condição de desbloqueio:** se alguma página só deve aparecer depois de um evento (ex: uma
  flag do `InsightJournal`), o dono do conteúdo decide isso ANTES de chamar `add_page()` — o
  `Diary` continua sem saber de flag nenhuma, só guarda o que mandaram guardar. É a mesma divisão
  de responsabilidade que o `EventBus` recomenda entre "quem decide" e "quem guarda".
- **Três ou mais sistemas reagindo a abrir/fechar o diário** (ex: SFX de virar página, pausar
  música, achievement de primeira leitura): nesse ponto `diary_opened`/`diary_closed` deixam de ser
  relação direta com um único ouvinte e passam a fazer sentido no `EventBus` — mover pra lá segue a
  regra de `docs/event_bus.md` ("três ou mais sistemas reagem ao mesmo fato").
- **`pause_game_on_open = false`:** se o diário passar a ser lido sem pausar o jogo (ex: HUD
  permanente), troque a leitura de página de `move_left`/`move_right` (usada hoje em
  `DiaryOverlay._unhandled_input`) por ações de input dedicadas — do jeito que está, um jogador
  segurando "mover para a direita" também folhearia página, porque o mundo continuaria rodando ao
  mesmo tempo que o diário.
- **Conteúdo não-textual (imagem, ícone):** dá pra adicionar um campo opcional em `DiaryPage` (ex:
  `icon: Texture2D`) e a `DiaryOverlay` desenhar condicionalmente — o array de páginas já é
  genérico o bastante pra isso sem quebrar quem só usa texto.

## Depurar

Com `Diary` registrado no `DebugMenu` (seção "Diário", ver `docs/debug_menu.md`): abrir/fechar,
avançar/voltar página, adicionar uma página de teste, limpar o diário e listar o estado atual no
log — tudo sem precisar reproduzir a condição de jogo que adicionaria conteúdo de verdade.
