defmodule Trivia.Game do
  @moduledoc """
  GenServer que gestiona la lógica de una partida (single y multi).

  Responsabilidades:
  - Inicializar la partida (preguntas, jugadores).
  - Enviar preguntas y manejar temporizadores (:next_question / :timeout).
  - Recibir respuestas y actualizar puntajes.
  - En modo multijugador: acumular respuestas y enviar un resumen al Lobby
    cuando todos respondan o ocurra timeout.
  - En modo singleplayer: enviar feedback directo al proceso que inició el juego.

  API pública:
  - start_link(args :: map) -> inicia el GenServer con la configuración.
  - answer(pid_or_lobby, ...) -> enviar respuestas (soporta single y multi).
  """

  use GenServer
  alias Trivia.{UserManager, QuestionBank, History}

  # -----------------------
  # API pública
  # -----------------------

  @doc """
  Inicia el GenServer de la partida.

  args (map) esperado:
  - Multi: %{mode: :multi, lobby_pid: pid, players: %{username => %{pid: pid, score: 0}}, category:, num:, time:}
  - Single: %{mode: :single, username:, category:, num:, time:, caller: pid}
  """
  def start_link(args) when is_map(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc "Enviar respuesta a un juego single (pid)."
  def answer(pid, answer) when is_pid(pid), do: GenServer.cast(pid, {:answer, answer})

  @doc """
  Enviar respuesta en modo multijugador indicando el lobby y el usuario.
  El Lobby redirige al Game; si el lobby no existe devuelve error.
  """
  def answer(lobby_id, username, answer) do
    case :global.whereis_name({:lobby, lobby_id}) do
      :undefined -> {:error, "Lobby no encontrado"}
      pid -> GenServer.cast(pid, {:answer, username, answer})
    end
  end

  # -----------------------
  # Integración con DynamicSupervisor
  # -----------------------

  @doc """
  child_spec permite arrancar el juego bajo un DynamicSupervisor con restart: :temporary.
  """
  def child_spec(arg) do
    %{
      id: {__MODULE__, arg[:lobby_id] || make_ref()},
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc "Cancelar timers/limpiar recursos al terminar."
  @impl true
  def terminate(_reason, state) do
    if Map.get(state, :timer_ref), do: Process.cancel_timer(state.timer_ref)
    :ok
  end

  # -----------------------
  # Inicialización
  # -----------------------

  @impl true
  def init(%{mode: :multi} = args) do
    IO.puts("\n Iniciando partida MULTIJUGADOR en '#{args.category}'...\n")
    questions = QuestionBank.get_random_questions(args.category, args.num)

    if questions == [] do
      IO.puts(" No hay preguntas disponibles para la categoría #{args.category}.")
      {:stop, :no_questions}
    else
      players_with_state =
        Enum.into(args.players, %{}, fn {username, data} ->
          {username, Map.put(data, :answered, false)}
        end)

      state = %{
        mode: :multi,
        lobby_pid: args.lobby_pid,
        players: players_with_state,
        category: args.category,
        questions: questions,
        current: nil,
        time: args.time,
        timer_ref: nil,
        current_responses: []
      }

      Process.send_after(self(), :next_question, 500)
      {:ok, state}
    end
  end

  @impl true
  def init(%{mode: :single, username: username, category: category, num: num, time: time, caller: caller}) do
    questions = QuestionBank.get_random_questions(category, num)

    state = %{
      mode: :single,
      username: username,
      caller: caller,
      category: category,
      questions: questions,
      current: nil,
      score: 0,
      time: time,
      timer_ref: nil,
      answered: false,
      question_number: 0
    }

    Process.send_after(self(), :next_question, 100)
    {:ok, state}
  end

  # -----------------------
  # Manejo de preguntas / timeouts
  # -----------------------

  # MULTIJUGADOR: fin de preguntas
  @impl true
  def handle_info(:next_question, %{mode: :multi, questions: []} = state) do
    Enum.each(state.players, fn {username, %{score: score}} ->
      UserManager.update_score(username, score)
      History.save_result(username, state.category, score)
    end)

    send(state.lobby_pid, {:game_over, state.players})
    send(state.lobby_pid, :game_finished)
    {:stop, :normal, state}
  end

  def handle_info(:next_question, %{mode: :multi, questions: [q | rest]} = state) do
    IO.puts("\n==================================")
    IO.puts("Pregunta #{length(state.questions) - length(rest)}/#{length(state.questions)}")
    IO.puts("Categoría: #{state.category}")
    IO.puts("==================================")

    reset_players =
      Enum.into(state.players, %{}, fn {username, data} ->
        {username, %{data | answered: false}}
      end)

    send(state.lobby_pid, {:question, q})
    ref = Process.send_after(self(), :timeout, state.time * 1000)

    {:noreply, %{state |
      questions: rest,
      current: q,
      timer_ref: ref,
      players: reset_players,
      current_responses: []
    }}
  end

  # MULTIJUGADOR: timeout de la pregunta
  def handle_info(:timeout, %{mode: :multi, current: _q, players: players} = state) do
    {updated_players, timeout_responses} =
      Enum.map_reduce(players, [], fn {username, data}, acc ->
        if not data.answered do
          new_data = %{data | score: data.score - 5, answered: true}
          resp = {username, :timeout, false, -5}
          {{username, new_data}, [resp | acc]}
        else
          {{username, data}, acc}
        end
      end)

    combined_summary = Enum.reverse(state.current_responses) ++ Enum.reverse(timeout_responses)
    send(state.lobby_pid, {:question_summary, combined_summary})
    send(state.lobby_pid, {:timeout, state.current})

    Process.send_after(self(), :next_question, 2000)
    {:noreply, %{state | current: nil, timer_ref: nil, players: Enum.into(updated_players, %{}), current_responses: []}}
  end

  # SINGLEPLAYER: fin de preguntas
  @impl true
  def handle_info(:next_question, %{mode: :single, questions: []} = state) do
    IO.puts(" Fin del juego - Puntaje final: #{state.score}")
    UserManager.update_score(state.username, state.score)
    History.save_result(state.username, state.category, state.score)

    if state.caller, do: send(state.caller, {:game_over, state.score})
    {:stop, :normal, state}
  end

  def handle_info(:next_question, %{mode: :single, questions: [q | rest]} = state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    question_number = state.question_number + 1
    IO.puts("\n=== Pregunta #{question_number} ===")
    if state.caller, do: send(state.caller, {:question, q["question"], q["options"]})

    timer_ref = Process.send_after(self(), :timeout, state.time * 1000)

    {:noreply, %{state |
      questions: rest,
      current: q,
      timer_ref: timer_ref,
      answered: false,
      question_number: question_number
    }}
  end

  @impl true
  def handle_info(:timeout, %{mode: :single, answered: false, current: q} = state) do
    IO.puts(" Tiempo agotado para: #{q["question"]}")
    IO.puts(" Respuesta correcta: #{q["answer"]}")

    new_score = state.score - 1
    IO.puts(" Penalización: -1 puntos | Puntaje actual: #{new_score}")
    if state.caller, do: send(state.caller, {:timeout_notice, q["answer"]})

    Process.send_after(self(), :next_question, 2000)

    {:noreply, %{state |
      score: new_score,
      current: nil,
      timer_ref: nil,
      answered: true
    }}
  end

  def handle_info(:timeout, %{mode: :single, answered: true} = state), do: {:noreply, state}

  # -----------------------
  # Manejo de respuestas
  # -----------------------

  # MULTIJUGADOR: recibir respuesta de un jugador (username, ans)
  @impl true
  def handle_cast({:answer, username, ans}, %{mode: :multi, current: q} = state) do
    if q && Map.has_key?(state.players, username) do
      player = state.players[username]

      if player.answered do
        {:noreply, state}
      else
        correct = String.downcase(ans) == String.downcase(q["answer"])
        delta = if correct, do: 10, else: -5

        updated_players =
          Map.update!(state.players, username, fn p -> %{p | score: p.score + delta, answered: true} end)

        response = {username, :answered, correct, delta}
        new_responses = [response | state.current_responses]

        # No enviar notificación inmediata; sólo enviar resumen cuando todos respondan.
        all_answered = Enum.all?(updated_players, fn {_, p} -> p.answered end)

        if all_answered do
          send(state.lobby_pid, {:question_summary, Enum.reverse(new_responses)})
          if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
          Process.send_after(self(), :next_question, 2000)
        end

        {:noreply, %{state | players: updated_players, current_responses: new_responses}}
      end
    else
      {:noreply, state}
    end
  end

  # SINGLEPLAYER: respuesta del jugador single
  @impl true
  def handle_cast({:answer, answer}, %{mode: :single, current: q, answered: false} = state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    user_answer = String.downcase(String.trim(answer))
    correct_answer = String.downcase(String.trim(q["answer"]))
    is_correct = user_answer == correct_answer

    delta = if is_correct, do: 5, else: -3
    new_score = state.score + delta

    if state.caller, do: send(state.caller, {:feedback, is_correct, delta})
    Process.send_after(self(), :next_question, 2000)

    {:noreply, %{state |
      score: new_score,
      timer_ref: nil,
      answered: true
    }}
  end

  def handle_cast({:answer, _}, %{mode: :single, answered: true} = state) do
    IO.puts(" Ya respondiste esta pregunta. Espera la siguiente...")
    {:noreply, state}
  end

  def handle_cast({:answer, _}, %{mode: :single, current: nil} = state) do
    IO.puts(" No hay pregunta activa en este momento.")
    {:noreply, state}
  end

  # Manejo cuando un jugador se desconecta en medio de la pregunta
  @impl true
  def handle_cast({:player_disconnected, username}, %{mode: :multi, current: _q, players: players} = state) do
    if Map.has_key?(players, username) do
      player = players[username]
      if player.answered do
        {:noreply, state}
      else
        delta = -5
        updated_players = Map.update!(players, username, fn p -> %{p | score: p.score + delta, answered: true} end)
        resp = {username, :timeout, false, delta}
        new_responses = [resp | state.current_responses]

        all_answered = Enum.all?(updated_players, fn {_u, p} -> p.answered end)

        if all_answered do
          send(state.lobby_pid, {:question_summary, Enum.reverse(new_responses)})
          if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
          Process.send_after(self(), :next_question, 2000)
          {:noreply, %{state | players: updated_players, current_responses: new_responses}}
        else
          {:noreply, %{state | players: updated_players, current_responses: new_responses}}
        end
      end
    else
      {:noreply, state}
    end
  end
end
