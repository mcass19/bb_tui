defmodule BB.TUI.State.Viz do
  @moduledoc """
  Visualization-tab state: the orbit camera and render mode for the 3D robot view.

  `camera` is `nil` until first used; `BB.TUI.State.viz_camera/1` falls back to
  `BB.TUI.Viz.RobotScene.default_camera/0` so a fresh state still renders.

  `render_mode` is the `ExRatatui.Widgets.Viewport3D` mode. `:auto` (the default)
  renders crisp pixel graphics on terminals that speak a graphics protocol
  (Kitty — Ghostty/WezTerm/Kitty; Sixel — WezTerm) and falls back to `:braille`
  over `CellSession`/SSH and unsupported terminals. The explicit pixel protocols
  (`:kitty`, `:sixel`, `:iterm2`) and cell-blit modes (`:half_block`, `:braille`,
  `:ascii`) can also be selected by cycling with `m`.
  """

  alias ExRatatui.ThreeD.Camera

  defstruct camera: nil, render_mode: :auto

  @type render_mode ::
          :auto | :kitty | :sixel | :iterm2 | :half_block | :braille | :ascii
  @type t :: %__MODULE__{camera: Camera.t() | nil, render_mode: render_mode()}
end
