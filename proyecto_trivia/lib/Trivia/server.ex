defmodule Trivia.Server do
  @moduledoc """
  Servidor principal que gestiona y supervisa las partidas activas.
  - Supervisa partidas de un jugador (Trivia.Game)
  - Supervisa partidas multijugador (Trivia.Lobby)
  - Permite funcionamiento distribuido entre nodos conectados (usa nombres globales)
  """

  use DynamicSupervisor
  alias Trivia.{Game, Lobby}

  # ===============================
  # Inicialización del supervisor
  # ===============================

  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    IO.puts("\n🧩 Servidor de partidas iniciado (modo distribuido habilitado).\n")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # ===============================
  # API pública
  # ===============================

  # 🔹 Iniciar una nueva partida individual
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
        IO.puts("🎯 Partida individual iniciada para #{username}")
        IO.puts("📝 Configuración: #{num} preguntas de #{category}, #{time}s por pregunta")
        {:ok, pid}

      {:error, reason} ->
        IO.puts("❌ No se pudo iniciar la partida: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # 🔹 Iniciar una partida multijugador (Lobby)
  def start_game(%{id: id, owner: owner, category: category, num: num, time: time}) do
    spec = %{
      id: {:lobby, id},
      start:
        {Lobby, :start_link,
         [%{id: id, owner: owner, category: category, num: num, time: time}]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        IO.puts("🎮 Partida multijugador #{id} creada por #{owner} (PID: #{inspect(pid)})")
        {:ok, pid}

      {:error, reason} ->
        IO.puts("❌ Error al crear partida: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # 🔹 Listar partidas activas globalmente (entre nodos conectados)
  def list_games do
    :global.registered_names()
    |> Enum.filter(fn
      {:lobby, _id} -> true
      _ -> false
    end)
    |> Enum.map(fn {:lobby, id} -> id end)
  end

  # 🔹 Finalizar una partida
  def stop_game(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
