defmodule Trivia.SessionManager do
  @moduledoc """
  Módulo responsable de gestionar las sesiones de usuarios conectados al servidor de trivia.

  Este GenServer mantiene un registro global de todos los usuarios en línea, asociando
  cada nombre de usuario con su PID y estado de conexión.

  ## Características principales:
  - Registro global distribuido usando `:global` para acceso desde múltiples nodos
  - Autenticación de usuarios contra el UserManager
  - Gestión de conexiones y desconexiones
  - Consulta de usuarios en línea
  - Verificación de estado de conexión

  ## Modo distribuido:
  - Se registra globalmente con `{:global, Trivia.SessionManager}`
  - Los clientes remotos pueden autenticarse, desconectarse o consultar usuarios en línea
  - Soporta operaciones desde múltiples nodos en un cluster Erlang/Elixir
  """

  use GenServer
  alias Trivia.UserManager

  # ===============================
  # API pública
  # ===============================

  @doc """
  Inicia el SessionManager con registro global.

  Si ya existe una instancia global registrada, retorna el PID existente.
  De lo contrario, crea una nueva instancia.

  ## Parámetros:
    - `args`: Argumentos de inicialización (no utilizados actualmente)

  ## Retorna:
    - `{:ok, pid}` en caso de éxito
    - `{:error, reason}` en caso de error al iniciar el GenServer
  """
  def start_link(_args) do
    case :global.whereis_name(__MODULE__) do
      :undefined ->
        GenServer.start_link(__MODULE__, %{}, name: {:global, __MODULE__})
      pid when is_pid(pid) ->
        {:ok, pid}
    end
  end

  @doc """
  Autentica y conecta un usuario al sistema.

  Verifica las credenciales del usuario contra el UserManager y, si son válidas,
  registra al usuario como conectado en el SessionManager.

  ## Parámetros:
    - `username`: Nombre de usuario a autenticar
    - `password`: Contraseña del usuario
    - `caller`: PID del proceso que solicita la conexión

  ## Retorna:
    - `{:ok, "Conectado exitosamente"}` si la autenticación es exitosa
    - `{:error, reason}` si la autenticación falla o el usuario ya está conectado
  """
  def connect(username, password, caller) do
    GenServer.call({:global, __MODULE__}, {:connect, username, password, caller})
  end

  @doc """
  Desconecta a un usuario del sistema.

  Elimina al usuario del registro de sesiones activas.

  ## Parámetros:
    - `username`: Nombre de usuario a desconectar

  ## Retorna:
    - `:ok` si la desconexión fue exitosa
    - `{:error, "Usuario no conectado"}` si el usuario no estaba conectado
  """
  def disconnect(username) do
    GenServer.call({:global, __MODULE__}, {:disconnect, username})
  end

  @doc """
  Obtiene la lista de todos los usuarios actualmente en línea.

  ## Retorna:
    - Lista de strings con el formato "usuario (nodo)" para cada usuario conectado
  """
  def list_online do
    GenServer.call({:global, __MODULE__}, :list_online)
  end

  @doc """
  Verifica si un usuario específico está conectado al sistema.

  ## Parámetros:
    - `username`: Nombre de usuario a verificar

  ## Retorna:
    - `true` si el usuario está conectado
    - `false` si el usuario no está conectado
  """
  def online?(username) do
    GenServer.call({:global, __MODULE__}, {:check_online, username})
  end

  # ===============================
  # Callbacks internos del GenServer
  # ===============================

  @doc """
  Inicializa el estado del SessionManager.
  """
  @impl true
  def init(_args) do
    IO.puts(" Servidor global de sesiones iniciado.")
    {:ok, %{}}
  end

  @doc """
  Maneja la solicitud de conexión de un usuario.

  Realiza la autenticación a través del UserManager y, si es exitosa,
  agrega al usuario al estado de sesiones activas.
  """
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

  #Maneja la solicitud de desconexión de un usuario.
  #Elimina al usuario del estado de sesiones activas si existe.
  @impl true
  def handle_call({:disconnect, username}, _from, state) do
    if Map.has_key?(state, username) do
      IO.puts(" #{username} se desconectó.")
      {:reply, :ok, Map.delete(state, username)}
    else
      {:reply, {:error, "Usuario no conectado"}, state}
    end
  end

  #Maneja la solicitud de listar usuarios en línea.
  #Formatea la información de usuarios conectados para su presentación.
  @impl true
  def handle_call(:list_online, _from, state) do
    users =
      state
      |> Enum.map(fn {u, %{pid: pid}} ->
        "#{u} (#{node(pid)})"
      end)

    {:reply, users, state}
  end


  #Maneja la verificación de estado de conexión de un usuario.
  #Verifica si el usuario existe en el estado de sesiones activas.
  @impl true
  def handle_call({:check_online, username}, _from, state) do
    {:reply, Map.has_key?(state, username), state}
  end
end
