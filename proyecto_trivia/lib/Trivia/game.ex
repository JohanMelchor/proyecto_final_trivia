defmodule Trivia.Game do
  use GenServer
  alias Trivia.{UserManager, QuestionBank}

  # ===============================
  # API pública
  # ===============================

  @doc """
  Inicia un nuevo proceso de juego para un usuario
  """
  def start_link(args) when is_map(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc """
  Consulta el puntaje actual del juego en curso
  """
  def get_score(pid) do
    GenServer.call(pid, :get_score)
  end

  @doc """
  Envía una respuesta del usuario para la pregunta actual
  """
  def answer(pid, answer) do
    GenServer.cast(pid, {:answer, answer})
  end

  # ===============================
  # Callbacks de GenServer
  # ===============================

  @impl true
  def init(%{username: username, category: category, num: num, time: time, caller: caller}) do
    IO.puts("\n🎮 Iniciando partida de #{username} en '#{category}'...\n")

    questions = QuestionBank.get_random_questions(category, num)

    # Estado inicial del proceso
    state = %{
      username: username,
      questions: questions,
      current: nil,  # Pregunta actual (nil al inicio)
      score: 0,
      time: time,
      timer_ref: nil,  # Referencia del temporizador
      caller: caller
    }

    # Programar la primera pregunta
    Process.send_after(self(), :next_question, 100)

    {:ok, state}
  end

  @impl true
  def handle_info(:next_question, %{questions: []} = state) do
    if state.caller do
      send(state.caller, {:game_over, state.score})
    end

    Trivia.UserManager.update_score(state.username, state.score)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:next_question, %{questions: [q | rest]} = state) do
    # Enviar la pregunta al CLI
    if state.caller do
      send(state.caller, {:question, q["question"], q["options"]})
    end

    # Programar el timeout
    Process.send_after(self(), :timeout, state.time * 1000)

    {:noreply, %{state | questions: rest, current: q}}
  end

  @impl true
  def handle_info(:timeout, state) do
    IO.puts("\n⏰ Tiempo agotado. -5 puntos.")
    # Pasar a siguiente pregunta
    Process.send_after(self(), :next_question, 1000)
    {:noreply, %{state |
      score: state.score - 5,
      timer_ref: nil
    }}
  end

  @impl true
  def handle_cast({:answer, answer}, %{current: q, timer_ref: timer_ref} = state) do
    # Cancelar temporizador ya que el usuario respondió
    if timer_ref do
      Process.cancel_timer(timer_ref)
    end

    # Evaluar respuesta
    result =
      cond do
        not (answer in Map.keys(q["options"])) ->
          IO.puts("⚠️ Respuesta inválida. -10 puntos.")
          -10
        answer == String.downcase(q["answer"]) ->
          IO.puts("✅ Correcto. +10 puntos.")
          10
        true ->
          IO.puts("❌ Incorrecto. Era #{q["answer"]}. -5 puntos.")
          -5
      end

    # Pasar a siguiente pregunta después de un breve delay
    Process.send_after(self(), :next_question, 1500)

    {:noreply, %{state |
      score: state.score + result,
      timer_ref: nil
    }}
  end

  @impl true
  def handle_call(:get_score, _from, state) do
    {:reply, state.score, state}
  end
end
