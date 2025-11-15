defmodule Trivia.ServerTest do
  use ExUnit.Case, async: true
  alias Trivia.Server

  setup do
    # Asegurar que Server (DynamicSupervisor) esté iniciado
    {:ok, _} = Server.start_link([])
    :ok
  end

  test "DynamicSupervisor inicia y está activo" do
    # Verificar que Trivia.Server existe y es un DynamicSupervisor
    assert is_pid(GenServer.whereis(Trivia.Server))
  end

  test "arrancar lobby con restart :temporary" do
    id = :erlang.unique_integer([:positive])

    # Crear spec con restart :temporary
    spec = %{
      id: {:lobby, id},
      start: {Trivia.Lobby, :start_link, [%{id: id, owner: "test_owner", category: "entretenimiento", num: 1, time: 5, creator_pid: self()}]},
      restart: :temporary
    }

    # Arrancar lobby a través del DynamicSupervisor
    assert {:ok, pid} = Server.start_child(spec)
    assert is_pid(pid)
  end
end
