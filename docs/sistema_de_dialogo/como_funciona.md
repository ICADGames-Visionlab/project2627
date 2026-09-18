# Como o sistema de diálogo funciona

Este documento é para quem vai mexer no código ou quer entender por que o sistema é como é. Para usar o sistema sem ler código, vá ao [tutorial](primeiro_dialogo.md) e à [referência](referencia.md).

---

## A ideia central

O roteiro descreve a estrutura da conversa. O texto mora no `translations.csv`.

O `.dlg` diz quem fala, quais opções existem e para onde cada uma leva. Cada fala e cada opção é só uma chave. Isso segue a regra do resto do projeto (ver [localization.md](../localization.md)): o texto vive no CSV e o código só cita a chave. Na prática, traduzir uma conversa nunca exige tocar no roteiro.

Por isso o parser recusa texto literal onde se espera uma chave. Uma chave errada vira erro de sintaxe com número de linha, em vez de aparecer na tela como "texto estranho".

O sistema não usa o addon Godot Dialogue Manager, e não vai usar. O formato é próprio, no estilo de Ink e Yarn simplificados.

---

## Do clique à tela

```
clique no NPC
  -> NPCInteraction (Area2D filha do NPC)
  -> EventBus.conversation_requested(conversation_id, npc_id)
  -> DialogueScreen.open()
  -> DialogueCatalog.create_runner(conversation_id)
  -> o runner emite um DialogueStep por vez
  -> a tela mostra falas e opções; o jogador escolhe
  -> EventBus.conversation_ended
```

Cada peça tem um trabalho só:

| Peça | O que faz |
| --- | --- |
| `NPCInteraction` | Recebe o clique no NPC (só picking, sem colisão física) e pede a conversa pelo `EventBus`. Só age se o `conversation_id` do NPC não estiver vazio. |
| `DialogueCatalog` | Descobre o runner certo para o id: conversa sintética de debug (`__stress_*`) ou `res://dialogue/<id>.dlg`. |
| `DialogueScriptParser` | Lê o texto do `.dlg` e devolve um `Dictionary` no formato que o `MemoryRunner` consome, ou a lista de erros com o número da linha. É estático: não toca em cena nem em save. |
| `MemoryRunner` | Anda pelo `Dictionary` nó a nó e emite um `DialogueStep` (falas, opções, modo de avanço). Concede flags quando uma opção com `grant:` é escolhida. |
| `SingleLineRunner` | Conversa de uma fala só, para os insights de personagem (`EventBus.dialogue_requested`). |
| `DialogueScreen` | A tela: uma máquina de estados que mostra o log, as opções, a revelação do texto, e cuida do teclado, do mouse e do controle. |
| `DialogueSpeakerResolver` | Transforma um id de falante em nome e cor. Para um NPC do roster, também entrega o `NPCDefinition`, de onde sai o retrato. |
| `DialoguePortrait` | O nó do retrato: fundo, imagem e moldura, tudo em `_draw`. Sem imagem, desenha uma silhueta de placeholder. |

O `Dictionary` que o parser produz é o mesmo formato das conversas sintéticas de teste em `DialoguePrototypeData`. É por isso que os dois caminhos passam pelo mesmo `MemoryRunner`.

### O que o parser gera

```gdscript
{
    "start": &"inicio",
    "nodes": {
        &"inicio": { "line": [line_id, speaker_id, text_key], "choices": [ {...}, {...} ] },
        &"pao":    { "line": [...], "next": &"END" },
    }
}
```

Cada opção é um `Dictionary` com `id`, `text`, `next` e, se houver, `tag`, `if_flag`, `show_disabled`, `reason` e `grant`. O `id` da opção é `<conversa>:<CHAVE>`. O prefixo da conversa evita que duas conversas com a mesma chave de texto (um "Sim." genérico) marquem a escolha uma da outra como já feita.

---

## Estado e flags

| Peça | Guarda | Onde salva |
| --- | --- | --- |
| `DialogueState` | Quais opções o jogador já escolheu e quais nós já visitou. | Chave `"dialogue"` de `user://save1.json`. |
| `DialogueGameState` | Nada. É a fachada que os runners usam para ler e gravar flags. | O `InsightJournal`, no mesmo save. |

`DialogueGameState` é o único ponto do sistema que conhece o `InsightJournal`. Se as flags forem extraídas para um sistema próprio, só esse arquivo muda.

O Passeio automático usa um modo sandbox do `DialogueGameState`: as flags vão para um `Dictionary` local e as marcas de "já escolhida" não são tocadas, para não sujar o save.

---

## Integração com NPCs

Um NPC conversa quando `NPCDefinition.conversation_id` não está vazio. Enquanto a conversa está aberta:

- O `NPCDirector` segura o NPC parado e o vira para o jogador.
- O `Player` trava o movimento.
- O `InsightInteractor` desliga os orbes.
- O `GameClock` fica congelado, para o tempo do jogo não correr durante a conversa.

Tudo destrava quando `conversation_ended` chega. A `DialogueScreen` emite `conversation_started` e `conversation_ended`, e o `NPCDirector`, o `Player` e o `InsightInteractor` ouvem os dois.

O `NPCDefinition` também avisa no Inspector (`collect_issues()`) quando `dialogue_color` não passa no contraste mínimo contra o fundo da coluna de diálogo.

O retrato segue o NPC da conversa. Ao abrir, a `DialogueScreen` pede ao resolvedor o NPC do `initiator_id` e mostra o retrato dele. A cada fala, se o falante resolve para um NPC, o retrato passa a ser o dele. A posição vem de `DialoguePortraitLayout`, que só faz conta (slot, espaço à esquerda da coluna, encolhimento em tela pequena) e por isso é coberta pelo autoteste.

A ordem dos cliques está resolvida: o `_input_event` do `NPCInteraction` roda antes do `_unhandled_input` do `Player`, então clicar no NPC não faz o jogador andar até ele. É o mesmo esquema do `InsightInteractor`.

---

## Preferências do jogador

Ficam no `GameManager` (`user://gameplay_settings.cfg`, seção `[dialogue]`) e na tela de Configurações:

- Tamanho do texto, de 0,8× a 2,0×.
- Fonte sem serifa.
- Opacidade do painel, de 0,82 a 1,0.
- Revelação do texto: instantânea ou progressiva.
- Velocidade da animação: normal, rápida ou instantânea.

A tela aplica todas ao vivo.

**Revelação progressiva.** Cada fala aparece letra por letra, com pausa maior depois de vírgula e de ponto (`DialogueRevealTimer`). Clicar ou apertar `dialogue_confirm` durante a revelação mostra o texto inteiro e nada além disso: o clique que completa a fala não é o mesmo que avança a conversa. Nas falas com avanço `[auto]`, o tempo gasto revelando conta como leitura.

**Velocidade da animação.** O multiplicador escala todos os tempos de tween da tela: abrir e fechar o painel, o brilho e o recolhimento da confirmação, a entrada de cada fala. Duas coisas têm piso próprio mesmo no modo instantâneo: a trava de entrada e o intervalo depois da confirmação (`DialogueStyle.effective_input_lock` e `effective_beat`). Sem a trava, um clique duplo poderia quebrar a máquina de estados. O intervalo dá tempo de ler a réplica do jogador na velocidade máxima.

---

## Mapa do código

Tudo fica em `scripts/dialogue/`.

| Pasta | Conteúdo |
| --- | --- |
| (raiz) | A tela e suas partes (`DialogueScreen`, `DialogueLog`, `DialogueEntry`, `DialogueOptionList`, `DialogueOption`, `DialoguePortrait`), o `DialogueCatalog`, o `DialogueSpeakerResolver`, o `DialogueState`, o `DialogueGameState` e o `DialogueStyle`. |
| `model/` | Os dados que o runner entrega à tela: `DialogueLine`, `DialogueChoice`, `DialogueStep`. |
| `runners/` | `DialogueRunner` (base), `MemoryRunner`, `SingleLineRunner`. |
| `format/` | O `DialogueScriptParser`. |
| `logic/` | Lógica pura, sem nó: layout das opções, posição do retrato, contraste WCAG, rastreio de trocas, trava de entrada, política de rolagem, cronograma da revelação. |
| `debug/` | O validador de conversas e de estilo, o passeio automático, os dados de teste e o autoteste. |

A lógica de `logic/` é pura de propósito: o autoteste a cobre sem abrir cena nem depender de vídeo.

---

## Detalhes de polimento

- **Sons.** Os campos `DialogueStyle.sfx_*` (abrir, fechar, nova fala, confirmar, hover) estão vazios. Enquanto isso, a tela toca um bipe sintetizado em código (`DialoguePlaceholderAudio`), e o boot avisa no log quais pistas ainda são placeholder. O som final entra pelo Inspector.
- **Controle.** O D-pad e o analógico esquerdo repetem `dialogue_focus_up` e `dialogue_focus_down` a cada `DialogueScreen.analog_repeat_interval` (0,18 s) enquanto seguros. O joypad não gera eco de tecla como o teclado, então sem a repetição o analógico moveria o destaque uma vez só. O R3 (`dialogue_jump_to_end`) já estava mapeado.
- **Escala de 200%.** A lista de opções ganha rolagem própria (`OptionsScroll`) quando passaria de 50% da altura da coluna, para o log nunca ficar com menos de uns 50% dela.
- **Blur de fundo.** Está implementado (`BackBufferCopy` e `resources/shaders/backdrop_blur.gdshader`, caixa 3×3 de um passe) e desligado por padrão (`DialogueStyle.backdrop_blur_enabled = false`). O custo no renderer Compatibility ainda não foi medido em hardware real.

---

## Estado e pendências

| Fase | O quê | Estado |
| --- | --- | --- |
| 1. Protótipo visual | Modelo de dados, `DialogueStyle`, lógica pura, `MemoryRunner`, a coluna de diálogo. | Pronta. |
| 2. Runner e dados | Catálogo, `DialogueSpeaker` e resolvedor, `SingleLineRunner`, congelamento do relógio. | Pronta. |
| 3. Integração | Insights na tela real, clique no NPC, trava de Player e orbes, `DialogueState` e save, preferências do jogador. | Pronta. |
| 4. Ferramentas | Seção Diálogo no menu de debug, validadores, passeio automático, autoteste. | Pronta, já validando roteiros reais. |
| 5. Polimento | Sons placeholder, revelação progressiva, repetição de analógico e D-pad, rolagem em 200%, blur opcional. | Pronta, exceto os sons finais e o teste em 21:9. |

O layout do painel é ancorado à direita com largura própria, então em tela 21:9 deveria só sobrar mais fundo à esquerda. Ninguém conferiu isso numa tela ultrawide de verdade.

Pendências para o Lead. Nenhuma bloqueou o trabalho, porque o `MemoryRunner` e o `DialogueGameState` não dependem de nenhuma resposta:

1. Aprovar `initiator_id` nos eventos de conversa, que diverge da assinatura do PRD (V4).
2. Decidir se o `DialogueState` continua estático, como está, ou vira um Autoload `DialogueJournal` (V9).
3. Confirmar que as flags ficam no `InsightJournal`, atrás do `DialogueGameState`, na v1 (D3). Já está implementado assim.
4. Decidir se a interação com NPC por teclado ou controle, que ficou fora da v1, entra no foco do `InsightInteractor` ou ganha foco próprio.
5. "Novo Jogo" não zera o save: `DialogueState` e o diário sobrevivem a ele. Ninguém decidiu se deve zerar.
