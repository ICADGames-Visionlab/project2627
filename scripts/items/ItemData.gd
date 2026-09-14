## ItemData - descreve um TIPO de item que pode existir no inventário do jogador (ex: "bilhete
## misterioso"), não uma unidade específica dele.
##
## COMO USAR: botão direito em res://items/ -> New Resource -> ItemData, preencher os campos no
## Inspector e salvar como .tres. O mesmo .tres pode ser referenciado por várias pilhas de
## inventário, por vários ItemPickup no mundo e por diálogos/missões, sem duplicar dado nenhum.
##
## Ver docs/Inventory.md para o passo a passo completo de criação de um item novo.
class_name ItemData
extends Resource

## Espaço para variáveis

# Identificador estável do item, usado como chave no inventário (Inventory._stacks) e no comando
# de debug ("dar_evidencia"). NUNCA muda depois de criado: mudar quebraria saves e outros
# Resources que já referenciam esse id por texto. Quem pode mudar à vontade é display_name_key.
@export var id: StringName = &""

# Chave de tradução (ver docs/localizacao_Godot.md) para o nome mostrado ao jogador. Nunca um
# texto solto aqui: o guideline de idioma proíbe string hardcoded exibida na UI.
@export var display_name_key: StringName = &""

# Chave de tradução para a descrição do item, exibida no detalhe do slot.
@export var description_key: StringName = &""

# Ícone mostrado no slot do inventário e no ItemPickup no mundo. Pode ficar vazio durante o
# desenvolvimento (a UI e o ItemPickup lidam com ícone nulo sem quebrar) — mas, se for placeholder,
# precisa ser identificável e ter uma Issue de substituição, conforme o guideline.
@export var icon: Texture2D

# Quantas unidades cabem numa única pilha do inventário antes de o excedente ser descartado. 1 =
# item não empilhável (evidência única, por exemplo). Ver "Limitações atuais" em docs/Inventory.md.
@export_range(1, 999, 1) var max_stack: int = 99

# Se true, o jogador pode destruir este item pela UI (Inventory.destroy_item). False para itens
# que a investigação exige manter (evidência-chave que não pode ser perdida, por exemplo).
@export var destructible: bool = true
