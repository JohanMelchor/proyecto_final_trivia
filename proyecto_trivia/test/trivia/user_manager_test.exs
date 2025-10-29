defmodule Trivia.UserManagerTest do
  use ExUnit.Case
  alias Trivia.UserManager

  @test_file "data/users_test.json"

  setup do
    # Limpiamos archivo de pruebas
    File.write!(@test_file, "[]")
    on_exit(fn -> File.rm!(@test_file) end)
    :ok
  end

  test "registrar nuevo usuario" do
    {:ok, user} = UserManager.register_or_login("pepe", "1234")
    assert user["username"] == "pepe"
    assert user["score"] == 0
  end

  test "iniciar sesión con usuario existente" do
    UserManager.register_or_login("ana", "abcd")
    {:ok, user} = UserManager.register_or_login("ana", "abcd")
    assert user["username"] == "ana"
  end

  test "error si contraseña incorrecta" do
    UserManager.register_or_login("carlos", "pass1")
    {:error, msg} = UserManager.register_or_login("carlos", "wrong")
    assert msg == "Contraseña incorrecta"
  end

  test "actualizar puntaje" do
    UserManager.register_or_login("luis", "xyz")
    :ok = UserManager.update_score("luis", 5)
    {:ok, score} = UserManager.get_score("luis")
    assert score == 5
  end
end
