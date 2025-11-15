defmodule Trivia.Supervisor do
  use Supervisor

  @impl true
  # Callback requerido por :application (start/2)
  def start(_type, args) do
    start_link(args)
  end

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      # proceso global de sesiones (GenServer, name global dentro del módulo)
      {Trivia.SessionManager, []},
      # DynamicSupervisor para lobbies / partidas
      {Trivia.Server, []}
      # puedes añadir Registry u otros procesos aquí
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
