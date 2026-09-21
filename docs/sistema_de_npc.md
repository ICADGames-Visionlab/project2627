# Sistema de NPC

Cada NPC do HopeFarm cumpre uma rotina própria, e qual rotina ele cumpre depende de duas coisas: a
**emoção vigente** dele e se hoje é **dia de trabalho ou de folga** pra ele. São seis rotinas por
NPC, todas definidas em arquivos que o design abre no Inspector.

---

## A ideia

Uma rotina é uma lista de entradas, e cada entrada diz três coisas:

```
[horário, cena, waypoint]     # "às 12:00, na cidade, na praça"
```

A entrada não diz quanto tempo ele fica: ele fica **até a entrada seguinte**. É isso que torna a
rotina de um dia inteiro uma lista de cinco ou seis linhas em vez de uma agenda com início e fim em
cada compromisso.

Quem escolhe a rotina é a combinação de emoção e calendário:

|              | dia de trabalho           | dia de folga              |
|--------------|---------------------------|---------------------------|
| **neutro**   | `routine_neutral_workday` | `routine_neutral_day_off` |
| **emoção 1** | `routine_first_workday`   | `routine_first_day_off`   |
| **emoção 2** | `routine_second_workday`  | `routine_second_day_off`  |

> **Slot, não emoção.** As rotinas são indexadas por *slot* (neutro / primeira / segunda), e cada
> NPC diz quais emoções do catálogo preenchem seus dois slots. A emoção 1 do Zé é raiva e a da Ana é
> medo — e as duas rodam exatamente no mesmo código, porque a resolução de rotina nunca pergunta
> *qual* emoção está vigente, só *qual slot*.

> **E quem não cabe nesse molde?** Um policial que ronda a cidade não *fica* em lugar nenhum entre
> 08:00 e 17:00: ele circula. Esses casos têm um espaço próprio e opcional na rotina, as
> [exceções](#exceções-de-rotina).

---

## A decisão que explica o resto: a posição é derivada

No Godot só existe **uma cena viva por vez**. Se a rotina do Zé diz "07:00, interior da padaria,
forno" enquanto o jogador está na cidade, não existe nó do Zé em lugar nenhum para andar até o forno.

Em vez de simular os NPCs fora da cena, o sistema **deriva** a posição do relógio:

```
entrada vigente = última entrada da rotina cujo horário já passou
```

Isso é uma função pura, recalculada a qualquer momento. Consequências:

- **Não existe estado de NPC pra dessincronizar.** A posição não é guardada em paralelo ao relógio —
  é uma divisão do relógio, do mesmo jeito que hora e dia são divisões de `total_minutes`
  (ver `docs/sistema_de_tempo.md`).
- **Pular o tempo sai de graça.** `advance(600)` no menu de debug, dormir, carregar um save: em
  todos os casos é só resolver de novo. Não existe "catch-up" a simular.
- **Voltar pra uma cena horas depois funciona.** Cada NPC aparece onde deveria estar, sem nenhuma
  simulação rodando em background.

O preço, explícito: o NPC não "anda de verdade" fora da cena do jogador, e não há interpolação de
trajeto entre cenas. Para um jogo em que o jogador vê uma cena por vez, isso é invisível — e é o
mesmo preço que Stardew Valley paga ao teleportar o NPC quando a location é carregada.

---

## Os arquivos

| Arquivo | O que é |
|---|---|
| `scripts/npc/EmotionDefinition.gd` | Uma emoção do catálogo (raiva, medo...). Recurso, não enum: o design cria emoção nova sem tocar em código. |
| `scripts/npc/NPCRoutineEntry.gd` | Uma linha `[horário, cena, waypoint]`. |
| `scripts/npc/NPCRoutineException.gd` | Uma **exceção** à rotina padrão: faixa de horário em que um comportamento especial assume o NPC. Classe abstrata; opcional. |
| `scripts/npc/NPCPatrol.gd` | A **ronda**, primeira exceção: o NPC circula por uma lista de pontos. É o caso do policial. |
| `scripts/npc/NPCRoutine.gd` | Uma rotina inteira, com as exceções opcionais. Reaproveitável entre slots e entre NPCs. |
| `scripts/npc/NPCDefinition.gd` | Um NPC: nome, cor, velocidade, as 2 emoções, os dias de trabalho e as 6 rotinas. |
| `scripts/npc/NPCRoster.gd` | A lista dos NPCs que existem no jogo. |
| `scripts/npc/NPCRoutineResolver.gd` | A calculadora: cruza NPC + emoção + relógio e diz onde ele deveria estar, na rotina padrão ou numa exceção. Não é Node. |
| `scripts/npc/NPCDirector.gd` | Nó da cena de gameplay: povoa a cena, move os NPCs quando o relógio anda, registra o debug. |
| `scripts/npc/NPC.gd` | O corpo: anda pelo `Pathfinder`, toca animação, mostra o nome. |
| `scripts/world/Waypoint.gd` | `Marker2D` nomeado que as rotinas apontam. |
| `scripts/shared/Isometric.gd` | Direção → animação e direção → velocidade achatada. Compartilhado com o `Player`. |
| `scenes/npc/NPC.tscn` | A cena do corpo. |
| `scripts/npc/NPCRoutineSelfTest.gd` | O autoteste da resolução, exceções incluídas. Roda pelo menu de debug ou por `tests/run_npc_routine_self_test.gd`. |
| `resources/npcs/`, `resources/emocoes/` | Os dados: 3 NPCs de exemplo (Zé, Ana e o policial, que tem ronda), 17 rotinas, 3 rondas, 4 emoções, o roster. |

A divisão entre `NPCRoutineResolver` (calculadora pura) e `NPCDirector` (nó, eventos, cena) é a
mesma que existe entre `GameTime` e `GameClock`, e pelo mesmo motivo: a parte que dá bug é a
aritmética de horário, e assim ela pode ser conferida sem rodar o jogo.

---

## Como o design cria um NPC

1. **Criar as emoções** (se ainda não existirem): `resources/emocoes/emocao_<nome>.tres`, recurso
   `EmotionDefinition`. Precisa de `id`, `name_key` (chave do CSV) e uma cor.
2. **Criar as rotinas**: `resources/npcs/rotinas/rotina_<npc>_<situacao>.tres`, recurso `NPCRoutine`.
   Vá adicionando entradas; o campo `resumo` mostra a rotina em ordem e aponta o que falta. Se o NPC
   circula em vez de ficar parado (o policial), a rotina ganha uma
   [exceção](#exceções-de-rotina) no campo `Exceptions`.
3. **Criar o NPC**: `resources/npcs/npc_<nome>.tres`, recurso `NPCDefinition`. Preencher nome, cor,
   velocidade, as duas emoções, os dias de trabalho e apontar as seis rotinas.
4. **Arrastar pro roster**: `resources/npcs/npc_roster.tres`.

Pronto — nenhuma edição de código e nenhuma cena tocada. Se um slot ficar vazio, o NPC não quebra:
cai no fallback (abaixo) e o `resumo` avisa.

### Criando um waypoint

Um `Marker2D` com o script `Waypoint.gd`, posicionado **no chão** (é onde os pés do NPC vão parar).
O nome do nó é o identificador que a rotina aponta; se você preferir que sejam diferentes (nó em
`PascalCase`, identificador em `snake_case`, como está na `City.tscn`), preencha `waypoint_id`.

No editor ele desenha o próprio identificador ao lado do ponto, e reclama se dois waypoints da cena
tiverem o mesmo identificador. Em jogo, o console tem **Listar waypoints da cena**.

### A cadeia de fallback

Quando o slot pedido está vazio, a resolução desce um degrau:

```
(slot pedido, tipo de dia)  ->  (neutro, tipo de dia)  ->  (neutro, trabalho)  ->  nenhuma
```

É o mesmo princípio das chaves de agenda do Stardew Valley: sempre existe um degrau abaixo, e o
último é o neutro de dia de trabalho. Uma emoção que o design ainda não detalhou faz o NPC se
comportar como sempre, em vez de deixá-lo parado sem rotina.

### Duas convenções de autoria que valem ouro

- **A última entrada do dia é a casa dele.** Quando o relógio está antes da primeira entrada (o
  jogador acabou de acordar), a entrada vigente é a *última* do dia — é onde ele passou a noite.
- **Para sair de cena com elegância, ponha um waypoint na porta.** Uma entrada na porta pouco antes
  da entrada que troca de cena faz o NPC caminhar até a porta e só então desaparecer. Não existe
  mecanismo especial pra isso: é só a rotina dizendo o que dizer.

---

## Exceções de rotina

A rotina padrão responde "onde ele está agora?" com **um ponto**, que vale até a entrada seguinte.
Isso cobre quase todo mundo, mas não o policial: entre 08:00 e 17:00 ele não *fica* em lugar nenhum,
ele *circula*. Dá pra escrever a ronda como uma entrada a cada meia hora, mas fica trabalhoso, esconde
a ideia ("isto é uma ronda") em vinte linhas, e cada rotina que a repete precisa da própria cópia.

Para esses casos a rotina tem um espaço **opcional**: a lista `exceptions`. Cada exceção tem uma
**faixa de horário** e um comportamento especial que assume o NPC dentro dela.

- **Vazio é o normal.** O campo não é obrigatório e nenhum NPC precisa saber que ele existe. Uma rotina
  sem exceção resolve exatamente como resolvia antes de as exceções existirem.
- **Dentro da faixa a exceção manda; fora dela a rotina padrão vale sozinha.** A rotina padrão continua
  correndo por baixo da ronda, então, quando a faixa acaba, vale a entrada que ela tem *para aquele
  horário* (e não a que estava valendo quando a ronda abriu). Ninguém escreve a "volta".
- **Onde duas faixas da mesma rotina se sobrepõem, vale a primeira da lista.** O **Validar rotinas**
  avisa da sobreposição, porque quase sempre é engano.
- **Continua sendo uma função do relógio.** A exceção não guarda estado: dado o minuto do dia, ela diz
  onde o NPC está. Pular o tempo, dormir e carregar um save funcionam como sempre, sem código nenhum.
- **A exceção é da rotina, não do NPC.** Cada um dos seis slots pode ter a sua ou nenhuma: a ronda do
  policial na raiva não é a do neutro. E o mesmo recurso pode ser reaproveitado em várias rotinas, como
  uma rotina inteira é reaproveitada entre slots.

> **Não confundir com "dia de exceção"** (feature #4, mais abaixo): aquela seria uma rotina que vale um
> dia inteiro, escolhida na virada de dia. A exceção de rotina é uma **faixa de horário dentro do dia**.

### A ronda

`NPCPatrol` é a primeira exceção: o NPC circula por uma lista de pontos, ficando um tempo em cada um.

| Campo | O que é |
|---|---|
| Faixa de horário | Quando a ronda vale (`start_hour`/`start_minute` até `end_hour`/`end_minute`), em relógio de parede. O fim é **exclusivo**: numa ronda das 08:00 às 17:00, às 17:00 ela já acabou. Fim antes do começo atravessa a meia-noite (22:00 às 02:00). Começo igual ao fim é **o dia inteiro**. |
| `scene_path` | A cena da ronda. **Uma só**: circular pela cidade é uma ronda; entrar na padaria já é trabalho de uma entrada da rotina. |
| `waypoints` | Os pontos, na ordem em que ele passa (o nome de um `Waypoint` da cena, o mesmo campo de uma entrada). Chegou no último, volta ao primeiro. **Repita um ponto** pra escrever ida e volta numa rua: `A, B, C, B`. |
| `dwell_minutes` | Quanto tempo ele fica **parado** em cada ponto, **contado a partir da chegada**: a caminhada até o ponto é somada por fora. Múltiplo de 10: o relógio só anuncia a passagem do tempo de 10 em 10 minutos. |

O ponto em que ele está é uma conta, não um estado guardado. Cada parada dura **a caminhada até o ponto mais
o tempo parado**, e a ronda passa pelas paradas em ordem, dando a volta na lista de pontos.

A caminhada é **calculada**, e não medida com o NPC andando: o `NPCDirector` acha o caminho de verdade
(Pathfinder) entre os dois pontos, percorre na velocidade do NPC (a mesma conta do movimento,
`Isometric.walk_seconds`) e arredonda **pra cima** em blocos de 10 minutos, o passo do relógio. A primeira
parada caminha desde onde ele estava quando a faixa abriu (a entrada da rotina padrão do minuto anterior); se
ele já estava no primeiro ponto, ou vinha de outra cena, não caminha.

Por isso a ronda continua **idêntica todo dia**, que é justamente o que o jogador aprende observando, e pular
o tempo, dormir e voltar à cena funcionam sem simular nada. Variação por dia ou por condição é uma feature à
parte (a #8, abaixo): sortear o ponto a cada tique quebraria a posição derivada.

#### O policial, por extenso

A rotina neutro/trabalho do policial (`rotina_policial_trabalho.tres`) tem três entradas e uma exceção:

```
entradas:   06:00  casa_do_policial
            07:30  quartel_porta
            19:00  casa_do_policial
exceção:    ronda 08:00-17:00, 30 min parado em cada ponto (ronda_policial_centro.tres):
            quartel_porta -> banco_da_praca -> praca -> feira -> praca -> banco_da_praca
```

E o dia dele, na prática:

```
06:00 casa  ->  07:30 quartel  ->  08:00 a ronda começa (cada volta = 6 tempos parados + as caminhadas)  ->  17:00 a ronda acaba
            ->  volta ao quartel (a entrada das 07:30 é a que vale às 17:00)  ->  19:00 casa
```

As emoções mudam a **ronda**, não só o horário: na tristeza ela é mais curta e lenta (09:00 às 15:00, 40 min
parado em cada ponto); na raiva é mais longa e inquieta (08:00 às 18:00, 20 min parado em cada ponto, e passa
pelo beco, que é longe). No dia de folga não há exceção nenhuma: as rotinas de folga dele são só entradas.

#### Como o design cria uma ronda

1. **Criar a ronda**: `resources/npcs/rondas/ronda_<npc>_<situacao>.tres`, recurso `NPCPatrol`. Preencha a
   faixa, a cena, os pontos e o tempo parado em cada um.
2. **Apontar na rotina**: no campo `Exceptions` de cada `NPCRoutine` que deve ter essa ronda, adicione o
   `.tres`. Quando a ronda só serve àquela rotina, dá pra criá-la direto ali (*Add Element*, depois
   *New NPCPatrol*).
3. **Conferir**: o campo `resumo` da rotina mostra a ronda por extenso e aponta o que está errado. Em jogo,
   **Validar rotinas** confere cena e waypoints, e **Listar NPCs** mostra a exceção valendo.

> O `resumo` de uma rotina é gravado no arquivo dela. Como a ronda é um arquivo à parte, mexer nela não
> reescreve o `resumo` das rotinas que a usam até elas serem salvas de novo. Isso não muda o jogo: quem
> vale é sempre a ronda, e o **Validar rotinas** e o **Listar NPCs** leem o dado vivo.

O que o `resumo` e o **Validar rotinas** apontam numa ronda: sem cena, sem pontos, ponto vazio, um ponto só,
tempo parado fora do passo do relógio, faixa curta demais pra passar por todos os pontos, faixa depois do
fim do dia jogável, cena ou waypoint que não existe. E, na rotina: faixas que se sobrepõem, e rotina sem
nenhuma entrada cuja exceção não cobre o dia inteiro (fora da faixa, o NPC não teria onde ficar).

A conta de "faixa curta demais" existe em duas versões: no `resumo` ela não conta a caminhada (o editor não
conhece o cenário, então é o mínimo que fica de fora), e o **Validar rotinas** em jogo refaz a conta com a
caminhada de verdade e avisa quando só ela faz um ponto não caber.

#### Quanto ele fica parado, de verdade

Pelo menos o `dwell_minutes`, e às vezes até 9 minutos a mais: a caminhada é arredondada pra cima em blocos
de 10 minutos (o passo do relógio), e o NPC só é mandado pro ponto seguinte no tique que vem depois. É o preço
de a ronda seguir sendo uma conta do relógio, e na conta o erro é sempre pra mais, nunca pra menos.

Três casos em que a parada sai menor que o combinado:
- **A última parada** é cortada pelo fim da faixa: o fim é exclusivo, e às 17:00 a rotina padrão já mandou ele
  embora.
- **A primeira parada** conta a partir da abertura da faixa. Se ele já estava no ponto (o normal, por isso as
  rondas do policial abrem no quartel) ele já vinha parado; se vinha de longe, a caminhada dele entra na conta.
- **Algo travar o NPC no caminho** (o Player parado na rota, por exemplo) encurta a parada dele, mas não
  desloca a agenda: a caminhada é calculada, não medida.

Quem quiser o tempo parado mais curto que o passo do relógio esbarra no mesmo limite de todo o sistema: o
relógio só avisa de 10 em 10 minutos de jogo.

### Um tipo novo de exceção

A ronda é uma implementação do contrato de `NPCRoutineException`. Um tipo novo (alternar entre dois pontos com
tempos diferentes, sair pra outra cena por um tempo, o que o design inventar) é um script novo, com `@tool`, que
**estende essa classe** e implementa duas funções. Nada mais muda: nem o resolver, nem o diretor, nem as rotinas
que já existem.

| Função | O que responde |
|---|---|
| `get_stop(elapsed_minutes, travel)` | Onde o NPC está, `elapsed_minutes` depois do começo da faixa, escrito como uma entrada de rotina (`NPCRoutineEntry.from_clock_minutes`) cujo horário é o de quando ele é mandado pra lá. `null` quando a exceção não sabe: a rotina padrão vale. |
| `get_minutes_until_stop_change(elapsed_minutes, travel)` | Daqui a quantos minutos ele muda de lugar sem a faixa ter acabado. `0` se ele fica onde está até o fim. |

O `travel` (`NPCRoutineException.TravelTimes`) diz quanto a caminhada entre dois waypoints leva, e existe pro
tempo parado poder contar a partir da chegada. Pode ser `null` (caminhada zero) e tipo que não precisa dele
ignora. As duas respostas precisam concordar sobre onde cada parada começa e termina, e o autoteste confere isso
minuto a minuto.

Se quiser que as ferramentas conheçam o tipo novo: `get_places()` (os lugares que o **Validar rotinas**
confere), `collect_issues()` (o que aparece no `resumo`) e `describe()` (a linha do `resumo` e do **Listar
NPCs**). A faixa de horário, a sobreposição e a conversão pro relógio de jogo já vêm da classe base.

A regra que vale pra qualquer tipo: **a exceção é função do relógio**. Deixe a conta em `get_stop` e não
guarde em variável onde o NPC está, senão o tempo pulado e o save deixam de funcionar.

Dois limites do contrato, pra ninguém descobrir tarde: a parada é sempre **uma cena e um waypoint** (nunca uma
coordenada solta, então "vagar por uma área" só existe como escolha entre waypoints), e `get_stop` só sabe quantos
minutos se passaram desde a abertura da faixa, **não o dia nem a emoção**. Variação por dia ou por condição
pediria estender o contrato (ver a feature #8, abaixo).

---

## O horário é relógio de parede

O campo de horário da entrada é `00:00`–`23:55`, como o design pensa. A conversão pro minuto interno
do dia acontece em um lugar só (`NPCRoutineEntry.get_minutes_into_day`), porque **o minuto 0 do dia
de jogo é a hora de acordar, não a meia-noite** (ver `docs/sistema_de_tempo.md`). Duas consequências:

- Uma entrada à `01:00`, com `wake_hour` 06:00, é de madrugada no **fim do mesmo dia de jogo**.
- Uma entrada depois do fim do dia jogável **nunca é alcançada**. Com o `TimeSettings` atual (acorda
  06:00, 16 h jogáveis, dia acaba às 22:00), uma entrada às `23:00` só vale como "onde ele passou a
  noite". O comando **Validar rotinas** aponta esses casos.

E uma precisão: o relógio anuncia a passagem do tempo a cada `GameClock.TICK_MINUTES` (10 minutos de
jogo), então uma entrada às `14:03` passa a valer no anúncio das `14:10`. Por isso o campo de minuto
tem passo de 5 — e por isso não existe evento por minuto (seriam 1440 notificações por dia pra cidade
inteira, sem diferença visível).

As faixas das [exceções](#exceções-de-rotina) seguem a mesma regra: relógio de parede, com o dia de jogo
começando na hora de acordar. É por isso que uma ronda das `05:00` às `07:00` atravessa a hora de acordar
sem reiniciar o ciclo, e uma das `22:00` às `02:00` atravessa a meia-noite.

---

## Emoção: o que existe e o que não existe

O que existe: cada NPC tem duas emoções, um slot vigente, e o slot escolhe a rotina.

O que **não** existe: qualquer coisa que mude o slot. Por decisão de escopo, a emoção vigente é
escolhida **na virada de dia** — e é exatamente isso que `NPCDirector._refresh_emotion_slots()` faz,
hoje lendo o `starting_slot` que o design marcou no `.tres`.

> **É aqui que o sistema de emoção entra**, quando existir: dentro dessa função, e em nenhum outro
> lugar. Todo o resto do sistema só consulta o slot já decidido, e por isso não precisa saber nada
> sobre o que causa emoção. A API pública já está de pé: `NPCDirector.set_emotion_slot(id, slot)`.

Até lá, o menu de debug força qualquer slot em qualquer NPC, o que permite revisar as seis rotinas de
um NPC em dois minutos.

---

## Debug (F4 / F1, seção **NPCs**)

| Entrada | O que faz |
|---|---|
| **Forçar emoção** | `npc` + `neutro/emocao1/emocao2`. O NPC recalcula a rotina e **anda** até o novo lugar. |
| **Forçar tipo de dia** | `automatico/trabalho/folga` — pra ver a rotina de folga numa terça. |
| **Trazer NPC até o player** | Atalho pra ver um NPC de perto. Não muda rotina: no próximo tique ele volta pra dele. |
| **Listar NPCs** | Emoção vigente, tipo de dia, rotina escolhida, entrada atual, próxima entrada e em quantos minutos. Com uma exceção valendo (a ronda), "agora" é a parada em que ele está, "próxima" é a próxima parada (ou a volta da rotina padrão) e uma linha `exceção:` descreve a ronda. |
| **Listar waypoints da cena** | Os nomes exatos que as rotinas devem escrever. |
| **Validar rotinas** | Varre o roster: campo faltando, horário nunca alcançado, cena inexistente, waypoint que não existe. Nas exceções: faixa depois do fim do dia jogável, ronda sem pontos, faixas que se sobrepõem, cena e waypoints da ronda que não existem. |
| **Autoteste das rotinas** | Confere a lógica da resolução (rotina padrão e exceções) contra rotinas montadas em memória. Também roda sem abrir o jogo: `godot --headless --path . --script res://tests/run_npc_routine_self_test.gd`. |
| **Desenhar caminho dos NPCs** | Desenha o trecho que falta percorrer, de cada NPC em cena. |

### Como testar uma rotina inteira em um minuto

1. Rode a `City.tscn` (F6 no editor, ou `--path . scenes/City.tscn`).
2. F1 → `npcs.listar_npcs` pra ver onde cada um está e o que vem depois.
3. Seção **Tempo** → *Avançar minutos* pra atravessar o dia. Cada entrada da rotina acontece na hora.
4. **Forçar emoção** e repetir: são as outras rotinas do mesmo NPC, sem esperar nada.
5. Pra ver uma ronda: avance até o horário dela (a do policial abre às 08:00) e liste os NPCs; a linha
   `exceção:` diz qual ronda está valendo, e cada avanço de meia hora muda a parada. O console também
   registra o instante em que a ronda começa e termina (`"policial" assumiu a exceção: ...` e `"policial"
   saiu da exceção ...`). **Forçar tipo de dia** → `folga` mostra o policial sem ronda.

---

## Encaixe com os outros sistemas

- **Relógio.** O diretor escuta `EventBus.time_changed` (tique de 10 min, que também chega ao iniciar
  a sessão e ao carregar save) e `EventBus.day_changed` (reescolhe a emoção e reposiciona todo mundo).
  `hour_changed` **não** é usado: a granularidade de 10 minutos já o contém. Nenhum `Timer` em lugar
  nenhum — `Timer` não congela junto com o relógio, não acelera junto e não sobrevive a um save.
- **Pausa e congelamento.** Os NPCs só andam enquanto `GameClock.is_running() and not
  GameClock.is_frozen()`. Durante diálogo, cutscene, troca de cena ou fim do dia, a cidade para junto
  com o tempo.
- **Pathfinder.** O NPC pede caminho como qualquer agente:
  `find_path(global_position, destino, [get_rid()])`. Se não há caminho ou ele trava, espera
  `repath_interval` e tenta de novo; depois de `give_up_attempts` tentativas, assume a posição do
  waypoint. A rotina é um compromisso: é melhor o NPC estar no lugar certo do que encalhado numa
  quina pelo resto do dia.
- **Dois NPCs no mesmo waypoint.** O diretor espalha os NPCs em volta do ponto (`waypoint_scatter`,
  exportado, 56 px por padrão), com deslocamento derivado do id — e não sorteado, senão o destino
  mudaria a cada tique do relógio e o NPC passaria o dia dando passinhos em volta do ponto. Sem
  isso, dois NPCs que a rotina manda pro mesmo lugar na mesma hora miram o mesmo pixel, se empurram
  e um deles acaba desistindo do caminho.
- **Camadas de física.** Obstáculos na camada 1, **agentes (Player e NPCs) na camada 2**. Isso é
  requisito do `Pathfinder`: ele monta a lista de corpos a ignorar uma vez, no `rebuild()`, então um
  NPC que nascesse depois — na mesma camada dos obstáculos — apagaria arestas do grafo e faria
  caminhos falharem dependendo de quem estava onde. Consequência a lembrar: **toda Area2D que precise
  detectar o jogador tem que ter a máscara na camada 2** (ver `Structure.AGENTS_LAYER`).
- **Y-sort.** O diretor instancia os corpos no nó apontado em *Agents Parent*, que precisa ser o nó
  com `y_sort_enabled` da cena (o `YSort` da `City.tscn`).
- **`Structure`.** Só fica transparente para o `Player`, de propósito: prédio piscando por causa de
  NPC passando atrás seria ruído visual.
- **EventBus.** O sistema **não declara nenhum evento novo**. Não há fato aqui que três sistemas
  precisem ouvir ainda; o NPC avisa a própria chegada por um `signal` local, escutado pelo diretor que
  vive na mesma cena (a regra está em `docs/event_bus.md`). O primeiro evento natural é
  `npc_emotion_changed`, quando o sistema de emoção existir e houver um fato a anunciar.

---

## Placeholders

- **Corpo do NPC**: todos usam o `SpriteFrames` do Player (`resources/player_sprite_frames.tres`),
  diferenciados por `modulate` e pelo nome acima da cabeça. Chave `PLACEHOLDER_NPC_BODY`.
- **Interior da padaria**: `scenes/BakeryInterior.tscn` existe só pra as rotinas de exemplo terem uma
  segunda cena pra apontar (é o que exercita o NPC sair e voltar). Não é jogável ainda. Chave
  `PLACEHOLDER_BAKERY_INTERIOR`.
- **Posição dos waypoints da `City.tscn`**: chutadas pra o sistema poder ser testado. O design deve
  arrastá-las pros lugares certos — e é só arrastar, nenhuma rotina precisa ser editada.

- **Rotina do policial**: os horários, os pontos da ronda e a posição do waypoint `casa_do_policial` são
  chutes pra exercitar o mecanismo de exceção. A rotina do policial escrita pelo design substitui esses
  arquivos (`npc_policial.tres`, `rotina_policial_*.tres`, `ronda_policial_*.tres`) sem mudar código.
  O nome acima da cabeça (`NPC_NAME_POLICIAL`, "Policial") também é provisório.

Os dois primeiros precisam de Issue com a tag "Substituição de Placeholder" antes do PR, como manda
o `docs/GUIDELINE_PROGRAMACAO.md`.

---

## Features futuras

O que existe hoje resolve **onde o NPC está** a cada hora do dia. O que falta é *o que ele faz ali* e
*o que acontece de diferente* — e as duas coisas são camadas por cima da rotina, não reescrita dela.

A lista abaixo saiu da conferência do sistema contra a **rotina do policial**, a primeira rotina de
design escrita por extenso (neutro/triste/raiva × trabalho/folga). Está em ordem de execução: as
primeiras são baratas e independentes, e as últimas dependem das de cima.

| # | Feature | O que entrega | Depende de | Custo |
|---|---|---|---|---|
| 1 | **Atividade na entrada** | Um campo `activity` na entrada dizendo o que o NPC faz ao chegar: dormir, comer, assistir TV, beber, trabalhar. Hoje ele chega e fica parado em idle. É o maior custo-benefício da lista — sozinha, cobre "faz café", "assiste TV", "senta na mesa", "dorme". | — | Baixo |
| 2 | **Ritmo e postura por emoção** | Multiplicador de velocidade (e, depois, conjunto de animações) no `EmotionDefinition`, pra o NPC triste "andar mais devagar e desatento". Hoje a velocidade é do NPC, igual nas seis rotinas. | 1 | Baixo |
| 3 | **Cenário que reage à rotina** | Luz da casa que acende quando o dono está lá, porta que fica destrancada, som vindo de dentro. Fica barato justamente porque a posição é derivada: o objeto do cenário PERGUNTA ("meu dono está aqui agora?") em vez de a rotina ter que conhecer luz e porta. | — | Baixo |
| 4 | **Dia de exceção** | Uma rotina que vale por um dia só, escolhida na virada de dia — "depois do colapso, ele passa o dia inteiro no hospital". Entra no mesmo gancho da emoção (`_refresh_emotion_slots`), sem tocar na resolução. Não é a [exceção de rotina](#exceções-de-rotina), que é uma faixa de horário dentro do dia. | — | Baixo |
| 5 | **Ronda e perambulação** | **A ronda por lista de pontos está pronta** (ver [Exceções de rotina](#exceções-de-rotina)) e não precisou da #1. Falta a **perambulação** por uma *área*, sem lista de pontos, e o NPC *fazer* algo em cada ponto da ronda, que é a própria #1. | 1 | Médio |
| 6 | **Estado persistente de NPC** | Um Autoload (`NPCManager`) + entrada no save para os fatos que precisam sobreviver à troca de cena: emoção vigente, morto, hospitalizado, reputação. É a fundação das features 7 a 10 — sem ela, "o policial morreu" não tem onde morar. **Criar Autoload exige discussão com o Lead de Programação.** | — | Médio |
| 7 | **Sistema de emoção (appraisal)** | O que efetivamente TROCA a emoção vigente na virada de dia. O consumo da emoção já está pronto; falta o que a causa. Ver [Emoção](#emoção-o-que-existe-e-o-que-não-existe). | 6 | Médio |
| 8 | **Condição e acaso na entrada** | Entradas que só valem sob condição ou com chance: "às vezes ele vai pro beco beber", "se o ladrão roubar hoje". É o mesmo mecanismo das chaves de agenda do Stardew, aplicado por entrada. | 6 | Médio |
| 9 | **Influência entre rotinas** | Uma rotina consultar o estado de outro NPC: "a chance de o vizinho salvar o policial depende da emoção do vizinho". Metade já existe — o diretor conhece a emoção de todos (`get_emotion_slot`); falta o lugar de escrever a regra. | 6, 8 | Médio |
| 10 | **Camada de interrupção** | Um evento quebrar a rotina do dia e assumir o controle do NPC: prisão, colapso, ser levado ao hospital, julgamento. A rotina vira o "plano do dia" e o evento passa por cima, por prioridade — é o *package stack* do Skyrim. | 6 | Alto |
| 11 | **Interação e diálogo** | NPC conversando com NPC ("o amigo o visita e eles conversam") e com o jogador ("responde agressivo com a mão no coldre", "o jogador tenta ajudá-lo"). Sistema próprio; daqui só precisa dos ganchos, que já existem (`definition`, `get_body(id)`). | 1 | Alto |
| 12 | **Evasão entre agentes** | Dois NPCs deixarem de se atravancar num vão estreito. Hoje o travamento é tratado (desistir → tentar de novo → assumir a posição) e o espalhamento em volta do waypoint evita o caso comum. Só vale quando incomodar de verdade. | — | Baixo |

### Uma decisão de level design que vem junto

Casa de NPC pode ser **cena própria** (ele some do mapa enquanto está dentro — barato e é o que o
sistema faz melhor) ou **recorte dentro da cena externa** (ele continua visível). A rotina do
policial exige o segundo caso num ponto específico: *"caso o player olhe pela janela semi-aberta,
consegue ver o policial jogado no chão"*. Isso muda como aquela rotina é escrita, e é decisão de
level design, não do sistema.

### Limitações que são escolha, não pendência

- **O NPC não anda "de verdade" fora da cena do jogador.** É a consequência aceita da posição
  derivada (ver [A decisão que explica o resto](#a-decisão-que-explica-o-resto-a-posição-é-derivada)).
  Se um dia importar ver alguém chegando pela rua na hora exata, o que entra é interpolação entre
  duas entradas na cena atual — não simulação global.
- **A emoção não sobrevive à troca de cena.** Hoje o slot é recalculado do `.tres` quando o diretor
  nasce. Como nada muda o slot durante o dia, isso é invisível — e a feature 6 resolve no dia em que
  deixar de ser.

---

## Armadilhas

Checklist rápido pra revisão de PR que mexa em NPC:

- [ ] Nenhum NPC colocado à mão na cena — quem povoa é o `NPCDirector`, a partir do roster.
- [ ] Nenhum `Timer` usado pra marcar hora de rotina.
- [ ] Nenhum nome de NPC ou de emoção escrito direto: só chave do CSV (`NPC_NAME_*`, `EMOTION_*`).
- [ ] Nenhuma posição de NPC guardada em variável — a posição é derivada do relógio.
- [ ] `find_path` chamado sempre com o próprio RID na lista de exclusão.
- [ ] Agente novo entrou na camada de física 2 (e não na 1, dos obstáculos).
- [ ] Area2D nova que precise ver o jogador tem a máscara na camada 2.
- [ ] Rotina nova passou pelo **Validar rotinas** sem apontar problema.
- [ ] Ronda com tempo parado múltiplo de 10 e faixa que dá tempo de passar por todos os pontos, contando a
      caminhada (o **Validar rotinas** em jogo confere).
- [ ] Tipo novo de exceção estende `NPCRoutineException` (com `@tool`) e mantém a posição como conta do
      relógio, sem guardar onde o NPC está.
- [ ] Quem compara entradas compara o **lugar** (`is_same_place`), e não a identidade: a parada de uma
      exceção é uma entrada avulsa, recriada a cada resolução.
- [ ] Mexeu no `NPCRoutineResolver` ou numa exceção? O **Autoteste das rotinas** passa sem nenhum ✗.
- [ ] Entradas de rotina em múltiplos de 5 min, e dentro da janela jogável do `TimeSettings`.
- [ ] Waypoint novo posicionado no chão, com nome único na cena.
