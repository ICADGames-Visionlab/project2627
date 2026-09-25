# Sistema de Profiling

Este guia explica como o jogador entende um NPC dentro do mundo dos sonhos — escolhendo a emoção
dele e preenchendo a história por trás de cada emoção com palavras que descobriu pela cidade — e
como pôr conteúdo novo no jogo sem abrir um script.

O sistema implementa o GDD de Profiling **até a seção "Exemplo da história da emoção TRISTE"**,
inclusive. O que vem depois no documento (o fluxograma e a ideia paralela do *emocional do
protagonista*) está fora de escopo por decisão da tarefa.

---

## Índice

1. [A ideia](#a-ideia)
2. [O ciclo, inteiro](#o-ciclo-inteiro)
3. [As duas telas](#as-duas-telas)
4. [As cenas: onde se mexe na UI](#as-cenas-onde-se-mexe-na-ui)
5. [Criar conteúdo (sem tocar em código)](#criar-conteúdo-sem-tocar-em-código)
6. [Os recursos](#os-recursos)
7. [As palavras e o glossário](#as-palavras-e-o-glossário)
8. [A correção da página](#a-correção-da-página)
9. [A emoção do NPC](#a-emoção-do-npc)
10. [Os eventos](#os-eventos)
11. [O estado: diário e save](#o-estado-diário-e-save)
12. [Ferramentas de debug](#ferramentas-de-debug)
13. [O que ainda não existe](#o-que-ainda-não-existe)
14. [Placeholders](#placeholders)
15. [Erros comuns](#erros-comuns)
16. [Antes de abrir PR](#antes-de-abrir-pr)

---

## A ideia

Cada NPC carrega emoções, e **cada emoção tem uma história por trás** — algo que fez aquela emoção
tomar conta dele. No mundo dos sonhos, o jogador encontra o espírito do NPC e investiga essas
histórias: o texto aparece cheio de lacunas, e ele as preenche arrastando palavras que descobriu
pela cidade. Entender todas as emoções de um NPC é entender por que ele está ali.

Duas coisas acontecem nessa tela, e elas são independentes:

|  | Investigar | Mudar a emoção |
| --- | --- | --- |
| Gesto | Passar o mouse na emoção → botão **INVESTIGAR** | **Segurar** o botão esquerdo sobre a emoção |
| O que muda | O conhecimento do jogador sobre o passado do NPC | O comportamento do NPC no mundo real |
| Quando vale | Na hora | **A partir do dia seguinte** |
| Quem é o dono | `ProfilingScreen` + `ProfilingPage` | `ProfilingJournal` → `NPCDirector` |

Mudar a emoção é uma ferramenta de investigação, não um prêmio: deixar o policial triste muda a
rotina dele, e a rotina nova põe o jogador em situações que revelam palavras que não existiam antes.
É o laço central do jogo — **mudar a cidade para descobrir mais sobre ela**.

---

## O ciclo, inteiro

```
MUNDO REAL       o jogador explora, conversa e acha palavras       -> glossário do NPC
SONHO            encontra o espírito -> escolhe a emoção -> INVESTIGAR
                 preenche a história com o glossário               -> história resolvida
                 (segurando uma emoção)                            -> emoção agendada
MUNDO REAL       no dia seguinte o NPC acorda na emoção escolhida
  (dia seguinte) rotina nova -> situações novas -> palavras novas   -> mais histórias
```

Acertar **todas** as histórias de um NPC faz o jogador acordar: entender alguém por inteiro fecha o
sonho. Depois de ler a última história ele volta pra tela de emoções (onde ainda pode escolher a
emoção do NPC), e **sair dela é acordar**.

---

## As duas telas

**Tela do espírito** (`ProfilingScreen`, view `SPIRIT`)

- a **arte do espírito** do NPC cobrindo a tela inteira (`NPCDefinition.spirit_art`, 1920x1080), com
  o nome e as emoções por cima. Ela fica abaixo do filtro de cor da emoção (o filtro a tinge) e
  treme junto com a tela. Ela passa 24 px de cada borda (offsets do `SpiritArt` na cena) pra a
  beirada não aparecer no tremor — ao aumentar `Shake Strength`, aumente essa sobra junto. Numa tela
  de outra proporção ela é cortada nas bordas, nunca esticada;
- uma opção por emoção do NPC (`ProfilingEmotionOption`), com o nome na cor da emoção. As opções
  **já estão na cena**, filhas do nó `Emotions` (`EmotionFirst` na esquerda, `EmotionSecond` na
  direita), e cada uma fica onde foi posta no editor: a 1ª filha recebe a primeira emoção do NPC, a
  2ª a segunda. Opção sobrando fica escondida; emoção sobrando (um terceiro slot, no futuro) pede
  uma opção a mais — é duplicar uma na cena. O "Emoção" escrito nelas só aparece no editor;
- **segurar** o botão esquerdo: a tela treme, o nome cresce, o retângulo em volta enche e a tela
  ganha um filtro na cor da emoção. Quando enche, a emoção é agendada. Soltar antes, ou arrastar o
  mouse pra fora, **cancela** — e o cancelamento devolve a tela ao repouso: sem tremor e com o filtro
  de volta na cor da emoção que realmente vale (a agendada, se houver, senão a de hoje);
- **hover**: aparece o **INVESTIGAR** logo embaixo da emoção;
- checkmark (`✓`) na emoção cuja história já foi resolvida, e um rótulo dizendo qual emoção vale
  *hoje* e qual vale *amanhã*;
- **Sair**, no canto inferior direito, volta pro sonho — o jogador pode investigar quantos espíritos
  quiser, preenchendo um pedaço de cada.

**Tela da história** (view `STORY`)

- a tela é dividida **50/50**: na metade esquerda, a página (`ProfilingPage`) com o texto e as
  lacunas (`ProfilingBlank`) e o glossário do NPC embaixo (`GlossaryPanel`); na metade direita, a
  arte do NPC, sem moldura;
- a seta **Voltar**, no canto inferior esquerdo, volta pra tela de emoções. Ao reabrir uma história
  já resolvida, ela **pisca**. Logo depois do acerto ela **não aparece**: no lugar dela fica o
  *"Clique para continuar"* (ver [A correção da página](#a-correção-da-página));
- `ESC` volta um passo: da história pras emoções, das emoções pro sonho.

**O aviso do rodapé** (`SpiritInteraction` + `ActionPrompt`) — *"Aperte F para investigar o
espírito"* aparece ao chegar perto de um NPC no sonho, **sai de cena enquanto o espírito está
aberto** (a tela cobre tudo; o aviso ficaria escrito por baixo) e volta quando o jogador fecha o
espírito ainda do lado dele. Acordar não devolve o aviso: sem sonho não há espírito.

**HUD do sonho** (`DreamHud`) — o "acordar" que o GDD pede sempre presente na tela do sonho, no canto
inferior esquerdo, com a pergunta *"Deseja sair do mundo dos sonhos?"*. A cama continua funcionando
(`Bed.gd`); os dois caminhos terminam na mesma chamada, `GameClock.start_next_day()` atrás de uma
`DreamTransition`.

---

## As cenas: onde se mexe na UI

**Nenhuma peça da interface é montada em código.** Cada coisa que aparece na tela é uma cena, e o
script só põe o dado no lugar: o que é repetido (uma palavra do glossário, uma lacuna, uma emoção)
é uma cena que o script INSTANCIA, apontada no Inspector de quem instancia.

**O layout é livre.** As peças de `ProfilingScreen.tscn`, `ProfilingPage.tscn` e
`GlossaryPanel.tscn` são nós soltos, posicionados por âncora — não estão presas em
`VBoxContainer`/`HBoxContainer`. Dá pra arrastar cada uma no editor. Os scripts acham os nós pelo
**nome único** (`%Nome`, o "Access as Unique Name" do editor), então mudar um nó de pai também não
quebra nada — **só não renomeie** um nó marcado com `%`. Contêiner sobrou só onde o conteúdo é
montado em código: a barra de filtros, o texto da página e a lista de palavras. As opções de emoção
também são nós soltos na cena (ver [As duas telas](#as-duas-telas)).

Quem quiser trocar
fonte, cor de moldura, cantos, margens ou posição abre a cena e mexe — sem tocar em `.gd`.

| Cena | O que é | Quem a instancia |
| --- | --- | --- |
| `ProfilingScreen.tscn` | A tela inteira: espírito, história, filtro de cor, botões | está na `City.tscn` |
| `ProfilingPage.tscn` | A moldura do papel, a mensagem de resultado e o texto resolvido | a tela (é um nó dela) |
| `ProfilingPageLine.tscn` | Um parágrafo do texto (embrulha sozinho) | a página, um por parágrafo |
| `ProfilingPageWord.tscn` | Uma palavra do texto da história | a página, uma por palavra |
| `ProfilingBlank.tscn` | Uma lacuna | a página, uma por lacuna |
| `GlossaryPanel.tscn` | Título, contagem, os cinco filtros, a pesquisa e a área das palavras | a tela (e, no futuro, o diário) |
| `GlossaryWordChip.tscn` | O retângulo de uma palavra | o glossário, um por palavra descoberta |
| `GlossaryMarkMenu.tscn` | O retângulo de lixo/estrela que abre acima da palavra | está na tela |
| `ProfilingEmotionOption.tscn` | Uma emoção do espírito, com moldura, barra e INVESTIGAR | está na tela, uma por posição (filhas do nó `Emotions`) |
| `WordDiscoveryToast.tscn` | O aviso de palavra nova e o canto do diário | está na `City.tscn` |
| `FlyingWord.tscn` | A palavra que desce pro canto | o aviso, uma por descoberta |
| `DreamHud.tscn` | O "Acordar" e a pergunta de sair do sonho | está na `City.tscn` |

**As cores que o código mexe são as que vêm do conteúdo** — a cor da categoria da palavra e a cor da
emoção. Elas são aplicadas por `self_modulate`/`modulate` POR CIMA do estilo da cena, e não criando
`StyleBox` em código: a borda, o raio do canto e as margens continuam sendo as que estão na cena.
É por isso que o fundo do chip e da lacuna é branco no arquivo — branco é o que aceita tingimento.

> **Menu de marcas:** o retângulo de lixo/estrela é um `Control` comum dentro da tela, e não um
> `PopupMenu`. Um `PopupMenu` é uma *janela*, e janela aberta engole o clique de fora pra se fechar —
> o que fazia o clique direito na palavra do lado não abrir menu nenhum. Sendo um nó da tela, o
> clique chega ao outro chip e o menu só muda de lugar.

---

## Criar conteúdo (sem tocar em código)

Para dar a um NPC a história de uma emoção:

1. **Escreva os textos no CSV** (`translations/translations.csv`, ver `docs/localizacao_Godot.md`):
   uma chave para o texto com lacunas, uma para a história resolvida e uma para o resumo do diário.
   Nunca escreva texto no `.tres`.
2. **Crie as palavras** que faltarem: botão direito em `res://resources/profiling/palavras/` →
   *New Resource* → `GlossaryWord`. Preencha `id`, `text_key` e `category`.
3. **Crie a história**: *New Resource* → `ProfilingStory` em
   `res://resources/profiling/historias/`. Aponte a `emotion` (um `.tres` de
   `res://resources/emocoes/`), as chaves de texto e a lista `solution` — uma palavra por lacuna, na
   ordem dos índices `{0}`, `{1}`, ...
4. **Ponha a história no perfil do NPC**: abra (ou crie) o `NPCProfile` em
   `res://resources/profiling/npcs/`, com `npc_id` igual ao id do `NPCDefinition`. Arraste a história
   pra lista `stories` e **todas as palavras** que o glossário dele pode ter pra `glossary_words`.
5. **Rode o jogo.** Se algo não aparecer, não abra código: o campo `resumo` de cada recurso já diz o
   que está faltando, e o menu de debug (F4) tem *Validar conteúdo do profiling*.

Nenhum passo exige editar script, e nenhum exige mexer em cena.

---

## Os recursos

| Recurso | O que é | Onde mora |
| --- | --- | --- |
| `GlossaryCategory` | Uma categoria de palavra: nome, arma, ação, objeto. Tem a **cor** do retângulo. | `resources/profiling/categorias/` |
| `GlossaryWord` | Uma palavra que o jogador pode descobrir. Aponta a categoria e, se for o caso, as palavras em conjunto. | `resources/profiling/palavras/` |
| `ProfilingStory` | A história de **uma** emoção: texto com lacunas, solução, texto resolvido. | `resources/profiling/historias/` |
| `NPCProfile` | O que se pode descobrir sobre **um** NPC: as histórias e o pool de palavras. | `resources/profiling/npcs/` |

As **artes do NPC** não são nenhum desses: são a cara dele, e moram no `NPCDefinition`
(`resources/npcs/npc_<nome>.tres`), junto do nome e da cor. São duas: `portrait` (o retrato, na
metade direita da página da história) e `spirit_art` (a imagem 1920x1080 que cobre a tela de
escolher a emoção). É lá que a arte é arrastada, e é de lá que o diário e a tela de diálogo vão ler
os mesmos arquivos quando existirem.

Categoria é **recurso, e não enum**, pela mesma razão de `EmotionDefinition` (ver
`docs/sistema_de_npc.md`): categoria é conteúdo. Criar uma categoria nova é criar um arquivo e
escolher a cor no Inspector — nenhum script sabe que "nome é verde".

O perfil **não** mora dentro do `NPCDefinition`: o NPC existe no mundo acordado sem saber que existe
profiling, e um NPC novo entra na cidade sem obrigar ninguém a escrever história nenhuma. NPC sem
perfil simplesmente não tem espírito no sonho.

**Cada NPC tem o pool dele**, e os pools não precisam ser iguais: hoje o Zé tem 17 palavras, a Ana 16
e o policial 20, com algumas palavras aparecendo em mais de um pool (`VINHO` está no da Ana e no do
policial). O glossário é por NPC — descobrir uma palavra para o Zé não a põe no glossário da Ana.

**As emoções vêm do NPC, não de uma lista fixa.** O GDD fala de três emoções por NPC; o projeto usa
emoções modulares em slots (`emotion_first`, `emotion_second`), então a tela mostra as que aquele
NPC tiver. No dia em que existir um terceiro slot, nada no profiling muda.

### O texto com lacunas

O texto vive no CSV, com as lacunas escritas como `{0}`, `{1}`, `{2}`... e a quebra de parágrafo como
`\n`:

```
PROFILING_EXAMPLE_TEMPLATE,"{0} {1} wanted {2} {3} dead...","{0} {1} queria {2} {3} morta..."
```

O índice é proposital, e não um "preenche na ordem": em inglês a ordem das palavras muda, e com
índice a tradução reordena as lacunas sem mexer na solução. A lacuna `{3}` sempre espera a quarta
palavra de `solution`, em qualquer idioma.

---

## As palavras e o glossário

As palavras vêm da exploração: falar com um NPC, receber um insight, interagir com uma evidência.
Toda palavra que serve pro profiling aparece **sublinhada de vermelho** no texto; clicar nela a manda
pro glossário do NPC, com a palavra descendo pro canto do diário e o aviso *"Palavra adicionada ao
Glossário de Zé"* (`WordDiscoveryToast`).

A marcação no texto é a **mesma legenda do GDD**, e vale no CSV:

| No CSV | O que acontece |
| --- | --- |
| `Achei uma [FACA] no beco.` | Uma palavra clicável. |
| `O nome dele era [MARCOS]/[CASTRO].` | Duas palavras; clicar em qualquer uma adiciona **as duas**. |

Quem desenha isso é o `ClickableWordText`, e quem liga o par são as `paired_words` do
`GlossaryWord` — apontadas **num sentido só** (marcar `CASTRO` em `MARCOS` basta). O grupo é
resolvido nos dois sentidos em código (`ProfilingCatalog.find_pair_group`), justamente pra não
precisar de duas referências cruzadas entre dois `.tres`.

O par vale **só na descoberta**: clicar em uma das duas no texto adiciona as duas ao glossário, e
para aí. No preenchimento cada metade é arrastada por conta, e em que lacuna cada uma entra é
escolha do jogador — a página não preenche o par sozinha (e não poderia adivinhar a ordem sem olhar
a solução, o que entregaria a resposta).

**A porta de entrada de qualquer descoberta é uma função só:**

```gdscript
ProfilingJournal.discover_word(&"faca", &"ze")   # pro glossário do Zé
ProfilingJournal.discover_word(&"faca")          # pro glossário de quem tiver a palavra no pool
```

O glossário (`GlossaryPanel`) mostra as palavras descobertas, cada uma num retângulo da cor da
categoria, a contagem `23/36` (descobertas / pool do NPC) e os filtros: **Lixo**, **Estrela**,
**A-Z** e **Categoria**, com a **Lupa** sempre à direita deles.

- Só **um** filtro fica selecionado por vez (a lupa não conta: ela combina com qualquer um).
- O selecionado vai pra primeira posição; os outros ficam **na ordem em que estão na cena**, sem
  se embaralhar. O selecionado pulsa devagar na escala (`Selected Scale`, `Pulse Amount` e
  `Pulse Period`, no Inspector do `GlossaryPanel`).
- **Lixo** e **Estrela** têm dois passos: o 1º clique **ordena** (as marcadas primeiro), o 2º
  **filtra** (só as marcadas, e o botão fica na cor `Only Marked Modulate`), o 3º desliga.
  **A-Z** e **Categoria** ligam e desligam.
- A **Lupa** abre o campo de pesquisa do lado dela; fechar a lupa limpa a pesquisa.

O clique direito numa palavra abre o retângulo de marcas (lixo e estrela), e escolher a marca que
já está posta a remove.

Uma palavra que já está numa lacuna continua na lista, apagada — o jogador conta as palavras que
descobriu, e uma palavra que desaparece ao ser usada parece perdida.

**Os três gestos de uma palavra** (`GlossaryWordChip`), que são de propósito distintos:

| Gesto | O que faz |
| --- | --- |
| Arrastar | **Puxa** a palavra: o chip some do glossário (guardando o lugar) e a palavra inteira segue o cursor, centrada nele. Se ela não entrar em lacuna nenhuma, reaparece. |
| Clique curto | Atalho: põe a palavra na primeira lacuna vazia **da categoria dela**. Numa palavra que já está em lacuna, não faz nada. É o caminho de quem joga de teclado/controle. |
| Clique direito | Abre o retângulo de marcas acima da palavra. |

**Os gestos de uma palavra que já está numa lacuna** (`ProfilingBlank`) são os mesmos, espelhados:

| Gesto | O que faz |
| --- | --- |
| Arrastar para outra lacuna | Move a palavra. A lacuna de onde ela saiu fica vazia já durante o arraste. |
| Arrastar e soltar no glossário | Devolve a palavra: a lacuna esvazia. |
| Arrastar e soltar em qualquer outro lugar | Idem: devolve a palavra. |
| Clique **direito** | Devolve a palavra direto. |

O clique **esquerdo** numa lacuna não tira a palavra: o esquerdo é o botão de arrastar, e pegar a
palavra pra levá-la a outra lacuna não pode correr o risco de devolvê-la ao glossário.

**Cada lacuna tem categoria**: a da palavra esperada nela. A lacuna vazia aparece na cor dessa
categoria e **só aceita palavras dela** — não dá pra pôr um nome onde a frase pede uma arma. Soltar
uma palavra de outra categoria em cima dela é como soltar no nada: a palavra volta pro glossário.
A regra mora em `GlossaryWord.fits_category()`, que a lacuna (no arraste) e a página (no clique
curto) usam.

**Arraste que não termina em lacuna devolve a palavra ao glossário**, e isso vale nos dois sentidos:
puxando da lacuna ou puxando do próprio glossário uma palavra que está em uso. Quem detecta é
`NOTIFICATION_DRAG_END` + `Viewport.gui_is_drag_successful()` — a pergunta "alguém aceitou o drop?".
Quando alguém aceitou (uma lacuna, ou o glossário recebendo palavra vinda de lacuna), quem resolve é
o `_drop_data` de lá; quando ninguém aceitou, o nó que COMEÇOU o arraste devolve a palavra. Sem isso,
soltar no meio do nada deixava a palavra presa na lacuna e o gesto sem desfecho.

No chip, o atalho do clique dispara **ao soltar** o botão, e só se o arraste não tiver começado no
meio. Se ele disparasse na pressão, pegar a palavra para arrastar já a mandaria para a lacuna — e o
arraste ficaria impossível. É o `_press_pending` do chip: a pressão só marca a intenção, e
`_get_drag_data` ser chamada cancela o clique.

Com o mouse em cima, a palavra clareia e faz um lerp pequeno de escala e rotação (`Hover Scale`,
`Hover Rotation Degrees` e `Hover Lerp Speed`, no Inspector do chip). O `_process` do chip liga no
hover e **desliga sozinho** quando a animação assenta, para o glossário não pagar um quadro por
palavra parada.

> **A margem do glossário não é decoração.** A lista de palavras rola dentro de um `ScrollContainer`,
> e `ScrollContainer` **recorta** o que passa das bordas dele. Sem folga, a palavra da ponta era
> cortada justamente ao crescer no hover. Por isso existe o `Margin` entre o `Scroll` e o `Words`, na
> `GlossaryPanel.tscn`: é o espaço que a escala e a rotação ocupam. Ao aumentar `Hover Scale`,
> aumente a margem junto.

---

## A correção da página

Só com a página **inteira** preenchida o jogo diz algo — é explícito no GDD. Aí sai uma das três
mensagens, acima da página:

| Erradas | Mensagem | Cor |
| --- | --- | --- |
| 0 | *Tudo foi preenchido corretamente* | verde |
| 1 ou 2 | *Duas ou menos palavras estão erradas* | amarelo |
| 3+ | *Várias palavras estão incorretas* | vermelho |

A mensagem conta **quantas**, nunca **quais**. É por isso que não existe lacuna marcada em vermelho:
apontar a lacuna errada transformaria a história num jogo de tentativa e erro de uma lacuna por vez.
O único destaque por lacuna é o checkmark verde, e ele aparece **quando tudo está certo**.

O limite de "duas ou menos" é balanceamento: `ProfilingPage.few_wrong_limit`, no Inspector.

Ao acertar tudo, **na hora**: a história é marcada como resolvida → a página é substituída pelo
texto completo → o glossário e a seta de voltar saem da tela → aparece o *"Clique para continuar"*.
Um clique em qualquer lugar (ou Enter, ou ESC) leva à tela de emoções, onde a emoção ganha o
checkmark — e o jogador ainda pode mudar a emoção do NPC pra essa. Reabrir a história depois mostra
o texto completo com a seta de voltar piscando.

A correção é função pura (`ProfilingEvaluation.evaluate`), e é o miolo do autoteste.

---

## A emoção do NPC

Segurar uma emoção **agenda** a mudança: ela vale a partir do dia seguinte. O jogador pode segurar
FELICIDADE, depois TRISTEZA, depois RAIVA — amanhã o NPC acorda com RAIVA, porque foi a última.

Quem guarda a escolha é o `ProfilingJournal` (que a grava no save, com o dia em que ela passa a
valer). Quem a aplica é o `NPCDirector`, na virada de dia, dentro de `_refresh_emotion_slots()` — o
ponto de extensão que `docs/sistema_de_npc.md` já reservava pro sistema de emoção:

```gdscript
_slots[definition.id] = ProfilingJournal.resolve_emotion_slot(definition)
```

`resolve_emotion_slot` promove a escolha quando o dia dela chega e devolve o `starting_slot` do
`.tres` quando o jogador nunca escolheu nada — é por isso que a cidade funciona igual antes do
primeiro sonho. **Nada aqui depende de ordem de evento na virada de dia**: a escolha é guardada com
o dia em que vence, e a pergunta "qual é a emoção dele hoje?" pode ser feita a qualquer momento.

O menu de debug (seção *NPCs*) continua forçando qualquer slot na hora; isso não grava escolha, então
a próxima virada de dia devolve a emoção que o profiling manda.

---

## Os eventos

Declarados em `scripts/singletons/EventBus.gd`, bloco *Profiling*:

| Evento | Quem emite | Quem escuta |
| --- | --- | --- |
| `profiling_requested(npc_id)` | `SpiritInteraction`, menu de debug | `ProfilingScreen` (**1 ouvinte**) |
| `profiling_opened(npc_id)` / `profiling_closed(npc_id)` | `ProfilingScreen` | `DreamHud` |
| `glossary_word_discovered(npc_id, word_id)` | `ProfilingJournal` | `WordDiscoveryToast`; no futuro, o diário |
| `npc_profiling_completed(npc_id)` | `ProfilingJournal` | `ProfilingScreen` (o jogador acorda) |

O que **não** é evento de bus, e por quê:

- **`journal_changed`** (`ProfilingJournal`) é um `signal` direto. O único interessado é a tela
  aberta, que se redesenha — relação direta e permanente entre duas partes do mesmo sistema, que
  `docs/event_bus.md` manda resolver sem engordar o bus.
- **"história resolvida"** e **"emoção agendada"** não têm evento nenhum: hoje ninguém escutaria (o
  diário, a música e o diálogo não existem), e *criar evento porque um dia alguém vai usar* é o erro
  comum que `docs/event_bus.md` lista — o logger do bus, inclusive, acusa evento órfão em tempo de
  execução. Os dois ganchos estão no funil por onde todo acerto e toda escolha passam:
  `ProfilingJournal.mark_story_solved()` e `ProfilingJournal.schedule_emotion_slot()`. Quando o
  primeiro ouvinte existir, declarar o sinal no bus e emitir ali é uma linha em cada lugar.
- **A emoção vigente** não é anunciada: o `NPCDirector` **pergunta** na virada de dia, o que faz
  nada depender de ordem de evento.

---

## O estado: diário e save

`ProfilingJournal` (Autoload) é o dono de tudo o que o jogador fez:

- palavras descobertas, por NPC;
- as palavras que estão nas lacunas de cada história, **mesmo incompletas**;
- histórias resolvidas;
- marcas de lixo/estrela;
- a emoção escolhida pra cada NPC e o dia em que ela passa a valer;
- se o jogador já encontrou o NPC no mundo real (hoje sempre sim — ver
  [O que ainda não existe](#o-que-ainda-não-existe)).

É isso que faz o GDD funcionar: preencher metade de uma página, sair do espírito, acordar, jogar um
dia inteiro e voltar — as palavras continuam nas lacunas onde ele as deixou.

O save usa a chave `profiling` dentro do arquivo do slot, preservando as chaves dos outros sistemas
(`SaveManager`, ver `docs/SaveManager.md`), e grava a cada mudança. Como o `InsightJournal`, ele
carrega e salva sozinho no **slot 1** enquanto não existir dono do slot ativo; `to_dict`/`from_dict`
já são a API desse fluxo.

> **Armadilha do JSON:** na volta do save, todo `StringName` vira `String` e todo `int` vira `float`.
> As conversões na leitura (`StringName(...)`, `int(...)`) são obrigatórias, não estilo — sem elas o
> jogador reencontra palavras que já tinha, e um slot de emoção que volta como `1.0` não casa com o
> enum.

**Criar Autoload exige validação com o Lead de Programação** (guideline). A justificativa aqui é a
mesma do `InsightJournal`: este estado atravessa troca de cena e de dia, e tem que estar no save.

---

## Ferramentas de debug

Seção **Profiling** no menu (F4) e no console (F1):

| Entrada | O que faz |
| --- | --- |
| *Descobrir palavra* | Põe uma palavra no glossário sem precisar achá-la no mundo. |
| *Descobrir todas as palavras* | Enche o glossário de um NPC (ou de todos) — o atalho pra revisar uma página inteira. |
| *Resolver história* | Preenche a história com a solução e a marca como resolvida. |
| *Abrir espírito* | Abre a tela de profiling de um NPC sem precisar achá-lo no sonho. |
| *Listar estado do profiling* | Palavras, histórias e emoção de cada NPC, com o resultado da correção de cada página. |
| *Validar conteúdo do profiling* | Varre o projeto: preenchimento dos recursos, chave que não existe no CSV, perfil de NPC fora do roster, história numa emoção que o NPC não tem. |
| *Autoteste do profiling* | Roda `ProfilingSelfTest`. |
| *Recarregar catálogo* | Descarta a varredura, pra editar um `.tres` e ver o resultado sem reabrir o jogo. |
| *Resetar / Salvar / Carregar profiling* | Estado do diário. |
| *Salvar automático* | Liga/desliga a gravação a cada mudança. |

### O autoteste

`ProfilingSelfTest` confere a **lógica**, sem abrir tela: as três mensagens da correção, a lacuna que
move a palavra em vez de duplicá-la, o parser do texto, as marcas, o agrupamento `[A]/[B]` e a regra
de que a emoção escolhida **não** vale no mesmo dia. Ele usa o diário de verdade, guarda o estado
antes e devolve depois.

Pela linha de comando, saindo com código de erro quando algo falha:

```bash
godot --headless --path . --script res://tests/run_profiling_self_test.gd
```

---

## O que ainda não existe

Estas partes do GDD estão **documentadas e com o gancho pronto**, mas dependem de sistemas que ainda
não chegaram (vários em outras branches). Nenhuma delas é "esqueceram": todas têm o ponto exato onde
entram.

| O que falta | O que já está de pé | Onde ele entra |
| --- | --- | --- |
| **Evidências / inventário** | A descoberta de palavra é uma função pública. | `ProfilingJournal.discover_word(word_id, npc_id)` |
| **Diálogo** | O texto com palavras clicáveis (`ClickableWordText`) e a marcação `[FACA]` já funcionam; a tela de diálogo troca o Label dela por esse nó. | `ClickableWordText.set_marked_text()` |
| **Opções de diálogo liberadas por emoção concluída** | Todo acerto passa por um funil só. | `ProfilingJournal.mark_story_solved()` |
| **História narrada pelo NPC** (o GDD sugere animatic) | A história resolvida aparece como texto na própria página. | `ProfilingScreen._reveal_solved()` |
| **Música curta no acerto** | Não há música no projeto (`docs/AudioManager.md`). | comentário `MÚSICA` em `ProfilingScreen._reveal_solved()` |
| **Diário do jogador** ("Pessoas Importantes", o glossário fora do sonho) | `GlossaryPanel` já funciona **sem história** — é assim que o diário vai usá-lo —, e `ProfilingStory.journal_entry_key` já guarda o texto da entrada. | instanciar `scenes/profiling/GlossaryPanel.tscn`; `ProfilingJournal.mark_story_solved()` |
| **Espírito só aparece depois de conversar no mundo real** | A regra está escrita e ligada. Hoje `has_met()` responde sim pra todo mundo. | desligar `ProfilingJournal.ASSUME_MET_UNTIL_DIALOGUE_EXISTS` e fazer o diálogo chamar `mark_met()` |
| **Convencer o NPC a sair da cidade** | `npc_profiling_completed` é emitido quando todas as emoções são entendidas — e esse tem ouvinte hoje (a tela, que acorda o jogador). | ouvinte de `EventBus.npc_profiling_completed` |

---

## Placeholders

Todo placeholder é identificável na tela, como o guideline exige — e **cada um precisa de uma issue
com a tag "Substituição de Placeholder"** antes do PR.

- **Retrato do NPC**: retângulo com o nome do NPC e a etiqueta *Placeholder - Portrait do NPC*.
  A arte final entra em `NPCDefinition.portrait`, no `.tres` do NPC — nada a mexer no profiling.
- **Arte do espírito**: sem ela, a tela de emoções mostra o fundo escurecido e a etiqueta
  *Placeholder - Arte do espírito do NPC (1920x1080)*. A arte final entra em
  `NPCDefinition.spirit_art`, no `.tres` do NPC.
- **Ícone do diário**, no canto inferior direito: retângulo etiquetado. É o destino da animação da
  palavra.
- **Marcas e checkmarks**: glifos de texto (`✗`, `★`, `✓`), em `GlossaryMark` e `ProfilingBlank`.
- **A tela inteira**: desenhada em `StyleBox` e contêineres, sem arte. A etiqueta
  *Placeholder - Tela de profiling* fica no canto superior esquerdo.
- **O espírito**: no sonho, o NPC continua com o corpo e o sprite do mundo acordado. O que muda hoje
  é a posição fixa (`NPCDefinition.dream_entry`) e o fato de ele poder ser investigado.
- **As histórias**: são seis, uma por emoção dos três NPCs, e **todas são conteúdo provisório de
  programação** — escritas para o sistema ter o que rodar, não pela equipe de GD. A do GDD (a do vinho
  envenenado, que o próprio documento avisa não ter relação com a temática) ficou em **uma só**: a
  TRISTEZA do policial. As outras cinco são inventadas em cima do que a cidade já sugere nos insights
  (o quebra-mar, a maré, as janelas do beco): a raiva do Zé é a obra assinada com o nome de outro, a
  tristeza dele é o barco emprestado com a rede rasgada, o medo da Ana são as batidas na janela, a
  euforia dela são os três dias de festa, e a raiva do policial é o revólver trocado antes da ronda.
  Trocar qualquer uma é editar o CSV e a lista `solution` do `.tres` — nenhum código.

---

## Erros comuns

### Palavra na solução que não está no pool do NPC

A lacuna fica impossível: a palavra nunca chegaria ao glossário do jogador. O `resumo` do
`NPCProfile` acusa, e a validação em lote também. **Toda palavra da solução tem que estar em
`glossary_words`.**

### Número de lacunas diferente do tamanho da solução

`solution` é a autoridade sobre quantas lacunas existem. Se o texto usa `{7}` e a solução tem 7
palavras (índices 0 a 6), aquela lacuna não tem resposta — o `resumo` da história acusa, e a página
nunca fica correta.

### Texto escrito no `.tres`

Nunca. Texto de jogador vive no CSV (`docs/localizacao_Godot.md`), e os campos aqui são todos de
**chave**. Palavra escrita no `.tres` garante localização refeita depois.

### Duas histórias na mesma emoção

Uma delas nunca apareceria: a tela pergunta pela emoção e recebe a primeira. O `resumo` do perfil
acusa.

### Mudar o `id` de uma história

O progresso é gravado **por id de história**. Renomear descarta as lacunas preenchidas e o "já
resolvida" de quem já jogou.

### Marcar o par nos dois `.tres`

Não faça: `MARCOS` aponta `CASTRO` e pronto. Referência circular entre dois recursos é o tipo de
coisa que o Godot não carrega bem, e o grupo já é resolvido nos dois sentidos em código.

### Esperar a emoção mudar no mesmo dia

Ela vale **a partir do dia seguinte**, por design. Pra testar o efeito na hora, use *Forçar emoção*
na seção **NPCs** do menu de debug.

---

## Antes de abrir PR

- [ ] Rodou o autoteste (`tests/run_profiling_self_test.gd`) e ele passou.
- [ ] Rodou *Validar conteúdo do profiling* (F4) e não sobrou problema.
- [ ] Nenhum texto de jogador fora do CSV; nenhuma chave nova sem tradução em `en` e `pt_BR`.
- [ ] Placeholder novo? Issue com a tag "Substituição de Placeholder" criada.
- [ ] Nenhum warning novo no editor.
- [ ] Prints de debug no padrão `[Profiling] - O que aconteceu`; nenhum print temporário sobrando.
