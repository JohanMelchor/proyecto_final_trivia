defmodule Trivia.Game do
  use GenServer
  alias Trivia.{UserManager, QuestionBank, History}

  # ===============================
  # API pública
  # ===============================

  def start_link(args) when is_map(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def answer(pid, username, answer) do
    GenServer.cast(pid, {:answer, username, answer})
  end

  # ===============================
  # Inicialización
  # ===============================

  @impl true
  def init(%{mode: :multi} = args) do
    IO.puts("\n🎮 Iniciando partida MULTIJUGADOR en '#{args.category}'...\n")

    questions = QuestionBank.get_random_questions(args.category, args.num)

    if questions == [] do
      IO.puts("⚠️ No hay preguntas disponibles para la categoría #{args.category}.")
      {:stop, :no_questions}
    else
      state = %{
        mode: :multi,
        lobby_pid: args.lobby_pid,
        players: args.players,
        category: args.category,
        questions: questions,
        current: nil,
        time: args.time
      }

      Process.send_after(self(), :next_question, 500)
      {:ok, state}
    end
  end

  def init(%{mode: :single, username: username, category: category, num: num, time: time, caller: caller}) do
    IO.puts("\n🎮 Iniciando partida de #{username} en '#{category}' (singleplayer)...\n")

    questions = QuestionBank.get_random_questions(category, num)

    state = %{
      mode: :single,
      username: username,
      caller: caller,
      category: category,
      questions: questions,
      current: nil,
      score: 0,
      time: time
    }

    Process.send_after(self(), :next_question, 500)
    {:ok, state}
  end

  # ===============================
  # MANEJO DE PREGUNTAS
  # ===============================

  @impl true
  def handle_info(:next_question, %{mode: :multi, questions: []} = state) do
    send(state.lobby_pid, {:game_over, state.players})
    {:stop, :normal, state}
  end

  def handle_info(:next_question, %{mode: :multi, questions: [q | rest]} = state) do
    send(state.lobby_pid, {:question, q})
    Process.send_after(self(), :timeout, state.time * 1000)
    {:noreply, %{state | questions: rest, current: q}}
  end

  def handle_info(:timeout, %{mode: :multi} = state) do
    send(state.lobby_pid, {:timeout, state.current})
    Process.send_after(self(), :next_question, 2000)
    {:noreply, %{state | current: nil}}
  end

  # --- SINGLEPLAYER ---
  def handle_info(:next_question, %{mode: :single, questions: []} = state) do
    UserManager.update_score(state.username, state.score)
    History.save_result(state.username, state.category, state.score)

    if state.caller, do: send(state.caller, {:game_over, state.score})
    {:stop, :normal, state}
  end

  def handle_info(:next_question, %{mode: :single, questions: [q | rest]} = state) do
    if state.caller, do: send(state.caller, {:question, q["question"], q["options"]})
    Process.send_after(self(), :timeout, state.time * 1000)
    {:noreply, %{state | questions: rest, current: q}}
  end

  def handle_info(:timeout, %{mode: :single} = state) do
    IO.puts("\n⏰ Tiempo agotado. -5 puntos.")
    Process.send_after(self(), :next_question, 1000)
    {:noreply, %{state | score: state.score - 5}}
  end

  # ===============================
  # RESPUESTAS
  # ===============================

  @impl true
  def handle_cast({:answer, username, ans}, %{mode: :multi, current: q} = state) do
    if q && Map.has_key?(state.players, username) do
      correct = String.downcase(ans) == String.downcase(q["answer"])
      delta = if correct, do: 10, else: -5

      updated_players =
        Map.update!(state.players, username, fn p ->
          %{p | score: p.score + delta}
        end)

      send(state.lobby_pid, {:player_answered, username, correct, delta})
      {:noreply, %{state | players: updated_players}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:answer, answer}, %{mode: :single, current: q} = state) do
    correct = String.downcase(answer) == String.downcase(q["answer"])
    delta = if correct, do: 5, else: -2
    Process.send_after(self(), :next_question, 1500)
    {:noreply, %{state | score: state.score + delta}}
  end
end
