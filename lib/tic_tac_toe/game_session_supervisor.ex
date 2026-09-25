defmodule TicTacToe.GameSessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing individual game sessions.
  Spawns and supervises GameServer processes for each game.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new game session with the given session_id
  """
  def start_game_session(session_id) do
    child_spec = %{
      id: TicTacToe.GameServer,
      start: {TicTacToe.GameServer, :start_link, [session_id]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
