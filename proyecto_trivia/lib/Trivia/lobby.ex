defmodule Trivia.Lobby do
  use GenServer
  alias Trivia.{Game, SessionManager, QuestionBank, UserManager, History}

  @max_players 4

  # ===============================
  # Creación y registro global
  # ===============================
  def start_link(%{id: id} = args) do
    GenServer.start_link(__MODULE__, args, name: {:global, {:lobby, id}})
  end

  # Crear partida (con validaciones)
  def create_game(id, owner, category, num, time) do
    cond do
      not SessionManager.online?(owner) ->
        {:error, :invalid_user}

      not Enum.member?(QuestionBank.load_categories(), category) ->
        {:error, :invalid_category}

      true ->
        questions = QuestionBank.get_random_questions(category, num)

        if questions == [] do
          {:error, :no_questions}
        else
          case DynamicSupervisor.start_child(
                 Trivia.Server,
                 {__MODULE__, %{id: id, owner: owner, category: category, num: num, time: time}}
               ) do
            {:ok, pid} ->
              {:ok, pid}

            {:error, reason} ->
              {:error, reason}

            other ->
              {:error, other}
          end
        end
    end
  end

  # Unirse a partida existente
  def join_game(id, username, caller) do
    case :global.whereis_name({:lobby, id}) do
      :undefined ->
        {:error, :not_found}

      pid ->
        if SessionManager.online?(username) do
          GenServer.call(pid, {:join, username, caller})
        else
          {:error, :invalid_user}
        end
    end
  end

  def leave_game(id, username) do
    case :global.whereis_name({:lobby, id}) do
      :undefined -> {:error, :not_found}
      pid -> GenServer.cast(pid, {:leave, username})
    end
  end

  def start_game(id), do: cast(id, :start)
  def cancel_game(id), do: cast(id, :cancel)

  defp cast(id, msg) do
    case :global.whereis_name({:lobby, id}) do
      :undefined -> {:error, :not_found}
      pid -> GenServer.cast(pid, msg)
    end
  end

  # ===============================
  # Callbacks principales
  # ===============================
  @impl true
  def init(%{id: id, owner: owner, category: category, num: num, time: time}) do
    questions = QuestionBank.get_random_questions(category, num)

    if questions == [] do
      IO.puts("⚠️ No hay preguntas disponibles para la categoría #{category} o no existe.")
      {:stop, :no_questions}
    else
      IO.puts("🎮 Lobby #{id} creado por #{owner}. Esperando jugadores...")

      # Crear estado inicial
      state = %{
        id: id,
        owner: owner,
        category: category,
        num: num,
        time: time,
        started: false,
        players: %{owner => %{pid: nil, score: 0}},
        game_pid: nil
      }

      # Programar cierre por inactividad (3 min)
      Process.send_after(self(), :timeout_lobby, 180_000)

      {:ok, state}
    end
  end

  @impl true
  def handle_info(:timeout_lobby, state) do
    unless state.started do
      IO.puts("⏰ Lobby #{state.id} cerrado por inactividad.")
      send_message_to_all(state.players, "⏰ El lobby fue cerrado por inactividad.")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  # ===============================
  # Jugadores
  # ===============================
  @impl true
  def handle_call({:join, username, caller}, _from, state) do
    cond do
      state.started ->
        {:reply, {:error, :started}, state}

      map_size(state.players) >= @max_players ->
        {:reply, {:error, :full}, state}

      Map.has_key?(state.players, username) ->
        {:reply, {:error, :already}, state}

      true ->
        send_message_to_all(state.players, "👋 #{username} se unió a la partida.")
        IO.puts("✅ #{username} se unió al lobby #{state.id}")
        new_state = %{state | players: Map.put(state.players, username, %{pid: caller, score: 0})}
        {:reply, {:ok, "Unido correctamente"}, new_state}
    end
  end

  @impl true
  def handle_cast({:leave, username}, state) do
    if Map.has_key?(state.players, username) do
      send_message_to_all(state.players, "🚪 #{username} abandonó la partida.")
      IO.puts("👋 #{username} salió del lobby #{state.id}")
      new_state = %{state | players: Map.delete(state.players, username)}
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # ===============================
  # Control de partida
  # ===============================
  @impl true
  def handle_cast(:start, state) do
    {:ok, game_pid} =
      Game.start_link(%{
        mode: :multi,
        lobby_pid: self(),
        players: state.players,
        category: state.category,
        num: state.num,
        time: state.time
      })

    send_message_to_all(state.players, "🚀 ¡Partida iniciada!")
    IO.puts("🕹️ Partida del lobby #{state.id} iniciada.")
    {:noreply, %{state | started: true, game_pid: game_pid}}
  end

  @impl true
  def handle_cast(:cancel, state) do
    send_message_to_all(state.players, "❌ El host canceló la partida.")
    IO.puts("❌ Lobby #{state.id} cancelado por el host.")
    {:stop, :normal, state}
  end

  # ===============================
  # Comunicación con Trivia.Game
  # ===============================
  @impl true
  def handle_info({:question, q}, state) do
    send_message_to_all(state.players, "\n❓ #{q["question"]}")
    Enum.each(q["options"], fn {k, v} -> send_message_to_all(state.players, "#{k}. #{v}") end)
    {:noreply, state}
  end

  def handle_info({:player_answered, username, correct, delta}, state) do
    send_message_to_all(
      state.players,
      "#{username} respondió #{if correct, do: "✅ Correcto", else: "❌ Incorrecto"} (#{delta} pts)"
    )
    {:noreply, state}
  end

  def handle_info({:timeout, _}, state) do
    send_message_to_all(state.players, "⏰ Tiempo agotado! Siguiente pregunta...")
    {:noreply, state}
  end

  def handle_info({:game_over, players}, state) do
    send_message_to_all(players, "🏁 ¡Fin de la partida!")
    Enum.each(players, fn {u, %{score: s}} ->
      UserManager.update_score(u, s)
      History.save_result(u, state.category, s)
    end)
    {:stop, :normal, state}
  end

  # ===============================
  # Utilidad de envío de mensajes
  # ===============================
  defp send_message_to_all(players, msg) do
    Enum.each(players, fn {_u, %{pid: pid}} ->
      if pid, do: send(pid, {:game_message, msg})
    end)
  end
end
