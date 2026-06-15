defmodule BB.TUI.State.Viz do
  @moduledoc """
  Visualization-tab state: the orbit camera and render mode for the 3D robot view.

  `camera` is `nil` until first used; `BB.TUI.State.viz_camera/1` falls back to
  `BB.TUI.Viz.RobotScene.default_camera/0` so a fresh state still renders.

  `render_mode` is the `ExRatatui.Widgets.Viewport3D` mode — one of `:braille`
  (supersampled, anti-aliased color; the prettiest of the cell-blit modes),
  `:half_block` (one `▀` per cell, blockier), or `:ascii` (shaded ramp fallback).

  ## Future: true pixel graphics

  All three modes above blit into terminal *cells*. For crisp, non-blocky 3D on
  terminals that speak a graphics protocol (Kitty — Ghostty/WezTerm/Kitty; Sixel —
  WezTerm), the scene would instead be rendered to an RGB framebuffer and emitted
  through the Kitty/Sixel encoder that `ExRatatui.Image` already implements
  (`:protocol` `:kitty | :sixel | :iterm2`). `Viewport3D` does not expose a pixel
  output yet — wiring render3d's framebuffer to the image-protocol path is the
  enhancement to chase, gated to `:auto` so it falls back to `:braille` over
  `CellSession`/SSH transports.
  """

  alias ExRatatui.ThreeD.Camera

  defstruct camera: nil, render_mode: :braille

  @type render_mode :: :braille | :half_block | :ascii
  @type t :: %__MODULE__{camera: Camera.t() | nil, render_mode: render_mode()}
end
