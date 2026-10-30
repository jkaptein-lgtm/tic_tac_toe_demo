Dit is deel 2 van deze serie waarin ik je meeneem in het bouwen van boter, kaas en eieren in Elixir Phoenix. In het [vorige deel](TODO linken) beschreef ik hoe je LiveView gebruikt om een versie van het spel te maken waarbij beide spelers op hetzelfde scherm spelen. In dit deel bouwen we het uit naar een online multiplayerversie. In het 3e deel beschrijven we hoe je meerdere games op 1 server kan laten draaien.

Om via meerdere devices te kunnen spelen, maken we gebruik van 2 soorten processen: de game server, waarop het spel draait, en clients. De clients zijn in ons geval de LiveView processen.

We implementeren:

- Het verbinden met het spel
- Het uitvoeren van beurten
- De verbinding verbreken.

We beginnen met het bouwen van een GenServer rond de `Game` module. Een GenServer is een Elixir-proces dat gebruikt kan worden om bijvoorbeeld staat op te slaan. In dit geval zouden we dat ook in het LiveView-proces kunnen doen, zoals we dat ook deden bij de lokale versie. Het voordeel van het gebruik van een apart GenServer-proces is dat we 2 duidelijke rollen hebben: 1 server waar het spel op draait, en 2 spelers die hun beurten spelen. Ook is het verbinden met deze GenServer makkelijker dan wanneer we 2 willekeurige LiveView processen zouden moeten koppelen.

Een GenServer werkt op basis van Erlangs `messages`. We gaan dus berichten sturen van en naar de server. GenServer is een `behaviour` met de volgende functies die helpen bij het verwerken van berichten:

- `init`, die de server initialiseert als die opstart
- `handle_call`, voor berichten waarop degene die het aanroept direct een antwoord verwacht (synchroon)
- `handle_cast`, voor berichten waarop niet direct een antwoord wordt verwacht. (asynchroon)

We beginnen met het toevoegen van de module, met daarin de init functie. In de init functie maken we de data aan die we bij gaan houden:

- `players`: een nu nog lege lijst waarin we de processen bijhouden van de spelers
- `board`: het bord waarop gespeeld wordt.

```elixir
defmodule TicTacToe.GameServer do
    use GenServer

    alias TicTacToe.Game

    @impl true
    def init(_) do
        {:ok, %{players: [], board: Game.empty_board()}}
    end
end
```

Vervolgens voegen we dit proces toe aan de processen die altijd draaien binnen de applicatie. Daarvoor maken we een functie aan waarmee je vertelt hoe je het proces start. Hierin roepen we de `GenServer.start_link` functie aan:

```elixir
defmodule TicTacToe.GameServer do
    ...
    def start_link(opts \\ Keyword.new()) do
        GenServer.start_link(__MODULE__, :ok, opts)
    end
    ...
end
```

In application.ex:

```diff
...
   def start(_type, _args) do
     children = [
       TicTacToeWeb.Telemetry,
       {DNSCluster, query: Application.get_env(:tic_tac_toe,  :dns_cluster_query) || :ignore},
       {Phoenix.PubSub, name: TicTacToe.PubSub},
       # Start a worker by calling: TicTacToe.Worker.start_link(arg)
       # {TicTacToe.Worker, arg},
       # Start to serve requests, typically the last entry
       TicTacToeWeb.Endpoint,
+      {TicTacToe.GameServer, name: TicTacToe.GameServer}
    ]
...
```

Nu kunnen we een bericht toevoegen om je als speler aan een spel toe te voegen. Omdat we hier een antwoord terug willen krijgen, gebruiken we `handle_call`. `handle_call` heeft 3 argumenten: het bericht, informatie over degene die het bericht stuurde, en de huidige staat. `handle_call` geeft vervolgens een bericht terug in de vorm `{:reply, <antwoord>, <nieuwe staat>}`.

Als er 1 of 0 spelers in onze lijst spelers staan, voegen we het proces-id (PID) van degene die het bericht heeft gestuurd toe aan de lijst met spelers. Aan degene die de functie heeft aangeroepen, geven we de nieuwe status terug (`:waiting`), en het symbool dat we die speler hebben toegewezen (`:x` of `:o`). Ook slaan we de nieuwe staat op. Als er al 2 spelers zijn geregistreerd, geven we een foutmelding terug, die aangeeft dat het spel al vol zit.

Als je met een GenServer werkt, is het vaak makkelijk om voor ieder bericht ook een functie toe te voegen die het bericht stuurt. Zo is het voor de ontwikkelaar van de client makkelijk te zien welke berichten er allemaal te sturen zijn.

```elixir

  def join() do
    GenServer.call(__MODULE__, :join)
  end


  defp pid_to_symbol(players, pid) do
    if hd(players) == pid, do: :x, else: :o
  end


  def handle_call(:join, {pid, _}, state) do
    case state.players do
      [x_pid] ->
        state = %{state | players: [x_pid, pid]}
        {:reply, {:ok, %{status: :waiting, my_symbol: pid_to_symbol(state.players, pid)}}, state}

      [] ->
        state = %{state | players: [pid]}
        {:reply, {:ok, %{status: :waiting, my_symbol: pid_to_symbol(state.players, pid)}}, state}

      _ ->
        {:reply, {:error, :game_full}, state}
    end
  end
```

In de LiveView-applicatie kunnen we nu gaan verbinden met de server.

We maken een nieuwe functie `connect/1` aan, die de `GameServer.join/0` functie aanroept, en op basis daarvan de huidige status en het symbool van de huidige speler toevoegt aan de assigns. Als we een foutmelding terugkrijgen, laten we de speler weten dat er al 2 spelers bezig zijn, en hij dus niet meer mee kan doen. Dat is een belangrijke limitatie van hoe we het nu opzetten: de server draait maar 1 spel tegelijk. In deel 3 van deze serie kijken we naar hoe we onbeperkt nieuwe games aan kunnen maken.

```elixir
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
```

Om deze functie op de juiste manier aan te roepen, moeten we iets verder in de `mount/3` functie van onze LiveView-applicatie duiken. De mount functie wordt twee keer aangeroepen: de eerste keer als de pagina voor de eerste keer getoond wordt. Op dat moment hebben we nog geen proces waaraan we dingen kunnen koppelen. De tweede keer dat dit gebeurt, draait er een proces dat via WebSockets communiceert met de pagina in de browser, en kunnen we dus de verbinding gaan leggen door deze functie aan te roepen. We kunnen zien of we aan het proces gekoppeld zijn met behulp van `connected?/1`. Omdat we de status nu hier direct zetten, kunnen we de afleiding die in de render functie stond nu verwijderen.

```diff
 @impl true
 def mount(_params, _session, socket) do
     socket =
     socket
     |> assign_new(:board, fn -> Game.empty_board() end)
+    |> assign_new(:status, fn -> :connecting end)

+ socket =
+     if not connected?(socket) do
+        socket
+     else
+        connect(socket)
+     end

 {:ok, socket}
 end
...
 @impl true
def render(assigns) do

-     assigns =
-      assigns
-      |> assign(
-        :status,
-        Game.result(assigns.board) || {:taking_turn, Game.active_player(assigns.board)}
-      )

     ~H"""
     ...
     """
 end
...
```

Doordat iedereen nu zijn eigen scherm heeft, worden de berichten die we aan de gebruiker tonen ook anders:

```diff
...
+  defp message(:other_turn), do: "The other player is thinking"
+  defp message(:your_turn), do: "It's your turn!"
+  defp message(:connecting), do: "Establishing websocket connection"
+  defp message(:waiting), do: "Waiting for other player"
+  defp message(:you_won), do: "You won!"
+  defp message(:you_lost), do: "You lost!"
+  defp message(:draw), do: "It's a draw!"
-  defp message({:taking_turn, player}),
-    do: "#{player |> Atom.to_string() |> String.upcase()}'s turn"

- defp message({:win, player}), do: "Winner: #{player |> Atom.to_string() |> String.upcase()}"
- defp message(:draw), do: "Draw!"
```

Draai de applicatie met `mix phx.server`, en ga naar `localhost:4000` in drie verschillende tabbladen. De eerste twee zullen blijven hangen in de status "Waiting for other player". In het derde tabblad krijg je een foutmelding, omdat er geen ruimte meer is.

We maken een nieuwe functie om aan de spelers door te geven dat de andere speler er is, en het spel kan starten. Hiervoor werken we in tegengestelde richting: in plaats van de client die een bericht stuurt naar de server, stuurt de server een bericht naar de client. We gebruiken hiervoor de `send/2` functie; deze functie stuurt een bericht naar het gegeven PID.

```elixir
 defp activate_players(%{players: [x_pid, o_pid], board: board} = state) do

    {active, waiting} =
      case Game.active_player(board) do
        :x -> {x_pid, o_pid}
        :o -> {o_pid, x_pid}
      end

    send(active, {:progress, %{status: :your_turn, board: board}})
    send(waiting, {:progress, %{status: :other_turn, board: board}})

    state
  end
```

We roepen deze functie aan zodra de tweede speler zich aan het spel heeft toegevoegd:

```diff
 def handle_call(:join, {pid, _}, state) do
   case state.players do
   [x_pid] ->
+    state = %{state | players: [x_pid, pid]} |> activate_players()
-    state = %{state | players: [x_pid, pid]}
```

Voordat we hier iets van merken, moeten we in de LiveView-client bepalen hoe we op het bericht reageren:

```elixir
  @impl true
  def handle_info({:progress, %{status: status, board: board}}, socket) do
    socket =
      socket
      |> assign(:board, board)
      |> assign(:status, status)

    {:noreply, socket}
  end

```

Vervolgens passen we ook de logica aan die bepaalt of een veld aan te klikken is, zodat alleen de actieve gebruiker de knoppen in kan drukken:

```diff
 defp board(assigns) do
...
 ~H"""
 ...

- disabled={not match?({:taking_turn, _}, @status) or not is_nil(Enum.at(@board, idx))}
+ disabled={not (@status == :your_turn) or not is_nil(Enum.at(@board, idx))}
```

Omdat we nog niets hebben gedaan met het verbreken van de verbinding met de server, moet je de server voor nu opnieuw opstarten met `ctrl+c, a, mix phx.server`. Doe dit en open `localhost:4000` opnieuw in twee tabbladen: zodra je in beide tabbladen verbonden bent, zie je in het ene de status "It's your turn!" en in het andere de status "The other player is thinking".

Om de beurten goed te verwerken, passen we de event handler voor het "choose" event aan. In plaats van direct de Game module aan te roepen, roepen we de GameServer aan. Zoals je ziet blijft de structuur vrijwel hetzelfde, maar we moeten wel rekening houden met de extra foutmelding die kan ontstaan doordat de gebruiker op het verkeerde moment een keuze maakt.

```diff
 @impl true
   def handle_event("choose", params, socket) do
     choice = params["index"] |> String.to_integer()

     socket =
-      case Game.choose(socket.assigns.board, choice) do
+      case GameServer.choose(choice) do
-        :error -> socket |> put_flash(:error, "That location is already taken!")
+        {:error, error} ->
+          message =
+            case error do
+              :already_token -> "That location is already taken!"
+              :not_your_turn -> "It's not your turn!"
+            end
+
+          socket |> put_flash(:error, message)
+
-        {:ok, board} -> socket |> assign(:board, board)
+        {:ok, %{board: board}} ->
+          socket |> assign(:board, board)
      end

    {:noreply, socket}
  end

```

We moeten dit bericht natuurlijk ook goed verwerken in de server. We maken daarbij weer gebruik van de `Game.choose/2` functie die we net hebben vervangen aan de kant van de client. De `activate_players/1` functie die we eerder gebruikten, stuurt een berichtje naar beide spelers, zodat ze allebei weten wat de nieuwe staat van het bord is, en wie er aan de beurt is.

```elixir
  def choose(location) do
    GenServer.call(__MODULE__, {:choose, location})
  end
  ...
  def handle_call({:choose, position}, {pid, _}, state) do
    player_symbol = pid_to_symbol(state.players, pid)
    active_player = Game.active_player(state.board)

    if player_symbol != active_player do
      {:reply, {:error, :not_your_turn}, state}
    else
      case Game.choose(state.board, position) do
        {:ok, board} ->
          state = state |> Map.put(:board, board) |> Map.put(:status, :other_turn)

          activate_players(state)

          {:reply, {:ok, state}, state}

        :error ->
          {:reply, {:error, :already_token}, state}
      end
    end
  end
```

Start de server opnieuw op, en probeer een potje te spelen tussen twee tabbladen: de beurten wisselen nu netjes, en de status van het bord wordt na iedere beurt doorgestuurd naar de andere gebruiker.

We doen nu nog niets als het spel afgelopen is. We moeten hier goed opletten dat we het juiste bericht naar de juiste gebruiker sturen: als er een winnaar is, krijgt die een ander resultaat te zien dan de verliezer.

```elixir
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
```

Waar we eerst direct de beurt doorgaven, moeten we nu kijken of we een winnaar hebben; als dat niet zo is, geven we de beurt door, en anders sturen we het resultaat naar beide spelers:

```diff
 def handle_call({:choose, position}, {pid, _}, state) do
 ...
-          activate_players(state)
+          state =
+            case Game.result(board) do
+              nil -> activate_players(state)
+              result -> announce_result(state, result)
+            end
 ...
 end
```

Omdat we eerder alle status-berichten al hadden ingevoerd, werkt het spel nu van begin tot eind!

Er is nog één knop die niet werkt: de "Restart"-knop roept nog direct de `Game` module aan. We maken hiervoor een nieuwe functie aan in de GameServer, met twee functiedefinities: als we precies 2 spelers hebben, kunnen we de reset uitvoeren. Anders doen we niets.

```elixir
  def restart() do
    GenServer.cast(__MODULE__, :restart)
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

```

Vervolgens kunnen we vanuit de LiveView het nieuwe bericht sturen:

```diff
  def handle_event("restart", _params, socket) do
-    socket = assign(socket, :board, Game.empty_board())
-
+    GameServer.restart()
     {:noreply, socket}
  end

```

We hebben al een paar keer gemerkt dat zoals het nu staat, 2 gebruikers altijd hun plekje in het spel in bezit houden. Dat is natuurlijk niet de bedoeling. Als iemand de pagina sluit, willen we dat de verbinding wordt verbroken, en iemand anders het plekje in kan nemen.

LiveView heeft de `terminate` functie, die automatisch wordt aangeroepen als de verbinding met de pagina verbroken wordt. In de server voegen we een nieuw bericht `:disconnect` toe, waarbij we de speler die het bericht verstuurde uit de lijst spelers halen. De andere speler sturen we een bericht om aan te geven dat hij of zij op een nieuw spel wacht:

```elixir

def disconnect() do
  GenServer.cast(__MODULE__, {:disconnect, self()})
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
        %{status: :waiting, board: state.board, my_symbol: pid_to_symbol(state.players, player)}}
    )
  end)

  {:noreply, state}
end
```

In de LiveView roepen we deze functie aan in de `terminate` callback, en verwerken we het `:new_game` bericht dat de overgebleven speler ontvangt:

```elixir
@impl true
def terminate(_, _) do
  GameServer.disconnect()
end

@impl true
def handle_info({:new_game, %{status: status, board: board, my_symbol: symbol}}, socket) do
  socket =
    socket
    |> assign(:board, board)
    |> assign(:status, status)
    |> assign(:my_symbol, symbol)

  {:noreply, socket}
end
```

Probeer het uit: open `localhost:4000` in twee tabbladen, en sluit vervolgens een van de twee. Het andere tabblad komt weer in de status "Waiting for other player".

We hebben nu een volledig werkende versie van boter, kaas en eieren die door twee spelers op verschillende devices gespeeld kan worden. Zoals je hebt gemerkt is het in Elixir heel makkelijk om staat te delen tussen verschillende processen met behulp van de `GenServer` behaviour. 

Je kunt berichten asynchroon sturen met `cast`, en synchroon met `call`. Naast de functies die berichten verwerken, schrijf je vaak ook een setje functies waarmee je die berichten stuurt. Berichten hoeven niet alleen van de `GenServer` naar de client toe te gaan; in Elixir kunnen alle processen berichten sturen en ontvangen, waardoor onze LiveView clients continu door de server op de hoogte gebracht konden worden van updates.

Ons spel heeft nog 1 grote limitatie: momenteel kan er maar 1 spel gespeeld worden op de server. In het volgende deel van deze serie bespreken we hoe we de applicatie kunnen schalen naar meerdere spellen op 1 server.