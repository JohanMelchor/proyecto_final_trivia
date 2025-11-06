defmodule Trivia.UserManager do
  @moduledoc """
  Módulo para gestionar usuarios del juego Trivia:
  - Registro e inicio de sesión
  - Consulta y actualización de puntajes
  - Persistencia en archivo JSON (data/users.json)
  """

  @file_path "data/users.json"

  # ---------- API pública ----------

  @doc """
  Registra o inicia sesión de un usuario.
  Si el usuario no existe, se crea.
  Si ya existe, valida la contraseña.
  """
  def register(username, password) do
    users = load_users()
    if Enum.any?(users, &(&1["username"] == username)) do
      {:error, "Usuario ya existe"}
    else
      new_user = %{"username" => username, "password" => password, "score" => 0}
      save_users([new_user | users])
      {:ok, new_user}
    end
  end

  def login(username, password) do
    users = load_users()
    case Enum.find(users, &(&1["username"] == username && &1["password"] == password)) do
      nil -> {:error, "Usuario o contraseña incorrectos"}
      user -> {:ok, user}
    end
  end


  @doc """
  Devuelve el puntaje acumulado de un usuario.
  """
  def get_score(username) do
    users = load_users()

    case Enum.find(users, fn u -> u["username"] == username end) do
      nil -> {:error, "Usuario no encontrado"}
      user -> {:ok, user["score"]}
    end
  end

  @doc """
  Actualiza el puntaje de un usuario sumando un valor `delta`.
  Puede ser positivo o negativo.
  """
  def update_score(username, delta) do
    users = load_users()

    updated_users =
      Enum.map(users, fn
        %{"username" => ^username} = u ->
          Map.put(u, "score", u["score"] + delta)

        other ->
          other
      end)

    save_users(updated_users)
    :ok
  end

  # ---------- Funciones internas ----------

  def load_users do
    case File.read(@file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} when is_list(data) -> data
          _ -> []
        end

      _ ->
        []
    end
  end

  defp save_users(users) do
    json = Jason.encode!(users, pretty: true)
    File.write!(@file_path, json)
  end

end
