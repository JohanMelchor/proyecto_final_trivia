defmodule Trivia.SessionManager do
  @moduledoc """
  Gestiona las sesiones de los usuarios conectados al servidor.
  Cada sesión se asocia al nombre de usuario y su PID de CLI.

  ✅ Adaptado a modo distribuido:
  - Se registra globalmente con {:global, Trivia.SessionManager}.
  - Permite que clientes en otros nodos conectados puedan autenticarse,
    desconectarse o consultar usuarios en línea mediante llamadas globales.
  """

  use GenServer
  alias Trivia.UserManager

  # ===============================
  # API pública
  # ===============================

  # 🚀 Inicia el servidor global de sesiones
  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: {:global, __MODULE__})
  end

  # 🔹 Conectar o registrar usuario (llamada global)
  def connect(username, password, caller) do
    GenServer.call({:global, __MODULE__}, {:connect, username, password, caller})
  end

  # 🔹 Desconectar usuario
  def disconnect(username) do
    GenServer.call({:global, __MODULE__}, {:disconnect, username})
  end

  # 🔹 Obtener usuarios en línea
  def list_online do
    GenServer.call({:global, __MODULE__}, :list_online)
  end

  # 🔹 Verificar si un usuario está conectado
  def online?(username) do
    GenServer.call({:global, __MODULE__}, {:check_online, username})
  end

  # ===============================
  # Callbacks internos
  # ===============================

  @impl true
  def init(_args) do
    IO.puts("🌐 Servidor global de sesiones iniciado.")
    {:ok, %{}}
  end

  @impl true
  def handle_call({:connect, username, password, caller}, _from, state) do
    case UserManager.register_or_login(username, password) do
      {:ok, _user} ->
        IO.puts("✅ #{username} conectado desde #{inspect(node(caller))}")
        new_state = Map.put(state, username, %{pid: caller, status: :online})
        {:reply, {:ok, "Conectado exitosamente"}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:disconnect, username}, _from, state) do
    if Map.has_key?(state, username) do
      IO.puts("👋 #{username} se desconectó.")
      {:reply, :ok, Map.delete(state, username)}
    else
      {:reply, {:error, "Usuario no conectado"}, state}
    end
  end

  @impl true
  def handle_call(:list_online, _from, state) do
    users =
      state
      |> Enum.map(fn {u, %{pid: pid}} ->
        "#{u} (#{node(pid)})"
      end)

    {:reply, users, state}
  end

  @impl true
  def handle_call({:check_online, username}, _from, state) do
    {:reply, Map.has_key?(state, username), state}
  end
end
