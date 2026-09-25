Dit is deel 2 van deze serie waarin ik je meeneem in het bouwen van boter, kaas en eieren in Elixir Phoenix. In het [vorige deel](TODO linken) Beschreef ik hoe je LiveView gebruikt om een versie van het spel te maken waarbij beide spelers op hetzelfde scherm spelen. In dit deel bouwen we het uit naar een online multiplayer versie. In het 3e deel zullen beschrijven we hoe je meerdere games op 1 server kan laten draaien.

Om via meerdere devices te kunnen spelen, maken we gebruik van 2 type processen: de game server, waarop het spel draait, en clients. De clients zijn in ons geval de LiveView processen.

We implementeren:
* Het verbinden met het spel
* Het uitvoeren van beurten
* De verbinding verbreken.

We beginnen met het bouwen van een GenServer rond de `Game` module. Een GenServer is een elixir proces dat gebruikt kan worden om bijvoorbeeld staat op te slaan. In dit geval zouden we dat ook in het LiveView proces kunnen doen, zoals we dat ook deden bij de locale versie. Het voordeel van het gebruik van een apart GenServer proces, is dat we 2 duidelijke rollen hebben: 1 server waar het spel op draait, en 2 spelers die hun beurten spelen. Ook is het verbinden met deze GenServer makkelijker dan wanneer we 2 willekeurige LiveView processen zouden moeten koppelen. 

Een GenServer werkt op basis van erlangs `messages`. We gaan dus berichten sturen van en naar de server. Een genserver is een `Behavior` met de volgende functies die helpen bij het verwerken van berichten.

* `init`, die de service initialiseert als het opstart
* `handle_call`, voor berichten waarop degene die het aanroept direct een antwoord verwacht
* `handle_cast`, voor berichten die waarop niet direct een antwoord wordt verwacht.

We beginnen met het toevoegen van de module, met daarin de init functie. In de init  functie maken we de data aan die we bij gaan houden:

* `players`: een nu nog lege lijst waarin we de processen bijhouden van de spelers
* `board`: het bord waarop gespeeld wordt.

```elixir
defmodule TicTacToe.GameServer do
    use GenServer

    @impl true
    def init(_) do
        {:ok, %{players: [], board: [nil, nil, nil, nil, nil, nil, nil, nil, nil]}}
    end
end
```

Vervolgens voegen we dit proces toe aan de processen die altijd draaien binnen de applicatie.

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

Nu kunnen we een bericht toevoegen om je als speler aan een spel toe te voegen. Omdat we hier een antwoord terug willen krijgen, gebruiken we `handle_call`. `handle_call` heeft 3 argumenten: Het bericht, informatie over degene die het bericht stuurde, en de huidige staat. `handle_call` geeft vervolgens een bericht terug in de vorm `{:reply, <antwoord>, <nieuwe staat>}`. 

Als er 1 of 0 spelers in onze lijst spelers staan, voegen we de proces-id van degene die het bericht heeft gestuurd toe aan de lijst met spelers. Aan degene die de functie heeft aangeroepen, geven we de nieuwe status terug (`:waiting`), en het symbool dat we die speler hebben toegewezen (`:x` of `:o`). Ook slaan we de nieuwe staat op.

```elixir

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