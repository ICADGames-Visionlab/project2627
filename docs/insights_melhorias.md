# Insights — sugestões de melhoria

Levantamento feito sobre a branch `28-implementar-sistema-de-insights`, lendo o código, as cenas, o
conteúdo da cidade e o `docs/insights.md`. Organizado por urgência: primeiro o que já atrapalha quem
joga, depois o que custa pouco e melhora a sensação, por fim decisões de design que pedem conversa
com o time.

**Status (13/09/2026):** 1.1, 1.2, toda a seção 2 e toda a seção 4 foram implementados; cada um traz
uma nota "Como ficou" quando a implementação difere da sugestão. Continuam abertos o 1.3 e a seção 3.

**Mudança de design depois do levantamento (14/09/2026):** o orbe de ambiente passou a abrir de
qualquer distância, e clicar no próprio orbe com a caixa aberta fecha a caixa. Com isso saíram o
estado "apagado" (fora do alcance), a dica "Chegue mais perto" e o tremor do 2.1, e a caixa deixou de
fechar quando o jogador se afasta. O raio da fonte hoje só vale para o canal de personagem.

---

## 1. Já atrapalha quem joga

### 1.1 Com a caixa aberta, clicar em um orbe só fecha a caixa — ✅ resolvido

`InsightBubble._unhandled_input()` fecha a caixa em qualquer clique e chama `set_input_as_handled()`.
O comentário em `scripts/insights/InsightBubble.gd:50` diz que o clique no orbe "nunca chega aqui",
mas na engine a ordem é a inversa: `_input` → GUI → `_unhandled_input` → **só então** o physics
picking que dispara o `input_event` da `Area2D`. A caixa recebe o clique antes do orbe, consome o
evento, e o picking nunca roda.

**Sintoma:** com uma caixa aberta, o primeiro clique em qualquer orbe (outro orbe de ambiente ou uma
cabeça na órbita) só fecha a caixa. Clicar no mesmo orbe para reler também só fecha. O jogador
precisa clicar duas vezes e acha que o clique falhou.

**Para reproduzir hoje:** fique entre a poça e o Building3 (os raios se sobrepõem), abra a caixa da
poça e clique no orbe azul da cabeça do jogador.

**Correção sugerida:** a caixa fecha, mas **não consome** o clique do mouse — o evento continua até
o picking. Se o clique acertou um orbe, o `reveal()` abre o conteúdo novo (e `open_bubble()` já fecha
a caixa anterior). Se não acertou nada, nada mais no mundo escuta clique, então não há efeito
colateral. O `ui_cancel` pode continuar consumindo. Corrigir o comentário junto.

### 1.2 Quem joga de controle não abre insight nenhum — ✅ resolvido

O Input Map tem o analógico configurado nas quatro ações de movimento, mas o único jeito de abrir um
insight é clicar com o mouse. Um jogador de controle anda até o orbe e não tem o que apertar.

**Sugestão:** uma ação `interact` (tecla e botão do controle) que abre o orbe de ambiente clicável
mais próximo, e uma forma de alternar entre os orbes da órbita (ombros do controle, ou a mesma ação
ciclando). O orbe selecionado ganha o mesmo destaque do hover (ver 2.1).

Isso não contradiz a regra "não há tecla para revelar nada": a regra fala de **esconder** orbes atrás
de uma tecla. Aqui o orbe continua sempre visível; a tecla só **ativa** o que já está na tela.

**Como ficou:** `insight_interact` (E / A) e `insight_cycle` (Tab / RB), tratadas pelo
`InsightInteractor` no `Player`. Ver `docs/insights.md`, "Teclado e controle".

### 1.3 Parte do conteúdo lido fica inacessível para sempre

Quando todos os insights de uma fonte já foram lidos, `pick_best()`
(`scripts/singletons/InsightDirector.gd`) devolve sempre o de maior prioridade. No Building1,
depois de ler os dois, o orbe vazado mostra só a argamassa — o texto dos tijolos nunca mais aparece
para o jogador.

**Sugestão:** entre os já lidos, cliques seguidos na mesma fonte alternam em rodízio (um índice por
fonte basta). Novidade continua ganhando de relido, então a regra de escolha não muda para o que
importa. O caderno (3.1) resolve isso de outro jeito, mas o rodízio é barato e vale mesmo com ele.

---

## 2. Barato e melhora a sensação

### 2.1 Hover no orbe — ✅ resolvido

Hoje nada acontece quando o mouse passa por cima. Com `mouse_entered`/`mouse_exited` da `Area2D`:
o orbe cresce um pouco, o cursor vira a mão, e o orbe de cabeça mostra o nome da cabeça.

No orbe **fora do alcance**, o clique hoje é descartado em silêncio
(`scripts/insights/InsightMarker.gd:130`). Um tremor curto ou um "chegue mais perto" no hover diz ao
jogador que o clique foi entendido e o que falta — sem isso, orbe apagado e orbe quebrado parecem a
mesma coisa.

### 2.2 Área de clique maior que o desenho — ✅ resolvido

A forma de colisão tem exatamente o raio do desenho (16 px, `InsightMarker.gd:107`), e a pulsação
encolhe o orbe em até 8% (`InsightMarker.gd:57`). Os orbes de cabeça ainda se movem junto com o
jogador a 450 px/s. É um alvo pequeno e em movimento.

**Sugestão:** um `@export var hit_radius` separado do `radius` visual, algo como 1,5× o desenho.
É padrão em jogo point-and-click e ninguém percebe a diferença, só que o clique "pega".

### 2.3 Orbe de cabeça não diz do que está falando — ✅ resolvido

A fonte é o gatilho, mas o orbe nasce no jogador. Com duas fontes no alcance, o jogador não sabe se
a cabeça vai falar da parede ou da calha. No hover do orbe de cabeça, uma linha fina (ou um brilho)
até a fonte de origem resolve — a `InsightOffer` já carrega a `source`.

### 2.4 Orbe que reacende merece ser visto — ✅ resolvido

Ler a poça concede `puddle_examined`, e o orbe já vazado do Building1 volta a ficar cheio com a
argamassa. É a melhor coisa que o conteúdo atual faz, e acontece em silêncio, geralmente longe da
câmera. Um flash quando o marcador passa de lido para novo (em `set_read`, na transição
`true → false`) transforma isso numa descoberta.

### 2.5 Retorno da primeira leitura — ✅ resolvido

Um som curto quando `insight_revealed` chega com `first_time = true`. O evento já existe no bus,
então é um ouvinte no `AudioManager` sem tocar em `scripts/insights/`.

**Como ficou:** o ouvinte é uma cena própria (`InsightAudio`, na `main.tscn`), e não código dentro do
`AudioManager`: o `AudioManager` é Autoload de script, sem Inspector para escolher o som. Enquanto o
som final não existe, toca um sininho sintetizado em código (placeholder, precisa de Issue).

---

## 3. Decisões de design

### 3.1 Um caderno para o jogador

O `InsightJournal` já guarda tudo o que foi lido, mas o jogador não tem onde rever. Uma tela de
caderno, agrupada por lugar ou por cabeça, dá sentido a coletar observações e resolve de vez o 1.3.

**Cuidado com a regra "insight virando obrigação":** um contador "4/6 nesta área" transforma o
caderno em lista de tarefas. Mostrar só o que foi encontrado, sem total, preserva o papel de
caracterização.

### 3.2 Tela cheia e jogo pausado para uma frase

Os três insights de personagem atuais têm uma frase cada, e cada um pausa o jogo e abre uma tela
cheia. É muito peso para o tamanho do conteúdo, e tende a fazer o jogador evitar os orbes de cabeça.

**Sugestão:** um balão perto do jogador, com a borda na cor da cabeça, para falas curtas; a tela de
diálogo fica para falas longas ou para o dia em que duas cabeças conversarem. A escolha deve ser um
campo explícito no `InsightData`, e não automática pelo tamanho do texto — o tamanho muda com o
idioma.

### 3.3 A cabeça do jogador fala igual ao mundo

O próprio `docs/insights.md` diz que cada cabeça precisa enxergar algo que as outras não enxergam.
No conteúdo atual:

- **Calha** (velho pescador): "quem construiu nunca tinha visto uma maré de verdade" — tem ponto de
  vista. É o modelo.
- **Janelas** e **parede morna** (jogador): são observações neutras, na mesma voz dos insights de
  ambiente. Se o texto não depende de quem fala, é insight de ambiente com passos a mais.

Duas sugestões de conteúdo:

- Reescrever as falas da cabeça do jogador com interpretação ou sentimento, ou movê-las para o canal
  de ambiente.
- Criar pelo menos um objeto com **duas cabeças comentando a mesma coisa**. É a demonstração mais
  clara do motivo de existirem cabeças, e hoje não há nenhum caso assim.

### 3.4 O que `one_shot = false` quer dizer

Com `one_shot = false`, `is_new()` devolve sempre `true` (`InsightDirector.gd`): o orbe pulsa
para sempre e nunca fica vazado. Não parece ser o que alguém quer ao desmarcar a opção. Vale decidir
o caso de uso real antes que um `.tres` dependa disso. Um candidato: "volta a ser novidade quando a
flag X for concedida" (um campo `resets_on_flag`), que casa com o reacender do 2.4.

### 3.5 Slot fixo da cabeça deixa de ser fixo acima do teto

O slot é `posição_no_elenco % max_visible_orbs` (`HeadOrbitLayer._assign_slots()`), e as colisões são
resolvidas na ordem de prioridade das ofertas. Com duas cabeças não aparece; com quatro ou mais, a
posição de uma cabeça passa a depender de quem mais está presente — justamente o que a regra do slot
fixo quer evitar. Opções: um slot por cabeça do elenco (o teto só limita quantos aparecem), ou
documentar que a garantia só vale até o tamanho do teto.

---

## 4. Manutenção

### 4.1 Testes da regra de escolha — ✅ resolvido

`pick_best()`, `candidate_beats()` e `is_open()` são a parte mais sujeita a regressão silenciosa,
e o projeto não tem framework de teste. A validação em lote cobre o **conteúdo**, não a **lógica**.
Uma suíte pequena com GUT (ou uma ação de debug de autoteste) cobrindo "novidade ganha de relido",
"prioridade desempata" e "porta fechada não desenha" pega a regressão antes de alguém procurar um
orbe sumido.

**Como ficou:** autoteste próprio (`InsightSelfTest`), sem adicionar GUT ao projeto — trazer um addon
de teste é decisão do time. Roda pela ação "Autoteste da escolha" do menu de debug e pela linha de
comando (`tests/run_insight_self_test.gd`, sai com código 1 em falha). Ver `docs/insights.md`,
"O autoteste".

### 4.2 Orbe na camada de colisão do mundo — ✅ resolvido

O `InsightMarker` usa a `collision_layer` padrão (1), a mesma do mundo. Hoje é inofensivo, porque a
`InsightSource` só escuta corpos. Mas qualquer `Area2D` futura que use `area_entered` na camada 1
vai detectar orbes. Uma camada própria para os orbes evita o problema antes de ele existir.

**Como ficou:** camada 16, `insight_orbs`, nomeada no `project.godot` (a camada 1 ganhou o nome
`world`).

---

## Ordem sugerida

| # | Item | Esforço | Por quê primeiro | Status |
| --- | --- | --- | --- | --- |
| 1.1 | Caixa engolindo o clique | Pequeno | Bug perceptível no conteúdo que já existe | ✅ |
| 2.2 | Área de clique maior | Pequeno | Uma linha, e o clique para de falhar | ✅ |
| 1.3 | Rodízio de relidos | Pequeno | Conteúdo escrito que o jogador perde | Aberto |
| 2.1 | Hover e orbe fora do alcance | Pequeno | Diferencia "longe" de "quebrado" | ✅ |
| 2.4 / 2.5 | Reacender e som da primeira leitura | Pequeno | Recompensa o encadeamento de flags | ✅ |
| 1.2 | Ação de interagir para controle | Médio | Pré-requisito se o jogo sai com suporte a controle | ✅ |
| 2.3 | Linha até a fonte | Médio | Fica importante com mais cabeças | ✅ |
| 3.x | Caderno, balão de cabeça, voz das cabeças | Conversa | Mudam o que o sistema é, não só como funciona | Aberto |
| 4.x | Autoteste e camada própria | Pequeno | Protege o que já funciona | ✅ |
