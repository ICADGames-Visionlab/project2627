# AudioDirector.gd — Reage a fatos do mundo para trocar o ambiente sonoro.
# Existe na validação como exemplo do ouvinte mais simples possível: um sistema que só escuta,
# nunca emite, e não conhece quem produziu o fato.
#
# Placeholder: aqui o diretor apenas registra o que faria. A reprodução real entra quando os
# assets de áudio existirem.
class_name AudioDirector
extends Node

var _current_ambience: StringName = &""


func _ready() -> void:
	EventBus.night_started.connect(_on_night_started)


# Troca o ambiente sonoro quando anoitece. Isto é reação a fato, e não a comando: o relógio
# anuncia que anoiteceu, e cada sistema decide sozinho o que fazer com isso.
func _on_night_started() -> void:
	_current_ambience = &"night"
	print("[Audio] - Ambiente sonoro trocado para \"%s\"" % _current_ambience)
