# Sistema de Localização Godot 4.7

*Esse documento visa guiar a equipe de programação no processo de localização do jogo.*

---

## Sumário

1. [Locale vs. idioma](#1-locale-vs-idioma)
2. [Criando arquivos de tradução (CSV)](#2-criando-arquivos-de-tradução-csv)
3. [Adicionando as traduções ao projeto](#3-adicionando-as-traduções-ao-projeto)
4. [Usando tr() no código](#4-usando-tr-no-código)
5. [Tradução automática em Controls (Button, Label...)](#5-tradução-automática-em-controls-button-label)
6. [Placeholders / textos dinâmicos](#6-placeholders--textos-dinâmicos)
7. [Pluralização](#7-pluralização)
8. [Separador decimal (6.5 vs. 6,5)](#8-separador-decimal-65-vs-65)
9. [TranslationServer e troca de idioma em runtime](#9-translationserver-e-troca-de-idioma-em-runtime)
10. [Detectando o idioma do sistema automaticamente](#10-detectando-o-idioma-do-sistema-automaticamente)
11. [Testando traduções e reimportando o CSV](#11-testando-traduções-e-reimportando-o-csv)
12. [Referências](#12-referências)

---

## 1. Locale vs. idioma

Um locale normalmente combina um idioma com uma região/país. Exemplos:

| Locale | Significado |
|---|---|
| en | Inglês (genérico) |
| en_US | Inglês dos EUA |
| pt | Português (genérico) |
| pt_BR | Português do Brasil |
| pt_PT | Português de Portugal |

Não é de extrema importância pro projeto, mas é bom saber a diferença — o `TranslationServer` e o CSV trabalham com o código de locale, não com "idioma" como conceito solto.

---

## 2. Criando arquivos de tradução (CSV)

A forma usada nesse projeto: `translations/translations.csv`. Qualquer editor de planilhas (LibreOffice Calc, Google Sheets) exporta nesse formato.

**Regras do formato:**

- A primeira coluna contém a **chave** (KEY), única, em `MAIUSCULO_COM_UNDERSCORE` (ex.: `MENU_VOLUME`) — nunca o texto em inglês cru.
- As colunas seguintes têm como cabeçalho o **código do locale** (`en`, `pt_BR`) — precisa ser um locale válido reconhecido pelo Godot.
- O arquivo deve ser salvo em UTF-8 sem BOM.
- Valores contendo vírgula, quebra de linha ou aspas duplas devem ficar entre aspas duplas (com aspas internas escapadas como `""`).

### Exemplo — translations.csv

```csv
keys,en,pt_BR
MENU_VOLUME,General Volume,Volume Geral
MENU_EXIT,Exit,Sair
GREETING_HELLO,"Hello, %s!","Olá, %s!"
```

### Importando

- O arquivo já mora dentro de `res://translations/`.
- O Godot detecta o arquivo automaticamente e o trata como tradução.
- Ao (re)importar, o Godot gera um recurso `.translation` compactado por idioma, e essas traduções ficam listadas em Project Settings (ver seção 3).
- **Depois de editar o CSV, sempre confira se ele foi reimportado** — ver seção 11, é a causa nº 1 de "mudei o CSV e não aparece na cena".

---

## 3. Adicionando as traduções ao projeto

Um arquivo de tradução só é carregado em runtime se estiver listado em:

**Project → Project Settings → Localization → Translations**

(nesse projeto já está configurado, apontando pros dois `.translation` gerados a partir do CSV). Remover ali só tira do sistema de tradução — não apaga o arquivo do disco.

---

## 4. Usando tr() no código

A função `tr()` (herdada de `Object`) busca uma chave nas traduções carregadas e retorna o texto convertido pro locale atual. Se a chave não existir, retorna a própria chave sem alteração (é assim que a gente percebe uma chave esquecida ou não reimportada — o texto cru aparece na tela).

```gdscript
func _ready() -> void:
    $Label.text = tr("MENU_VOLUME")
```

---

## 5. Tradução automática em Controls (Button, Label...)

Controles de UI (Button, Label, etc.) traduzem automaticamente o próprio campo `Text` se ele for igual a uma chave existente — ou seja, digita `MENU_VOLUME` direto no campo Text do inspetor (ou no `.tscn`), sem chamar `tr()` manualmente. É o que usamos pros textos estáticos do menu.

Isso só vale pro campo `Text` do próprio nó, setado na cena — texto montado em código (ex.: itens de `OptionButton` via `add_item()`) **não** se retraduz sozinho, precisa de `tr()` manual e repopular quando o idioma muda (ver seção 9).

Se algum Label não deve ser traduzido mesmo coincidindo com uma chave (ex.: nome de jogador), desativa no inspetor: **Auto Translate → Mode → Disabled**.

---

## 6. Placeholders / textos dinâmicos

Pra strings com parte variável, usa `%s`/`%d` (printf-style) e substitui depois do `tr()`:

```csv
keys,en,pt_BR
WELCOME_MSG,Welcome %s!,Bem-vindo %s!
```

```gdscript
welcome_label.text = tr("WELCOME_MSG") % nome_do_jogador
# pt_BR: "Bem-vindo Ogro!"
```

Mais de um valor: `tr("CHAVE") % [valor1, valor2]`.

> Regra de sempre: nunca guarda o resultado do `tr()` pronto se o texto pode precisar ser reconstruído (idioma mudou, valor mudou) — chama `tr()` de novo na hora de exibir.

---

## 7. Pluralização

Pra textos que mudam de forma dependendo de uma quantidade ("1 save encontrado" vs. "3 saves encontrados"), usa duas chaves independentes (uma por forma) e escolhe qual usar no código, comparando o número:

```csv
keys,en,pt_BR
SAVE_COUNT_ONE,%d save found,%d save encontrado
SAVE_COUNT_OTHER,%d saves found,%d saves encontrados
```

```gdscript
func texto_contagem_saves(quantidade: int) -> String:
    var chave := "SAVE_COUNT_ONE" if quantidade == 1 else "SAVE_COUNT_OTHER"
    return tr(chave) % quantidade
```

Se algum dia o projeto precisar de um idioma com regras de plural mais complexas (russo, árabe — 3+ formas), essa abordagem manual não escala bem; reavaliar nesse momento.

---

## 8. Separador decimal (6.5 vs. 6,5)

O GDScript **não** troca o separador decimal sozinho por locale — `str(6.5)` e `"%.1f" % 6.5` sempre dão `"6.5"` com ponto, mesmo com o sistema operacional (ou o `TranslationServer`) em `pt_BR`. Testado nesse projeto: confirmado que não muda sozinho.

Pra mostrar vírgula em português, é manual — um helper que troca o separador dependendo do locale ativo:

```gdscript
func formatar_numero(valor: float, casas_decimais: int = 1) -> String:
    var texto := "%.*f" % [casas_decimais, valor]
    if TranslationServer.get_locale().begins_with("pt"):
        texto = texto.replace(".", ",")
    return texto
```

```gdscript
label.text = formatar_numero(6.5)
# en: "6.5"
# pt_BR: "6,5"
```

Mesmo truque de comparar só os 2 primeiros caracteres do locale que já usamos em `_locale_para_indice()` (settings.gd) — funciona pra qualquer variante de português (`pt_BR`, `pt_PT`), não só `pt_BR` exato.

---

## 9. TranslationServer e troca de idioma em runtime

`TranslationServer` é o servidor de baixo nível que guarda o locale ativo e permite trocar em tempo de execução (o seletor de idioma do menu de Opções usa isso), sem reiniciar o jogo.

```gdscript
TranslationServer.set_locale("pt_BR")
var atual := TranslationServer.get_locale()
```

Assim que `set_locale()` roda, os Controls com tradução automática (seção 5) se atualizam sozinhos. Texto montado em código (OptionButton, labels dinâmicos da seção 6/7) **não** se atualiza sozinho — precisa reagir a `NOTIFICATION_TRANSLATION_CHANGED` (via `_notification()`) e reconstruir o texto, ou só ficar desatualizado até a próxima vez que o valor mudar / a cena recarregar.

---

## 10. Detectando o idioma do sistema automaticamente

**Não precisa chamar nada explicitamente pra isso.** O Godot já inicializa o `TranslationServer` sozinho com o idioma do sistema operacional, automaticamente, antes de qualquer script rodar — é o comportamento padrão da engine, tanto no editor quanto no `.exe` exportado.

O que o projeto faz (em `main_menu.gd` e `settings.gd`) é só **restaurar uma escolha salva, quando ela existir**:

```gdscript
func _apply_saved_locale() -> void:
    var config := ConfigFile.new()
    if config.load(CONFIG_PATH) != OK:
        return  # sem config salva: mantém o idioma do SO que a engine já aplicou
    var saved_locale: String = config.get_value("idioma", "codigo", "")
    if saved_locale != "":
        TranslationServer.set_locale(saved_locale)
```

Ou seja: quando não há nada salvo, simplesmente não fazemos nada — e o idioma que fica valendo já é o do sistema operacional do jogador, de graça. Mesmo com a detecção automática, sempre deixamos o jogador trocar manualmente nas Opções (idioma do SO pode não bater com a preferência dele, ou a tradução pra aquele idioma pode não existir ainda).

---

## 11. Testando traduções e reimportando o CSV

Formas de testar sem trocar o idioma do sistema operacional:

- **Editor → View → Preview Translation**: escolhe um idioma na barra superior do editor; todo texto nas cenas abertas passa a exibir a tradução escolhida, só no editor.
- Rodando pelo terminal: `godot --language pt_BR`.

**Causa mais comum de "mudei o CSV e não apareceu":** o `.csv` é só a fonte — o Godot precisa **reimportar** (reprocessar o CSV e gerar de novo os `.translation` compactados) toda vez que ele muda. Isso só acontece automaticamente se o editor estiver **aberto** no momento em que o arquivo é salvo.

- Editor aberto → salva o CSV → reimporta sozinho (raramente precisa fazer mais nada).
- Editor fechado, ou não reimportou sozinho → **FileSystem dock → botão direito em `translations.csv` → Reimport**.
- Pra conferir se está desatualizado: compara a data de modificação do `.csv` com a dos `.en.translation`/`.pt_BR.translation` — se o `.csv` for mais recente, precisa reimportar.

---

## 12. Referências

- **Documentação oficial — Internationalizing games:** `docs.godotengine.org/en/stable/tutorials/i18n/internationalizing_games.html`
- **Documentação oficial — Importing translations:** `docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_translations.html`
- **Documentação oficial — Locale codes:** `docs.godotengine.org/en/stable/tutorials/i18n/locales.html`

> Contexto de tradução (`?context`), remaps de recurso por locale (imagens/áudio), pseudolocalização e RTL/bidi não estão documentados aqui porque o projeto não usa nada disso hoje — estão nos links oficiais acima (seção "Internationalizing games") se algum dia precisar.
