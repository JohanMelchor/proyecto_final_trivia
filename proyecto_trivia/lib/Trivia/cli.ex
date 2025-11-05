defmodule Trivia.CLI do
  alias Trivia.{UserManager, SessionManager, Server, Game, QuestionBank}

  # ===============================
  # INICIO
  # ===============================
  def start do
    IO.puts("\n=== Bienvenido a Trivia Elixir ===\n")
    {:ok, _server} = ensure_server_started()
    main_menu()
  end

  def start_server do
    {:ok, _session} = ensure_session_manager_started()
    {:ok, _server} = ensure_server_started()
    IO.puts("\n=== 🌐 SERVIDOR DE TRIVIA ===\n")
    multiplayer_menu()
  end

  # ===============================
  # MENÚ PRINCIPAL
  # ===============================
  defp main_menu do
    IO.puts("""
    1. Jugar Modo Individual
    2. Jugar Modo Multijugador
    3. Ver puntaje
    4. Ver ranking general
    5. Ver historial
    6. Salir
    """)

    case IO.gets("Seleccione una opción: ") |> handle_input() do
      "1" -> singleplayer_flow()
      "2" -> multiplayer_menu()
      "3" -> show_score()
      "4" -> show_ranking()
      "5" -> show_history()
      "6" -> IO.puts("\n¡Hasta luego!\n")
      _ ->
        IO.puts("\n❌ Opción inválida.\n")
        main_menu()
    end
  end

  # ===============================
  # MENÚ MULTIJUGADOR
  # ===============================
  defp multiplayer_menu do
    IO.puts("""
    === 🌐 MODO MULTIJUGADOR ===
    1. Conectarse a servidor (opcional)
    2. Crear partida
    3. Unirse a partida
    4. Ver partidas activas
    5. Ver usuarios conectados
    6. Volver al menú principal
    """)

    case IO.gets("Seleccione una opción: ") |> String.trim() do
      "1" -> connect_flow()
      "2" -> create_game_flow()
      "3" -> join_game_flow()
      "4" -> list_games_flow()
      "5" -> list_online_flow()
      "6" -> main_menu()
      _ ->
        IO.puts("\n❌ Opción inválida.\n")
        multiplayer_menu()
    end
  end

  # ===============================
  # MENÚS DE LOBBY
  # ===============================

  defp host_lobby_menu(id, username) do
    IO.puts("\n=== 🎮 Lobby #{id} (Host: #{username}) ===")

    info = Trivia.Lobby.get_info(id)
    if is_map(info) do
      IO.puts("Jugadores: #{Enum.join(info.jugadores, ", ")}")
    end

    IO.puts("""
    1. Iniciar partida
    2. Cancelar partida
    3. Actualizar lista
    """)

    case IO.gets("Seleccione: ") |> String.trim() do
      "1" ->
        Trivia.Lobby.start_game(id)
        IO.puts("🚀 Partida iniciada!")
        listen_multiplayer()

      "2" ->
        Trivia.Lobby.cancel_game(id)
        IO.puts("❌ Partida cancelada. Cerrando lobby...")
        Process.sleep(1500)
        multiplayer_menu()

      "3" ->
        host_lobby_menu(id, username)

      _ ->
        host_lobby_menu(id, username)
    end
  end

  defp guest_lobby_menu(id, username) do
    IO.puts("\n=== 🕒 Esperando inicio de partida #{id} ===")
    IO.puts("1. Salir de la partida")

    spawn(fn -> listen_multiplayer() end)

    case IO.gets("Seleccione: ") |> String.trim() do
      "1" ->
        Trivia.Lobby.leave_game(id, username)
        IO.puts("🚪 Saliste de la partida.")
        multiplayer_menu()

      _ ->
        guest_lobby_menu(id, username)
    end
  end

  # ===============================
  # NUEVO: LISTAR USUARIOS ONLINE
  # ===============================
  defp list_online_flow do
    users = SessionManager.list_online()

    if users == [] do
      IO.puts("\n⚠️ No hay usuarios conectados.\n")
    else
      IO.puts("\n=== Usuarios Conectados ===")
      Enum.each(users, fn u -> IO.puts("• #{u}") end)
      IO.puts("===========================\n")
    end

    multiplayer_menu()
  end

  # ===============================
  # CONEXIÓN
  # ===============================
  defp connect_flow do
    IO.puts("\n🌍 Conexión a servidor Trivia")
    remote = IO.gets("¿Quieres conectar a un nodo remoto? (s/n): ") |> String.trim()

    if remote in ["s", "S"] do
      host = IO.gets("Host o IP del servidor (ej. server@192.168.1.10): ") |> String.trim()
      if Node.connect(String.to_atom(host)) do
        IO.puts("✅ Conectado al servidor #{host}\n")
      else
        IO.puts("❌ No se pudo conectar al nodo #{host}\n")
      end
    else
      IO.puts("Conectado localmente.\n")
    end

    username = IO.gets("Usuario: ") |> String.trim()
    password = IO.gets("Contraseña: ") |> String.trim()

    case SessionManager.connect(username, password, self()) do
      {:ok, msg} -> IO.puts("✅ #{msg}\n")
      {:error, reason} -> IO.puts("❌ Error: #{inspect(reason)}\n")
    end

    multiplayer_menu()
  end

  # ===============================
  # MULTIJUGADOR
  # ===============================
  defp create_game_flow do
    username = IO.gets("Creador (usuario conectado): ") |> String.trim()

    # Verificar si está conectado realmente
    if not SessionManager.online?(username) do
      IO.puts("❌ Debes estar conectado al servidor para crear una partida.\n")
      multiplayer_menu()
    else
      categories = QuestionBank.load_categories()

      IO.puts("\n=== Categorías disponibles ===")
      Enum.each(categories, fn c -> IO.puts("• #{c}") end)

      category = IO.gets("Tema: ") |> String.trim()

      if not Enum.member?(categories, category) do
        IO.puts("⚠️ Categoría inválida. Intenta de nuevo.\n")
        multiplayer_menu()
      else
        num = IO.gets("Número de preguntas: ") |> String.trim() |> String.to_integer()
        time = IO.gets("Tiempo por pregunta (segundos): ") |> String.trim() |> String.to_integer()
        id = :rand.uniform(9999)

        case Trivia.Lobby.create_game(id, username, category, num, time) do
          {:ok, _pid} ->
            IO.puts("✅ Partida #{id} creada correctamente!\n")
            host_lobby_menu(id, username)

          {:error, :invalid_user} ->
            IO.puts("❌ El usuario no está conectado.\n")
            multiplayer_menu()

          {:error, :invalid_category} ->
            IO.puts("⚠️ Categoría inválida.\n")
            multiplayer_menu()

          {:error, :no_questions} ->
            IO.puts("⚠️ No hay preguntas disponibles en esa categoría.\n")
            multiplayer_menu()

          {:error, reason} ->
            IO.puts("❌ Error: #{inspect(reason)}")
            multiplayer_menu()
        end
      end
    end
  end

  defp join_game_flow do
    id = IO.gets("ID de partida: ") |> String.trim() |> String.to_integer()
    username = IO.gets("Usuario: ") |> String.trim()

    case Trivia.Lobby.join_game(id, username, self()) do
      {:ok, msg} ->
        IO.puts("✅ #{msg}")
        guest_lobby_menu(id, username)

      {:error, :invalid_user} ->
        IO.puts("❌ El usuario no está conectado. Usa la opción 'Conectarse al servidor' antes.\n")
        multiplayer_menu()

      {:error, :not_found} ->
        IO.puts("❌ No existe una partida con ese ID.\n")
        multiplayer_menu()

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}\n")
        multiplayer_menu()
    end
  end

  defp list_games_flow do
    IO.puts("\n=== Partidas activas ===")
    games = Server.list_games()

    if games == [] do
      IO.puts("No hay partidas disponibles.\n")
    else
      Enum.each(games, fn id -> IO.puts("• ID: #{id}") end)
    end

    multiplayer_menu()
  end

  # ===============================
  # ESCUCHAR MENSAJES MULTIJUGADOR
  # ===============================
  defp listen_multiplayer do
    receive do
      {:game_message, msg} ->
        IO.puts("\n📢 #{msg}")
        listen_multiplayer()
    after
      60_000 ->
        IO.puts("\n⏰ Desconectado por inactividad.")
    end
  end

  # ===============================
  # SINGLEPLAYER
  # ===============================
  defp singleplayer_flow do
    username = IO.gets("Usuario: ") |> handle_input()
    password = IO.gets("Contraseña: ") |> handle_input()

    case UserManager.register_or_login(username, password) do
      {:ok, user} ->
        IO.puts("\n✅ Bienvenido #{user["username"]}! — MODO INDIVIDUAL\n")
        start_single_game(user["username"])

      {:error, reason} ->
        IO.puts("\n❌ Error: #{inspect(reason)}\n")
        main_menu()
    end
  end

  defp start_single_game(username) do
    IO.puts("\n=== 🎯 Configura tu partida ===\n")

    categories = QuestionBank.load_categories()
    Enum.each(Enum.with_index(categories, 1), fn {cat, i} ->
      IO.puts("#{i}. #{String.capitalize(cat)}")
    end)

    category = seleccionar_opcion(categories)
    num = pedir_numero("¿Cuántas preguntas deseas?", 3)
    time = pedir_numero("Tiempo por pregunta (segundos)?", 10)

    case Server.start_game(%{
           username: username,
           category: category,
           num: num,
           time: time,
           mode: :single
         }) do
      {:ok, pid} -> play_game(pid)
      {:error, reason} -> IO.puts("❌ No se pudo iniciar el juego: #{inspect(reason)}")
    end
  end

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
      30_000 ->
        IO.puts("\n⏰ Tiempo de espera excedido, cerrando partida.")
    end
  end

  # ===============================
  # UTILIDADES
  # ===============================
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
      {:ok, score} -> IO.puts("\nTu Puntaje actual: #{score}\n")
      _ -> IO.puts("\n⚠️ Usuario no encontrado o error.\n")
    end

    main_menu()
  end

  def show_ranking do
    users = UserManager.load_users()

    if users == [] do
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

  def show_history do
    IO.puts("\n=== 🕑 Historial de Partidas ===\n")
    Trivia.History.show_last(10)
    IO.puts("\n=================================\n")
    main_menu()
  end

  defp handle_input(nil), do: ""
  defp handle_input(input), do: String.trim(input)

  defp ensure_server_started do
    case Process.whereis(Server) do
      nil -> Server.start_link(nil)
      pid -> {:ok, pid}
    end
  end

  defp ensure_session_manager_started do
    case :global.whereis_name(Trivia.SessionManager) do
      :undefined -> SessionManager.start_link(nil)
      pid when is_pid(pid) -> {:ok, pid}
    end
  end
end
