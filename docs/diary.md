# Diário do jogador — Issue #60

O livro que o jogador abre com **L** (botão **Y** no controle) e folheia com as **setas**. Ele
reúne, numa sequência só, o que o jogador sabe de cada pessoa e as anotações pessoais dele.

| Peça | Arquivo |
| --- | --- |
| Estado, ordem das páginas, gatilhos, save | `scripts/singletons/Diary.gd` (Autoload `Diary`) |
| Endereço de uma página | `scripts/diary/DiaryPage.gd` |
| Anotação pessoal (conteúdo) | `scripts/diary/DiaryNote.gd` + `.tres` em `resources/diary/notas/` |
| Catálogo das anotações | `scripts/diary/DiaryNoteCatalog.gd` |
| O livro na tela | `scenes/ui/diary/DiaryBook.tscn` + `scripts/ui/diary/DiaryBook.gd` |
| Uma cena por tipo de página | `scenes/ui/diary/pages/` + `scripts/ui/diary/Diary*Page.gd` |
| Peças repetidas (cartões, seções, pop-ups) | `scenes/ui/diary/parts/` |
| Cores e fontes | `resources/diary/diary_theme.tres` (variações `DiaryLabel`, `DiaryTitle`, `DiaryLink`...) |

## A sequência do livro

```
capa -> sumário (+ primeiras pessoas) -> mais pessoas -> [geral -> evidências -> rotina] x cada pessoa
     -> anotações pessoais -> coro -> cidade -> cidade distorcida -> memórias
```

- As pessoas entram **na ordem em que o jogador as conheceu**. "Conheceu" é o mesmo fato que leva o
  NPC ao sonho: uma conversa no mundo real em que ele foi abordado (`ProfilingJournal.has_met`). O
  diário só guarda a ordem.
- Seção que não cabe num par de folhas vira várias páginas (`people_per_spread`,
  `evidence_per_spread`, `notes_per_spread`, no `Diary`).
- A lista de páginas nunca é guardada: é refeita dos fatos (`Diary.get_pages()`). A página atual é
  lembrada pela chave (`DiaryPage.get_key()`), então conteúdo novo no meio do livro não tira o
  jogador da página que ele está lendo.
- A primeira abertura da partida mostra a capa; as seguintes voltam na página em que ele parou.

## As páginas

| Página | O que mostra |
| --- | --- |
| Sumário | Esquerda: o título e os links Pessoas (vai pra primeira pessoa) e Anotações pessoais. Direita: o primeiro grupo de pessoas (`people_on_contents`, 4), pra não sobrar folha vazia. A aba Pessoas abre aqui |
| Pessoas | Só existe quando há mais pessoas do que cabem ao lado do sumário, e continua a lista dali. Grupos de 4 por folha: na coluna da esquerda nome e depois retrato, na da direita retrato e depois nome. Clicar abre a pessoa |
| Pessoa (geral) | Esquerda: retrato (`NPCDefinition.portrait`), nome e a história. Direita: o glossário por categoria, com lupa e os filtros A-Z / ★ / ✗ na borda |
| Pessoa (evidências) | As evidências lidas que têm palavra do glossário dela. Clicar amplia, escurecendo o fundo |
| Pessoa (rotina) | Tabela das 6 rotinas (emoção x trabalho/folga) nas horas do dia, com "?" no que ainda não foi visto e a linha do horário atual |
| Anotações pessoais | Os subtópicos com a contagem, e a última anotação |
| Subtópico | As anotações, com a data (dia/mês) no canto, o texto e as imagens |

**História da pessoa:** não tem ficha (nome, profissão, idade) de propósito. É a apresentação
`DIARY_PERSON_INTRO_<ID>` do CSV, se existir, mais a entrada de diário de cada história de profiling
resolvida (`ProfilingStory.journal_entry_key`).

**Glossário:** é o do `ProfilingJournal`, com os mesmos chips do sonho. Clique numa palavra abre o
pop-up com as evidências que a mencionam; botão direito abre o menu de lixo/estrela.

**Rotina:** um trecho de rotina vira conhecido quando o NPC **está na tela** enquanto ele vale
(conferido a cada passo do relógio e ao abrir o diário), ou quando o jogador conversa com ele. O
resto fica "?". A tabela usa a mesma resolução do `NPCRoutineResolver` (fallback, exceções como a
ronda).

## Anotações pessoais: criar uma nova (sem código)

1. Escreva o texto no `translations/translations.csv`.
2. `res://resources/diary/notas/` → *New Resource* → `DiaryNote`. Preencha `id`, `topic`,
   `text_key`, as `images` e o gatilho:

| Gatilho | Quando entra |
| --- | --- |
| `MANUAL` | Só com `Diary.add_note(&"id")` (ou o menu de debug) |
| `DREAM_ENTERED` | Ao entrar no mundo dos sonhos (`EventBus.dream_started`) |
| `INSIGHT_READ` | Ao ler um dos insights de `trigger_ids` |
| `CONVERSATION_STARTED` | Ao abrir uma das conversas de `trigger_ids` |

Cada anotação entra uma vez, com a data do dia de jogo. O dia 1 é `calendar_start_day` /
`calendar_start_month` no `Diary` (01/03 por padrão).

Anotações de teste (placeholders): `cidade_quartel` (ler qualquer insight do quartel de bombeiros) e
`cidade_distorcida_primeiro_sonho` (entrar no sonho).

## API

| Membro | Para quê |
| --- | --- |
| `open_diary()` / `close_diary()` / `toggle_diary()` / `is_open()` | Abrir e fechar (pausa o jogo) |
| `next_page()` / `previous_page()` / `go_to_page(i)` / `go_to_key(key)` | Navegar |
| `add_evidence(item)` | Chamado pelo `EvidenceViewer` ao fechar uma evidência |
| `get_evidence_for_npc(id)` / `get_evidence_for_word(id)` | O que as páginas de evidência e o pop-up mostram |
| `add_note(id)` / `get_notes(topic)` / `format_date(day)` | Anotações |
| `mark_routine_seen(id, key)` / `is_routine_seen(id, key)` | Rotina observada |
| `content_changed`, `page_changed`, `diary_opened`, `diary_closed`, `note_added` | Sinais diretos |

## Save

Seção `diary`: `people` (ordem), `evidences`, `notes` (`id` + `day`) e `routines` (chaves dos
trechos vistos por NPC). Glossário, marcas e histórias continuam no `profiling`. Um save do
protótipo antigo (seção `evidences` com `ids`) tem as evidências lidas na primeira abertura.

## Depurar

Seção **Diário** do menu (F4): abrir/fechar, folhear, adicionar uma ou todas as anotações, revelar as
rotinas inteiras, validar as anotações, listar o estado e resetar. Para ter pessoas sem conversa
escrita (o policial), use **Profiling → Marcar NPC como encontrado**.

## Placeholders

Tudo é desenhado com `StyleBox` e cor, sem arte. Retratos vêm do `NPCDefinition` (hoje o
placeholder), as imagens das anotações de teste reaproveitam imagens placeholder do projeto, e os
textos novos com `Placeholder -` no CSV são provisórios.
