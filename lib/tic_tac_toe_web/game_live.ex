defmodule TicTacToeWeb.GameLive do
  use TicTacToeWeb, :live_view

  alias TicTacToe.Game
  alias TicTacToe.GameServer
  alias TicTacToe.GameSessions

  defp connect(socket, session_id) do
    case GameServer.join(session_id) do
      {:error, :session_not_found} ->
        socket
        |> put_flash(:error, "Game session not found")
        |> redirect(to: ~p"/")

      {:error, _} ->
        socket |> put_flash(:error, "Game is full")

      {:ok, %{status: status, my_symbol: my_symbol}} ->
        socket
        |> assign(:status, status)
        |> assign(:my_symbol, my_symbol)
    end
  end

  @impl true
  def mount(%{"session_id" => session_id}, _session, socket) do
    socket =
      socket
      |> assign_new(:board, fn -> Game.empty_board() end)
      |> assign_new(:status, fn -> :connecting end)
      |> assign(:session_id, session_id)

    socket =
      if not connected?(socket) do
        socket
      else
        # Verify session exists
        case GameSessions.find_or_create_session(session_id) do
          {:ok, ^session_id} -> connect(socket, session_id)
          {:error, :session_not_found} ->
            socket
            |> put_flash(:error, "Game session not found")
            |> redirect(to: ~p"/")
        end
      end

    {:ok, socket}
  end

  def mount(_params, _session, socket) do
    # No session_id provided, redirect to create a new session
    case GameSessions.create_session() do
      {:ok, session_id} ->
        {:ok, push_navigate(socket, to: ~p"/game/#{session_id}")}

      {:error, _} ->
        socket =
          socket
          |> put_flash(:error, "Failed to create game session")
          |> assign(:status, :error)

        {:ok, socket}
    end
  end

  @impl true
  def terminate(_, %{assigns: %{session_id: session_id}}) do
    GameServer.disconnect(session_id)
  end

  def terminate(_, _), do: :ok

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
      case GameServer.choose(socket.assigns.session_id, choice) do
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
    GameServer.restart(socket.assigns.session_id)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :game_over?, game_over?(assigns.status))

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

  # Check if the game is over
  defp game_over?(status) when status in [:you_won, :you_lost, :draw], do: true
  defp game_over?(_), do: false

end
