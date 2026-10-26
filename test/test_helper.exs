Application.ensure_all_started(:mimic)

Mimic.copy(BB)
Mimic.copy(BB.Actuator)
Mimic.copy(BB.Safety)
Mimic.copy(BB.Robot)
Mimic.copy(BB.Robot.Joint)
Mimic.copy(BB.Robot.Runtime)
Mimic.copy(BB.PubSub)
Mimic.copy(BB.Parameter)
Mimic.copy(BB.Dsl.Info)
Mimic.copy(BB.Command)
Mimic.copy(BB.TUI.Rpc)
Mimic.copy(BB.TUI.App)

{:ok, _} = BB.TUI.Test.Endpoint.start_link()

# `:distributed` tests start a `:peer` node and need a distributed test node:
# elixir --sname test -S mix test --only distributed
ExUnit.start(exclude: [:distributed])
