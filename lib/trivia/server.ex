defmodule Trivia.Server do
  @moduledoc """
  DynamicSupervisor que gestiona las partidas activas de la aplicación.

  Propósito
  - Supervisar partidas singleplayer (cada una es un `Trivia.Game`).
  - Supervisar lobbies/multijugador (cada lobby es un `Trivia.Lobby`).
  - Mantener la política de reinicio adecuada: partidas y lobbies se arrancan
    con `restart: :temporary` para que no sean recreadas automáticamente cuando
    terminan de forma normal.

  Diseño y notas de implementación
  - Este módulo implementa la API pública usada por la CLI: `start_game/1`,
    `list_games/0` y `stop_game/1`.
  - Para entornos distribuidos se aprovecha `:global.registered_names()` para
    enumerar lobbies registrados globalmente.
  - `start_link/1` reutiliza una instancia ya existente si el proceso ya fue
    arrancado (evita fallos por arranque doble durante desarrollo).
  """

  use DynamicSupervisor
  alias Trivia.{Game, Lobby}

  # ===============================
  # Inicialización del supervisor
  # ===============================

  @doc """
  Arranca el DynamicSupervisor del servidor de partidas.

  Reutiliza el proceso si ya existe (útil durante desarrollo/recargas).
  """
  def start_link(_args) do
    case GenServer.whereis(__MODULE__) do
      nil ->
        DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  @impl true
  #inicialización del DynamicSupervisor
  def init(:ok) do
    IO.puts("\n🧩 Servidor de partidas iniciado (modo distribuido habilitado).\n")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # ===============================
  # API pública
  # ===============================

  @doc """
  Inicia una partida singleplayer gestionada por el DynamicSupervisor.

  Parámetros esperados (map):
    %{
      username: username,
      category: category,
      num: num_questions,
      time: seconds_per_question,
      mode: :single
    }

  Retorna `{:ok, pid}` o `{:error, reason}`.
  """
  def start_game(%{
        username: username,
        category: category,
        num: num,
        time: time,
        mode: :single
      }) do
    caller = self()

    spec = %{
      id: make_ref(),
      start:
        {Game, :start_link,
         [
           %{
             username: username,
             category: category,
             num: num,
             time: time,
             caller: caller,
             mode: :single
           }
         ]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        IO.puts(" Partida individual iniciada para #{username}")
        {:ok, pid}

      {:error, reason} ->
        IO.puts(" No se pudo iniciar la partida: #{inspect(reason)}")
        {:error, reason}
    end
  end


  #Inicia una partida multijugador (lobby).

  #Parámetros esperados (map):
  #  %{
  #    id: id,
  #    owner: owner_username,
  #   category: category,
  #    num: num_questions,
  #    time: seconds_per_question
  #  }

  #Retorna `{:ok, pid}` o `{:error, reason}`.

  def start_game(%{id: id, owner: owner, category: category, num: num, time: time}) do
    creator_pid = self()

    spec = %{
      id: {:lobby, id},
      start:
        {Lobby, :start_link,
         [%{
           id: id,
           owner: owner,
           category: category,
           num: num,
           time: time,
           creator_pid: creator_pid
         }]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        IO.puts(" Partida multijugador #{id} creada por #{owner}")
        {:ok, pid}

      {:error, reason} ->
        IO.puts(" Error al crear partida: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Devuelve la lista de IDs de lobbies registrados globalmente.

  Nota: filtra nombres globales que tengan la forma `{:lobby, id}`.
  """
  def list_games do
    :global.registered_names()
    |> Enum.filter(fn
      {:lobby, _id} -> true
      _ -> false
    end)
    |> Enum.map(fn {:lobby, id} -> id end)
  end

  @doc """
  Finaliza una partida supervisada dado su pid (termina el child).
  """
  def stop_game(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
