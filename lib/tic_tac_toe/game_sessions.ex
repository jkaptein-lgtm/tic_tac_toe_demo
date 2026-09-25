defmodule TicTacToe.GameSessions do
  @moduledoc """
  Context module for managing game sessions.
  Provides functions to create and join game sessions.
  """

  alias TicTacToe.GameRegistry
  alias TicTacToe.GameSessionSupervisor

  @doc """
  Creates a new game session with a randomly generated ID.
  Returns {:ok, session_id} or {:error, reason}
  """
  def create_session do
    session_id = generate_session_id()

    case GameSessionSupervisor.start_game_session(session_id) do
      {:ok, _pid} -> {:ok, session_id}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Finds or creates a game session.
  If session_id is nil, creates a new session.
  If session_id exists, returns it.
  If session_id doesn't exist, returns error.
  """
  def find_or_create_session(nil), do: create_session()

  def find_or_create_session(session_id) do
    case GameRegistry.lookup(session_id) do
      {:ok, _pid} -> {:ok, session_id}
      {:error, :not_found} -> {:error, :session_not_found}
    end
  end

  @doc """
  Calls a function on a specific game session.
  Returns the result of the GenServer call or {:error, :session_not_found}
  """
  def call(session_id, message) do
    case GameRegistry.lookup(session_id) do
      {:ok, pid} -> GenServer.call(pid, message)
      {:error, :not_found} -> {:error, :session_not_found}
    end
  end

  @doc """
  Sends a cast to a specific game session.
  """
  def cast(session_id, message) do
    case GameRegistry.lookup(session_id) do
      {:ok, pid} -> GenServer.cast(pid, message)
      {:error, :not_found} -> {:error, :session_not_found}
    end
  end

  # Generates a memorable 3-word session ID
  defp generate_session_id do
    MnemonicSlugs.generate_slug(3)
  end
end
