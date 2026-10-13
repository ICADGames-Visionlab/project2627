# Suporte a controle — Issue #55

O jogo inteiro é jogável no controle: menus, mundo (andar, NPCs, objetos, orbes, cama), diálogo,
diário, inventário, sonho e profiling. Os avisos na tela trocam sozinhos entre tecla e botão conforme
o que o jogador está usando ("Aperte ESPAÇO para dormir" vira "Aperte X para dormir" no instante em
que ele toca no controle, e volta quando ele toca no teclado ou mexe o mouse).

Este guia tem duas partes: **como funciona** (as cinco peças) e **como manter** (o checklist para toda
feature nova continuar funcionando no controle). Se você só vai criar uma feature, pule para
[Checklist](#checklist-feature-nova-sem-quebrar-o-controle).

## Índice

1. [O mapa do controle](#o-mapa-do-controle)
2. [Como funciona](#como-funciona)
3. [Checklist: feature nova sem quebrar o controle](#checklist-feature-nova-sem-quebrar-o-controle)
4. [O autoteste](#o-autoteste)
5. [Testar na mão](#testar-na-mão)
6. [Decisões e limites](#decisões-e-limites)
7. [Quando a branch da corrida (#54) entrar](#quando-a-branch-da-corrida-54-entrar)
8. [Arquivos](#arquivos)

---

## O mapa do controle

Nomes do controle de Xbox (é o padrão SDL que a Godot usa; num controle de PlayStation, A = ✕,
B = ○, X = □, Y = △). A fonte da verdade é **Projeto > Configurações do Projeto > Mapa de Entrada**.

| Botão | No mundo | Em menus | No diálogo | No sonho / profiling |
| --- | --- | --- | --- | --- |
| Analógico esq. / D-pad | anda | navega o foco | sobe/desce a opção | navega o foco (emoções, lacunas, palavras) |
| **A** | aciona o que está em foco (orbe, NPC, objeto) | aperta o botão focado | confirma / avança | *segurar* numa emoção muda a emoção; numa palavra, põe na lacuna; numa lacuna cheia, devolve a palavra; "Aperte A para continuar" |
| **B** | — | volta / fecha | — | abre "Deseja acordar?" (no sonho livre); dentro do profiling, volta um passo |
| **X** | dorme (na cama) / investiga o espírito | — | colhe as palavras sublinhadas da fala | colhe as palavras da história resolvida |
| **Y** | abre/fecha o diário | — | — | abre as marcas (lixo/estrela) da palavra focada |
| **LB** | *segurar* destaca os interagíveis | — | — | — |
| **RB** | passa o foco pro próximo alvo na tela | — | — | — |
| **Back** | abre/fecha o inventário | — | — | — |
| **Start** | pausa | — | — | pausa |
| **Analógico dir.** | — | — | rola o histórico | — |
| **L3 / R3** | — | — | vai ao início / ao fim do histórico | — |

---

## Como funciona

### 1. Qual dispositivo está em uso — `GameManager` + `InputDeviceDetector`

O `GameManager` guarda o dispositivo em uso (`GameManager.active_input_device`, um
`GameManager.InputDevice`: `KEYBOARD_MOUSE` ou `JOYPAD`) e responde `GameManager.is_joypad_active()`.
Quem descobre é o `InputDeviceDetector`, um nó que o `GameManager` cria como filho no `_ready()`:

- roda em `_input` com `PROCESS_MODE_ALWAYS` (pega o controle mesmo no menu de pausa) e **só observa**,
  nunca consome o evento;
- botão do controle apertado, ou analógico além de `joypad_axis_threshold` → controle;
- tecla apertada (sem eco), clique, ou mouse andando mais que `mouse_motion_threshold` pixels →
  teclado/mouse. Mouse tremendo parado na mesa e analógico na folga não trocam nada;
- controle desconectado (o último) → volta pro teclado/mouse.

Os dois limiares são `@export` do `GameManager` (Inspector do Autoload).

Quando o dispositivo **muda** (e só quando muda), sai o evento `EventBus.input_device_changed(device)`.
Quem precisa reagir escuta ele; quem só precisa saber na hora pergunta `GameManager.is_joypad_active()`.

> Não é um Autoload novo: o guideline pede aprovação do Lead para Singleton, e a pergunta "qual
> dispositivo" já tem dono global (o `GameManager`, que também guarda o esquema de movimentação).

### 2. Avisos que trocam sozinhos — `InputGlyphs`

Nenhum texto escreve a tecla. O CSV cita a **ação** entre chaves, em minúsculas, como no Mapa de
Entrada:

```
PROMPT_SLEEP,Press {sleep} to sleep,Aperte {sleep} para dormir
```

e quem desenha usa `InputGlyphs.tr_prompt()` no lugar de `tr()`:

```gdscript
label.text = InputGlyphs.tr_prompt("PROMPT_SLEEP")
```

- O `{sleep}` vira o nome do primeiro evento da ação **no dispositivo em uso**: no teclado, tecla antes
  de botão do mouse; no controle, botão antes de analógico. Trocar a tecla no Mapa de Entrada muda o
  aviso sozinho.
- **Variante de controle**: quando a frase inteira muda (no mouse é "Clique para continuar", no
  controle "Aperte A para continuar"), crie uma segunda chave com o sufixo `_JOYPAD`. Com o controle em
  uso, `tr_prompt()` usa ela; sem ela, usa a normal com o botão no lugar.
- Os nomes das teclas e botões estão no CSV: `INPUT_KEY_*` (só as que precisam de tradução, como
  ESPAÇO), `INPUT_JOY_BUTTON_<n>`, `INPUT_JOY_AXIS_<n>_NEG/POS`, `INPUT_MOUSE_<n>`. Letra e número
  saem do jeito que a engine escreve.
- Tecla física (WASD, E, F) é convertida pro layout do teclado do jogador antes de virar texto: num
  AZERTY, o "W" sai "Z".
- Texto que não passa por `tr_prompt()` (montado com `String.format()`, por exemplo) pode chamar
  `InputGlyphs.format_actions(texto, GameManager.active_input_device)` — é o que o `DiaryOverlay` faz
  com as páginas.

Como o texto é montado em código, a `Label` precisa de `auto_translate_mode = DISABLED` e de ser
reescrita em dois momentos: `EventBus.input_device_changed` e `NOTIFICATION_TRANSLATION_CHANGED`. O
`ActionPrompt` é o exemplo mais curto.

### 3. Menus — `MenuFocus`

Um nó que se põe **dentro** do menu (Adicionar Nó > `MenuFocus`) e faz ele funcionar no controle sem
código no menu. Três campos no Inspector:

| Campo | O que é | Vazio |
| --- | --- | --- |
| `Menu Root` | o `Control` que, visível, quer dizer "menu aberto" | o pai |
| `Initial Focus` | quem recebe o foco ao abrir | o primeiro focável do menu |
| `Cancel Button` | o botão que o B / ESC aperta | o menu não responde ao cancelar |

O que ele faz:

- menu abre com o controle em uso → foco no `Initial Focus`;
- o jogador pega o controle com o menu já aberto → mesmo foco. O aperto que trouxe o controle **só põe
  o foco**, não anda com ele (senão o jogador começaria no segundo botão);
- seta/D-pad com nada focado → o primeiro aperto só põe o foco;
- `ui_cancel` com o menu aberto → aperta o `Cancel Button`;
- botão desabilitado sai do caminho do D-pad (`Skip Disabled Buttons`, ligado por padrão) e volta
  quando é habilitado: o cursor não para no "Continuar" sem save, onde o A não faria nada.

Com o mouse, ele não mexe em foco: quem joga de mouse não vê o contorno de foco pulando sem ter pedido.

**Só o menu de cima responde.** Um menu que o jogo pausou por baixo de outra tela (as evidências, que
não pausam, com o diário ou a pausa aberta por cima) continua visível, mas fica quieto
(`is_menu_active()` olha se o menu está rodando). Sem isso o B fechava a tela de baixo.

**`MenuFocus.is_any_menu_open()`** responde "tem menu aberto e respondendo agora?". É a pergunta de quem
cuida do **mundo** antes de reagir a um botão que os menus também usam (ver a seção 4).

Já está em: `MainMenu`, `Settings`, `SaveSlotMenu`, `PauseMenu`, `InventoryUI`, `ProfilingScreen`.

Para tela cujo foco de entrada muda com o estado, há duas portas em código:

- **`initial_focus_provider`** — um `Callable` que devolve o `Control` que deve receber o foco agora. A
  `ProfilingScreen` usa: primeira emoção na vista do espírito, primeira palavra na da história, a seta
  de voltar numa história resolvida.
- **`focus_if_needed()`** — põe o foco de entrada se ele não estiver no menu. Para a tela que troca de
  conteúdo com o menu aberto (o foco que estava na parte que sumiu se perde junto com ela).
- **`refresh_focus_modes()`** — para menu que habilita/desabilita botão com ele já aberto.

E duas funções estáticas para casos que o nó não cobre:

- **`MenuFocus.bind_joypad_cancel(dialogo)`** — para `AcceptDialog`/`ConfirmationDialog`. A Godot
  fecha esses diálogos no ESC, mas **não no B** (testado na 4.7), mesmo com o B no `ui_cancel`. O D-pad
  e o A já funcionam dentro deles. Chame no `_ready()` do menu; o `SaveSlotMenu` é o exemplo.
- **`MenuFocus.apply_joypad_focus_mode(control)`** — para peça que a cena tirou do foco por causa do
  mouse (um botão que, focado, desenharia o contorno depois de cada clique) mas que precisa ser
  alcançável pelo D-pad: liga o foco só no controle. Chame de novo em `input_device_changed`. Exemplos:
  `GlossaryWordChip`, `ProfilingBlank`, `ProfilingEmotionOption`.

### 4. Mundo — `FocusTargets` + `InsightInteractor`

O foco de teclado/controle no mundo é um só: o anel do `InsightInteractor`, que segue o alvo mais
perto do jogador, troca com RB e aciona com A (ou E). Ele percorre os orbes de insight **e todo nó do
grupo `FocusTargets.GROUP`** que cumprir o contrato. É assim que NPCs (`NPCInteraction`) e objetos
(`Interactable`) entraram no controle sem o `InsightInteractor` saber o que é um NPC.

O contrato (seis métodos, documentados em `scripts/shared/FocusTargets.gd`):

```gdscript
get_focus_world_position() -> Vector2      # para "mais perto do jogador"
get_focus_screen_rect() -> Rect2           # para "está na tela"
can_be_focused() -> bool                   # dá pra acionar AGORA (mesma regra do clique)
set_focused(focused: bool) -> void         # acende/apaga o destaque de foco
activate_focus(player: Player) -> void     # faz o que o clique faria
set_mouse_hover_suppressed(suppressed: bool) -> void  # no modo foco, o hover do mouse não destaca
```

Regras que vêm junto:

- o modo foco liga com RB/E/Tab ou qualquer botão do controle, e desliga quando o mouse se move. Com
  ele ligado, o hover do mouse não destaca nada (o foco é o único destaque);
- **menu aberto manda nos botões que ele também usa.** Com as evidências abertas (elas não pausam o
  jogo), quatro coisas do mundo perguntam `MenuFocus.is_any_menu_open()` e ficam quietas: o analógico
  não anda o personagem (`Player._get_input_direction`, só no controle), A e RB não acionam nem trocam
  o alvo (`InsightInteractor`), o B não fecha a caixa de um orbe (`InsightBubble`) e não pergunta se o
  jogador quer acordar (`DreamHud`). Quem criar outra reação do mundo a A, B ou D-pad faz a mesma
  pergunta;
- **o A depois de uma conversa tem folga.** No controle, avançar a fala e falar com alguém são o mesmo
  botão: o A que fecha a conversa (ou os apertos seguintes) reabriria a conversa na hora, porque o foco
  volta pro mesmo NPC. Durante `InsightInteractor.interact_cooldown_after_conversation` (0,75 s) o
  interagir não faz nada, e cada aperto dentro da folga recomeça a contagem — quem martela o A não
  reabre nada; quem para e aperta de novo fala normalmente.

### 5. Telas com foco próprio

Algumas telas distribuem o foco elas mesmas, porque o "menu" muda de forma enquanto está aberto:

- **Diálogo** (`DialogueScreen`): opções pelo D-pad/analógico, A confirma. O X colhe de uma vez as
  palavras sublinhadas da fala (`DialogueEntry.collect_glossary_words()`); o aviso "Aperte X para colher"
  só aparece no controle e só quando sobra palavra.
- **Profiling** (`ProfilingScreen`): ver a tabela em [docs/sistema_de_profiling.md](sistema_de_profiling.md),
  seção "No controle". O foco de entrada é de um `MenuFocus` com `initial_focus_provider` (ver a
  seção 3). A lista de palavras se refaz a cada mudança, então o painel devolve o foco à palavra/lacuna
  certa depois de cada refação. O "aperte A para continuar" depois do acerto é lido em `_input`, antes
  do `MenuFocus`: o acerto some com o glossário (e com o foco), e o primeiro A seria gasto pondo o foco
  de volta.
- **Sonho** (`DreamHud`): o B (`dream_wake`) faz a pergunta "Deseja acordar?", que já nasce com foco no
  "não". Só com o sonho livre: jogo pausado ou um painel com foco são donos do B naquela hora.
- **Diário** (`DiaryOverlay`): o D-pad vira a página e o Y/B fecha. Os botões do diário **não**
  recebem foco de propósito: focados, o D-pad navegaria entre eles em vez de virar a página.
- **Pausa** (`PauseMenu`): não abre por cima de uma tela que já pausou o jogo (diário, profiling, a
  pergunta de acordar). O menu ficaria escondido atrás dela (camada mais baixa) e, ao despausar,
  soltaria o jogo com a tela ainda aberta. Cada uma dessas telas tem a própria saída.

---

## Checklist: feature nova sem quebrar o controle

O autoteste ([abaixo](#o-autoteste)) acusa os itens marcados com 🔒 — mas é bem mais barato acertar
antes do que descobrir no PR.

1. 🔒 **Criou uma ação no Mapa de Entrada?** Dê a ela um botão do controle também. Se ela realmente
   não faz sentido no controle, ponha em `EXEMPT_ACTIONS` do `ControllerSupportSelfTest` **com o
   motivo** (e o motivo é o que o controle faz no lugar). Ações `debug_*` já estão isentas.
2. 🔒 **Usou um botão ou analógico que ninguém usava?** Dê nome a ele no CSV (`INPUT_JOY_BUTTON_<n>` ou
   `INPUT_JOY_AXIS_<n>_NEG/POS`), nos dois idiomas.
3. 🔒 **Escreveu um texto que cita tecla?** Use `{acao}` no CSV e `InputGlyphs.tr_prompt()` no código
   (o autoteste acusa "Aperte ESPAÇO", "Press F" e afins escritos à mão),
   e reescreva a `Label` em `input_device_changed`. Se a frase muda inteira no controle, crie a chave
   `_JOYPAD`. Ação que só existe no controle (como `dream_wake`) entra em `JOYPAD_ONLY_ACTIONS`, e o
   texto que cita ela só pode aparecer no controle.
4. 🔒 **Criou uma tela ou menu com botões?** Ponha um nó `MenuFocus` dentro e preencha os três campos.
   Se a tela distribui o foco sozinha, registre em `SELF_MANAGED_FOCUS_SCENES` com o motivo. Tem
   `AcceptDialog`/`ConfirmationDialog`? `MenuFocus.bind_joypad_cancel(dialogo)` no `_ready()`.
5. **Tirou o foco de um `Control` por causa do mouse** (`focus_mode = NONE`)? Se o jogador de controle
   precisa chegar nele, use `MenuFocus.apply_joypad_focus_mode()`.
6. 🔒 **Criou uma coisa interagível no mundo** (uma porta, um baú)? Herdar de `Interactable` já resolve.
   Senão, `add_to_group(FocusTargets.GROUP)` no `_ready()` e os seis métodos do contrato.
7. **Algo precisa reagir ao dispositivo?** Escute `EventBus.input_device_changed` ou pergunte
   `GameManager.is_joypad_active()`. Não leia `Input.get_connected_joypads()`: ter um controle ligado
   não quer dizer que o jogador está usando ele.
8. **Algo do mundo reage a A, B, X, Y ou ao D-pad?** Pergunte `MenuFocus.is_any_menu_open()` antes:
   com um menu aberto, o botão é dele. (Os menus pausados não contam, então a pergunta não atrapalha
   quem roda com o jogo pausado.)
9. **Um botão some no próprio aperto** (lista refeita, como Largar nas evidências)? Refaça a lista
   adiado (`call_deferred`). Refazendo na hora, o botão sai da árvore antes de marcar o aperto como
   usado, e o mesmo A segue adiante e aciona o que estiver por baixo.
10. **Uma tela pausa o jogo?** Quem recebe o input dela precisa de `PROCESS_MODE_ALWAYS` — inclusive
    para o mesmo botão que abriu poder fechar (foi o bug do diário: o Y abria e não fechava). E ela
    precisa ter a própria saída: a pausa não abre por cima.
11. 🔒 **Leu uma ação no código** (`is_action_pressed(&"...")`, `const ..._ACTION: StringName`)? O
    autoteste confere que ela existe no Mapa de Entrada — ação renomeada não dá erro nenhum, o botão só
    para de funcionar.
12. **Rode o autoteste** e, se mexeu em input, faça o [teste na mão](#testar-na-mão).

---

## O autoteste

```
godot --headless --path . --script res://tests/run_controller_support_self_test.gd
```

ou **F4 > Controle > Autoteste do controle** com o jogo aberto. Sai com código 1 quando algo falha,
então pode virar verificação de CI.

| Confere | Falha típica |
| --- | --- |
| Toda ação do Mapa de Entrada tem botão no controle (ou exceção com motivo) | ação nova só com tecla |
| Toda exceção ainda existe | ação apagada que ficou na lista de exceções |
| Todo botão usado tem nome no CSV, nos dois idiomas | aviso escreveria "JOY 15" |
| Todo `{acao}` citado no CSV existe e tem botão (e tecla, fora as só de controle) | erro de digitação no CSV; aviso escreveria "?" |
| Toda chave `_JOYPAD` tem a chave normal | variante órfã |
| Todo script que entra em `FocusTargets.GROUP` tem os seis métodos | método renomeado; o foco pularia o alvo |
| Toda cena com botão tem `MenuFocus` (ou exceção com motivo) | menu novo que o controle não alcança |
| Nenhum texto do CSV escreve a tecla à mão | "Aperte ESPAÇO" no lugar de "Aperte {sleep}" |
| Toda ação lida no código existe no Mapa de Entrada | ação renomeada; `is_action_pressed` com erro de digitação |
| Detecção do dispositivo, aviso de troca, `tr_prompt` | regressão na lógica |
| `MenuFocus`: foco ao pegar o controle, cancelar, botão desabilitado, `initial_focus_provider`, menu congelado pela pausa | regressão na lógica |

Cada falha diz o que fazer ("dê um botão em Projeto > Input Map ou ponha em EXEMPT_ACTIONS com o
motivo"). As listas de exceção ficam no topo de `ControllerSupportSelfTest.gd` — são elas que o code
review lê.

O autoteste lê o `project.godot` e o `translations.csv` direto, então roda no editor e na linha de
comando, não em build exportada (ele é ferramenta de debug, como os outros autotestes).

---

## Testar na mão

Com um controle ligado, roteiro de cinco minutos depois de mexer em input:

1. Menu principal: D-pad para baixo → foco no primeiro botão (não no segundo). Opções → navegar até o
   fim → B volta. Novo jogo → slot ocupado → B fecha a confirmação.
2. Cidade: RB passa entre orbes, NPCs e objetos; A num NPC abre a conversa; A avança até o fim.
3. Mexer o mouse: o anel some. Tocar no controle: volta.
4. Start → pausa com foco em "Continuar" → B despausa. Back → inventário → B fecha. Y → diário → D-pad
   vira a página → Y fecha.
5. Na cama (de noite): o aviso diz "X"; apertar qualquer tecla troca pra "ESPAÇO". X dorme.
6. No sonho: o botão diz "Acordar (B)"; B pergunta, B cancela. X perto de um espírito → profiling:
   segurar A numa emoção, D-pad até INVESTIGAR, A abre a história, A numa palavra põe na lacuna, Y abre
   as marcas, B volta.
7. Precedência: RB até um orbe, A abre a caixa; Back abre as evidências; B fecha as evidências (a caixa
   continua); B fecha a caixa. Back, depois Y: B fecha o diário (as evidências continuam). Com o diário
   aberto, Start não abre a pausa.
8. Fim de conversa: martelar o A enquanto a última fala fecha não reabre a conversa.

---

## Decisões e limites

- **Nomes de botão, não ícones.** Os avisos escrevem "A", "LB", "D-pad ↓" a partir do CSV. Trocar por
  ícones é trocar `InputGlyphs.event_label()` — que é o único lugar que transforma evento em texto — por
  algo que devolva BBCode `[img]` (e as `Label`s por `RichTextLabel`).
- **Um controle só.** Os nomes são os de Xbox para qualquer controle. Para mostrar ✕/○ num controle de
  PlayStation, `event_label()` pode olhar `Input.get_joy_name(0)` e escolher um prefixo de chave
  (`INPUT_JOY_PS_BUTTON_<n>`); o resto do sistema não muda.
- **O foco que vem do controle é adiado pro fim do quadro.** A troca de dispositivo é avisada no meio do
  evento que a causou, antes de a interface recebê-lo. Focar na hora fazia aquele mesmo aperto andar o
  foco.
- **B no sonho acorda, mas pergunta antes.** O GDD pede "acordar" sempre presente na tela do sonho; o B
  é o atalho do botão, e a pergunta nasce com foco no "não" porque acordar perde o resto do sonho.
- **X colhe tudo de uma vez.** Quem joga de mouse clica em cada palavra sublinhada; no controle não há
  como apontar uma palavra no meio do texto, então o X colhe todas as da fala (ou da história
  resolvida). O resultado no glossário é o mesmo.
- **A folga do A depois da conversa recomeça a cada aperto.** Uma folga fixa não bastava: quem martela
  o A três vezes por segundo passava dela e reabria a conversa.
- **"Tem menu aberto?" é do `MenuFocus`, e não do foco da interface.** A primeira versão perguntava "tem
  algum Control com foco?", mas um botão clicado com o mouse fica com o foco: pegar o controle depois
  travaria o personagem.
- **Ações sem botão, de propósito:** `move_click` (andar pelo clique é do mouse), `dialogue_option_1..9`
  (atalhos numéricos; no controle a opção é escolhida pelo D-pad + A), `ui_focus_next/prev` (sem tecla
  nenhuma, ver [docs/insights.md](insights.md)) e as `debug_*`.

---

## Quando a branch da corrida (#54) entrar

A branch `54-adicionar-corrida...` ainda não está na `development`. Duas coisas para quem fizer o merge:

1. **A ação `move_run` (SHIFT) não tem botão no controle.** O autoteste vai falhar com "sem botão:
   move_run" — é ele funcionando. Sugestão: **L3** (clicar o analógico esquerdo, o "correr" mais comum)
   ou **RT**. O L3 já é `dialogue_jump_to_start`, mas só dentro da conversa, onde o personagem não anda.
2. **No esquema "Clique do mouse", o analógico não anda.** Na branch 54, o `Player` só lê `move_*`
   quando o esquema inclui o teclado, e o analógico e o D-pad estão nas mesmas ações. O controle tem
   que andar em qualquer esquema: a leitura das direções precisa valer também quando
   `GameManager.is_joypad_active()`.

---

## Arquivos

| Arquivo | Papel |
| --- | --- |
| `scripts/singletons/GameManager.gd` | dispositivo em uso, limiares, cria o detector |
| `scripts/shared/InputDeviceDetector.gd` | descobre o dispositivo pelos eventos |
| `scripts/singletons/EventBus.gd` | `input_device_changed` |
| `scripts/shared/InputGlyphs.gd` | `{acao}` → tecla/botão, variantes `_JOYPAD` |
| `scripts/ui/MenuFocus.gd` | foco de menus, cancelar, botão desabilitado, `is_any_menu_open`, `bind_joypad_cancel`, `apply_joypad_focus_mode` |
| `scripts/shared/FocusTargets.gd` | contrato de alvo do mundo |
| `scripts/insights/InsightInteractor.gd` | o anel de foco do mundo (orbes + `FocusTargets`) |
| `scripts/shared/ControllerSupportSelfTest.gd` | o autoteste e as listas de exceção |
| `tests/run_controller_support_self_test.gd` | o autoteste pela linha de comando |
| `translations/translations.csv` | `INPUT_*` (nomes) e os avisos com `{acao}` |
| `project.godot` | botões do controle de cada ação |
