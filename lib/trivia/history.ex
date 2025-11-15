defmodule Trivia.History do
  @moduledoc """
  Manejo del historial de partidas.
  Guarda los resultados en results.log y permite consultarlos.
  """

  @log_file "data/results.log"

  # Guarda un resultado en el log
  def save_result(username, category, score) do
    timestamp = DateTime.now!("Etc/UTC") |> DateTime.to_string()
    entry = "[#{timestamp}] Usuario: #{username} | Categoría: #{category} | Puntaje: #{score}\n"

    File.write!(@log_file, entry, [:append])
  end

  # Carga el historial completo
  def load_results do
    case File.read(@log_file) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)

      _ ->
        []
    end
  end

  # Muestra los últimos N resultados
  def show_last(n \\ 5) do
    load_results()
    |> Enum.take(-n)
    |> Enum.each(&IO.puts/1)
  end
end
