defmodule Trivia.Lobby do
  @moduledoc """
  Representa una partida multijugador.
  Cada lobby es un proceso GenServer que mantiene jugadores, preguntas y puntajes.

  Cambios principales:
  - Registra cada lobby globalmente con {:global, {:lobby, id}} para que sea accesible
    desde otros nodos conectados (Node.connect/1).
  - Evita crashes al intentar acceder a un lobby inexistente: las APIs públicas comprueban
    existencia antes de hacer GenServer.call/cast.
  """

  use GenServer
  alias Trivia.{QuestionBank, UserManager, History}

  @max_players 4

  # ===============================
  # API pública
  # ===============================

  # start_link registra el GenServer con nombre global {:global, {:lobby, id}}
  def start_link(%{id: id} = args) do
    name = {:global, {:lobby, id}}
    GenServer.start_link(__MODULE__, args, name: name)
  end

  # Helper para obtener el "via" que usamos internamente
  defp via_tuple(id), do: {:global, {:lobby, id}}

  defp lookup(id) do
    case :global.whereis_name({:lobby, id}) do
      :undefined -> :undefined
      pid when is_pid(pid) -> pid
    end
  end

  def create_game(id, owner, category, num, time) do
    args = %{id: id, owner: owner, category: category, num: num, time: time}
    DynamicSupervisor.start_child(Trivia.Server, {__MODULE__, args})
  end

  # join_game ahora comprueba con :global.whereis_name para evitar crashes si no existe
  def join_game(id, username, caller) do
    case lookup(id) do
      :undefined ->
        {:error, :not_found}

      _pid ->
        GenServer.call(via_tuple(id), {:join, username, caller})
    end
  end

  # start_game: comprobar existencia antes de cast
  def start_game(id) do
    case lookup(id) do
      :undefined -> {:error, :not_found}
      _ -> GenServer.cast(via_tuple(id), :start)
    end
  end

  # answer: comprobar existencia
  def answer(id, username, ans) do
    case lookup(id) do
      :undefined -> {:error, :not_found}
      _ -> GenServer.cast(via_tuple(id), {:answer, username, ans})
    end
  end

  # get_info: comprobar existencia y devolver error si no existe
  def get_info(id) do
    case lookup(id) do
      :undefined -> {:error, :not_found}
      _ -> GenServer.call(via_tuple(id), :info)
    end
  end

  # ===============================
  # GenServer callbacks
  # ===============================

  @impl true
  def init(%{id: id, owner: owner, category: category, num: num, time: time}) do
    IO.puts("🎮 Partida #{id} creada por #{owner}. Esperando jugadores...")

    questions = QuestionBank.get_random_questions(category, num)

    {:ok,
     %{
       id: id,
       owner: owner,
       category: category,
       num: num,
       time: time,
       players: %{owner => %{pid: nil, score: 0}},
       questions: questions,
       current_q: nil,
       timer_ref: nil,
       started: false
     }}
  end

  @impl true
  def handle_call({:join, username, caller}, _from, state) do
    cond do
      state.started ->
        {:reply, {:error, :already_started}, state}

      map_size(state.players) >= @max_players ->
        {:reply, {:error, :full}, state}

      Map.has_key?(state.players, username) ->
        {:reply, {:error, :already_joined}, state}

      true ->
        IO.puts("➕ #{username} se unió a la partida #{state.id}")
        {:reply, {:ok, "Unido correctamente"},
         %{state | players: Map.put(state.players, username, %{pid: caller, score: 0})}}
    end
  end

  @impl true
  def handle_call(:info, _from, state) do
    {:reply,
     %{
       id: state.id,
       jugadores: Map.keys(state.players),
       started: state.started,
       category: state.category
     }, state}
  end

  @impl true
  def handle_cast(:start, %{started: false} = state) do
    IO.puts("🚀 Iniciando partida #{state.id} con jugadores: #{Enum.join(Map.keys(state.players), ", ")}")

    Process.send_after(self(), :next_question, 500)

    {:noreply, %{state | started: true}}
  end

  @impl true
  def handle_cast({:answer, username, ans}, state) do
    %{current_q: q} = state

    if q && Map.has_key?(state.players, username) do
      correct = String.downcase(ans) == String.downcase(q["answer"])
      delta = if correct, do: 10, else: -5

      updated_players =
        Map.update!(state.players, username, fn p ->
          %{p | score: p.score + delta}
        end)

      send_message_to_all(updated_players, "#{username} respondió #{if correct, do: "✅ Correcto", else: "❌ Incorrecto"} (#{delta} pts)")
      {:noreply, %{state | players: updated_players}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:next_question, %{questions: [q | rest]} = state) do
    send_message_to_all(state.players, "\n❓ #{q["question"]}")
    Enum.each(q["options"], fn {k, v} -> send_message_to_all(state.players, "#{k}. #{v}") end)

    Process.send_after(self(), :timeout, state.time * 1000)
    {:noreply, %{state | current_q: q, questions: rest}}
  end

  def handle_info(:timeout, %{questions: []} = state) do
    send_message_to_all(state.players, "🏁 Fin de la partida!")

    Enum.each(state.players, fn {username, %{score: s}} ->
      UserManager.update_score(username, s)
      History.save_result(username, state.category, s)
    end)

    {:stop, :normal, state}
  end

  def handle_info(:timeout, state) do
    send_message_to_all(state.players, "⏰ Tiempo agotado! Siguiente pregunta...")
    Process.send_after(self(), :next_question, 2000)
    {:noreply, %{state | current_q: nil}}
  end

  defp send_message_to_all(players, msg) do
    Enum.each(players, fn {_user, %{pid: pid}} ->
      # Si el pid es remoto o local, send/2 funcionará siempre que el PID sea válido y el nodo esté conectado.
      if pid && is_pid(pid) do
        send(pid, {:game_message, msg})
      end
    end)
  end
end
