defmodule TicTacToe.GameRegistry do
  @moduledoc """
  Registry for tracking game sessions.
  Each game session is registered by its session_id.
  """

  def child_spec(_) do
    Registry.child_spec(
      keys: :unique,
      name: __MODULE__
    )
  end

  @doc """
  Returns the via tuple for a game session
  """
  def via(session_id) do
    {:via, Registry, {__MODULE__, session_id}}
  end

  @doc """
  Looks up a game session by ID
  """
  def lookup(session_id) do
    case Registry.lookup(__MODULE__, session_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
end
