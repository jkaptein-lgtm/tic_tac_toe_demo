defmodule TicTacToe.Game do
  @moduledoc """
  Contains the core game logic for the TicTacToe game.
  """

  @doc """
  Creates an empty board to play the game on

  ## Examples

      iex> empty_board()
      [
        nil, nil, nil,
        nil, nil, nil,
        nil, nil, nil
      ]
  """
  def empty_board do
    for _row <- 0..8, do: nil
  end

  @doc """
  returns the outcome of the game if the game is decided, otherwise returns nil

  ## Examples

      iex> result?([
      ...>   :x, :x, :x,
      ...>   :o, nil, nil,
      ...>   :o, :o, nil
      ...> ])
      {:win, :x}

      iex> result?(empty_board())
      nil

      iex> result?([
      ...>   :x, :o, :x,
      ...>   :x, :x, :o,
      ...>   :o, :x, :o
      ...> ])
      :draw
  """
  def result?(board) do
    case winner?(board) do
      nil ->
        if Enum.all?(board) do
          :draw
        else
          nil
        end

      winner ->
        {:win, winner}
    end
  end

  defp winner?(board) do
    cols = board |> Enum.chunk_every(3)
    r1 = board |> Enum.take_every(3)
    r2 = board |> Enum.drop(1) |> Enum.take_every(3)
    r3 = board |> Enum.drop(2) |> Enum.take_every(3)
    diag1 = [board |> Enum.at(0), board |> Enum.at(4), board |> Enum.at(8)]
    diag2 = [board |> Enum.at(2), board |> Enum.at(4), board |> Enum.at(6)]

    lines =
      cols ++
        [
          r1,
          r2,
          r3,
          diag1,
          diag2
        ]

    Enum.find_value(lines, fn
      [:x, :x, :x] -> :x
      [:o, :o, :o] -> :o
      _ -> nil
    end)
  end

  @doc """
  Claims a position for the player at play

  ## Examples

      iex> board = [
      ...>   :x, :x, nil,
      ...>   :o, nil, nil,
      ...>   :o, :o, nil
      ...> ]
      iex> board |> choose(2)
      {:ok, [
        :x, :x, :x,
        :o, nil, nil,
        :o, :o, nil
      ]}
      iex> board |> choose(3)
      :error
  """
  def choose(board, choice) do
    case Enum.at(board, choice) do
      nil -> {:ok, List.update_at(board, choice, fn _ -> active_player(board) end)}
      _ -> :error
    end
  end

  @doc """
  Returns the player that's currently at play; :x always starts

  ## Examples

      iex> active_player(empty_board())
      :x

      iex> board = [
      ...>   :x, :x, nil,
      ...>   :o, :x, :x,
      ...>   :o, :o, nil
      ...> ]
      iex> active_player(board)
      :o

  """
  def active_player(board) do
    xs = Enum.count(board, fn v -> v == :x end)
    os = Enum.count(board, fn v -> v == :o end)

    if xs > os do
      :o
    else
      :x
    end
  end
end
