defmodule Trivia.SessionManager do
  @moduledoc """
  Gestiona las sesiones de los usuarios conectados al servidor.
  Cada sesión se asocia al nombre de usuario y su PID de CLI.

   Modo distribuido (global):
  - Se registra globalmente con {:global, Trivia.SessionManager}.
  - Los clientes remotos pueden autenticarse, desconectarse o consultar usuarios en línea.
  """

  use GenServer
  alias Trivia.UserManager

  # ===============================
  # API pública
  # ===============================

  def start_link(_args) do
    # Si ya existe globalmente, devolver {:ok, pid_existente} en lugar de error
    case :global.whereis_name(__MODULE__) do
      :undefined ->
        GenServer.start_link(__MODULE__, %{}, name: {:global, __MODULE__})
      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  #  Conectar usuario (ya registrado)
  def connect(username, password, caller) do
    GenServer.call({:global, __MODULE__}, {:connect, username, password, caller})
  end

  #  Desconectar usuario
  def disconnect(username) do
    GenServer.call({:global, __MODULE__}, {:disconnect, username})
  end

  #  Listar usuarios en línea
  def list_online do
    GenServer.call({:global, __MODULE__}, :list_online)
  end

  #  Verificar si un usuario está conectado
  def online?(username) do
    GenServer.call({:global, __MODULE__}, {:check_online, username})
  end

  # ===============================
  # Callbacks internos
  # ===============================

  @impl true
  def init(_args) do
    IO.puts(" Servidor global de sesiones iniciado.")
    {:ok, %{}}
  end

  # LOGIN
  @impl true
  def handle_call({:connect, username, password, caller}, _from, state) do
    case UserManager.authenticate(username, password) do
      {:ok, _user} ->
        IO.puts(" #{username} conectado desde #{inspect(node(caller))}")
        new_state = Map.put(state, username, %{pid: caller, status: :online})
        {:reply, {:ok, "Conectado exitosamente"}, new_state}

      {:error, reason} ->
        IO.puts(" Falló el inicio de sesión para #{username}: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end


  #  Desconectar usuario
  @impl true
  def handle_call({:disconnect, username}, _from, state) do
    if Map.has_key?(state, username) do
      IO.puts(" #{username} se desconectó.")
      {:reply, :ok, Map.delete(state, username)}
    else
      {:reply, {:error, "Usuario no conectado"}, state}
    end
  end

  # Listar usuarios en línea
  @impl true
  def handle_call(:list_online, _from, state) do
    users =
      state
      |> Enum.map(fn {u, %{pid: pid}} ->
        "#{u} (#{node(pid)})"
      end)

    {:reply, users, state}
  end

  # Verificar conexión
  @impl true
  def handle_call({:check_online, username}, _from, state) do
    {:reply, Map.has_key?(state, username), state}
  end
end
