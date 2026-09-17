# run_dialogue_self_test.gd — Roda o autoteste do sistema de diálogo pela linha de comando.
#
#     godot --headless --path . --script res://tests/run_dialogue_self_test.gd
#
# Sai com código 0 quando todos os casos passam e 1 quando algum falha (critério de aceite do
# SPEC §15.5). Os casos em si ficam em DialogueSelfTest, os mesmos da ação "Autoteste do diálogo"
# do menu de debug.
extends SceneTree

# Carregado por caminho, e não pelo nome da classe, pelo mesmo motivo de run_insight_self_test.gd:
# com --script este arquivo compila antes de os Autoloads existirem, e citar DialogueSelfTest aqui
# forçaria a compilação dele (que usa DialogueState e GameManager) cedo demais.
const SELF_TEST_PATH: String = "res://scripts/dialogue/debug/DialogueSelfTest.gd"


func _initialize() -> void:
	# Adiado para o primeiro quadro: os Autoloads ainda estão entrando na árvore quando
	# _initialize() roda.
	_run.call_deferred()


func _run() -> void:
	var self_test_script: GDScript = ResourceLoader.load(SELF_TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if self_test_script == null or not self_test_script.can_instantiate():
		push_error("[Dialogue] - ERRO: autoteste não compilou (%s)" % SELF_TEST_PATH)
		quit(1)
		return
	var self_test: RefCounted = self_test_script.new()
	# run() é uma coroutine (espera o step_ready do MemoryRunner) — precisa de await mesmo chamada
	# por nome.
	await self_test.call(&"run")
	print(self_test.call(&"report"))
	quit(0 if int(self_test.get(&"failed_count")) == 0 else 1)
