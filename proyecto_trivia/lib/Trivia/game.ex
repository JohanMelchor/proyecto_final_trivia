defmodule Trivia.Game do
  alias Trivia.UserManager

  @questions_file "data/questions.json"
  @points_correct  10
  @points_wrong   -5
  @points_invalid -10
  @points_timeout -5

  def start(username) do
    IO.puts("\n=== 🎮 ¡Configuración de partida! ===\n")

    with {:ok, categories} <- load_categories() do
      category = select_category(categories)
      num = select_question_count(category)
      time = select_time_limit()

      IO.puts("\nIniciando partida en '#{category}' con #{num} preguntas y #{time}s por respuesta...\n")

      case load_questions(category, num) do
        {:ok, questions} ->
          {score, total} = play_rounds(questions, 0, 0, time)
          IO.puts("\n📊 Resultado final: #{score} puntos (#{total} preguntas)\n")
          UserManager.update_score(username, score)
          IO.puts("✅ Puntaje actualizado exitosamente.\n")

        {:error, reason} ->
          IO.puts("⚠️  Error cargando preguntas: #{inspect(reason)}")
      end
    end
  end

  # --- CONFIGURACIÓN ---
  defp load_categories do
    case File.read(@questions_file) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, categories} -> {:ok, Map.keys(categories)}
          error -> error
        end
      error -> error
    end
  end

  defp select_category(categories) do
    IO.puts("Categorías disponibles:")
    Enum.each(Enum.with_index(categories, 1), fn {cat, i} ->
      IO.puts("#{i}. #{String.capitalize(cat)}")
    end)
    opt = IO.gets("\nSeleccione una categoría: ") |> String.trim()
    case Integer.parse(opt) do
      {n, _} when n in 1..length(categories) -> Enum.at(categories, n - 1)
      _ ->
        IO.puts("⚠️  Opción inválida, usando la primera categoría por defecto.")
        hd(categories)
    end
  end

  defp select_question_count(_category) do
    opt = IO.gets("\n¿Cuántas preguntas desea jugar? ") |> String.trim()
    case Integer.parse(opt) do
      {n, _} when n > 0 -> n
      _ ->
        IO.puts("⚠️  Valor inválido, usando 3 por defecto.")
        3
    end
  end

  defp select_time_limit do
    opt = IO.gets("\nTiempo límite por pregunta (segundos): ") |> String.trim()
    case Integer.parse(opt) do
      {n, _} when n > 0 -> n
      _ ->
        IO.puts("⚠️  Tiempo inválido, usando 10 segundos.")
        10
    end
  end

  # --- LÓGICA DE JUEGO ---
  defp load_questions(category, num) do
    case File.read(@questions_file) do
      {:ok, data} ->
        with {:ok, decoded} <- Jason.decode(data),
             questions when is_list(questions) <- Map.get(decoded, category) do
          selected = Enum.take_random(questions, num)
          {:ok, selected}
        else
          _ -> {:error, :no_category}
        end
      error -> error
    end
  end

  defp play_rounds([], score, total, _time), do: {score, total}

  defp play_rounds([q | rest], score, total, time) do
    IO.puts("\n#{q["question"]}")
    Enum.each(q["options"], fn {key, value} ->
      IO.puts("#{key}. #{value}")
    end)

    case timed_input(time) do
      {:ok, answer} ->
        evaluate_answer(answer, q, score, total, rest, time)

      :timeout ->
        IO.puts("⏰ Tiempo agotado. Pierdes #{@points_timeout} punto.\n")
        play_rounds(rest, score + @points_timeout, total + 1, time)
    end
  end

  # --- LECTURA CON TEMPORIZADOR ---
  defp timed_input(seconds) do
    parent = self()

    task = Task.async(fn ->
      input = IO.gets("\nTu respuesta (a, b, c, d): ")
      send(parent, {:user_input, input})
    end)

    receive do
      {:user_input, input} ->
        Task.shutdown(task, :brutal_kill)
        {:ok, String.trim(input) |> String.downcase()}
    after
      seconds * 1000 ->
        Task.shutdown(task, :brutal_kill)
        :timeout
    end
  end

  # --- EVALUACIÓN ---
  defp evaluate_answer(answer, q, score, total, rest, time) do
    cond do
      not (answer in Map.keys(q["options"])) ->
        IO.puts("⚠️ Respuesta inválida. #{@points_invalid} punto.\n")
        play_rounds(rest, score + @points_invalid, total + 1, time)

      answer == String.downcase(q["answer"]) ->
        IO.puts("✅ Correcto. +#{@points_correct}\n")
        play_rounds(rest, score + @points_correct, total + 1, time)

      true ->
        IO.puts("❌ Incorrecto. Era #{q["answer"]}. #{@points_wrong} punto.\n")
        play_rounds(rest, score + @points_wrong, total + 1, time)
    end
  end
end
