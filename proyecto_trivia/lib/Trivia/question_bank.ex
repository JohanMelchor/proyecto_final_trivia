defmodule Trivia.QuestionBank do
  @moduledoc """
  Módulo encargado de manejar las preguntas de trivia.
  Lee, organiza y entrega preguntas aleatorias por categoría.
  """

  @questions_file "data/questions.json"

  # Cargar categorías disponibles
  def load_categories do
    with {:ok, data} <- File.read(@questions_file),
         {:ok, categories} <- Jason.decode(data) do
      Map.keys(categories)
    else
      _ -> []
    end
  end

  # Obtener preguntas aleatorias por categoría
  def get_random_questions(category, num) do
    case File.read(@questions_file) do
      {:ok, data} ->
        with {:ok, decoded} <- Jason.decode(data),
             questions when is_list(questions) <- Map.get(decoded, category) do
          Enum.take_random(questions, num)
        else
          _ -> []
        end

      _ -> []
    end
  end
end
