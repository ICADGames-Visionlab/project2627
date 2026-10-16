## ItemCatalog - acha o ItemData de um id, varrendo os .tres de res://items/.
##
## O save guarda só o id do item (ver docs/SaveManager.md, "Save é retrato de fatos"), e quem carrega
## o inventário ou um item largado no chão precisa voltar do id para o recurso. Não é Autoload: é dado
## estático, sem estado de partida, então uma classe com funções static basta (mesmo jeito do
## InsightCatalog). Ver docs/Inventory.md.
class_name ItemCatalog
extends RefCounted

## Espaço para constantes

const ITEMS_DIR: String = "res://items/"

## Espaço para variáveis

# Cache id -> ItemData, montado na primeira consulta. A pasta não muda com o jogo rodando, e varrer
# a cada item de um save seria ler o disco N vezes por nada.
static var _items: Dictionary[StringName, ItemData] = {}
static var _loaded: bool = false

## Espaço para funções personalizadas

# ItemData do id, ou null se nenhum .tres de res://items/ tiver esse id. Quem chama trata o null: id
# que o conteúdo não tem mais (item removido ou renomeado) é ignorado, nunca erro.
static func find_item(item_id: StringName) -> ItemData:
	_ensure_loaded()
	return _items.get(item_id)


# Varre res://items/ uma vez e indexa cada ItemData pelo id. O trim_suffix(".remap") existe porque a
# exportação renomeia os recursos convertidos para .tres.remap: sem ele a varredura funciona no
# editor e devolve vazio na build.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not DirAccess.dir_exists_absolute(ITEMS_DIR):
		push_warning("[Inventory] - AVISO: pasta de itens \"%s\" não existe" % ITEMS_DIR)
		return
	for file_name: String in DirAccess.get_files_at(ITEMS_DIR):
		var clean_name: String = file_name.trim_suffix(".remap")
		if not clean_name.ends_with(".tres") and not clean_name.ends_with(".res"):
			continue
		var item: ItemData = ResourceLoader.load(ITEMS_DIR + clean_name) as ItemData
		if item == null or item.id == &"":
			push_warning("[Inventory] - AVISO: \"%s\" não é um ItemData com id" % (ITEMS_DIR + clean_name))
			continue
		if _items.has(item.id):
			push_warning("[Inventory] - AVISO: id de item repetido: \"%s\"" % item.id)
			continue
		_items[item.id] = item
	print("[Inventory] - Catálogo de itens: %d item(ns) em %s" % [_items.size(), ITEMS_DIR])
