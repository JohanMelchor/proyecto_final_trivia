defmodule Trivia.CLI do
  alias Trivia.{UserManager, SessionManager, Server, Game, QuestionBank}

  # ===============================
  # PUNTO DE ENTRADA
  # ===============================
  def start do
    IO.puts("\n=== 🎮 Bienvenido a Trivia Elixir ===\n")
    {:ok, _} = ensure_server_started()
    {:ok, _} = ensure_session_manager_started()
    auth_menu()
  end

  # Solo inicia los procesos globales (modo backend)
  def start_server do
    {:ok, _} = ensure_session_manager_started()
    {:ok, _} = ensure_server_started()
    IO.puts("\n=== 🌐 SERVIDOR DE TRIVIA INICIADO ===\n")
    IO.puts("Esperando jugadores remotos...\n")
    Process.sleep(:infinity)
  end

  # ===============================
  # MENÚ DE AUTENTICACIÓN
  # ===============================
  defp auth_menu do
    IO.puts("""
    === AUTENTICACIÓN ===
    1. Iniciar sesión
    2. Registrarse
    3. Salir
    """)

    case IO.gets("Seleccione una opción: ") |> String.trim() do
      "1" -> login_flow()
      "2" -> register_flow()
      "3" -> IO.puts("👋 Hasta luego!")
      _ ->
        IO.puts("\n❌ Opción inválida.\n")
        auth_menu()
    end
  end

  defp login_flow do
    username = IO.gets("Usuario: ") |> String.trim()
    password = IO.gets("Contraseña: ") |> String.trim()

    case SessionManager.connect(username, password, self()) do
      {:ok, _msg} ->
        IO.puts("\n✅ Sesión iniciada correctamente.\n")
        main_menu(username)

      {:error, reason} ->
        IO.puts("\n❌ Error: #{inspect(reason)}\n")
        auth_menu()
    end
  end

  defp register_flow do
    username = IO.gets("Nuevo usuario: ") |> String.trim()
    password = IO.gets("Contraseña: ") |> String.trim()

    case UserManager.register(username, password) do
      {:ok, _user} ->
        IO.puts("✅ Usuario creado exitosamente.\n")
        auth_menu()

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}\n")
        auth_menu()
    end
  end

  # ===============================
  # MENÚ PRINCIPAL
  # ===============================
  defp main_menu(username) do
    IO.puts("""
    === MENÚ PRINCIPAL ===
    Usuario actual: #{username}
    ---------------------------
    1. Jugar Modo Individual
    2. Modo Multijugador
    3. Ver puntaje
    4. Ver ranking general
    5. Ver historial
    6. Cerrar sesión
    """)

    case IO.gets("Seleccione una opción: ") |> String.trim() do
      "1" -> start_single_game(username)
      "2" -> multiplayer_menu(username)
      "3" -> show_score(username)
      "4" -> show_ranking(username)
      "5" -> show_history(username)
      "6" ->
        SessionManager.disconnect(username)
        IO.puts("👋 Sesión cerrada.\n")
        auth_menu()

      _ ->
        IO.puts("\n❌ Opción inválida.\n")
        main_menu(username)
    end
  end

  # ===============================
  # MULTIJUGADOR
  # ===============================
  defp multiplayer_menu(username) do
    IO.puts("""
    === 🌐 MODO MULTIJUGADOR ===
    1. Crear partida
    2. Unirse a partida
    3. Ver partidas activas
    4. Volver al menú principal
    """)

    case IO.gets("Seleccione una opción: ") |> String.trim() do
      "1" -> create_game_flow(username)
      "2" -> join_game_flow(username)
      "3" -> list_games_flow(username)
      "4" -> main_menu(username)
      _ ->
        IO.puts("\n❌ Opción inválida.\n")
        multiplayer_menu(username)
    end
  end

  defp create_game_flow(username) do
    if not SessionManager.online?(username) do
      IO.puts("❌ Debes estar conectado al servidor.\n")
      main_menu(username)
    else
      categories = QuestionBank.load_categories()

      if categories == [] do
        IO.puts("⚠️ No hay categorías disponibles.\n")
        main_menu(username)
      else
        IO.puts("\n=== 🎮 Configuración de la partida multijugador ===\n")

        # Mostrar categorías disponibles con numeración
        Enum.each(Enum.with_index(categories, 1), fn {cat, i} ->
          IO.puts("#{i}. #{String.capitalize(cat)}")
        end)

        # Usar la misma función que singleplayer
        category = seleccionar_opcion(categories)
        num = pedir_numero("Número de preguntas:", 3)
        time = pedir_numero("Tiempo por pregunta (segundos):", 10)

        id = :rand.uniform(9999)

        case Trivia.Lobby.create_game(id, username, category, num, time) do
          {:ok, _pid} ->
            IO.puts("\n✅ Partida #{id} creada correctamente!")
            host_lobby_menu(id, username)

          {:error, :invalid_user} ->
            IO.puts("❌ El usuario no está conectado.\n")
            multiplayer_menu(username)

          {:error, :invalid_category} ->
            IO.puts("⚠️ Categoría inválida.\n")
            multiplayer_menu(username)

          {:error, reason} ->
            IO.puts("❌ Error al crear partida: #{inspect(reason)}\n")
            multiplayer_menu(username)
        end
      end
    end
  end

  defp join_game_flow(username) do
    id = pedir_numero("ID de partida:", 0)
    case Trivia.Lobby.join_game(id, username, self()) do
      {:ok, msg} ->
        IO.puts("✅ #{msg}")
        guest_lobby_menu(id, username)

      {:error, :not_found} ->
        IO.puts("❌ No existe una partida con ese ID.\n")
        multiplayer_menu(username)

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}\n")
        multiplayer_menu(username)
    end
  end

  defp list_games_flow(username) do
    IO.puts("\n=== Partidas activas ===")
    games = Server.list_games()
    if games == [] do
      IO.puts("No hay partidas disponibles.\n")
    else
      Enum.each(games, fn id -> IO.puts("• ID: #{id}") end)
    end
    multiplayer_menu(username)
  end

  # ===============================
  # LOBBY
  # ===============================
  defp host_lobby_menu(id, username) do
    IO.puts("\n=== 🎮 Lobby #{id} (Host: #{username}) ===")
    IO.puts("1. Iniciar partida")
    IO.puts("2. Cancelar partida")

    case IO.gets("Seleccione: ") |> String.trim() do
      "1" ->
        Trivia.Lobby.start_game(id)
        IO.puts("🚀 Partida iniciada! Espera las preguntas...\n")
        listen_multiplayer()
      "2" ->
        Trivia.Lobby.cancel_game(id)
        IO.puts("❌ Partida cancelada.\n")
        :ok
      _ -> host_lobby_menu(id, username)
    end
  end

  defp guest_lobby_menu(id, username) do
    IO.puts("\n=== 🕒 Esperando inicio de partida #{id} ===")
    IO.puts("1. Salir de la partida")
    listen_multiplayer()
    case IO.gets("Seleccione: ") |> String.trim() do
      "1" ->
        Trivia.Lobby.leave_game(id, username)
        IO.puts("🚪 Saliste de la partida.")
        multiplayer_menu(username)
      _ ->
        guest_lobby_menu(id, username)
    end
  end

  # ===============================
  # PARTIDA INDIVIDUAL
  # ===============================
  defp start_single_game(username) do
    IO.puts("\n=== 🎯 Configuración de partida individual ===\n")

    categories = QuestionBank.load_categories()

    if categories == [] do
      IO.puts("⚠️ No hay categorías disponibles.\n")
      main_menu(username)
    else
      Enum.each(Enum.with_index(categories, 1), fn {cat, i} ->
        IO.puts("#{i}. #{String.capitalize(cat)}")
      end)

      category = seleccionar_opcion(categories)
      num = pedir_numero("Número de preguntas:", 3)
      time = pedir_numero("Tiempo por pregunta (segundos):", 10)

      case Server.start_game(%{
            username: username,
            category: category,
            num: num,
            time: time,
            mode: :single
          }) do
        {:ok, pid} ->
          IO.puts("✅ Partida iniciada correctamente!\n")
          play_game(pid, username)

        {:error, reason} ->
          IO.puts("❌ No se pudo iniciar el juego: #{inspect(reason)}")
          main_menu(username)
      end
    end
  end

  defp play_game(pid, username) do
    receive do
      {:question, question, options} ->
        IO.puts("\n#{question}")
        Enum.each(options, fn {k, v} -> IO.puts("#{k}. #{v}") end)
        answer = IO.gets("\nTu respuesta (a, b, c, d): ") |> String.trim() |> String.downcase()
        Game.answer(pid, answer)
        play_game(pid, username)

      {:feedback, correct, delta} ->
        IO.puts(if correct, do: "✅ Correcto! (+#{delta})", else: "❌ Incorrecto (#{delta})")
        play_game(pid, username)

      {:game_over, score} ->
        IO.puts("\n🏁 Fin de la partida. Puntaje total: #{score}")
        IO.puts("=====================================\n")
        main_menu(username)

      {:timeout_notice} ->
        IO.puts("\n⏰ Tiempo agotado. Pasando a la siguiente pregunta...")
        play_game(pid, username)
    after
      60_000 -> IO.puts("\n⏰ Tiempo excedido, partida cerrada.")
    end
  end

  # ===============================
  # UTILIDADES
  # ===============================
  defp seleccionar_opcion(categories) do
    opt = IO.gets("\nSeleccione una categoría: ") |> String.trim()
    case Integer.parse(opt) do
      {n, _} when n in 1..length(categories) -> Enum.at(categories, n - 1)
      _ -> hd(categories)
    end
  end

  defp pedir_numero(pregunta, default) do
    case IO.gets("#{pregunta} ") |> String.trim() |> Integer.parse() do
      {n, _} when n > 0 -> n
      _ -> default
    end
  end

  defp show_score(username) do
    case UserManager.get_score(username) do
      {:ok, score} -> IO.puts("\nTu Puntaje actual: #{score}\n")
      _ -> IO.puts("\n⚠️ Usuario no encontrado o error.\n")
    end
    main_menu(username)
  end

  def show_ranking(username) do
    users = UserManager.load_users()
    if users == [] do
      IO.puts("\n⚠️ No hay usuarios registrados todavía.\n")
    else
      IO.puts("\n=== 🏆 RANKING GENERAL ===\n")
      users
      |> Enum.sort_by(&(-&1["score"]))
      |> Enum.with_index(1)
      |> Enum.each(fn {user, i} ->
        IO.puts("#{i}. #{user["username"]} — #{user["score"]} puntos")
      end)
    end
    main_menu(username)
  end

  def show_history(username) do
    IO.puts("\n=== 🕑 Historial de Partidas ===\n")
    Trivia.History.show_last(10)
    IO.puts("\n=================================\n")
    main_menu(username)
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

  defp listen_multiplayer do
    receive do
      {:game_message, msg} ->
        IO.puts("\n📢 #{msg}")
        listen_multiplayer()
    after
      180_000 -> IO.puts("\n⏰ Desconectado por inactividad.")
    end
  end
end
