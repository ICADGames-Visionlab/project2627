# Evidências — issue #75

Substitui o inventário da issue #29. Não existe mais inventário, item largado no chão nem coleta por
contato. Uma evidência é um objeto do mundo que o jogador examina de perto:

1. Clica na evidência no mundo (um `Interactable` com consequência **Evidência**).
2. A tela escurece e a evidência aparece no centro, com o texto escrito nela. Dá para dar zoom
   (roda do mouse) e mexer um pouco (arrastar com o botão esquerdo fora das palavras). O jogo pausa
   enquanto ela está aberta, como no diário.
3. Algumas palavras do texto estão **sublinhadas de vermelho**. Com o mouse em cima, o fundo fica
   vermelho e a letra branca; clicar manda a palavra para o glossário do NPC dela, com a animação do
   `WordDiscoveryToast`, e ela deixa de ser sublinhada.
4. Palavras em par (`MARCOS` + `CASTRO`) acendem juntas no hover e entram juntas com um clique só.
5. **Só dá para fechar depois de colher todas as palavras** daquela evidência (botão "Fechar" ou Esc).
6. Ao fechar, a evidência vai para o **diário** (título = nome, texto = o que está escrito nela).
7. A evidência **continua no mundo**. Clicar de novo reabre, já com as palavras colhidas e o fechar
   liberado; o diário não ganha página repetida.

| Arquivo | Papel |
|---|---|
| `scripts/items/ItemData.gd` | Resource que descreve uma evidência: `id`, `display_name_key`, `description_key` (o texto, com a marcação do glossário) e `icon`. Nome herdado do inventário. |
| `scripts/items/ItemCatalog.gd` | Acha o `ItemData` pelo id, varrendo `res://items/`. Usado pelo diário ao refazer as páginas do save. |
| `scripts/interactables/Interactable.gd` | O objeto no mundo. Na consequência **Evidência**, abre o `EvidenceViewer`. |
| `scripts/ui/EvidenceViewer.gd` + `scenes/ui/EvidenceViewer.tscn` | A evidência de perto: escurecer, zoom, arrasto, a regra do fechar e o envio ao diário. |
| `scripts/profiling/ClickableWordText.gd` | O texto com palavras clicáveis (sublinhado, hover dos pares, clique). É o mesmo nó da história resolvida do profiling. |
| `scripts/singletons/Diary.gd` | `add_evidence()` e a seção `evidences` do save. |
| `items/TornNote.tres` | Evidência placeholder da cidade (`TornNoteEvidence` em `City.tscn`). |

---

## Criando uma evidência nova

1. No FileSystem do editor, botão direito em `res://items/` → **New Resource** → `ItemData`. Salve
   como `.tres` **direto** em `res://items/` (não numa subpasta): é ali que o `ItemCatalog` procura
   quando o save traz a evidência de volta para o diário.
2. Preencha no Inspector:
   - `id`: único, nunca muda depois (é o que vai no save).
   - `display_name_key`: chave do CSV com o nome (título da página no diário).
   - `description_key`: chave do CSV com o texto escrito na evidência.
   - `icon`: o desenho. É a imagem grande no viewer e, se o `Interactable` não tiver textura própria,
     também o objeto no mundo.
3. No `translations/translations.csv`, escreva o texto com a **marcação do glossário** (a mesma do
   diálogo, ver `docs/sistema_de_profiling.md`):

   ```
   PLACEHOLDER_EVIDENCE_TORN_NOTE_DESC,"... Signed by [MARCOS] [CASTRO], something about a [FACA].","... Assinado por [MARCOS] [CASTRO], algo sobre uma [FACA]."
   ```

   O id entre colchetes é o `GlossaryWord.id` em maiúsculas. A palavra vai para o glossário de
   **quem a tem no pool** (`ProfilingJournal.discover_word` sem NPC), igual ao diálogo. O par vem das
   `paired_words` da palavra, então `[MARCOS] [CASTRO]` (com espaço) e `[MARCOS]/[CASTRO]` (com barra,
   que aparece no texto) funcionam igual.
4. Arraste `scenes/interactables/Interactable.tscn` para o `YSort` da cena, escolha a consequência
   **Evidência** e aponte o `.tres` em `evidence`.

> **Cuidado:** uma palavra marcada que não está no pool de nenhum NPC **não bloqueia** o fechar
> (senão o jogador ficaria preso), mas também nunca entra em glossário nenhum, e o console avisa. Se
> uma evidência fecha "fácil demais", confira o aviso `[Profiling] - AVISO: a palavra ... não está no
> pool de nenhum NPC`.

## Testando

- **Na cidade:** o bilhete rasgado (`TornNoteEvidence`) tem `[MARCOS] [CASTRO]` e `[FACA]`. Clique
  nele, confira que o "Fechar" está desabilitado, passe o mouse em "Marcos" (as duas acendem), colha
  tudo, feche e abra o diário (**J**).
- **Autoteste do profiling** (F4, ou `godot --headless --path . --script res://tests/run_profiling_self_test.gd`):
  confere o hover do par e a regra do fechar (casos "O hover numa palavra acende o par junto",
  "Evidência com palavra por colher não fecha" e vizinhos).

---

## Save

- **Evidência lida:** o `Diary` guarda os ids na seção `evidences` (`{ "ids": ["torn_note"] }`) e
  refaz as páginas ao abrir a partida, pelo `ItemCatalog`. Id que não existe mais é ignorado.
- **Palavras colhidas:** são do `ProfilingJournal` (seção `profiling`), como qualquer palavra.
- **A evidência no mundo:** não tem save nenhum, porque nunca sai do mundo.
- Fechar o jogo com a evidência aberta não perde nada: as palavras já colhidas ficam colhidas, e a
  evidência entra no diário quando o jogador a fechar da próxima vez.

Saves antigos com as seções `inventory` e `pickups` continuam abrindo: o `SaveManager` guarda chave
desconhecida sem mexer. Um bilhete que estava no inventário de um save antigo não aparece no diário
até o jogador abrir e fechar a evidência de novo.

## Limitações atuais / como escalar

- **Uma imagem só.** O `icon` serve para o objeto no mundo e para a vista de perto. Se a arte de perto
  for outra (um bilhete aberto, frente e verso), é um campo `closeup: Texture2D` a mais no `ItemData`
  e uma linha no `EvidenceViewer.open()`.
- **Página do diário só com texto.** O diário de hoje desenha título e texto; a imagem da evidência
  entra quando o diário ganhar páginas com ícone (ver `docs/diary.md`, "Como escalar").
- **Glossário por pool.** Se uma palavra estiver no pool de dois NPCs, ela vai para os dois. Se uma
  evidência precisar mandar para um NPC específico, é um campo `npc_id` no `ItemData` passado para
  `set_marked_text()`.
- **Sem controle por gamepad no viewer.** Zoom e arrasto são de mouse; o fechar funciona com Esc.
