defmodule Trivia.CLI do
  alias Trivia.{UserManager, QuestionBank, Server, Game}

  def start do
    IO.puts("\n=== Bienvenido a Trivia Elixir ===\n")
    {:ok, _server} = ensure_server_started()
    main_menu()
  end

  # --- MENÚ PRINCIPAL ---
  defp main_menu do
    IO.puts("""
    1. Iniciar sesión o registrarse
    2. Ver puntaje
    3. Ver ranking general
    4. Salir
    """)

    case IO.gets("Seleccione una opción: ") |> handle_input() do
      "1" -> login_flow()
      "2" -> show_score()
      "3" -> show_ranking()
      "4" -> IO.puts("\n¡Hasta luego!\n")
      _ ->
        IO.puts("\n❌ Opción inválida.\n")
        main_menu()
    end
  end

  # --- LOGIN Y REGISTRO ---
  defp login_flow do
    username = IO.gets("Usuario: ") |> handle_input()
    password = IO.gets("Contraseña: ") |> handle_input()

    case UserManager.register_or_login(username, password) do
      {:ok, user} ->
        IO.puts("\n✅ Bienvenido #{user["username"]}!\n")
        iniciar_partida(user["username"])
        main_menu()

      {:error, reason} ->
        IO.puts("\n❌ Error: #{inspect(reason)}\n")
        main_menu()
    end
  end

  # --- CONFIGURACIÓN DE PARTIDA ---
  defp iniciar_partida(username) do
    IO.puts("\n=== 🎮 Configuración de partida ===\n")

    categories = QuestionBank.load_categories()
    Enum.each(Enum.with_index(categories, 1), fn {cat, i} ->
      IO.puts("#{i}. #{String.capitalize(cat)}")
    end)

    category = seleccionar_opcion(categories)
    num = pedir_numero("¿Cuántas preguntas desea jugar?", 3)
    time = pedir_numero("Tiempo límite por pregunta (segundos)?", 10)

    case Server.start_game(%{
           username: username,
           category: category,
           num: num,
           time: time
         }) do
      {:ok, pid} ->
        play_game(pid)

      {:error, reason} ->
        IO.puts("\n❌ No se pudo iniciar la partida: #{inspect(reason)}\n")
    end
  end

  # --- INTERFAZ DE PARTIDA ---
  defp play_game(pid) do
    receive do
      {:question, question, options} ->
        IO.puts("\n#{question}")
        Enum.each(options, fn {k, v} -> IO.puts("#{k}. #{v}") end)

        answer =
          IO.gets("\nTu respuesta (a, b, c, d): ")
          |> String.trim()
          |> String.downcase()

        Game.answer(pid, answer)
        play_game(pid)

      {:game_over, score} ->
        IO.puts("\n🏁 Fin de la partida. Puntaje total: #{score}")
        IO.puts("=====================================\n")
    after
      30000 ->
        IO.puts("\n⏰ Tiempo de espera excedido, cerrando partida.")
    end
  end

  # --- UTILIDADES ---
  defp seleccionar_opcion(categories) do
    opt = IO.gets("\nSeleccione una categoría: ") |> String.trim()
    case Integer.parse(opt) do
      {n, _} when n in 1..length(categories)//1 -> Enum.at(categories, n - 1)
      _ -> hd(categories)
    end
  end

  defp pedir_numero(pregunta, default) do
    case IO.gets("\n#{pregunta} ") |> String.trim() |> Integer.parse() do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp show_score do
    username = IO.gets("Ingrese su usuario: ") |> handle_input()

    case UserManager.get_score(username) do
      {:ok, score} ->
        IO.puts("\nTu Puntaje actual: #{score}\n")
      _ ->
        IO.puts("\n⚠️ Usuario no encontrado o error.\n")
    end

    main_menu()
  end

  def show_ranking do
    users = UserManager.load_users()

    if length(users) == 0 do
      IO.puts("\n⚠️ No hay usuarios registrados todavía.\n")
    else
      IO.puts("\n=== 🏆 RANKING GENERAL ===\n")

      users
      |> Enum.sort_by(fn u -> -u["score"] end)
      |> Enum.with_index(1)
      |> Enum.each(fn {user, i} ->
        IO.puts("#{i}. #{user["username"]} — #{user["score"]} puntos")
      end)

      IO.puts("\n=========================\n")
    end

    main_menu()
  end

  defp handle_input(nil), do: ""
  defp handle_input(input), do: String.trim(input)

  # Asegura que el servidor esté corriendo
  defp ensure_server_started do
    case Process.whereis(Server) do
      nil -> Server.start_link(nil)
      pid -> {:ok, pid}
    end
  end
end
