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
  -> EventBus.conversation_approach_started(conversation_id, npc_id)
       trava o Player e os orbes de insight; NPCDirector segura no lugar TODOS os
       NPCs do elenco da conversa (DialogueCatalog.read_participants)
  -> Player.start_conversation_approach() anda até perto do NPC (Pathfinder)
       await player.conversation_approach_arrived
  -> DialogueCamera.engage() aproxima a câmera do Player e dos NPCs do elenco
       await camera.tween_completed
  -> EventBus.conversation_requested(conversation_id, npc_id)
  -> DialogueScreen.open()
  -> DialogueCatalog.create_runner(conversation_id)
  -> a tela monta um retrato por NPC do elenco (o runner traz a lista do roteiro)
  -> o runner emite um DialogueStep por vez
  -> a tela mostra falas e opções; o jogador escolhe
  -> EventBus.conversation_ended
       DialogueCamera devolve a câmera pra PlayerCamera; Player e NPCs destravam
```

`NPCInteraction._start_conversation()` é quem conduz a abordagem inteira, com `await` em cada etapa — sem Player ou `DialogueCamera` na cena (cena de teste, por exemplo), ela pula a etapa que faltar e pede a conversa direto, sem travar nada.

Cada peça tem um trabalho só:

| Peça | O que faz |
| --- | --- |
| `NPCInteraction` | Recebe o clique no NPC (só picking, sem colisão física) e conduz a abordagem: aproximação, zoom e só então o pedido de conversa pelo `EventBus`. Só age se o `conversation_id` do NPC não estiver vazio. |
| `DialogueCamera` | `PhantomCamera2D` parada (priority 0) até `engage()` subir a prioridade acima da `PlayerCamera` (10, em `Player.tscn`) e enquadrar todo mundo que está na conversa (`FollowMode.GROUP`); o `PhantomCameraHost` (`City.tscn`) faz o tween sozinho a cada troca de prioridade. Devolve a câmera em `conversation_ended`. |
| `DialogueCatalog` | Descobre o runner certo para o id: conversa sintética de debug (`__stress_*`) ou `res://dialogue/<id>.dlg`. Também responde quem é o elenco de uma conversa, sem montá-la (`read_participants`/`cast_for`). |
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
    "participants": [&"ze", &"ana"],
    "nodes": {
        &"inicio": { "line": [line_id, speaker_id, text_key], "choices": [ {...}, {...} ] },
        &"pao":    { "line": [...], "next": &"END" },
    }
}
```

Cada opção é um `Dictionary` com `id`, `text`, `next` e, se houver, `tag`, `if_flag`, `show_disabled`, `reason` e `grant`. O `id` da opção é `<conversa>:<CHAVE>`. O prefixo da conversa evita que duas conversas com a mesma chave de texto (um "Sim." genérico) marquem a escolha uma da outra como já feita.

`participants` é o elenco declarado na linha `participants:` do roteiro, e é a única parte do conteúdo que não descreve um nó. O `MemoryRunner` só o repassa (`DialogueRunner.participant_ids`); quem o usa é a tela, para montar os retratos.

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

Um NPC conversa quando `NPCDefinition.conversation_id` não está vazio. O `Player` e o `InsightInteractor` já travam em `conversation_approach_started` (clique no NPC, antes de a tela abrir — ver [Do clique à tela](#do-clique-à-tela)); o `NPCDirector` segura os NPCs parados nesse mesmo momento, mas só os vira para o jogador em `conversation_started`, quando o jogador de fato chegou perto. Enquanto a conversa está aberta:

- O `NPCDirector` mantém os NPCs da conversa segurados e virados para o jogador.
- O `Player` mantém o movimento travado.
- O `InsightInteractor` mantém os orbes desligados.
- O `GameClock` fica congelado, para o tempo do jogo não correr durante a conversa.

Tudo destrava quando `conversation_ended` chega. A `DialogueScreen` emite `conversation_started` e `conversation_ended`; o `NPCDirector`, o `Player`, o `InsightInteractor` e a `DialogueCamera` ouvem `conversation_ended`, e os três primeiros também ouvem `conversation_approach_started`.

O `NPCDefinition` também avisa no Inspector (`collect_issues()`) quando `dialogue_color` não passa no contraste mínimo contra o fundo da coluna de diálogo.

### Dois NPCs na mesma conversa

O roteiro declara o elenco numa linha `participants: ze ana` (ver a [referência](referencia.md#elenco-quem-está-na-conversa)). Um elenco é o jogador e **um ou dois NPCs** — o parser recusa mais que isso (`DialogueScriptParser.MAX_PARTICIPANTS`), porque é o que a coluna de retratos e o enquadramento da câmera foram pensados para mostrar.

Quem participa é um fato da conversa, não do clique, e por isso **não viaja nos eventos**: os dois eventos de conversa continuam carregando só o id da conversa e quem a puxou, e quem precisa do elenco pergunta ao `DialogueCatalog`, que é quem lê o roteiro. São dois caminhos, pelo mesmo `cast_for()`:

| Quem | Quando | De onde tira o elenco |
| --- | --- | --- |
| `NPCInteraction` | antes de a tela abrir, para enquadrar a câmera | `DialogueCatalog.read_participants()` (lê o `.dlg`) |
| `NPCDirector` | em `conversation_approach_started` e `conversation_started`, para segurar e virar | idem |
| `DialogueScreen` | ao abrir, para montar os retratos | `DialogueRunner.participant_ids`, que já veio parseado |

A regra é sempre a mesma, e mora num lugar só: `DialogueCatalog.cast_for(declarados, initiator_id)` é o elenco declarado mais quem puxou a conversa, sem repetir. É ela que faz uma conversa sem `participants:` ter como elenco só o NPC clicado, e a mesma conversa aberta pelo console (sem NPC de origem) ter o elenco que o roteiro declara.

Um participante que não está na cena naquele horário, ou que está a mais de `DialogueStyle.camera_group_max_distance` do NPC clicado, fica de fora do enquadramento (com aviso no Output) — a conversa roda igual, e as falas dele aparecem normalmente. Segurar um NPC longe é inofensivo: o `GameClock` está congelado, então nenhuma rotina ia movê-lo mesmo.

### Os retratos

A `DialogueScreen` monta um `DialoguePortrait` por NPC do elenco, na ordem do roteiro: o primeiro é o nó da cena, e os outros nascem em código conforme a conversa precisa. A cada fala, se o falante resolve para um NPC, o retrato dele acende e o outro apaga para `portrait_inactive_alpha`. Falas do jogador, da narração e de cabeças de insight não mexem em quem está aceso.

Um NPC que fala sem estar no elenco entra na coluna se ainda couber, e senão toma o retrato de quem não está falando. É rede de segurança para roteiro com elenco incompleto — "Validar conversas" avisa nesse caso, e é lá que o problema deve ser resolvido.

A posição vem de `DialoguePortraitLayout.compute_rects()`, que só faz conta (a pilha inteira, o espaço à esquerda da coluna, o encolhimento em tela pequena) — sem nó, sem estado.

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
| `debug/` | O validador de conversas e de estilo, o passeio automático e os dados de teste. |

A lógica de `logic/` é pura de propósito: dá pra chamar de qualquer lugar sem abrir cena nem depender de vídeo. O projeto não usa testes automatizados unitários — a verificação de conteúdo (chaves, contraste, becos sem saída) é o que os validadores e o passeio automático em `debug/` cobrem.

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
| 4. Ferramentas | Seção Diálogo no menu de debug, validadores, passeio automático. | Pronta, já validando roteiros reais. |
| 5. Polimento | Sons placeholder, revelação progressiva, repetição de analógico e D-pad, rolagem em 200%, blur opcional. | Pronta, exceto os sons finais e o teste em 21:9. |
| 6. Dois NPCs | Elenco no roteiro (`participants:`), os dois segurados e virados, câmera nos três, coluna de retratos com o falante aceso, validação do elenco. | Pronta. Falta arte de retrato para os dois NPCs. |

O layout do painel é ancorado à direita com largura própria, então em tela 21:9 deveria só sobrar mais fundo à esquerda. Ninguém conferiu isso numa tela ultrawide de verdade.

Pendências para o Lead. Nenhuma bloqueou o trabalho, porque o `MemoryRunner` e o `DialogueGameState` não dependem de nenhuma resposta:

1. Aprovar `initiator_id` nos eventos de conversa, que diverge da assinatura do PRD (V4).
2. Decidir se o `DialogueState` continua estático, como está, ou vira um Autoload `DialogueJournal` (V9).
3. Confirmar que as flags ficam no `InsightJournal`, atrás do `DialogueGameState`, na v1 (D3). Já está implementado assim.
4. Decidir se a interação com NPC por teclado ou controle, que ficou fora da v1, entra no foco do `InsightInteractor` ou ganha foco próprio.
5. "Novo Jogo" não zera o save: `DialogueState` e o diário sobrevivem a ele. Ninguém decidiu se deve zerar.
