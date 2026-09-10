# Insights

O que o mundo, e as cabeças do jogador, têm a dizer sobre as coisas — e como pôr conteúdo novo no
jogo sem abrir um script.

---

## A ideia

Um **insight** é uma observação disparada por um ponto do mundo. Ele chega ao jogador por um de dois
canais:

|  | Ambiente | Personagem |
| --- | --- | --- |
| Onde o orbe fica | No objeto, na cena | Flutuando perto do jogador |
| Cor do orbe | Verde, sempre | A cor da cabeça que está falando |
| Quem fala | Ninguém: é o mundo | Uma cabeça (`head_id`) |
| Saída | Caixa in loco, o jogo continua | Tela de diálogo, o jogo para |
| Porta típica | Flags do mundo | A cabeça precisa estar desbloqueada |
| Alcance do clique | Só dentro do raio da fonte | Sempre perto, por definição |
| Tamanho do texto | Até 4 linhas | Livre |

Os dois canais compartilham o recurso, a fonte, o marcador e o clique. Eles divergem só no fim —
onde o orbe nasce, quem fala e para onde o texto vai. É isso que faz o sistema ser **um sistema com
dois apresentadores**, e não dois sistemas paralelos com o dobro de bugs.

**Posição diz o canal. Cor diz quem está falando.** O orbe no objeto é o mundo; o orbe orbitando o
jogador é uma cabeça, e a cor identifica qual. Como cor sozinha não resolve daltonismo (nem as
primeiras horas de jogo de ninguém), todo orbe de cabeça carrega também um glifo.

---

## Criar um insight (sem tocar em código)

1. **Escreva o texto no CSV.** `translations/translations.csv`, uma chave nova em
   `MAIUSCULO_COM_UNDERSCORE` (ver `docs/localizacao_Godot.md`). Nunca escreva o texto no `.tres`.
2. **Crie o recurso.** Botão direito em `res://resources/insights/` → *New Resource* → `InsightData`.
   Preencha `id`, `channel`, `text_key` e, se for de personagem, `head_id`.
3. **Ponha uma fonte no objeto.** Arraste `res://scenes/insights/InsightSource.tscn` para dentro do
   objeto (ou do NPC), posicione, e arraste o `.tres` para a lista `Insights` no Inspector.
4. **Rode o jogo.** Se o orbe não aparecer, **não abra código**: abra o menu de debug (F4), seção
   *Insights*, e clique em **Diagnóstico da cena** (ver [Ferramentas](#ferramentas-de-debug)).

O passo 3 é a única coisa que se monta na cena, e a cena já vem com forma e camadas configuradas —
não existe caminho em que criar conteúdo exija acertar `collision_mask` na mão.

### O que o triângulo amarelo acusa

A `InsightSource` é um script `@tool`: os erros de preenchimento aparecem na árvore de cena, **antes**
de rodar o jogo. Ela acusa fonte sem insight, `id` vazio ou repetido no projeto, `text_key` vazio ou
inexistente no CSV, canal de personagem sem `head_id` e `head_id` que não corresponde a nenhuma
cabeça.

O mesmo script desenha, no editor, o raio da fonte e o orbe de ambiente na posição em que ele vai
nascer. Para o canal de personagem ele desenha um gizmo diferente, com uma seta saindo: aquele orbe
**não** vai aparecer ali, vai aparecer orbitando o jogador.

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

Um orbe **por fonte e por canal**, nunca um por insight: uma fonte com quatro insights de ambiente
mostra um orbe verde só, e o conteúdo é escolhido no clique. A regra, aplicada pelo `InsightDirector`:

1. Descarta tudo que estiver com porta fechada (cabeça bloqueada, `required_flags` faltando,
   `blocked_by_flags` presente). **Insight fechado não desenha marcador nenhum** — é isso que faz o
   mundo se limpar sozinho conforme o jogador lê.
2. Entre o que sobrou, **novidade ganha de relido**.
3. Entre iguais, ganha a **prioridade** mais alta.

`one_shot` não apaga o insight: ele sai da fila de novidades e vira releitura. O orbe continua no
lugar, vazado, e clicar nele mostra o texto de novo — sem emitir `insight_revealed` como
"primeira vez".

---

## As cabeças

`HeadData` (`scripts/insights/HeadData.gd`), um `.tres` por cabeça em `res://resources/heads/`:
`id`, `display_name_key` (chave do CSV), `origin` (`PLAYER` ou `NPC`), `color` e `glyph`.

A cabeça do jogador (`origin = PLAYER`) nasce desbloqueada. As de NPC só existem depois de
`HeadRegistry.unlock_head()` — hoje chamada só pela ação de debug, amanhã pelo sistema de derrota
(ver [Costuras](#costuras)).

### Elenco atual

| id | Nome | Cor | Glifo |
| --- | --- | --- | --- |
| `player` | `HEAD_PLAYER_NAME` | `#5B9EFF` azul | `P` |
| `old_fisherman` | `HEAD_OLD_FISHERMAN_NAME` | `#FF9B42` laranja | `F` |

### A paleta reservada

Vale fechar a paleta inteira de uma vez, mesmo com duas cabeças: é mais fácil escolher seis cores que
convivem do que descobrir na quarta que não sobrou espaço. Todas escolhidas para se distinguirem
entre si, do verde do ambiente (`#59D973`) e do cinza do cenário:

`#5B9EFF` azul · `#FF9B42` laranja · `#C77DFF` roxo · `#4FD8D8` ciano · `#FF6FA5` rosa ·
`#F2E14C` amarelo

Passando de cinco ou seis cabeças, a cor deixa de identificar sozinha e o glifo passa a ser o canal
principal. É o limite natural do elenco.

### A órbita

`HeadOrbitLayer` é filho do `Player` e arruma os orbes de cabeça em volta dele. Duas regras:

- **Slot derivado da cabeça, não da ordem de chegada.** O slot preferido de cada cabeça é a posição
  dela no elenco (ids em ordem alfabética), então uma cabeça calar não faz as outras pularem de lugar
  e o jogador clicar na errada.
- **Teto de orbes simultâneos** (`max_visible_orbs`, 3 por padrão). Acima disso o jogador vira
  pinheiro de natal e para de distinguir as cores — que é justamente o que a cor por cabeça veio
  criar. O teto é ajustável em jogo pelo menu de debug.

---

## Os marcadores

Não há tecla para revelar nada: **todo orbe disponível está sempre na tela**. Isso cobra curadoria de
conteúdo, e o orbe compensa comunicando o próprio estado à distância:

| Aparência | Significa |
| --- | --- |
| Cheio, pulsando | Tem novidade |
| Vazado | Já lido |
| Apagado | Fora do alcance de clique — ande até lá |

O alcance é o raio da própria fonte (`interaction_radius`). Um orbe clicável do outro lado da tela
deixaria o personagem irrelevante: o jogador varreria a cena com o mouse sem andar.

O clique é o botão esquerdo, direto no orbe (`Area2D.input_event`). O movimento do jogador é por
teclado/analógico, então o clique não disputa com nada. O marcador consome o evento
(`set_input_as_handled()`): sem isso, o mesmo clique continua viajando para quem estiver atrás do
orbe, e isso reaparece semanas depois como bug intermitente.

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
tem botão automático na seção "Eventos" do menu de debug — o Debug Menu não sabe montar um payload a
partir de campos de texto, e avisa isso no console no boot. Quem quiser disparar um insight à mão usa
a ação **Disparar insight**, que é justamente a ação registrada à mão que o `docs/debug_menu.md`
manda criar nesse caso.

---

## O estado: diário e save

`InsightJournal` guarda **o que já foi lido** e **quais flags o mundo concedeu**. Ele escuta
`insight_revealed` e se atualiza sozinho; ninguém escreve nele por fora.

O diário entra no save pela chave `insights` do Dictionary do slot, preservando as outras chaves do
arquivo. A conversão de volta é explícita (`StringName(...)`) por causa da armadilha do
`SaveManager`: ele serializa via `JSON.stringify`, e na volta todo `StringName` vira `String` e todo
número vira `float`. Comparar `StringName` com `String` falha **em silêncio**, e o sintoma é o jogador
reencontrando insights que já leu.

**Enquanto não há dono do slot ativo:** o jogo ainda vai do menu direto para a cidade, sem escolher
slot, então o diário carrega e grava sozinho no slot 1. No dia em que o fluxo de save existir, quem
for dono do slot define `InsightJournal.save_slot_path`, desliga `autosave_enabled` e chama
`to_dict()`/`from_dict()` de dentro do save do jogo — a API já é essa.

**O que ainda não é salvo:** quais cabeças estão desbloqueadas. Quem sabe persistir "este NPC foi
derrotado" é o sistema de derrota, que ainda não existe; duplicar isso no `HeadRegistry` criaria duas
verdades sobre o mesmo fato.

---

## Ferramentas de debug

Tudo na seção **Insights** do menu (F4), e cada entrada também é comando no console (F1) — o console
aceita o sufixo mais curto que for único, então `diagnostico_da_cena` basta.

| Entrada | O que faz |
| --- | --- |
| Diagnóstico da cena | Lista cada fonte e cada insight dela com ✓/✗ por porta e o vencedor marcado |
| Validar todos os insights | Varre o projeto: id repetido, `text_key` inexistente, `head_id` inexistente e porta morta |
| Ignorar portas | Mostra tudo que existe na cena, independente de flags e cabeças |
| Desenhar raio de clique | Desenha em jogo o raio de cada fonte |
| Disparar insight `<id>` | Dispara um insight direto, sem chegar perto de nada |
| Desbloquear cabeça `<head_id>` | Substituto da derrota de NPC |
| Desbloquear todas as cabeças | Destrava o elenco inteiro de uma vez |
| Teto de orbes de cabeça | Calibra o teto olhando a tela |
| Listar estado do diário | Imprime lidos e flags |
| Conceder flag `<flag>` | Abre uma porta sem reproduzir a condição de jogo |
| Resetar lidos / Resetar diário | Zera só os lidos, ou lidos e flags |
| Salvar / Carregar diário | Round-trip manual pelo slot atual |
| Salvar automático | Liga/desliga a gravação a cada mudança |

Os dois relatórios saem por `print()`, então aparecem no visualizador de log (F5) sem precisar do
editor aberto.

**As cinco linhas que o diagnóstico responde**, e que são a totalidade dos "sumiu e não sei por quê":

```
✗ city_building1_bricks — AMBIENTE — já lido (one_shot)
✗ city_building3_gutter — PERSONAGEM/old_fisherman — cabeça "old_fisherman" não desbloqueada
✗ city_building1_mortar — AMBIENTE — falta a flag "puddle_examined"
✗ city_porto_rede     — AMBIENTE — bloqueado pela flag "capitulo_2"
✗ city_building1_bricks — AMBIENTE — perdeu para city_building1_mortar (ALTA)
```

**Porta morta** é o achado mais valioso da validação em lote: uma `required_flag` que nenhum insight
do projeto concede. O insight nunca vai aparecer para ninguém, e o sintoma é o mesmo silêncio de todo
o resto — é o tipo de erro que sobrevive meses e some numa varredura de dez segundos.

---

## Costuras

Dois sistemas de que os insights dependem ainda não existem. Nenhum deles bloqueia nada, e os dois
têm costura definida para que, quando chegarem, **nenhum arquivo de `scripts/insights/` precise ser
editado**.

| Falta | Substituto de hoje | Some quando |
| --- | --- | --- |
| Tela de diálogo | `PlaceholderDialogueScreen`, instanciada na `main.tscn`, atendendo `dialogue_requested` | A tela real passar a atender o mesmo pedido |
| Derrota de NPC | Ação de debug "Desbloquear cabeça" chamando `HeadRegistry.unlock_head()` | O sistema de derrota emitir `npc_defeated` e o `HeadRegistry` conectar |

A troca da tela é grátis: o `EventBusLogger` acusa no console quando um pedido `_requested` tem zero
ou dois ouvintes, então esquecer de tirar o placeholder vira erro visível em vez de duas telas
abrindo juntas.

A troca da derrota é uma linha: quando `npc_defeated(npc_id: StringName)` existir no bus (aí sim com
ouvintes de verdade — cabeças, missões, som), o `HeadRegistry` conecta no `_ready()`. A ação de debug
continua existindo depois disso, como ferramenta de teste.

### Placeholders

Os dois precisam de Issue com a tag "Substituição de Placeholder" antes do PR, conforme o Guideline:

- **Orbe de insight** — desenhado em código (`InsightMarker._draw()`), sem arte final.
- **Tela de diálogo** — `PlaceholderDialogueScreen`, com o tema padrão da engine e uma etiqueta
  dizendo o que é.

---

## Erros comuns

**Sopa de orbes.** Risco número um, porque não há tecla para revelar. Mais de seis ou sete orbes
visíveis numa tela é problema de curadoria de conteúdo, não de código: corte insight, não esconda
marcador.

**Texto no `.tres`.** O primeiro texto escrito direto no recurso garante que a localização será
refeita. Chave desde o primeiro insight, sem exceção.

**Insight virando obrigação.** No momento em que um insight destrava progresso, o marcador sempre
visível vira lista de tarefas. Insight caracteriza; quem destrava é o objetivo.

**Cabeça sem viés.** Se a cabeça do NPC derrotado falar igual à do jogador, derrotar o NPC não entrega
nada. Cada cabeça precisa enxergar uma coisa que as outras não enxergam.

**Quando o `.tres` deixar de servir.** Por volta de 50 insights. Abaixo disso o Inspector é
confortável e cada `.tres` é revisável no PR; acima, criar um por um vira trabalho penoso e o diff
fica ilegível. A saída, quando chegar a hora: a mesma planilha que já guarda o texto ganha colunas de
estrutura, e um script de editor gera os `.tres`. Não construa antes — enquanto o formato ainda
estiver mudando, a ferramenta só congela decisões que não foram tomadas.

---

## Antes de abrir PR

O que o revisor procura:

- Todo texto novo tem chave no CSV, e a chave existe (a validação em lote confere isso de graça)?
- A validação em lote passa sem nenhum ✗?
- Os `.tres` novos estão em `res://resources/insights/` (ou `heads/`), com `id` único?
- Insight de personagem tem `head_id`, e a cabeça existe?
- Nenhuma fonte na cena está com triângulo amarelo?
- Placeholder novo tem Issue de substituição criada?
