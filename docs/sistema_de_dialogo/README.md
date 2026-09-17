# Sistema de Diálogo

Este guia explica o que já está pronto do sistema de diálogo, como testar sem abrir código e onde
ficam as pendências. O **como** de cada peça está em [`SPEC.md`](SPEC.md); o **porquê** está em
[`PRD.md`](PRD.md).

---

## Status por fase (SPEC §16)

| Fase | O quê | Estado |
| --- | --- | --- |
| 1 — Protótipo visual | Modelo de dados, `DialogueStyle`, lógica pura, `MemoryRunner`, a coluna de diálogo inteira (log, opções, sequência de confirmação) | **Pronta** |
| 2 — Runner e dados | Catálogo, `DialogueSpeaker`/resolvedor, `SingleLineRunner`, congelamento do relógio | **Pronta, exceto o addon** (D1 continua pendente — ver [Pendências](#pendências-para-o-lead)) |
| 3 — Integração | Insights ligados à tela real, clique no NPC, trava de Player/orbes, `DialogueState` + save, preferências do jogador | **Pronta** |
| 4 — Ferramentas | Seção "Diálogo" no menu de debug, validação de conversas e de estilo, passeio automático, autoteste headless | **Pronta** (a validação de roteiros reais some até o addon entrar) |
| 5 — Polimento | Sons placeholder, revelação progressiva ligada, repetição de analógico/D-pad, opções com rolagem própria em 200%, blur opcional | **Pronta, exceto sons finais e teste em 21:9** (ver abaixo) |

**O que "sem o addon" significa na prática:** o único jeito de abrir uma conversa hoje é por uma
conversa sintética (`__proto_garte`, `__stress_text`), servida pelo `MemoryRunner`. Um roteiro real
em `.dialogue` só funciona depois que o Lead aprovar o addon (D1) e ele for instalado — nesse dia,
`DialogueManagerRunner` e a indexação de roteiros do `DialogueCatalog` entram, e nada mais no
sistema muda.

---

## Testar agora

1. Rode o jogo e entre em `City.tscn` ("Novo Jogo" a partir do menu).
2. Abra o menu de debug (**F4**) ou o console (**F1**) e vá até a seção **Diálogo**.
3. **Abrir protótipo** abre `__proto_garte` na hora. O NPC "ze" (Zé, perto da `CasaDoZe`) também
   tem essa conversa em `conversation_id`: clicar nele pede a mesma coisa pelo caminho de jogo
   (`NPCInteraction` → `EventBus.conversation_requested` → `DialogueScreen`).
4. Durante a conversa: `1`–`9` escolhe por atalho, `Enter`/`Espaço`/clique confirma, `Page Up`/
   `Page Down` rola o histórico, `Home`/`End` pula para o início/fim.

Um insight de personagem (canal `CHARACTER`) também abre a tela real agora: `EventBus.
dialogue_requested` vira uma conversa de uma fala só, via `SingleLineRunner`.

---

## Comandos de debug (seção "Diálogo")

| Comando | O que faz |
| --- | --- |
| Iniciar conversa | Pede `conversation_id` (sugere as sintéticas) e abre pelo `EventBus`, como um NPC faria |
| Pular para nó | Abre uma conversa direto num nó, para testar um trecho sem repetir o começo |
| Validar conversas | Confere as chaves fixas do CSV e as conversas sintéticas: falante desconhecido, chave sem tradução, mais de 9 opções, fala longa demais |
| Validar estilo | Contraste WCAG (pior caso) de cada cor do `DialogueStyle`, de cada NPC do roster, cabeça e `DialogueSpeaker` |
| Mostrar IDs | Mostra o `line_id` de cada fala no log, para conferir contra o roteiro |
| Ignorar condições | Força toda opção condicional a aparecer disponível |
| Teste de estresse de texto | Escala 2.0 temporária + a fala mais longa do CSV entre as usadas nas conversas sintéticas, com o nome de falante mais longo do roster |
| Passeio automático | Roda a conversa sozinha, escolhendo ao acaso, `N` vezes; acusa beco sem saída e loop |
| Resetar escolhas | Zera `DialogueState` (escolhas e nós visitados) — pede confirmação |
| Autoteste do diálogo | Roda `DialogueSelfTest` e imprime o relatório |
| Abrir protótipo | Atalho direto para `__proto_garte` |

Todos os comandos também funcionam pelo console (F1), com autocomplete de nome e de argumento.

## Autoteste pela linha de comando

```bash
godot --headless --path . --script res://tests/run_dialogue_self_test.gd
```

Sai com código 1 se algum caso falhar — mesmo formato de `run_insight_self_test.gd`. Cobre as
classes puras (`scripts/dialogue/logic/*.gd`), o `MemoryRunner` e `DialogueState`; não abre cena
nem depende de vídeo.

---

## Preferências do jogador (SPEC §14)

Ficam em `GameManager` (`user://gameplay_settings.cfg`, seção `[dialogue]`) e na tela de
Configurações: tamanho do texto (0.8×–2.0×), fonte sem serifa, opacidade do painel (0.82–1.0),
revelação de texto (instantânea/progressiva) e velocidade da animação (normal/rápida/instantânea).

A tela aplica todas ao vivo. Revelação progressiva (SPEC §9.6): cada fala aparece letra por letra
pelo cronograma do `DialogueRevealTimer` (pausa maior depois de vírgula/ponto); clicar ou apertar
`dialogue_confirm` durante a revelação pula pro texto inteiro, sem confirmar nada além disso — o
clique que "acorda" a fala não é o mesmo que avança a conversa. No modo `AUTO` (fala sem escolhas),
o tempo já gasto revelando conta como parte da leitura, então ligar a revelação não dobra a espera.

O multiplicador de animação (normal/rápida/instantânea) agora escala todos os tempos de tween da
tela — abrir/fechar o painel, brilho e recolhimento da confirmação, entrada de cada fala — exceto
a trava de entrada e o beat da confirmação, que têm piso próprio mesmo no instantâneo
(`DialogueStyle.effective_input_lock`/`effective_beat`, SPEC §6.1): zerar essas duas abriria brecha
pra clique duplo quebrar a máquina de estados, e o beat existe pra dar tempo de ler a réplica do
jogador mesmo na velocidade máxima.

---

## Integração com NPCs

Um NPC conversa quando `NPCDefinition.conversation_id` não está vazio. O clique nele passa por
`NPCInteraction` (Area2D filha do `NPC`, sem colisão física — só picking), que pede a conversa pelo
`EventBus`. Enquanto a conversa está aberta, o `NPCDirector` segura o NPC parado e vira ele para o
jogador; o `Player` trava o movimento; o `InsightInteractor` desliga os orbes. Tudo isso destrava
sozinho quando `conversation_ended` chega.

`NPCDefinition` também avisa no Inspector (`collect_issues()`) quando `dialogue_color` não passa no
contraste mínimo contra o fundo da coluna de diálogo.

---

## Fase 5 — Polimento (SPEC §16)

- **Sons**: `DialogueStyle.sfx_*` (abrir, fechar, nova fala, confirmar, hover) continuam vazios —
  toca um bipe sintetizado em código (`DialoguePlaceholderAudio`, mesma técnica do `InsightAudio`)
  até o som final entrar pelo Inspector. O boot avisa no log quais pistas ainda são placeholder.
- **Controle**: D-pad e analógico esquerdo (eixo Y) repetem `dialogue_focus_up/down` a cada
  `DialogueScreen.analog_repeat_interval` (0,18 s por padrão) enquanto seguros — joypad não gera
  eco de tecla como o teclado, então sem isso segurar o analógico só moveria o destaque uma vez.
  R3 (`dialogue_jump_to_end`) já estava mapeado desde a Fase 1.
- **Escala 200%**: a lista de opções ganha rolagem própria (`OptionsScroll`) quando passaria de 50%
  da altura da coluna — muitas opções longas nessa escala —, garantindo que o log nunca fique com
  menos de ~50% da altura.
- **Blur opcional**: implementado (`BackBufferCopy` + `resources/shaders/backdrop_blur.gdshader`,
  caixa 3×3 de um passe só) mas **desligado por padrão** (`DialogueStyle.backdrop_blur_enabled =
  false`) — SPEC §7.2 pede medir o custo no Compatibility antes de ligar; isso ainda não foi feito
  em hardware real.
- **Teste em 21:9**: não verificado manualmente nesta fase (sem essa tela disponível) — o layout do
  painel é ancorado à direita com largura própria, então em teoria só sobra mais fundo à esquerda,
  mas vale conferir numa tela ultrawide de verdade antes de fechar o critério do PRD §13.

---

## Pendências para o Lead

As mesmas seis do `SPEC.md` §18 continuam abertas — nenhuma delas bloqueou o trabalho até aqui
porque o `MemoryRunner` e a fachada `DialogueGameState` não dependem de nenhuma resposta:

1. Aprovar o addon **Godot Dialogue Manager** e a versão fixada (D1).
2. Aprovar `initiator_id` nos eventos de conversa, divergindo da assinatura do PRD (V4).
3. `DialogueState` estático (como está) ou Autoload `DialogueJournal` (V9).
4. Confirmar que as flags ficam no `InsightJournal` atrás de `DialogueGameState` na v1 (D3) —
   **já implementado assim**, nesta suposição.
5. Interação por teclado/controle com NPC: fora da v1, decidir se entra no foco do
   `InsightInteractor` ou ganha foco próprio.
6. Ordem do clique no NPC × clique para andar: validada nesta fase (`NPCInteraction._input_event`
   roda antes do `_unhandled_input` do `Player`, mesmo esquema do `InsightInteractor`).
