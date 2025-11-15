defmodule Trivia.CLI do
  alias Trivia.{UserManager, SessionManager, Server, Game, QuestionBank}

  # ===============================
  # PUNTO DE ENTRADA
  # ===============================
  def start do
    IO.puts("\n===  Bienvenido  ===\n")
    Application.ensure_all_started(:proyecto_trivia)
    auth_menu()
  end

  # Solo inicia los procesos globales
  def start_server do
    Application.ensure_all_started(:proyecto_trivia)
    IO.puts("\n===  SERVIDOR DE TRIVIA INICIADO (supervisor) ===\n")
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
      "3" -> IO.puts(" Hasta luego!")
      _ ->
        IO.puts("\n Opción inválida.\n")
        auth_menu()
    end
  end

  defp login_flow do
    username = IO.gets("Usuario: ") |> String.trim()
    password = IO.gets("Contraseña: ") |> String.trim()

    case SessionManager.connect(username, password, self()) do
      {:ok, _msg} ->
        IO.puts("\n Sesión iniciada correctamente.\n")
        main_menu(username)

      {:error, reason} ->
        IO.puts("\n Error: #{inspect(reason)}\n")
        auth_menu()
    end
  end

  defp register_flow do
    username = IO.gets("Nuevo usuario: ") |> String.trim()
    password = IO.gets("Contraseña: ") |> String.trim()

    case UserManager.register(username, password) do
      {:ok, _user} ->
        IO.puts(" Usuario creado exitosamente.\n")
        auth_menu()

      {:error, reason} ->
        IO.puts(" Error: #{inspect(reason)}\n")
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
        IO.puts(" Sesión cerrada.\n")
        auth_menu()

      _ ->
        IO.puts("\n Opción inválida.\n")
        main_menu(username)
    end
  end

  # ===============================
  # MULTIJUGADOR
  # ===============================
  defp multiplayer_menu(username) do
    IO.puts("""
    ===  MODO MULTIJUGADOR ===
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
        IO.puts("\n Opción inválida.\n")
        multiplayer_menu(username)
    end
  end

  defp create_game_flow(username) do
    if not SessionManager.online?(username) do
      IO.puts(" Debes estar conectado al servidor.\n")
      main_menu(username)
    else
      categories = QuestionBank.load_categories()

      if categories == [] do
        IO.puts(" No hay categorías disponibles.\n")
        main_menu(username)
      else
        IO.puts("\n===  Configuración de la partida multijugador ===\n")

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
            IO.puts("\n Partida #{id} creada correctamente!")
            host_lobby_menu(id, username)

          {:error, :invalid_user} ->
            IO.puts(" El usuario no está conectado.\n")
            multiplayer_menu(username)

          {:error, :invalid_category} ->
            IO.puts(" Categoría inválida.\n")
            multiplayer_menu(username)

          {:error, reason} ->
            IO.puts(" Error al crear partida: #{inspect(reason)}\n")
            multiplayer_menu(username)
        end
      end
    end
  end

  defp join_game_flow(username) do
    id = pedir_numero("ID de partida:", 0)
    case Trivia.Lobby.join_game(id, username, self()) do
      {:ok, msg} ->
        IO.puts(" #{msg}")
        guest_lobby_menu(id, username)

      {:error, :not_found} ->
        IO.puts(" No existe una partida con ese ID.\n")
        multiplayer_menu(username)

      {:error, reason} ->
        IO.puts(" Error: #{inspect(reason)}\n")
        multiplayer_menu(username)
    end
  end

  defp list_games_flow(username) do
    IO.puts("\n=== Partidas activas ===")
    games = Server.list_games()

    if games == [] do
      IO.puts("No hay partidas disponibles.\n")
    else
      Enum.each(games, fn id ->
        # Verificar que el lobby sigue activo antes de mostrar
        case :global.whereis_name({:lobby, id}) do
          :undefined -> :ok  # Lobby terminado, no mostrar
          _pid -> IO.puts("• ID: #{id}")
        end
      end)
    end

    multiplayer_menu(username)
  end

  # ===============================
  # LOBBY
  # ===============================
  defp host_lobby_menu(id, username) do
    IO.puts("\n===  Lobby #{id} (Host: #{username}) ===")
    IO.puts("1. Iniciar partida")
    IO.puts("2. Cancelar partida")

    case IO.gets("Seleccione: ") |> String.trim() do
      "1" ->
        Trivia.Lobby.start_game(id)
        IO.puts(" Partida iniciada! Espera las preguntas...\n")
        listen_multiplayer(id, username)  #  Pasar id y username
      "2" ->
        Trivia.Lobby.cancel_game(id)
        IO.puts(" Partida cancelada.\n")
        multiplayer_menu(username)
      _ ->
        host_lobby_menu(id, username)
    end
  end

  defp guest_lobby_menu(id, username) do
    # Limpiar mensajes pendientes (evita que mensajes del lobby anterior se mezclen)
    flush_mailbox()

    IO.puts("\n===  Esperando inicio de partida #{id} ===")
    IO.puts("1. Abandonar partida")

    parent = self()

    # Spawn sólo para leer la entrada y notificar al proceso principal.
    spawn(fn ->
      case IO.gets("Opción: ") |> handle_input() do
        "1" ->
          # Enviar mensaje con el id del lobby para evitar mezclar con lobbies anteriores
          send(parent, {:leave_lobby, id, username})
        _ ->
          # Notificar entrada inválida (se ignora si ya no corresponde al lobby)
          send(parent, {:guest_input_invalid, id})
      end
    end)

    listen_multiplayer(id, username)
  end
  # vacía el mailbox del proceso para evitar usar mensajes viejos
  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end

  # ===============================
  # PARTIDA INDIVIDUAL
  # ===============================
  defp start_single_game(username) do
    IO.puts("\n===  Configuración de partida individual ===\n")

    categories = QuestionBank.load_categories()

    if categories == [] do
      IO.puts(" No hay categorías disponibles.\n")
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
          IO.puts(" Partida iniciada correctamente!\n")
          play_game(pid, username)

        {:error, reason} ->
          IO.puts(" No se pudo iniciar el juego: #{inspect(reason)}")
          main_menu(username)
      end
    end
  end

  defp play_game(pid, username) do
    receive do
      {:question, question, options} ->
        IO.puts("\n" <> String.duplicate("=", 50))
        IO.puts(" #{question}")
        IO.puts(String.duplicate("-", 50))
        Enum.each(options, fn {k, v} -> IO.puts("#{k}. #{v}") end)
        IO.puts(String.duplicate("=", 50))

        # Pedir respuesta en un proceso separado para no bloquear
        spawn(fn ->
          capture_single_answer(pid)
        end)

        play_game(pid, username)

      {:feedback, correct, delta} ->
        play_game(pid, username)

      {:timeout_notice, correct_answer} ->
        IO.puts("\n Tiempo agotado! La respuesta correcta era: #{correct_answer}")
        IO.puts(" Pasando a la siguiente pregunta...")
        play_game(pid, username)

      {:game_over, score} ->
        IO.puts("\n" <> String.duplicate("=", 15))
        IO.puts(" ¡FIN DEL JUEGO!")
        IO.puts(" Puntaje final: #{score} puntos")
        IO.puts(String.duplicate("=", 15))
        IO.puts("\n")
        main_menu(username)

      unexpected ->
        IO.puts("Mensaje inesperado: #{inspect(unexpected)}")
        play_game(pid, username)
    after
      300_000 ->
        IO.puts("\n Tiempo de inactividad excedido. Partida cancelada.")
        main_menu(username)
    end
  end

  defp capture_single_answer(pid) do
    answer = IO.gets("\nTu respuesta (a, b, c, d): ")
             |> String.trim()
             |> String.downcase()

    if answer in ["a", "b", "c", "d"] do
      Game.answer(pid, answer)
    else
      IO.puts(" Respuesta inválida. Usa a, b, c o d.")
      capture_single_answer(pid)  #  Reintentar recursivamente
    end
  end

  # ===============================
  # UTILIDADES
  # ===============================
  defp seleccionar_opcion(categories) do
    opt = IO.gets("\nSeleccione una categoría: ") |> String.trim()
    case Integer.parse(opt) do
      {n, _} when n in 1..length(categories)//1 ->  #  Corregir el warning del rango
        Enum.at(categories, n - 1)
      _ ->
        hd(categories)
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
      _ -> IO.puts("\n Usuario no encontrado o error.\n")
    end
    main_menu(username)
  end

  def show_ranking(username) do
    users = UserManager.load_users()
    if users == [] do
      IO.puts("\n No hay usuarios registrados todavía.\n")
    else
      IO.puts("\n===  RANKING GENERAL ===\n")
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
    IO.puts("\n=== Historial de Partidas ===\n")
    Trivia.History.show_last(10)
    IO.puts("\n=================================\n")
    main_menu(username)
  end

  defp handle_input(input), do: String.trim(input)

  defp listen_multiplayer(id, username) do
    receive do
      {:leave_lobby, ^id, _user} ->
        # Sólo actúa si el mensaje corresponde al lobby actual
        Trivia.Lobby.leave_game(id, username)
        IO.puts("\nHas abandonado la partida\n")
        multiplayer_menu(username)

      {:lobby_canceled, ^id} ->
        IO.puts("\nEl host canceló la partida. Volviendo al menú multijugador...\n")
        multiplayer_menu(username)

      {:guest_input_invalid, ^id} ->
        # Ignorar y seguir escuchando (usuario puede reingresar)
        listen_multiplayer(id, username)

      # ... rest of messages ...
      {:game_message, msg} ->
        IO.puts("\n #{msg}")
        listen_multiplayer(id, username)

      {:question_summary, summary} ->
        IO.puts("\n" <> String.duplicate("=", 50))
        IO.puts(" RESUMEN DE RESPUESTAS:")
        IO.puts(String.duplicate("-", 50))
        Enum.each(summary, fn
          {user, :timeout, _correct, delta} ->
            IO.puts("#{user}: tiempo agotado (#{delta} pts)")
          {user, :answered, correct, delta} ->
            status = if correct, do: " Correcto", else: " Incorrecto"
            IO.puts("#{user}: #{status} (#{delta} pts)")
          {user, _other, correct, delta} ->
            status = if correct, do: " Correcto", else: " Incorrecto"
            IO.puts("#{user}: #{status} (#{delta} pts)")
        end)
        IO.puts(String.duplicate("=", 50))
        listen_multiplayer(id, username)

      {:question, question, options} ->
        IO.puts("\n" <> String.duplicate("=", 50))
        IO.puts(" #{question}")
        IO.puts(String.duplicate("-", 50))
        Enum.each(options, fn {k, v} -> IO.puts("#{k}. #{v}") end)
        IO.puts(String.duplicate("=", 50))

        # pasar el pid del proceso principal para que capture_answer pueda notificarle
        spawn(fn -> capture_answer(id, username, self()) end)

        listen_multiplayer(id, username)

      {:player_answered, user, reason, correct, delta} ->
        case reason do
          :timeout ->
            IO.puts("#{user}:  tiempo agotado (#{delta} pts)")
          :answered ->
            IO.puts("#{user}: #{if correct, do: " Correcto", else: " Incorrecto"} (#{delta} pts)")
          _ ->
            IO.puts("#{user}: #{if correct, do: " Correcto", else: " Incorrecto"} (#{delta} pts)")
        end
        listen_multiplayer(id, username)

      {:timeout, _} ->
        IO.puts(" Tiempo agotado! Siguiente pregunta...")
        listen_multiplayer(id, username)

      {:game_over, players} ->
        IO.puts("\n" <> String.duplicate("=", 15))
        IO.puts(" ¡FIN DE LA PARTIDA MULTIJUGADOR!")
        IO.puts(String.duplicate("-", 50))
        Enum.each(players, fn {u, %{score: s}} -> IO.puts("#{u}: #{s} puntos") end)
        IO.puts(String.duplicate("=", 15))
        multiplayer_menu(username)

      {:question, q} when is_map(q) ->
        IO.puts("\n" <> String.duplicate("=", 50))
        IO.puts(" #{q["question"]}")
        IO.puts(String.duplicate("-", 50))
        Enum.each(q["options"], fn {k, v} -> IO.puts("#{k}. #{v}") end)
        IO.puts(String.duplicate("=", 50))

        spawn(fn -> capture_answer(id, username, self()) end)

        listen_multiplayer(id, username)

      unexpected ->
        IO.puts("Mensaje inesperado en multiplayer: #{inspect(unexpected)}")
        listen_multiplayer(id, username)
    after
      300_000 ->
        IO.puts("\n Desconectado por inactividad.")
        multiplayer_menu(username)
    end
  end

  defp capture_answer(id, username, parent_pid) do
    IO.write("Tu respuesta (a, b, c, d): ")

    case IO.read(:line) do
      :eof ->
        IO.puts("\n Error de entrada")
        capture_answer(id, username, parent_pid)

      answer when is_binary(answer) ->
        answer = answer |> String.trim() |> String.downcase()

        cond do
          answer in ["a", "b", "c", "d"] ->
            case get_game_pid_from_lobby(id) do
              {:ok, game_pid} ->
                GenServer.cast(game_pid, {:answer, username, answer})
              {:error, reason} ->
                IO.puts(" Error al enviar respuesta: #{reason}")
            end

          answer == "/salir" ->
            # Notificar al proceso principal que desea salir del lobby
            send(parent_pid, {:leave_lobby, id, username})
            :ok

          true ->
            IO.puts(" Respuesta inválida. Usa a, b, c o d.")
            capture_answer(id, username, parent_pid)
        end

      _ ->
        IO.puts(" Error de entrada")
        capture_answer(id, username, parent_pid)
    end
  end

  defp get_game_pid_from_lobby(id) do
    case :global.whereis_name({:lobby, id}) do
      :undefined ->
        {:error, "Lobby no encontrado"}
      lobby_pid ->
        try do
          game_pid = GenServer.call(lobby_pid, :get_game_pid, 5000)  # 5 segundos timeout
          if game_pid && Process.alive?(game_pid) do
            {:ok, game_pid}
          else
            {:error, "Juego no disponible"}
          end
        catch
          :exit, _ -> {:error, "Timeout al comunicarse con el lobby"}
          _, _ -> {:error, "Error al comunicarse con el lobby"}
        end
    end
  end
end
