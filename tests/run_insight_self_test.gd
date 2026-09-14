# run_insight_self_test.gd — Roda o autoteste da regra de escolha dos insights pela linha de comando.
#
#     godot --headless --path . --script res://tests/run_insight_self_test.gd
#
# Sai com código 0 quando todos os casos passam e 1 quando algum falha, para poder virar verificação
# automática antes de PR. Os casos em si ficam em InsightSelfTest, os mesmos da ação "Autoteste da
# escolha" do menu de debug.
extends SceneTree

# Carregado por caminho, e não pelo nome da classe: com --script, este arquivo é compilado antes de os
# Autoloads existirem, e citar InsightSelfTest aqui forçaria a compilação dele (que usa InsightJournal,
# HeadRegistry e InsightDirector) cedo demais — "Identifier not found".
const SELF_TEST_PATH: String = "res://scripts/insights/InsightSelfTest.gd"


func _initialize() -> void:
	# Adiado para o primeiro quadro: os Autoloads ainda estão entrando na árvore quando _initialize() roda.
	_run.call_deferred()


# Executa o autoteste, imprime o relatório e encerra com o código de saída do resultado.
func _run() -> void:
	var self_test_script: GDScript = ResourceLoader.load(SELF_TEST_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
	if self_test_script == null or not self_test_script.can_instantiate():
		push_error("[Insights] - ERRO: autoteste não compilou (%s)" % SELF_TEST_PATH)
		quit(1)
		return
	var self_test: RefCounted = self_test_script.new()
	self_test.call(&"run")
	print(self_test.call(&"report"))
	quit(0 if int(self_test.get(&"failed_count")) == 0 else 1)
