# Insights

Este guia explica o que o mundo e as cabeças do jogador têm a dizer sobre as coisas, e como pôr
conteúdo novo no jogo sem abrir um script.

---

## A ideia

Um insight é uma observação disparada por um ponto do mundo. Ele chega ao jogador por um de dois
canais:

|  | Ambiente | Personagem |
| --- | --- | --- |
| Onde o orbe fica | No objeto, na cena | Flutuando perto do jogador |
| Cor do orbe | Verde, sempre | A cor da cabeça que está falando |
| Quem fala | Ninguém: é o mundo | Uma cabeça (`head_id`) |
| Saída | Caixa in loco, o jogo continua | Tela de diálogo, o jogo para |
| Porta típica | Flags do mundo | A cabeça precisa estar desbloqueada |
| Alcance do clique | Qualquer distância | Sempre perto, por definição |
| Raio da fonte (`interaction_radius`) | Não se aplica | O orbe só aparece com o jogador dentro dele |
| Tamanho do texto | Até 4 linhas | Livre |

Os dois canais usam o mesmo recurso, a mesma fonte, o mesmo marcador e o mesmo clique. Eles só se
separam no fim: onde o orbe nasce, quem fala e para onde vai o texto. Por isso o sistema é um só,
com duas formas de apresentar. Dois sistemas paralelos teriam o dobro de lugares para dar bug.

A posição do orbe indica o canal, e a cor indica quem fala. O orbe no objeto é o mundo; o orbe
orbitando o jogador é uma cabeça, e a cor diz qual. Cor sozinha não resolve daltonismo, e ninguém
decorou a paleta nas primeiras horas de jogo, então todo orbe de cabeça também tem um glifo.

---

## Criar um insight (sem tocar em código)

1. Escreva o texto no CSV: uma chave nova em `MAIUSCULO_COM_UNDERSCORE` no
   `translations/translations.csv` (ver `docs/localizacao_Godot.md`). Nunca escreva o texto no
   `.tres`.
2. Crie o recurso: botão direito em `res://resources/insights/` → *New Resource* → `InsightData`.
   Preencha `id`, `channel`, `text_key` e, se for de personagem, `head_id`.
3. Ponha uma fonte no objeto: arraste `res://scenes/insights/InsightSource.tscn` para dentro do
   objeto (ou do NPC), posicione e arraste o `.tres` para a lista `Insights` no Inspector.
   Prédio com `Structure.gd` é exceção. Ele fica transparente quando o jogador passa atrás dele, e
   o `modulate` passa para os filhos, então o orbe sumiria junto com a parede. Nesse caso, ponha a
   fonte fora do prédio, como filha da cena e depois do `YSort`, como na `main.tscn`.
4. Rode o jogo. Se o orbe não aparecer, não abra código: abra o menu de debug (F4), seção
   *Insights*, e clique em Diagnóstico da cena (ver [Ferramentas](#ferramentas-de-debug)).

O passo 3 é a única montagem feita na cena, e a cena já vem com forma e camadas configuradas.
Nenhum caminho de criação de conteúdo exige acertar `collision_mask` na mão.

### O que o triângulo amarelo acusa

A `InsightSource` é um script `@tool`, então os erros de preenchimento aparecem na árvore de cena
antes de rodar o jogo. Ela acusa fonte sem insight, `id` vazio ou repetido no projeto, `text_key`
vazio ou inexistente no CSV, canal de personagem sem `head_id` e `head_id` que não corresponde a
nenhuma cabeça.

No editor, o mesmo script desenha o orbe de ambiente na posição em que ele vai nascer. Para o canal
de personagem, desenha um gizmo diferente, com uma seta saindo, porque esse orbe não aparece ali: ele
aparece orbitando o jogador. O raio da fonte só é desenhado quando ela tem insight de personagem, o
único canal que ele limita.

---

## O recurso

`InsightData` (`scripts/insights/InsightData.gd`), um `.tres` por insight:

| Campo | Para que serve |
| --- | --- |
| `id` | Identidade do insight. É o que o diário guarda e o que o console recebe |
| `channel` | `ENVIRONMENT` ou `CHARACTER` |
| `text_key` | Chave do CSV. Nunca o texto |
| `head_id` | Só no canal de personagem: quem fala. Some do Inspector nos insights de ambiente |
| `required_flags` | Flags que precisam estar concedidas |
| `blocked_by_flags` | Flags que fecham o insight |
| `priority` | `LOW` / `NORMAL` / `HIGH`. Desempate quando dois cabem |
| `one_shot` | Depois de lido, deixa de ser novidade (mas continua relegível) |
| `grants_flag` | Flag concedida na primeira leitura |

### Como a escolha acontece

Cada fonte mostra um orbe por canal, nunca um por insight. Uma fonte com quatro insights de ambiente
mostra um orbe verde só, e o conteúdo é escolhido no clique. O `InsightDirector` aplica esta regra:

1. Descarta tudo que estiver com porta fechada (cabeça bloqueada, `required_flags` faltando,
   `blocked_by_flags` presente). Insight fechado não desenha marcador nenhum, e é assim que o mundo
   vai se limpando conforme o jogador lê.
2. Entre o que sobrou, novidade ganha de relido.
3. Entre iguais, ganha a prioridade mais alta.

`one_shot` não apaga o insight. Ele sai da fila de novidades e vira releitura: o orbe continua no
lugar, vazado, e clicar nele mostra o texto de novo, sem emitir `insight_revealed` como
"primeira vez".

---

## As cabeças

`HeadData` (`scripts/insights/HeadData.gd`), um `.tres` por cabeça em `res://resources/heads/`:
`id`, `display_name_key` (chave do CSV), `origin` (`PLAYER` ou `NPC`), `color` e `glyph`.

A cabeça do jogador (`origin = PLAYER`) nasce desbloqueada. As de NPC só existem depois de
`HeadRegistry.unlock_head()`. Hoje só a ação de debug chama essa função; no futuro, quem vai chamá-la
é o sistema de derrota (ver [Costuras](#costuras)).

### Elenco atual

| id | Nome | Cor | Glifo |
| --- | --- | --- | --- |
| `player` | `HEAD_PLAYER_NAME` | `#5B9EFF` azul | `P` |
| `old_fisherman` | `HEAD_OLD_FISHERMAN_NAME` | `#FF9B42` laranja | `F` |

### A paleta reservada

Vale fechar a paleta inteira de uma vez, mesmo com duas cabeças: é mais fácil escolher seis cores que
convivem do que descobrir, na quarta cabeça, que não sobrou espaço. As seis foram escolhidas para se
distinguirem entre si, do verde do ambiente (`#59D973`) e do cinza do cenário:

`#5B9EFF` azul · `#FF9B42` laranja · `#C77DFF` roxo · `#4FD8D8` ciano · `#FF6FA5` rosa ·
`#F2E14C` amarelo

Com mais de cinco ou seis cabeças, a cor deixa de identificar sozinha e o glifo passa a ser o canal
principal. Esse é o limite natural do elenco.

### A órbita

`HeadOrbitLayer` é filho do `Player` e arruma os orbes de cabeça em volta dele, seguindo duas regras.

A primeira é que o slot vem da cabeça, e não da ordem de chegada. O slot preferido de cada cabeça é a
posição dela no elenco (ids em ordem alfabética). Assim, quando uma cabeça fica sem nada a dizer, as
outras não mudam de lugar e o jogador não clica na errada.

A segunda é o teto de orbes simultâneos (`max_visible_orbs`, 3 por padrão). Com mais orbes que isso
em volta do jogador, as cores deixam de ser distinguíveis, e distinguir as cores era justamente o
motivo de cada cabeça ter a sua. O teto pode ser ajustado em jogo pelo menu de debug.

O orbe flutuante tem um custo: ele nasce longe da coisa de que fala. Quando o orbe de cabeça está em
destaque (mouse em cima ou foco do controle), a órbita desenha uma linha tracejada até a fonte, na
cor da cabeça, com um anel no ponto de que ela vai falar. Com duas fontes no alcance, é essa linha
que mostra se a cabeça vai falar da parede ou da calha. A linha e o anel são `@export` do
`HeadOrbitLayer` (grupo *Ligação com a fonte*).

---

## Os marcadores

Não há tecla para revelar nada: todo orbe disponível fica sempre na tela. Isso exige curadoria de
conteúdo, e o orbe compensa mostrando o próprio estado à distância:

| Aparência | Significa |
| --- | --- |
| Cheio, pulsando | Tem novidade |
| Vazado | Já lido |
| Flash com anel que se expande | Estava vazado e voltou a ter novidade (uma flag abriu insight novo ali) |

De perto, quando o mouse passa por cima:

| Reação | Significa |
| --- | --- |
| Cresce e o cursor vira a mãozinha | O clique vai abrir |
| Mostra o nome da cabeça | Orbe de personagem: quem vai falar |

O orbe de ambiente abre de qualquer distância. Não há alcance de clique: o jogador pode abrir todo
orbe de ambiente que vê. O raio da fonte (`interaction_radius`) só vale para o canal de personagem,
onde decide quando a cabeça aparece na órbita. A caixa aberta também não fecha quando o jogador se
afasta, porque fechar por distância faria o mesmo orbe se comportar de um jeito ou de outro conforme
o jogador estava perto ou longe ao abrir.

O clique é o botão esquerdo, direto no orbe (`Area2D.input_event`). O marcador consome o evento
(`set_input_as_handled()`). Sem isso, o mesmo clique continua para quem estiver atrás do orbe, e o
problema volta semanas depois como bug intermitente.

O orbe funciona como liga/desliga. Com a caixa aberta, clicar no próprio orbe fecha a caixa, clicar
em outro orbe troca a caixa num clique só e clicar no vazio só fecha.

A área de clique é maior que o desenho (`hit_radius`, 26 px, contra `radius`, 16 px). O orbe é
pequeno, pulsa, e o de cabeça anda junto com o jogador. Ninguém percebe a folga, só percebe que o
clique acerta. Pelo mesmo motivo, toda a animação do orbe (pulsação, destaque, flash) é desenhada em
`_draw()`, e não aplicada ao `scale` do nó. A forma de colisão é filha do nó, e encolher o nó na
pulsação encolheria a área de clique junto: com o mouse parado na borda, o hover piscaria a cada
batida.

O orbe tem camada de física própria, `insight_orbs` (camada 16, nomeada no `project.godot`). Se ele
ficasse na camada do mundo, qualquer `Area2D` futura que escute `area_entered` detectaria orbes.

Toda a aparência é `@export` do `InsightMarker` (grupos *Aparência*, *Destaque* e *Animação*).

### Teclado e controle

O `InsightInteractor` (filho do `Player`) abre insights sem mouse. A regra "não há tecla para revelar
nada" continua valendo, porque ela trata de esconder orbes atrás de uma tecla. Aqui todo orbe
continua na tela, e a tecla só aciona o que o jogador já vê.

| Ação | Teclado | Controle | O que faz |
| --- | --- | --- | --- |
| `insight_interact` | E | A | Aciona o orbe em foco. De novo num orbe de ambiente com a caixa aberta, fecha a caixa |
| `insight_cycle` | Tab | RB | Passa o foco para o próximo orbe na tela e fixa a escolha |

O foco aparece como um anel branco em volta do orbe. Sem escolha do jogador, ele segue o orbe de
ambiente mais perto, ou a primeira cabeça se não houver orbe de ambiente na tela. O ciclo percorre os
orbes de ambiente do mais perto para o mais longe e depois as cabeças, da esquerda para a direita.

Só orbes na tela entram no foco. O orbe de ambiente não tem alcance, mas o mouse também só alcança o
que o jogador vê, e o ciclo não pode parar num orbe fora da câmera.

O anel só aparece no modo teclado/controle. Ele liga com as duas ações ou com qualquer botão ou
analógico do controle, e desliga quando o mouse se move. Assim, quem joga de mouse não vê um anel
pulando de orbe em orbe a cada passo.

O acionamento passa por `InsightMarker.activate()`, o mesmo caminho do clique. A fonte e a órbita não
sabem se o orbe foi clicado ou acionado por tecla.

A tela de diálogo dá foco ao botão de fechar quando abre, então o botão de confirmar do controle
também fecha a fala, além do de cancelar.

### Clique para andar

Com a movimentação por clique ligada nas configurações, o `Player` anda até o ponto clicado em
`_unhandled_input`, que roda antes do _physics picking_ que entregaria o clique ao orbe. Sem
tratamento, clicar num orbe abriria o insight e ainda mandaria o personagem andar até ele.

O `InsightInteractor` resolve o clique esquerdo antes do `Player`: se o clique caiu num orbe na tela,
ele consome o evento e aciona o orbe. Isso funciona porque ele é filho do `Player`. A engine chama
`_unhandled_input` primeiro nos nós que vêm depois na árvore, e o filho vem depois do pai. Um clique
fora de qualquer orbe segue normalmente, move o personagem e fecha a caixa aberta.

---

## Os eventos

Dois sinais no `EventBus` (ver `docs/event_bus.md`):

```gdscript
# Emitido quando o jogador lê um insight, descoberta ou releitura (first_time no payload separa).
signal insight_revealed(event: InsightRevealedEvent)

# Pede a exibição de uma fala na tela de diálogo. Pedido: espera exatamente 1 ouvinte.
signal dialogue_requested(head_id: StringName, text_key: String)
```

`insight_revealed` carrega um payload (`InsightRevealedEvent`) porque são seis campos: `insight_id`,
`channel`, `head_id`, `text_key`, `source_id` e `first_time`. Como toda classe de payload, ele não
ganha botão automático na seção "Eventos" do menu de debug: o Debug Menu não sabe montar um payload a
partir de campos de texto, e avisa isso no console no boot. Para disparar um insight à mão, use a
ação Disparar insight, que é a ação registrada à mão que o `docs/debug_menu.md` pede nesse caso.

---

## O estado: diário e save

`InsightJournal` guarda o que já foi lido e quais flags o mundo concedeu. Ele escuta
`insight_revealed` e se atualiza sozinho; nenhum outro script escreve nele.

O diário entra no save pela chave `insights` do Dictionary do slot, sem mexer nas outras chaves do
arquivo. A conversão de volta é explícita (`StringName(...)`) por causa de uma armadilha do
`SaveManager`: ele serializa com `JSON.stringify`, e na leitura todo `StringName` vira `String` e
todo número vira `float`. Comparar `StringName` com `String` falha sem erro nenhum, e o sintoma é o
jogador reencontrar insights que já leu.

Enquanto ninguém é dono do slot ativo, o jogo vai do menu direto para a cidade, sem escolher slot, e
o diário carrega e grava sozinho no slot 1. Quando o fluxo de save existir, quem for dono do slot
define `InsightJournal.save_slot_path`, desliga `autosave_enabled` e chama `to_dict()`/`from_dict()`
de dentro do save do jogo. A API já está pronta para isso.

As cabeças desbloqueadas ainda não são salvas. Quem sabe persistir "este NPC foi derrotado" é o
sistema de derrota, que ainda não existe, e duplicar isso no `HeadRegistry` criaria duas fontes de
verdade para o mesmo fato.

---

## Ferramentas de debug

Tudo fica na seção Insights do menu (F4), e cada entrada também é um comando no console (F1). O
console aceita o sufixo mais curto que seja único, então `diagnostico_da_cena` basta.

| Entrada | O que faz |
| --- | --- |
| Diagnóstico da cena | Lista cada fonte e cada insight dela com ✓/✗ por porta e o vencedor marcado |
| Validar todos os insights | Varre o projeto: id repetido, `text_key` inexistente, `head_id` inexistente e porta morta |
| Autoteste da escolha | Confere a lógica da escolha (novidade, prioridade, portas, desempate) com insights de teste em memória |
| Ignorar portas | Mostra tudo que existe na cena, independente de flags e cabeças |
| Desenhar raio das cabeças | Desenha em jogo o raio das fontes que têm insight de personagem |
| Disparar insight `<id>` | Dispara um insight direto, sem chegar perto de nada |
| Desbloquear cabeça `<head_id>` | Substituto da derrota de NPC |
| Desbloquear todas as cabeças | Destrava o elenco inteiro de uma vez |
| Teto de orbes de cabeça | Calibra o teto olhando a tela |
| Listar estado do diário | Imprime lidos e flags |
| Conceder flag `<flag>` | Abre uma porta sem reproduzir a condição de jogo |
| Resetar lidos / Resetar diário | Zera só os lidos, ou lidos e flags |
| Salvar / Carregar diário | Round-trip manual pelo slot atual |
| Salvar automático | Liga/desliga a gravação a cada mudança |

Os relatórios saem por `print()`, então aparecem no visualizador de log (F5) sem o editor aberto.

O diagnóstico responde com cinco tipos de linha, que cobrem todos os casos de "sumiu e não sei por
quê":

```
✗ city_building1_bricks — AMBIENTE — já lido (one_shot)
✗ city_building3_gutter — PERSONAGEM/old_fisherman — cabeça "old_fisherman" não desbloqueada
✗ city_building1_mortar — AMBIENTE — falta a flag "puddle_examined"
✗ city_porto_rede     — AMBIENTE — bloqueado pela flag "capitulo_2"
✗ city_building1_bricks — AMBIENTE — perdeu para city_building1_mortar (ALTA)
```

A porta morta é o achado mais útil da validação em lote: uma `required_flag` que nenhum insight do
projeto concede. Esse insight nunca vai aparecer para ninguém, e o sintoma é o mesmo silêncio de todos
os outros casos. Um erro assim pode passar meses sem ser notado, e a validação o encontra numa
varredura de uns dez segundos.

### O autoteste

A validação em lote confere o conteúdo, e o autoteste (`InsightSelfTest`) confere a lógica: novidade
ganha de relido, prioridade desempata, porta fechada não desenha orbe, `one_shot` tira da novidade e
o desempate entre ofertas de cabeça é estável. Essa é a parte mais sujeita a regressão silenciosa.
Uma mudança errada no `InsightDirector` não quebra nada visível; só faz um orbe sumir numa cena que
ninguém está olhando.

Ele roda contra o `InsightDirector` real, não contra uma cópia da regra. Os insights de teste são
criados em memória (ids com prefixo `__selftest_`). O diário do jogador é guardado antes e devolvido
no fim, e o salvamento automático fica desligado durante a execução, então rodar o autoteste no meio
de uma sessão de jogo não altera nada.

Ele também roda pela linha de comando, sem abrir o jogo, e sai com código 1 quando algum caso falha:

```
godot --headless --path . --script res://tests/run_insight_self_test.gd
```

Antes de mudar a regra de escolha no Director, acrescente o caso em `InsightSelfTest` e confira que
ele falha.

---

## Costuras

Dois sistemas de que os insights dependem ainda não existem. Nenhum deles bloqueia o trabalho, e os
dois têm uma costura definida para que, quando chegarem, nenhum arquivo de `scripts/insights/`
precise ser editado.

| Falta | Substituto de hoje | Some quando |
| --- | --- | --- |
| Tela de diálogo | `PlaceholderDialogueScreen`, instanciada na `main.tscn`, atendendo `dialogue_requested` | A tela real passar a atender o mesmo pedido |
| Derrota de NPC | Ação de debug "Desbloquear cabeça" chamando `HeadRegistry.unlock_head()` | O sistema de derrota emitir `npc_defeated` e o `HeadRegistry` conectar |

Trocar a tela não custa nada nos insights. O `EventBusLogger` acusa no console quando um pedido
`_requested` tem zero ou dois ouvintes, então esquecer o placeholder na cena aparece como erro, e não
como duas telas abrindo juntas.

Trocar a derrota custa uma linha. Quando `npc_defeated(npc_id: StringName)` existir no bus, com
ouvintes reais (cabeças, missões, som), o `HeadRegistry` se conecta a ele no `_ready()`. A ação de
debug continua existindo depois disso, como ferramenta de teste.

### Placeholders

Estes quatro precisam de Issue com a tag "Substituição de Placeholder" antes do PR, conforme o
Guideline:

- Orbe de insight: desenhado em código (`InsightMarker._draw()`), sem arte final.
- Caixa de texto: `InsightBubble`, com um StyleBox provisório (escuro, borda verde).
- Tela de diálogo: `PlaceholderDialogueScreen`, com o tema padrão da engine e uma etiqueta dizendo o
  que é.
- Som da primeira leitura: sininho de duas notas sintetizado em código pelo `InsightAudio` (cena na
  `main.tscn`) enquanto o campo `first_read_sfx` estiver vazio. O log do boot avisa quando o
  placeholder está em uso, e o som final entra pelo Inspector, sem mexer no script.

### Som

O `InsightAudio` escuta `insight_revealed` e pede o som ao `AudioManager` só quando `first_time` é
verdadeiro. A releitura não toca nada: o som é a recompensa da descoberta, e repeti-lo a cada clique
ensina o jogador a ignorá-lo. O som fica numa cena, e não no `AudioManager`, por dois motivos: o
`AudioManager` é um Autoload de script, sem Inspector onde escolher o som, e ele cuida de tocar
áudio, não de saber que existem insights.

---

## Erros comuns

### Control no mundo comendo o clique

O orbe é uma `Area2D`, e o clique só chega a ela pelo _physics picking_ do viewport, que a engine só
executa se nenhum `Control` tiver consumido o evento antes. Todo `Control` desenhado no mundo (um
`ColorRect` de placeholder, um painel de balão) nasce com `mouse_filter = Stop` e engole o clique da
tela inteira sem aviso. O orbe continua desenhado, opaco e pulsando, mas não abre. Todo `Control` que
está no mundo para ser visto, e não clicado, precisa de `mouse_filter = Ignore`.

### Fechar ao clicar consumindo o clique

A ordem da engine é `_input` → GUI → `_unhandled_input` → _physics picking_. Qualquer coisa que feche
ao clicar em `_unhandled_input`, como a caixa de texto, recebe o clique antes do orbe. Se ela chamar
`set_input_as_handled()` em todo clique, clicar num outro orbe só fecha a caixa, e o jogador precisa
clicar duas vezes. Se não chamar nunca, clicar no próprio orbe fecha a caixa e o orbe a reabre no
mesmo clique. A caixa resolve os dois casos perguntando ao seu orbe
(`InsightMarker.is_mouse_event_inside()`) e consome só o clique que caiu nele. Faça o mesmo em
qualquer coisa nova que feche ao clicar.

### Tirar o `InsightInteractor` de dentro do `Player`

Ele precisa ser filho do `Player` para receber o clique antes dele (ver
[Clique para andar](#clique-para-andar)). Em outro lugar da árvore, o clique num orbe volta a mover o
personagem no esquema de clique, e nada acusa erro.

### Sopa de orbes

É o maior risco do sistema, porque não há tecla para revelar. Mais de seis ou sete orbes visíveis
numa tela é problema de curadoria de conteúdo, e não de código: corte insight em vez de esconder
marcador.

### Texto no `.tres`

Basta um texto escrito direto no recurso para a localização ter que ser refeita. Use chave desde o
primeiro insight, sem exceção.

### Insight virando obrigação

Quando um insight destrava progresso, o marcador sempre visível vira uma lista de tarefas. O insight
serve para caracterizar; o que destrava progresso é o objetivo.

### Cabeça sem viés

Se a cabeça do NPC derrotado falar igual à do jogador, derrotar o NPC não dá nada de novo ao jogador.
Cada cabeça precisa enxergar algo que as outras não enxergam.

### Quando o `.tres` deixar de servir

Isso acontece por volta de 50 insights. Abaixo disso, o Inspector é confortável e cada `.tres` pode
ser revisado no PR. Acima, criar um por um fica penoso e o diff fica ilegível. Quando chegar a hora,
a planilha que já guarda o texto ganha colunas de estrutura, e um script de editor gera os `.tres`.
Não construa essa ferramenta antes: enquanto o formato ainda estiver mudando, ela só congelaria
decisões que ninguém tomou.

---

## Antes de abrir PR

O que o revisor procura:

- Todo texto novo tem chave no CSV, e a chave existe (a validação em lote já confere isso)?
- A validação em lote passa sem nenhum ✗?
- Mexeu no `InsightDirector`? O autoteste da escolha passa sem nenhum ✗?
- Os `.tres` novos estão em `res://resources/insights/` (ou `heads/`), com `id` único?
- Insight de personagem tem `head_id`, e a cabeça existe?
- Nenhuma fonte na cena está com triângulo amarelo?
- Placeholder novo tem Issue de substituição criada?
