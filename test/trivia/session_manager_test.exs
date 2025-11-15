defmodule Trivia.SessionManagerTest do
  use ExUnit.Case, async: true
  alias Trivia.SessionManager

  setup do
    # Asegurar que SessionManager esté iniciado
    {:ok, _} = SessionManager.start_link([])
    :ok
  end

  test "connect y disconnect de usuario" do
    username = "test_user_#{:erlang.unique_integer([:positive])}"

    # Conectar usuario
    assert :ok = SessionManager.connect(username)
    assert SessionManager.online?(username)

    # Desconectar usuario
    assert :ok = SessionManager.disconnect(username)
    refute SessionManager.online?(username)
  end

  test "list_online devuelve usuarios conectados" do
    user1 = "user1_#{:erlang.unique_integer([:positive])}"
    user2 = "user2_#{:erlang.unique_integer([:positive])}"

    SessionManager.connect(user1)
    SessionManager.connect(user2)

    online_users = SessionManager.list_online()
    assert user1 in online_users
    assert user2 in online_users
  end
end
