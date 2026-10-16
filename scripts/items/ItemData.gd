## ItemData - descreve uma EVIDÊNCIA (ex: "bilhete rasgado"): o desenho e o texto que o jogador lê
## quando clica nela no mundo.
##
## O nome é ItemData por herança do antigo inventário; hoje não existe mais inventário nem item
## largado no chão. Uma evidência fica no mundo (Interactable com consequência EVIDENCE), abre no
## EvidenceViewer ao ser clicada e vai para o diário quando o jogador a fecha.
##
## COMO USAR: botão direito em res://items/ -> New Resource -> ItemData, preencher os campos no
## Inspector e salvar como .tres direto em res://items/ (é lá que o ItemCatalog procura quando o save
## traz a evidência de volta para o diário).
##
## Ver docs/evidencias.md para o passo a passo completo de criação de uma evidência nova.
class_name ItemData
extends Resource

## Espaço para variáveis

# Identificador estável da evidência, gravado no save do diário (ver Diary.add_evidence). NUNCA muda
# depois de criado: mudar faria a evidência sumir do diário de quem já a leu. Quem pode mudar à
# vontade é display_name_key.
@export var id: StringName = &""

# Chave de tradução (ver docs/localizacao_Godot.md) do nome da evidência: o título da página no
# diário. Nunca um texto solto aqui: o guideline de idioma proíbe string hardcoded exibida na UI.
@export var display_name_key: StringName = &""

# Chave de tradução do texto escrito na evidência. Aceita a marcação do glossário ("Achei uma [FACA]",
# "[MARCOS] [CASTRO]", ver ClickableWordText): as palavras marcadas aparecem sublinhadas no
# EvidenceViewer, e o jogador só fecha a evidência depois de colher todas.
@export var description_key: StringName = &""

# O desenho da evidência: o objeto no mundo (quando o Interactable não tem textura própria) e a
# imagem grande no EvidenceViewer. Se for placeholder, precisa ser identificável e ter uma Issue de
# substituição, conforme o guideline.
@export var icon: Texture2D
