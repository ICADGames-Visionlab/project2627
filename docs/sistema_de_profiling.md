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
4. [Criar conteúdo (sem tocar em código)](#criar-conteúdo-sem-tocar-em-código)
5. [Os recursos](#os-recursos)
6. [As palavras e o glossário](#as-palavras-e-o-glossário)
7. [A correção da página](#a-correção-da-página)
8. [A emoção do NPC](#a-emoção-do-npc)
9. [Os eventos](#os-eventos)
10. [O estado: diário e save](#o-estado-diário-e-save)
11. [Ferramentas de debug](#ferramentas-de-debug)
12. [O que ainda não existe](#o-que-ainda-não-existe)
13. [Placeholders](#placeholders)
14. [Erros comuns](#erros-comuns)
15. [Antes de abrir PR](#antes-de-abrir-pr)

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
sonho (`ProfilingScreen.wake_delay` dá alguns segundos pra ele ler a última história antes).

---

## As duas telas

**Tela do espírito** (`ProfilingScreen`, view `SPIRIT`)

- portrait do NPC no centro, com o nome em cima;
- uma opção por emoção do NPC (`ProfilingEmotionOption`), com o nome na cor da emoção;
- **segurar** o botão esquerdo: a tela treme, o nome cresce, o retângulo em volta enche e a tela
  ganha um filtro na cor da emoção. Quando enche, a emoção é agendada. Soltar antes, ou arrastar o
  mouse pra fora, cancela;
- **hover**: aparece o **INVESTIGAR** logo embaixo da emoção;
- checkmark (`✓`) na emoção cuja história já foi resolvida, e um rótulo dizendo qual emoção vale
  *hoje* e qual vale *amanhã*;
- **Sair**, no canto inferior direito, volta pro sonho — o jogador pode investigar quantos espíritos
  quiser, preenchendo um pedaço de cada.

**Tela da história** (view `STORY`)

- a página (`ProfilingPage`) com o texto e as lacunas (`ProfilingBlank`);
- o glossário do NPC embaixo (`GlossaryPanel`);
- o portrait na direita, o mesmo da tela anterior;
- a seta **Voltar**, no canto inferior esquerdo, volta pra tela de emoções. Depois de uma história
  resolvida, ela **pisca**;
- `ESC` volta um passo: da história pras emoções, das emoções pro sonho.

**HUD do sonho** (`DreamHud`) — o "acordar" que o GDD pede sempre presente na tela do sonho, no canto
inferior esquerdo, com a pergunta *"Deseja sair do mundo dos sonhos?"*. A cama continua funcionando
(`Bed.gd`); os dois caminhos terminam na mesma chamada, `GameClock.start_next_day()` atrás de uma
`DreamTransition`.

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

O **retrato do NPC** não é um desses: ele é a cara do NPC, e mora em `NPCDefinition.portrait`
(`resources/npcs/npc_<nome>.tres`), junto do nome e da cor. É lá que a arte é arrastada, e é de lá
que o diário e a tela de diálogo vão ler o mesmo arquivo quando existirem.

Categoria é **recurso, e não enum**, pela mesma razão de `EmotionDefinition` (ver
`docs/sistema_de_npc.md`): categoria é conteúdo. Criar uma categoria nova é criar um arquivo e
escolher a cor no Inspector — nenhum script sabe que "nome é verde".

O perfil **não** mora dentro do `NPCDefinition`: o NPC existe no mundo acordado sem saber que existe
profiling, e um NPC novo entra na cidade sem obrigar ninguém a escrever história nenhuma. NPC sem
perfil simplesmente não tem espírito no sonho.

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

**A porta de entrada de qualquer descoberta é uma função só:**

```gdscript
ProfilingJournal.discover_word(&"faca", &"ze")   # pro glossário do Zé
ProfilingJournal.discover_word(&"faca")          # pro glossário de quem tiver a palavra no pool
```

O glossário (`GlossaryPanel`) mostra as palavras descobertas, cada uma num retângulo da cor da
categoria, a contagem `23/36` (descobertas / pool do NPC) e os cinco filtros do GDD: **Lixo**,
**Estrela**, **A-Z**, **Categoria** e **Lupa**. Ligar um filtro o preenche e o move pra primeira
posição; eles se combinam. O clique direito numa palavra abre o retângulo de marcas (lixo e
estrela), e escolher a marca que já está posta a remove.

Uma palavra que já está numa lacuna continua na lista, apagada — o jogador conta as palavras que
descobriu, e uma palavra que desaparece ao ser usada parece perdida. Clicar nela a devolve pro
glossário; clicar numa palavra livre a põe na primeira lacuna vazia (é o atalho de quem joga de
teclado ou controle, que não tem como arrastar).

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

Ao acertar tudo, na ordem: a mensagem fica `reveal_delay` segundos → a história é marcada como
resolvida → a página é substituída pelo texto completo → o glossário sai da tela → a seta de voltar
começa a piscar. Na tela de emoções, a emoção ganha o checkmark — e o jogador ainda pode entrar nela
e mudar a emoção do NPC pra essa.

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
- **Ícone do diário**, no canto inferior direito: retângulo etiquetado. É o destino da animação da
  palavra.
- **Marcas e checkmarks**: glifos de texto (`✗`, `★`, `✓`), em `GlossaryMark` e `ProfilingBlank`.
- **A tela inteira**: desenhada em `StyleBox` e contêineres, sem arte. A etiqueta
  *Placeholder - Tela de profiling* fica no canto superior esquerdo.
- **O espírito**: no sonho, o NPC continua com o corpo e o sprite do mundo acordado. O que muda hoje
  é a posição fixa (`NPCDefinition.dream_entry`) e o fato de ele poder ser investigado.
- **A história de exemplo**: as seis histórias em `resources/profiling/historias/` usam o exemplo do
  GDD (que, como o próprio documento avisa, não tem nada a ver com a temática do jogo), aplicado a
  todas as emoções. É conteúdo de teste: dá pra jogar o laço inteiro hoje, e trocar é editar o CSV.

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
