defmodule Trivia.CLI do
  alias Trivia.UserManager

  def start do
    IO.puts("\n=== Bienvenido a Trivia Elixir ===\n")
    main_menu()
  end

  defp main_menu do
    IO.puts("""
    1. Iniciar sesión o registrarse
    2. Ver puntaje
    3. Salir
    """)

    opcion =
      IO.gets("Seleccione una opción: ")
      |> handle_input()

    case opcion do
      "1" -> login_flow()
      "2" -> show_score()
      "3" -> IO.puts("\n¡Hasta luego!\n")
      _ ->
        IO.puts("\nOpción inválida. Intente de nuevo.\n")
        main_menu()
    end
  end

  defp login_flow do
    username = IO.gets("Usuario: ") |> handle_input()
    password = IO.gets("Contraseña: ") |> handle_input()

    case UserManager.register_or_login(username, password) do
      {:ok, user} ->
        IO.puts("\nBienvenido #{user["username"]}!\n")
        Trivia.Game.start(user["username"])
        main_menu()

      {:error, :wrong_password} ->
        IO.puts("\nContraseña incorrecta.\n")
        main_menu()

      {:error, :not_found} ->
        IO.puts("\nUsuario no encontrado.\n")
        main_menu()

      {:error, reason} ->
        IO.puts("\nError inesperado: #{inspect(reason)}\n")
        main_menu()
    end
  end

  defp show_score do
    username = IO.gets("Ingrese su usuario: ") |> handle_input()

    case UserManager.get_score(username) do
      {:ok, score} ->
        IO.puts("\nTu Puntaje actual: #{score}\n")
        main_menu()

      {:error, :not_found} ->
        IO.puts("\nUsuario no encontrado.\n")
        main_menu()

      _ ->
        IO.puts("\nError al obtener puntaje.\n")
        main_menu()
    end
  end

  # --- Utilidad para limpiar entradas nulas o vacías ---
  defp handle_input(nil), do: ""
  defp handle_input(input), do: String.trim(input)
end
