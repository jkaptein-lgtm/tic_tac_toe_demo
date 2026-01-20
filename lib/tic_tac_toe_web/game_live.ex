defmodule TicTacToeWeb.GameLive do
  use TicTacToeWeb, :live_view

  alias TicTacToe.Game
  alias TicTacToe.GameServer

  defp connect(socket) do
    case GameServer.join() do
      {:error, _} ->
        socket |> put_flash(:error, "Game is full")

      {:ok, %{status: status, my_symbol: my_symbol}} ->
        socket
        |> assign(:status, status)
        |> assign(:my_symbol, my_symbol)
    end
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_new(:board, fn -> Game.empty_board() end)
      |> assign_new(:status, fn -> :connecting end)

    socket =
      if not connected?(socket) do
        socket
      else
        connect(socket)
      end

    {:ok, socket}
  end

  @impl true
  def terminate(_, _) do
    GameServer.disconnect()
  end

  @impl true
  def handle_info({:progress, %{status: status, board: board}}, socket) do
    socket =
      socket
      |> assign(:board, board)
      |> assign(:status, status)

    IO.inspect(board, label: "received board")

    {:noreply, socket}
  end

  def handle_info({:new_game, %{status: status, board: board, my_symbol: symbol}}, socket) do
    socket =
      socket
      |> assign(:board, board)
      |> assign(:status, status)
      |> assign(:my_symbol, symbol)

    {:noreply, socket}
  end

  @impl true
  def handle_event("choose", params, socket) do
    choice = params["index"] |> String.to_integer()

    socket =
      case GameServer.choose(choice) do
        {:error, error} ->
          message =
            case error do
              :already_token -> "That location is already taken"
              :not_your_turn -> "It's not your turn!"
            end

          socket |> put_flash(:error, message)

        {:ok, %{board: board}} ->
          socket |> assign(:board, board)
      end

    {:noreply, socket}
  end

  def handle_event("restart", _params, socket) do
    GameServer.restart()
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.status status={@status} />
      <.board if:{@board} board={@board} status={@status} />
      <button
        type="button"
        class="btn"
        phx-click="restart"
      >
        restart
      </button>
    </Layouts.app>
    """
  end

  defp board(assigns) do
    assigns =
      assigns
      |> assign(:active_player, Game.active_player(assigns.board))

    ~H"""
    <table class="w-full table-fixed border-separate border-spacing-2">
      <tbody>
        <%= for row <- 0..2 do %>
          <tr>
            <%= for col <- 0..2 do %>
              <% idx = 3 * row + col %>
              <td class="aspect-square">
                <button
                  type="button"
                  phx-click="choose"
                  class="btn"
                  phx-value-index={idx}
                  disabled={not (@status == :your_turn) or not is_nil(Enum.at(@board, idx))}
                >
                  {cell_label(Enum.at(@board, idx) || @active_player)}
                </button>
              </td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>
    """
  end

  defp status(assigns) do
    ~H"""
    <div class="mt-4 text-center text-lg font-semibold">
      {message(@status)}
    </div>
    """
  end

  defp message(:other_turn), do: "The other player is thinking"
  defp message(:your_turn), do: "It's your turn!"
  defp message(:connecting), do: "Establishing websocket connection"
  defp message(:waiting), do: "Waiting for other player"
  defp message(:you_won), do: "You won!"
  defp message(:you_lost), do: "You loose!"
  defp message(:draw), do: "It's a draw "

  defp cell_label(nil), do: ""
  defp cell_label(player) when is_atom(player), do: player |> Atom.to_string() |> String.upcase()
end
