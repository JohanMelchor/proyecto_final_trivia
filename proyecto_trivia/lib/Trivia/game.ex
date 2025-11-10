defmodule Trivia.Game do
  use GenServer
  alias Trivia.{UserManager, QuestionBank, History}

  # ===============================
  # API pública
  # ===============================

  def start_link(args) when is_map(args) do
    GenServer.start_link(__MODULE__, args)
  end

  # Unificada: el CLI puede pasar 2 o 3 argumentos según el modo
  def answer(pid, answer), do: GenServer.cast(pid, {:answer, answer})
  def answer(lobby_id, username, answer) do
    case :global.whereis_name({:lobby, lobby_id}) do
      :undefined ->
        {:error, "Lobby no encontrado"}
      pid ->
        GenServer.cast(pid, {:answer, username, answer})
    end
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
      # ⬇️ INICIALIZAR JUGADORES CON ESTADO answered: false
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
        timer_ref: nil
      }

      Process.send_after(self(), :next_question, 500)
      {:ok, state}
    end
  end

  @impl true
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
      time: time,
      timer_ref: nil,
      answered: false,
      question_number: 0
    }

    # Iniciar inmediatamente con la primera pregunta
    Process.send_after(self(), :next_question, 100)
    {:ok, state}
  end

  # ===============================
  # MANEJO DE PREGUNTAS
  # ===============================

  # --- MULTIJUGADOR ---
  @impl true
  def handle_info(:next_question, %{mode: :multi, questions: []} = state) do
    send(state.lobby_pid, {:game_over, state.players})
    {:stop, :normal, state}
  end

  def handle_info(:next_question, %{mode: :multi, questions: [q | rest]} = state) do
    # ⬇️ RESETEAR ESTADO DE RESPUESTAS PARA NUEVA PREGUNTA
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
      players: reset_players
    }}
  end

  def handle_info(:timeout, %{mode: :multi} = state) do
    send(state.lobby_pid, {:timeout, state.current})
    Process.send_after(self(), :next_question, 2000)
    {:noreply, %{state | current: nil, timer_ref: nil}}
  end

  # --- SINGLEPLAYER ---
  @impl true
  def handle_info(:next_question, %{mode: :single, questions: []} = state) do
    IO.puts("🏁 Fin del juego - Puntaje final: #{state.score}")
    UserManager.update_score(state.username, state.score)
    History.save_result(state.username, state.category, state.score)

    if state.caller do
      send(state.caller, {:game_over, state.score})
    end

    {:stop, :normal, state}
  end

  def handle_info(:next_question, %{mode: :single, questions: [q | rest]} = state) do
    # Cancelar timer anterior si existe
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # Enviar pregunta al jugador
    question_number = state.question_number + 1
    IO.puts("\n=== Pregunta #{question_number} ===")

    if state.caller do
      send(state.caller, {:question, q["question"], q["options"]})
    end

    # Configurar nuevo temporizador
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
    IO.puts("⏰ Tiempo agotado para: #{q["question"]}")
    IO.puts("✅ Respuesta correcta: #{q["answer"]}")

    # Penalización por tiempo agotado
    new_score = state.score - 1
    IO.puts("📉 Penalización: -1 puntos | Puntaje actual: #{new_score}")

    if state.caller do
      send(state.caller, {:timeout_notice, q["answer"]})
    end

    # Programar siguiente pregunta después de breve pausa
    Process.send_after(self(), :next_question, 2000)

    {:noreply, %{state |
      score: new_score,
      current: nil,
      timer_ref: nil,
      answered: true
    }}
  end

  def handle_info(:timeout, %{mode: :single, answered: true} = state) do
    # Ignorar timeout si ya se respondió
    {:noreply, state}
  end

  # ===============================
  # RESPUESTAS
  # ===============================

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
          Map.update!(state.players, username, fn p ->
            %{p | score: p.score + delta, answered: true}
          end)

        send(state.lobby_pid, {:player_answered, username, correct, delta})

        # Verificar si todos respondieron
        all_answered = Enum.all?(updated_players, fn {_, p} -> p.answered end)

        if all_answered && state.timer_ref do
          Process.cancel_timer(state.timer_ref)
          Process.send_after(self(), :next_question, 2000)
        end

        {:noreply, %{state | players: updated_players}}
      end
    else
      {:noreply, state}
    end
  end

  # --- SINGLEPLAYER ---
  @impl true
  def handle_cast({:answer, answer}, %{mode: :single, current: q, answered: false} = state) do
    # Cancelar timer inmediatamente
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # Verificar respuesta
    user_answer = String.downcase(String.trim(answer))
    correct_answer = String.downcase(String.trim(q["answer"]))
    is_correct = user_answer == correct_answer

    # Calcular puntaje
    delta = if is_correct, do: 5, else: -3
    new_score = state.score + delta

    # Feedback inmediato
    IO.puts(if is_correct, do: "✅ Correcto! +#{delta} puntos", else: "❌ Incorrecto! #{delta} puntos")
    IO.puts("📊 Puntaje actual: #{new_score}")

    if not is_correct do
      IO.puts("💡 La respuesta correcta era: #{q["answer"]}")
    end

    # Enviar feedback al CLI
    if state.caller do
      send(state.caller, {:feedback, is_correct, delta})
    end

    # Programar siguiente pregunta después de breve pausa
    Process.send_after(self(), :next_question, 2000)

    {:noreply, %{state |
      score: new_score,
      timer_ref: nil,
      answered: true
    }}
  end

  def handle_cast({:answer, _}, %{mode: :single, answered: true} = state) do
    IO.puts("⚠️ Ya respondiste esta pregunta. Espera la siguiente...")
    {:noreply, state}
  end

  def handle_cast({:answer, _}, %{mode: :single, current: nil} = state) do
    IO.puts("⚠️ No hay pregunta activa en este momento.")
    {:noreply, state}
  end
end
