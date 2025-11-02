defmodule Trivia.Server do
  @moduledoc """
  Servidor principal que gestiona y supervisa las partidas activas.
  Crea procesos Trivia.Game supervisados dinámicamente.
  """

  use DynamicSupervisor
  alias Trivia.Game

  # ===============================
  # Inicialización del supervisor
  # ===============================
  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    IO.puts("\n🧠 Servidor de partidas iniciado.\n")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # ===============================
  # API pública
  # ===============================

  # Iniciar una nueva partida
  def start_game(%{username: username, category: category, num: num, time: time}) do
    caller = self()
    spec = %{
      id: Game,
      start: {Game, :start_link, [%{username: username, category: category, num: num, time: time, caller: caller}]},
      restart: :temporary
    }

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        IO.puts("🎮 Nueva partida iniciada para #{username} (PID: #{inspect(pid)})")
        {:ok, pid}

      {:error, reason} ->
        IO.puts("❌ No se pudo iniciar la partida: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Consultar número de partidas activas
  def list_games do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {id, pid, _type, _modules} ->
      %{id: id, pid: pid}
    end)
  end

  # Finalizar una partida
  def stop_game(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end
end
