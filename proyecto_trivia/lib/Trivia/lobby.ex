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

  def create_game(id, owner, category, num, time) do
    # OBTENER EL PID DEL CREATOR (HOST)
    creator_pid = self()

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
          # ⬇️ PASAR creator_pid AL MAPA
          case DynamicSupervisor.start_child(
                 Trivia.Server,
                 {__MODULE__, %{id: id, owner: owner, category: category, num: num, time: time, creator_pid: creator_pid}}
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
  def init(args) do
    case args do
      %{id: id, owner: owner, category: category, num: num, time: time, creator_pid: creator_pid} ->
        do_init(id, owner, category, num, time, creator_pid)

      %{id: id, owner: owner, category: category, num: num, time: time} ->
        IO.puts("⚠️ Advertencia: creator_pid no proporcionado, usando fallback")
        do_init(id, owner, category, num, time, self())

      _ ->
        IO.puts("❌ Argumentos inválidos para Lobby: #{inspect(args)}")
        {:stop, :invalid_args}
    end
  end

  defp do_init(id, owner, category, num, time, creator_pid) do
    questions = QuestionBank.get_random_questions(category, num)

    if questions == [] do
      IO.puts("⚠️ No hay preguntas disponibles para la categoría #{category} o no existe.")
      {:stop, :no_questions}
    else
      IO.puts("🎮 Lobby #{id} creado por #{owner}. Esperando jugadores...")

      timer_ref = Process.send_after(self(), :timeout_lobby, 180_000)

      # ⬇️ INICIALIZAR JUGADOR CON answered: false
      state = %{
        id: id,
        owner: owner,
        category: category,
        num: num,
        time: time,
        started: false,
        players: %{owner => %{pid: creator_pid, score: 0, answered: false}},
        monitors: %{owner => Process.monitor(creator_pid)},
        game_pid: nil,
        timer_ref: timer_ref
      }

      {:ok, state}
    end
  end

  def handle_call(:get_game_pid, _from, state) do
    {:reply, state.game_pid, state}
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
        monitor = Process.monitor(caller)
        new_players = Map.put(state.players, username, %{pid: caller, score: 0, answered: false})
        new_monitors = Map.put(state.monitors || %{}, username, monitor)
        new_state = %{state | players: new_players, monitors: new_monitors}
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
    # ⬇️ CANCELAR TIMER DE INACTIVIDAD
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

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
    {:noreply, %{state | started: true, game_pid: game_pid, timer_ref: nil}}
  end

  @impl true
  def handle_cast(:cancel, state) do
    # ⬇️ CANCELAR TIMER Y DETENER JUEGO SI EXISTE
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    if state.game_pid do
      Process.exit(state.game_pid, :normal)
    end

    send_message_to_all(state.players, "❌ El host canceló la partida.")
    IO.puts("❌ Lobby #{state.id} cancelado por el host.")

    # ⬇️ ASEGURAR QUE SE DETIENE COMPLETAMENTE
    {:stop, :normal, state}
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

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.monitors || %{}, fn {_user, mref} -> mref == ref end) do
      {username, _} ->
        IO.puts("⚠️ PID no válido o proceso muerto para #{username}")
        # eliminar monitor y jugador
        new_monitors = Map.drop(state.monitors || %{}, [username])
        new_players = Map.delete(state.players, username)
        # notificar a los demás
        send_message_to_all(new_players, "🚪 #{username} se desconectó.")
        # si el juego ya empezó, avisar al Game para forzar timeout de ese jugador
        if state.started && state.game_pid do
          GenServer.cast(state.game_pid, {:player_disconnected, username})
        end
        # si no quedan jugadores, cerrar lobby
        if map_size(new_players) == 0 do
          {:stop, :normal, %{state | players: new_players, monitors: new_monitors}}
        else
          {:noreply, %{state | players: new_players, monitors: new_monitors}}
        end

      nil ->
        {:noreply, state}
    end
  end

  # ===============================
  # Comunicación con Trivia.Game
  # ===============================
  @impl true
  def handle_info({:question, q}, state) do
    # ⬇️ ENVIAR MENSAJE ESTRUCTURADO, NO STRINGS
    send_message_to_all(state.players, {:question, q["question"], q["options"]})
    {:noreply, state}
  end

  def handle_info({:player_answered, username, reason, correct, delta}, state) do
    # reenviar a todos los clientes para notificación inmediata
    {:noreply, state}
  end

  def handle_info({:question_summary, summary}, state) do
    # summary es lista de {username, reason, correct, delta}
    send_message_to_all(state.players, {:question_summary, summary})
    {:noreply, state}
  end

  def handle_info({:timeout, _}, state) do
    send_message_to_all(state.players, {:timeout, nil})
    {:noreply, state}
  end

  def handle_info({:game_over, players}, state) do
    send_message_to_all(state.players, {:game_over, players})
    {:noreply, state}
  end

  # ===============================
  # Manejo de respuestas
  # ===============================

  @impl true
  def handle_cast({:answer, username, answer}, state) do
    if state.game_pid do
      # Reenviar la respuesta al juego
      GenServer.cast(state.game_pid, {:answer, username, answer})
    else
      IO.puts("⚠️ No hay partida activa para recibir respuestas")
    end
    {:noreply, state}
  end

  # ===============================
  # Utilidad de envío de mensajes
  # ===============================
  defp send_message_to_all(players, message) do
    Enum.each(players, fn {username, %{pid: pid}} ->
      if pid && Process.alive?(pid) do
        try do
          send(pid, message)
        rescue
          _ ->
            IO.puts("⚠️ No se pudo enviar mensaje a #{username}")
        end
      else
        IO.puts("⚠️ PID no válido o proceso muerto para #{username}")
      end
    end)
  end

end
