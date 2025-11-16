defmodule Trivia.Supervisor do
  @moduledoc """
    Supervisor principal de la aplicación Trivia.

    Este módulo define y gestiona el árbol de supervisión de todos los procesos
    críticos del sistema de trivia. Implementa la estrategia de supervisión
    `:one_for_one` donde cada proceso hijo es supervisado independientemente.

    ## Árbol de supervisión:
        Trivia.Supervisor
        ├── Trivia.SessionManager (GenServer)
        └── Trivia.Server (DynamicSupervisor)
    ## Características:
  - Inicia y supervisa el SessionManager para gestión de sesiones de usuarios
  - Inicia y supervisa el Server (DynamicSupervisor) para gestión de lobbies y partidas
  - Estrategia de reinicio: `:one_for_one` (cada proceso se reinicia individualmente)
  - Registrado con nombre local para fácil acceso

  ## Comportamiento en caso de fallos:
  - Si un proceso hijo falla, solo ese proceso será reiniciado
  - Los demás procesos continúan ejecutándose normalmente
  - Ideal para procesos independientes que no dependen entre sí
  """

  use Supervisor

  @doc """
  Callback de inicio para compatibilidad con aplicaciones OTP.

  Este callback es requerido por el comportamiento de aplicación OTP
  y delega en `start_link/1` para la inicialización real.

  ## Parámetros:
    - `type`: Tipo de inicio (normal o takeover)
    - `args`: Argumentos pasados a la aplicación

  ## Retorna:
    - `{:ok, pid}` en caso de éxito
    - `{:error, reason}` en caso de error
  """
  def start(_type, args) do
    start_link(args)
  end

  @doc """
  Inicia el supervisor principal con registro de nombre local.

  Crea el árbol de supervisión y registra el proceso con el nombre del módulo
  para permitir un acceso fácil desde otras partes de la aplicación.

  ## Parámetros:
    - `args`: Argumentos de inicialización (no utilizados actualmente)

  ## Retorna:
    - `{:ok, pid}` si el supervisor se inicia correctamente
    - `{:error, reason}` si hay un error en la inicialización

    - El supervisor se registra con el nombre `Trivia.Supervisor`
    - Esto permite acceder al supervisor directamente por nombre sin necesidad de conocer el PID
  """
  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Callback de inicialización del supervisor.

  Define la especificación de todos los procesos hijos que serán supervisados
  y la estrategia de supervisión a utilizar.

  ## Procesos hijos supervisados:

  1. `Trivia.SessionManager` - Gestor global de sesiones de usuarios
    - Tipo: `:worker`
    - Módulo: `Trivia.SessionManager`
    - Función de inicio: `start_link/1`

  2. `Trivia.Server` - DynamicSupervisor para lobbies y partidas
    - Tipo: `:supervisor` (si Trivia.Server es un supervisor)
    - Módulo: `Trivia.Server`
    - Función de inicio: `start_link/1`

  ## Estrategia de supervisión:
    - `:one_for_one`: Si un proceso hijo termina, solo ese proceso es reiniciado

  ## Retorna:
    - `{:ok, supervisor_spec}` con la especificación del supervisor
  """
  @impl true
  def init(:ok) do
    children = [
      # Proceso global de sesiones (GenServer, name global dentro del módulo)
      {Trivia.SessionManager, []},
      # DynamicSupervisor para lobbies / partidas
      {Trivia.Server, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
