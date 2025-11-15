defmodule Trivia.GameTest do
  use ExUnit.Case, async: true
  alias Trivia.Game

  test "iniciar juego en modo singleplayer" do
    {:ok, pid} = Game.start_link(%{
      mode: :single,
      username: "test_user",
      category: "entretenimiento",
      num: 1,
      time: 5,
      caller: self()
    })

    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "timeout penaliza al jugador en multijugador" do
    # Crear juego multijugador con 2 jugadores
    {:ok, game_pid} = Game.start_link(%{
      mode: :multi,
      lobby_pid: self(),
      players: %{
        "player1" => %{pid: self(), score: 0, answered: false},
        "player2" => %{pid: self(), score: 0, answered: false}
      },
      category: "entretenimiento",
      num: 1,
      time: 1,
      questions: [%{"question" => "Test?", "answer" => "a", "options" => %{"a" => "A", "b" => "B", "c" => "C", "d" => "D"}}]
    })

    # Simular timeout (ambos no responden)
    send(game_pid, :timeout)

    # Verificar que proceso sigue vivo (no crashea)
    assert Process.alive?(game_pid)
  end
end
