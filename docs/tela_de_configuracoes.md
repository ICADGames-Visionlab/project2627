# Tela de configurações

A tela de configurações (`scenes/ui/Settings.tscn` + `scripts/settings/Settings.gd`) é dividida em
abas. A mesma cena é usada no menu principal e no menu de pausa: cada um tem uma instância dela e
escuta o sinal `closed` (o cabeçalho do `Settings.gd` mostra como conectar).

## Abas e opções

| Aba | Opção | Quem guarda e salva | Arquivo |
| --- | --- | --- | --- |
| Geral | Idioma | `Settings.gd` | `user://settings.cfg` |
| Geral | Movimentação | `GameManager.set_movement_scheme()` | `user://gameplay_settings.cfg` |
| Vídeo | Modo de tela | `Settings.gd` | `user://settings.cfg` |
| Áudio | Volume geral | `AudioManager.set_general_volume()` | `user://audio_settings.cfg` |
| Diálogo | Tamanho do texto, fonte sem serifa, opacidade do painel, revelação do texto, animação | `GameManager.set_dialogue_preference()` | `user://gameplay_settings.cfg` |

A tela não é dona dos valores: ela mostra o valor atual e repassa a escolha para o sistema dono, que
aplica e salva. A exceção é vídeo e idioma, que não têm outro dono e são salvos pelo próprio
`Settings.gd`. Isso evita duas fontes de verdade para o mesmo valor.

## Como a cena está montada

```
Settings (Control, tema com fonte 24)
├─ Background            fundo escurecido, tela inteira
└─ Content (CenterContainer)
   └─ Column
      ├─ Title           "SETTINGS_TITLE"
      ├─ Tabs (TabContainer, %Tabs)
      │  ├─ General      metadado _tab_name = "SETTINGS_TAB_GENERAL"
      │  │  └─ Rows
      │  │     ├─ LanguageRow   Label + %LanguageOption
      │  │     └─ MovementRow   Label + %MovementOption
      │  ├─ Video        ScreenModeRow
      │  ├─ Audio        GeneralVolumeRow (slider + valor ao lado)
      │  └─ Dialogue     TextScaleRow, AltFontRow, PanelOpacityRow, TextRevealRow, AnimationRow
      └─ CloseButton (%CloseButton)  "SETTINGS_BACK"
```

- **Título da aba:** vem do metadado `_tab_name` do nó da aba, com uma chave do CSV. A engine traduz
  sozinha, inclusive quando o idioma muda com a tela aberta. O nome do nó (`General`, `Video`...) é
  só o identificador em inglês, nunca aparece para o jogador.
- **Linha:** todas as linhas seguem o mesmo molde, um `HBoxContainer` com um `Label` à esquerda (texto
  = chave do CSV, que se expande) e o controle à direita, com 440 px de largura. Sliders vêm dentro de
  um `SliderBox` com um `Label` que mostra o valor (`100%`, `1.0×`).
- **Nome único (`%`):** todo controle que o script usa tem "Access as Unique Name" ligado, e o script
  o busca por `%Nome`. Dá para mover uma linha de uma aba para outra, ou reordenar as linhas, sem mexer
  no script.
- **Tamanho:** o `TabContainer` usa `use_hidden_tabs_for_min_size`, então a janela tem sempre o
  tamanho da maior aba e não pula ao trocar de aba.
- **Fundo do painel:** o painel das abas tem um `StyleBoxFlat` quase opaco. Sem ele, os controles do
  tema padrão (que são translúcidos) somem sobre o jogo, no menu de pausa.

## Como adicionar uma opção

1. Na cena, duplique a linha mais parecida (`MovementRow` para um seletor, `GeneralVolumeRow` para um
   slider, `AltFontRow` para liga/desliga) dentro da aba certa.
2. Renomeie a linha e o controle em inglês (ex.: `MusicVolumeRow` / `MusicVolumeSlider`), confira que
   o controle está como nome único e troque o texto do `Label` por uma chave nova.
3. Crie a chave em `translations/translations.csv` (inglês e português).
4. No `Settings.gd`:
   - crie o `@onready var ...: Tipo = %NomeDoControle`;
   - se for um `OptionButton`, crie um `_populate_*()` que monta os itens com `tr()` e chame-o no
     `_ready()` **e** no `_notification()` (os itens montados em código não se retraduzem sozinhos);
   - conecte o sinal do controle no `_ready()`, **depois** do `_load_settings()`, a uma função que
     repassa o valor para o sistema dono;
   - em `_load_settings()`, faça o controle refletir o valor atual do sistema dono.
5. Se for um slider, acrescente o valor dele em `_refresh_value_labels()`.

O valor sempre pertence a um sistema (AudioManager, GameManager...), que aplica e salva. Só guarde
direto no `Settings.gd` o que não tiver outro dono, como vídeo e idioma. Nesse caso, lembre que
`_save_settings()` reescreve o arquivo inteiro: inclua a chave nova lá também.

## Como adicionar uma aba

1. Duplique uma aba (ex.: `Video`) como filha de `Tabs` e renomeie o nó em inglês (ex.: `Controls`).
2. Troque o metadado `_tab_name` por uma chave nova (ex.: `SETTINGS_TAB_CONTROLS`) e crie a chave no CSV.
3. Arraste o nó para a posição em que a aba deve aparecer: a ordem das abas é a ordem dos filhos.
4. Monte as linhas como em "Como adicionar uma opção".

## Navegação

- **Mouse:** clique na aba para trocar de aba.
- **Teclado:** com a barra de abas em foco, ← e → trocam de aba, e ↓ desce para a primeira opção. A tela
  reabre na última aba usada enquanto o jogo estiver aberto (a aba não é salva em disco).
- **ESC no menu de pausa:** fecha a tela de configurações e volta para os botões da pausa (quem cuida
  disso é o `PauseMenu.gd`).

## Quando outras branches entrarem

- **Suporte a controle (#55):** essa branch põe um nó `MenuFocus` na cena com
  `cancel_button = NodePath("../Sair")`. O botão agora se chama `CloseButton` e mora em
  `Content/Column`, então, ao resolver o conflito do `Settings.tscn`, fique com a versão em abas e
  aponte o `MenuFocus` para `../Content/Column/CloseButton`. O foco inicial pode ficar no padrão do
  `MenuFocus` (o primeiro controle focável, que é a barra de abas). Vale também mapear o LB/RB para
  trocar de aba (`tabs.select_previous_available()` / `select_next_available()`).
- **Corrida (#54):** essa branch acrescenta o esquema "Teclado + clique do mouse" (`MovementScheme.BOTH`)
  em `_populate_movement_options()`. Ao resolver o conflito, mantenha o terceiro item na mesma função.
