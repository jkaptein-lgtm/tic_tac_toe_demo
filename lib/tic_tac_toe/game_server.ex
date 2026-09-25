defmodule TicTacToe.GameServer do
  @moduledoc """
  Runs a game of tic tac toe

  Clients are expected to handle the following messages:
  {:progress, %{status: :you_lost | :you_won | :draw | :waiting | :your_turn | :other_turn, board: List(:o | :x | nil)}}
  {:new_game, %{status: :waiting, board: List(:o | :x | nil), my_symbol: :x | :o }}

  """

  use GenServer

  alias TicTacToe.Game

  alias TicTacToe.GameRegistry

  # Client
  def join(session_id) do
    GenServer.call(GameRegistry.via(session_id), :join)
  end

  def choose(session_id, location) do
    GenServer.call(GameRegistry.via(session_id), {:choose, location})
  end

  def restart(session_id) do
    GenServer.cast(GameRegistry.via(session_id), :restart)
  end

  def start_link(session_id) do
    GenServer.start_link(__MODULE__, session_id, name: GameRegistry.via(session_id))
  end

  def disconnect(session_id) do
    GenServer.cast(GameRegistry.via(session_id), {:disconnect, self()})
  end

  @impl true
  def init(session_id) do
    {:ok, %{session_id: session_id, players: [], board: [nil, nil, nil, nil, nil, nil, nil, nil, nil]}}
  end

  defp pid_to_symbol(players, pid) do
    if hd(players) == pid, do: :x, else: :o
  end

  defp activate_players(%{players: [x_pid, o_pid], board: board} = state) do
    IO.inspect(board, label: "board when activating players")

    {active, waiting} =
      case Game.active_player(board) do
        :x -> {x_pid, o_pid}
        :o -> {o_pid, x_pid}
      end

    send(active, {:progress, %{status: :your_turn, board: board}})
    send(waiting, {:progress, %{status: :other_turn, board: board}})

    state
  end

  defp announce_result(%{players: [x_pid, o_pid]} = state, result) do
    case result do
      :draw ->
        state.players
        |> Enum.each(&send(&1, {:progress, %{status: :draw, board: state.board}}))

      {:win, winner} ->
        {winner, loser} =
          case winner do
            :x -> {x_pid, o_pid}
            :o -> {o_pid, x_pid}
          end

        send(loser, {:progress, %{status: :you_lost, board: state.board}})
        send(winner, {:progress, %{status: :you_won, board: state.board}})
    end

    state
  end

  @impl true
  def handle_call({:choose, position}, {pid, _}, state) do
    player_symbol = pid_to_symbol(state.players, pid)
    active_player = Game.active_player(state.board)

    if player_symbol != active_player do
      {:reply, {:error, :not_your_turn}, state}
    else
      case Game.choose(state.board, position) do
        {:ok, board} ->
          state = state |> Map.put(:board, board) |> Map.put(:status, :other_turn)

          state =
            case Game.result?(board) do
              nil -> activate_players(state)
              result -> announce_result(state, result)
            end

          {:reply, {:ok, state}, state}

        :error ->
          {:reply, {:error, :already_chosen}, state}
      end
    end
  end

  def handle_call(:join, {pid, _}, state) do
    case state.players do
      [x_pid] ->
        state = %{state | players: [x_pid, pid]} |> activate_players()
        {:reply, {:ok, %{status: :waiting, my_symbol: pid_to_symbol(state.players, pid)}}, state}

      [] ->
        state = %{state | players: [pid]}
        {:reply, {:ok, %{status: :waiting, my_symbol: pid_to_symbol(state.players, pid)}}, state}

      _ ->
        {:reply, {:error, :game_full}, state}
    end
  end

  def handle_cast({:disconnect, pid}, state) do
    state =
      state
      |> Map.merge(%{
        players: state.players |> Enum.reject(fn player_pid -> player_pid == pid end),
        board: Game.empty_board()
      })

    state.players
    |> Enum.each(fn player ->
      send(
        player,
        {:new_game,
         %{status: :waiting, board: state.board, my_symbol: pid_to_symbol(state.players, pid)}}
      )
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast(:restart, %{players: [_, _]} = state) do
    state =
      state
      |> Map.put(:board, Game.empty_board())
      |> activate_players()

    {:noreply, state}
  end

  def handle_cast(:restart, state) do
    {:noreply, state}
  end
end
