defmodule TicTacToeWeb.GameLive do
  use TicTacToeWeb, :live_view

  alias TicTacToe.Game

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_new(:board, fn -> Game.empty_board() end)

    {:ok, socket}
  end

  @impl true
  def handle_event("choose", params, socket) do
    choice = params["index"] |> String.to_integer()

    socket =
      case Game.choose(socket.assigns.board, choice) do
        :error -> socket |> put_flash(:error, "That location is already taken!")
        {:ok, board} -> socket |> assign(:board, board)
      end

    {:noreply, socket}
  end

  def handle_event("restart", _params, socket) do
    socket = assign(socket, :board, Game.empty_board())

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        :status,
        Game.result?(assigns.board) || {:taking_turn, Game.active_player(assigns.board)}
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <.status status={@status} />
      <%= if is_list(assigns.board) do %>
        <.board board={@board} status={@status} />
      <% end %>
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
                  disabled={
                    not match?({:taking_turn, _}, @status) or not is_nil(Enum.at(@board, idx))
                  }
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

  defp message({:taking_turn, player}),
    do: "#{player |> Atom.to_string() |> String.upcase()}'s turn"

  defp message({:win, player}), do: "Winner: #{player |> Atom.to_string() |> String.upcase()}"
  defp message(:draw), do: "Draw!"

  defp cell_label(nil), do: ""
  defp cell_label(player) when is_atom(player), do: player |> Atom.to_string() |> String.upcase()
end
