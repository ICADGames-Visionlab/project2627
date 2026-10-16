# SaveSlotInfo.gd — Retrato de um slot de save, do jeito que o SaveManager o achou no disco.
#
# É o que o menu de slots desenha (estado, data, dia e local) e o que o SaveManager usa para abrir
# a partida. Quem monta é o SaveManager.get_slot_info(), que só lê: montar um SaveSlotInfo nunca
# cria, move nem apaga arquivo.
#
# DADO PURO: só guarda o que foi lido do disco, sem citar Autoload nem saber se desenhar. O rótulo
# do slot ("Dia 5, sexta, 14:20 — Cidade") é derivado das seções por quem desenha, não guardado aqui.
#
# O guia de uso está em docs/SaveManager.md.
class_name SaveSlotInfo
extends RefCounted

# EMPTY: nenhum arquivo do slot. OCCUPIED: o principal abriu. RECOVERED: o principal não abriu, mas
# o .tmp ou o .bak sim (o menu avisa). DAMAGED: existe arquivo, e nenhum abre — nunca vira EMPTY,
# para o jogador não perder o save achando que o slot está livre. NEWER: gravado por uma
# versão mais nova do jogo; não abre, não é apagado e não é sobrescrito.
enum State { EMPTY, OCCUPIED, RECOVERED, DAMAGED, NEWER }

var slot: int = 0
var state: State = State.EMPTY
# Versão do formato lida no arquivo (0 = save de desenvolvimento, sem versão).
var version: int = 0
# Unix UTC da gravação; 0 = desconhecido. No save v0 sai da data de modificação do arquivo, que é o
# único registro que existe. Quem desenha converte para a hora local.
var saved_at: int = 0
# Seções por chave de participante, já migradas para o formato atual. Vazias em EMPTY, DAMAGED e
# NEWER.
var sections: Dictionary = {}
# A partida veio do arquivo principal? Falso em RECOVERED: aí a próxima gravação apaga o principal
# podre em vez de empurrá-lo para o .bak, que guarda a última cópia boa.
var loaded_from_main: bool = false


# Diz se dá para continuar esta partida. RECOVERED também dá: é justamente o caso em que o backup
# salvou o progresso.
func can_continue() -> bool:
	return state == State.OCCUPIED or state == State.RECOVERED


# Devolve a seção de uma chave como Dictionary. Chave ausente, ou valor que não é Dictionary (o
# {"Var1": true} do menu antigo, por exemplo), devolve {} — que para todo participante é "novo
# jogo", nunca erro.
func get_section(key: String) -> Dictionary:
	var section: Variant = sections.get(key, {})
	if section is Dictionary:
		return section as Dictionary
	return {}
