# run_npc_routine_self_test.gd — Roda o autoteste da resolução de rotinas de NPC pela linha de comando.
#
#     godot --headless --path . --script res://tests/run_npc_routine_self_test.gd
#
# Sai com código 0 quando todos os casos passam e 1 quando algum falha, para poder virar verificação
# automática antes de PR. Os casos em si ficam em NPCRoutineSelfTest, os mesmos da ação "Autoteste das
# rotinas" do menu de debug.
extends SceneTree

# Carregado por caminho, e não pelo nome da classe, pelo mesmo motivo do autoteste dos insights: se o
# autoteste não compilar, o erro sai daqui com o caminho do arquivo, em vez de um "Identifier not found"
# solto num script que ninguém abriu.
const SELF_TEST_PATH: String = "res://scripts/npc/NPCRoutineSelfTest.gd"


# Executa o autoteste, imprime o relatório e encerra com o código de saída do resultado.
func _initialize() -> void:
	var self_test_script: GDScript = ResourceLoader.load(SELF_TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if self_test_script == null or not self_test_script.can_instantiate():
		push_error("[NPCs] - ERRO: autoteste não compilou (%s)" % SELF_TEST_PATH)
		quit(1)
		return
	var self_test: RefCounted = self_test_script.new()
	self_test.call(&"run")
	print(self_test.call(&"report"))
	quit(0 if int(self_test.get(&"failed_count")) == 0 else 1)
