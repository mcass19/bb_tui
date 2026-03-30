Application.ensure_all_started(:mimic)

Mimic.copy(BB)
Mimic.copy(BB.Safety)
Mimic.copy(BB.Robot)
Mimic.copy(BB.Robot.Joint)
Mimic.copy(BB.Robot.Runtime)
Mimic.copy(BB.PubSub)
Mimic.copy(BB.Parameter)

ExUnit.start()
