defmodule Trivia.LobbyTest do
  use ExUnit.Case, async: true
  alias Trivia.Lobby

  setup do
    # Asegurar SessionManager activo
    {:ok, _} = Trivia.SessionManager.start_link([])
    :ok
  end

  test "crear lobby y unirse correctamente" do
    id = :erlang.unique_integer([:positive])
    host = "host_#{id}"
    guest = "guest_#{id}"

    # Crear lobby
    {:ok, _pid} = Lobby.create_game(id, host, "entretenimiento", 1, 5)

    # Unirse como guest
    assert {:ok, _msg} = Lobby.join_game(id, guest, self())
  end

  test "no permitir unirse si lobby está lleno" do
    id = :erlang.unique_integer([:positive])
    host = "host_#{id}"

    {:ok, _} = Lobby.create_game(id, host, "entretenimiento", 1, 5)

    # Llenar lobby (4 máximo: host + 3 guests)
    Lobby.join_game(id, "guest1_#{id}", self())
    Lobby.join_game(id, "guest2_#{id}", self())
    Lobby.join_game(id, "guest3_#{id}", self())

    # Intento de 5to jugador debe fallar
    assert {:error, :full} = Lobby.join_game(id, "guest4_#{id}", self())
  end

  test "abandonar lobby correctamente" do
    id = :erlang.unique_integer([:positive])
    host = "host_#{id}"
    guest = "guest_#{id}"

    {:ok, _} = Lobby.create_game(id, host, "entretenimiento", 1, 5)
    Lobby.join_game(id, guest, self())

    # Abandonar
    assert :ok = Lobby.leave_game(id, guest)
  end
end
