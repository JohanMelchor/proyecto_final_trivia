defmodule Trivia.Lobby do
  @moduledoc """
  Lobby (GenServer) que gestiona la sala previa a una partida multijugador.

  Responsabilidades:
  - Crear y registrar lobbies globalmente.
  - Mantener la lista de jugadores (PID, puntaje, estado `answered`).
  - Monitorear PIDs de clientes para detectar desconexiones y limpiarlas.
  - Iniciar/Cancelar la partida (arrancar el `Trivia.Game` correspondiente).
  - Reenviar mensajes estructurados a los clientes (preguntas, resúmenes, cancelación).
  - Cerrar el lobby por inactividad o cuando la partida termina.

  Diseño de mensajes:
  - Mensajes internos / entre procesos:
    * {:question, q_map}                -> enviado desde Game al Lobby
    * {:question_summary, summary}      -> resumen de respuestas enviado desde Game
    * {:game_over, players_map}         -> fin de la partida (Game -> Lobby)
    * :game_finished                     -> orden al Lobby para finalizar
    * {:player_disconnected, username}  -> Lobby -> Game para forzar timeout/penalización
  - Mensajes hacia clientes (CLI) se envían como tuplas estructuradas:
    * {:game_message, string}
    * {:question, question_text, options_map}
    * {:question_summary, summary}
    * {:timeout, _}
    * {:game_over, players_map}
    * {:lobby_canceled, id}
  """

  use GenServer

  # aliases mínimos usados por este módulo
  alias Trivia.{Game, SessionManager, QuestionBank}

  @max_players 4

  # -------------------------------------------------------------------
  # API pública del Lobby (funciones invocadas desde CLI / Server)
  # -------------------------------------------------------------------

  @doc """
  Arranca el GenServer del lobby y lo registra globalmente como {:lobby, id}.
  args esperados: %{id:, owner:, category:, num:, time:, creator_pid: optional}
  """
  def start_link(%{id: id} = args) do
    GenServer.start_link(__MODULE__, args, name: {:global, {:lobby, id}})
  end

  @doc """
  Crea (arranca) un lobby bajo el DynamicSupervisor `Trivia.Server`.

  - Valida que el owner esté online y la categoría exista.
  - Usa un child_spec con restart: :temporary para evitar recreaciones al terminar.
  - Devuelve {:ok, pid} | {:error, reason}.
  """
  def create_game(id, owner, category, num, time) do
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
          spec = %{
            id: {:lobby, id},
            start:
              {__MODULE__, :start_link,
               [
                 %{
                   id: id,
                   owner: owner,
                   category: category,
                   num: num,
                   time: time,
                   creator_pid: creator_pid
                 }
               ]},
            restart: :temporary
          }

          case DynamicSupervisor.start_child(Trivia.Server, spec) do
            {:ok, pid} -> {:ok, pid}
            {:error, reason} -> {:error, reason}
            other -> {:error, other}
          end
        end
    end
  end

  @doc """
  Intenta unir `username` al lobby `id`. `caller` es el pid del cliente que se une.
  Devuelve {:ok, msg} o {:error, reason} (ej: :not_found, :full, :started, :already).
  """
  def join_game(id, username, caller) do
    case :global.whereis_name({:lobby, id}) do
      :undefined -> {:error, :not_found}
      pid ->
        if SessionManager.online?(username) do
          GenServer.call(pid, {:join, username, caller})
        else
          {:error, :invalid_user}
        end
    end
  end

  @doc "Ordena al lobby que elimine a username (async)."
  def leave_game(id, username) do
    case :global.whereis_name({:lobby, id}) do
      :undefined -> {:error, :not_found}
      pid -> GenServer.cast(pid, {:leave, username})
    end
  end

  @doc "Instruye al lobby para iniciar la partida (host)."
  def start_game(id), do: cast(id, :start)

  @doc "Instruye al lobby para cancelar la partida (host)."
  def cancel_game(id), do: cast(id, :cancel)

  defp cast(id, msg) do
    case :global.whereis_name({:lobby, id}) do
      :undefined -> {:error, :not_found}
      pid -> GenServer.cast(pid, msg)
    end
  end

  # -------------------------------------------------------------------
  # Callbacks GenServer
  # -------------------------------------------------------------------

  @impl true
  def init(args) do
    case args do
      %{id: id, owner: owner, category: category, num: num, time: time, creator_pid: creator_pid} ->
        do_init(id, owner, category, num, time, creator_pid)

      %{id: id, owner: owner, category: category, num: num, time: time} ->
        IO.puts(" Advertencia: creator_pid no proporcionado, usando fallback")
        do_init(id, owner, category, num, time, self())

      _ ->
        IO.puts(" Argumentos inválidos para Lobby: #{inspect(args)}")
        {:stop, :invalid_args}
    end
  end

  defp do_init(id, owner, category, num, time, creator_pid) do
    questions = QuestionBank.get_random_questions(category, num)

    if questions == [] do
      IO.puts(" No hay preguntas disponibles para la categoría #{category} o no existe.")
      {:stop, :no_questions}
    else
      IO.puts(" Lobby #{id} creado por #{owner}. Esperando jugadores...")

      # Cerrar lobby por inactividad si nunca se inicia (3 minutos)
      timer_ref = Process.send_after(self(), :timeout_lobby, 180_000)

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

  @impl true
  def handle_call(:get_game_pid, _from, state) do
    {:reply, state.game_pid, state}
  end

  # -------------------------
  # Gestión de jugadores
  # -------------------------
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
        send_message_to_all(state.players, {:game_message, "#{username} se unió a la partida."})
        IO.puts(" #{username} se unió al lobby #{state.id}")

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
      send_message_to_all(state.players, {:game_message, "#{username} abandonó la partida."})
      IO.puts(" #{username} salió del lobby #{state.id}")
      new_state = %{state | players: Map.delete(state.players, username)}
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:answer, username, answer}, state) do
    if state.game_pid do
      GenServer.cast(state.game_pid, {:answer, username, answer})
    else
      IO.puts(" No hay partida activa para recibir respuestas")
    end

    {:noreply, state}
  end

  # -------------------------
  # Control de partida
  # -------------------------
  @impl true
  def handle_cast(:start, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    {:ok, game_pid} =
      Game.start_link(%{
        mode: :multi,
        lobby_pid: self(),
        players: state.players,
        category: state.category,
        num: state.num,
        time: state.time
      })

    send_message_to_all(state.players, {:game_message, "¡Partida iniciada!"})
    IO.puts(" Partida del lobby #{state.id} iniciada.")
    {:noreply, %{state | started: true, game_pid: game_pid, timer_ref: nil}}
  end

  @impl true
  def handle_cast(:cancel, state) do
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)
    if state.game_pid, do: Process.exit(state.game_pid, :normal)

    # Notificar solo a invitados para que vuelvan al menú (host ya retorna por su flujo)
    other_players = Map.drop(state.players || %{}, [state.owner])
    send_message_to_all(other_players, {:lobby_canceled, state.id})

    IO.puts(" Lobby #{state.id} cancelado por el host.")
    {:stop, :normal, state}
  end

  # -------------------------
  # Mensajes entrantes (desde Game / timers / monitors)
  # -------------------------
  @impl true
  def handle_info({:question, q}, state) do
    # enviar mensaje estructurado a clientes
    send_message_to_all(state.players, {:question, q["question"], q["options"]})
    {:noreply, state}
  end

  def handle_info({:question_summary, summary}, state) do
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

  def handle_info(:game_finished, state) do
    IO.puts(" Lobby #{state.id} finalizado. Cerrando...")
    {:stop, :normal, state}
  end

  # Monitor de procesos cliente: detectar desconexiones y limpiar estado
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Enum.find(state.monitors || %{}, fn {_user, mref} -> mref == ref end) do
      {username, _} ->
        IO.puts(" PID no válido o proceso muerto para #{username}")
        new_monitors = Map.drop(state.monitors || %{}, [username])
        new_players = Map.delete(state.players, username)

        send_message_to_all(new_players, {:game_message, "#{username} se desconectó."})

        if state.started && state.game_pid do
          GenServer.cast(state.game_pid, {:player_disconnected, username})
        end

        if map_size(new_players) == 0 do
          {:stop, :normal, %{state | players: new_players, monitors: new_monitors}}
        else
          {:noreply, %{state | players: new_players, monitors: new_monitors}}
        end

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(:timeout_lobby, state) do
    unless state.started do
      IO.puts(" Lobby #{state.id} cerrado por inactividad.")
      send_message_to_all(state.players, {:game_message, "El lobby fue cerrado por inactividad."})
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  # -------------------------
  # Terminate
  # -------------------------
  @impl true
  def terminate(_reason, state) do
    IO.puts(" Limpiando recursos del Lobby #{state.id}...")
    :ok
  end

  # -------------------------------------------------------------------
  # Utilidades internas
  # -------------------------------------------------------------------

  @doc false
  defp send_message_to_all(players, message) do
    Enum.each(players, fn {username, %{pid: pid}} ->
      if pid && Process.alive?(pid) do
        try do
          send(pid, message)
        rescue
          _ -> IO.puts(" No se pudo enviar mensaje a #{username}")
        end
      else
        IO.puts(" PID no válido o proceso muerto para #{username}")
      end
    end)
  end
end
