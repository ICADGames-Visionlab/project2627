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
| `scripts/npc/NPCRoutine.gd` | Uma rotina inteira. Reaproveitável entre slots e entre NPCs. |
| `scripts/npc/NPCDefinition.gd` | Um NPC: nome, cor, velocidade, as 2 emoções, os dias de trabalho e as 6 rotinas. |
| `scripts/npc/NPCRoster.gd` | A lista dos NPCs que existem no jogo. |
| `scripts/npc/NPCRoutineResolver.gd` | A calculadora: cruza NPC + emoção + relógio e diz onde ele deveria estar. Não é Node. |
| `scripts/npc/NPCDirector.gd` | Nó da cena de gameplay: povoa a cena, move os NPCs quando o relógio anda, registra o debug. |
| `scripts/npc/NPC.gd` | O corpo: anda pelo `Pathfinder`, toca animação, mostra o nome. |
| `scripts/world/Waypoint.gd` | `Marker2D` nomeado que as rotinas apontam. |
| `scripts/shared/Isometric.gd` | Direção → animação e direção → velocidade achatada. Compartilhado com o `Player`. |
| `scenes/npc/NPC.tscn` | A cena do corpo. |
| `resources/npcs/`, `resources/emocoes/` | Os dados: 2 NPCs de exemplo, 11 rotinas, 4 emoções, o roster. |

A divisão entre `NPCRoutineResolver` (calculadora pura) e `NPCDirector` (nó, eventos, cena) é a
mesma que existe entre `GameTime` e `GameClock`, e pelo mesmo motivo: a parte que dá bug é a
aritmética de horário, e assim ela pode ser conferida sem rodar o jogo.

---

## Como o design cria um NPC

1. **Criar as emoções** (se ainda não existirem): `resources/emocoes/emocao_<nome>.tres`, recurso
   `EmotionDefinition`. Precisa de `id`, `name_key` (chave do CSV) e uma cor.
2. **Criar as rotinas**: `resources/npcs/rotinas/rotina_<npc>_<situacao>.tres`, recurso `NPCRoutine`.
   Vá adicionando entradas; o campo `resumo` mostra a rotina em ordem e aponta o que falta.
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
| **Listar NPCs** | Emoção vigente, tipo de dia, rotina escolhida, entrada atual, próxima entrada e em quantos minutos. |
| **Listar waypoints da cena** | Os nomes exatos que as rotinas devem escrever. |
| **Validar rotinas** | Varre o roster: campo faltando, horário nunca alcançado, cena inexistente, waypoint que não existe. |
| **Desenhar caminho dos NPCs** | Desenha o trecho que falta percorrer, de cada NPC em cena. |

### Como testar uma rotina inteira em um minuto

1. Rode a `City.tscn` (F6 no editor, ou `--path . scenes/City.tscn`).
2. F1 → `npcs_listar_npcs` pra ver onde cada um está e o que vem depois.
3. Seção **Tempo** → *Avançar minutos* pra atravessar o dia. Cada entrada da rotina acontece na hora.
4. **Forçar emoção** e repetir: são as outras rotinas do mesmo NPC, sem esperar nada.

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
| 4 | **Dia de exceção** | Uma rotina que vale por um dia só, escolhida na virada de dia — "depois do colapso, ele passa o dia inteiro no hospital". Entra no mesmo gancho da emoção (`_refresh_emotion_slots`), sem tocar na resolução. | — | Baixo |
| 5 | **Ronda e perambulação** | Um tipo de entrada que cobre vários pontos ("patrulha entre banco e prefeitura das 07:00 às 17:00") ou uma área. Hoje dá pra escrever ronda como várias entradas, mas fica trabalhoso e sai idêntico todo dia. | 1 | Médio |
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
- [ ] Entradas de rotina em múltiplos de 5 min, e dentro da janela jogável do `TimeSettings`.
- [ ] Waypoint novo posicionado no chão, com nome único na cena.
