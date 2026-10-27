# The `BB.TUI.Extension` DSL, without parens. Exported so a project with
# `import_deps: [:bb_tui]` formats its extensions the same way.
spark_locals_without_parens = [
  attitude: 1,
  attitude: 2,
  bind: 1,
  bind: 2,
  command: 1,
  decimals: 1,
  label: 1,
  panel: 1,
  panel: 2,
  pitch: 1,
  plot: 2,
  plot: 3,
  publish: 1,
  range: 1,
  rate: 1,
  readout: 2,
  readout: 3,
  roll: 1,
  scale: 1,
  spark: 1,
  state: 2,
  state: 3,
  stop: 1,
  tab: 1,
  throttle_scale: 1,
  title: 1,
  turn_scale: 1,
  unit: 1,
  window: 1,
  y_range: 1
]

[
  inputs: ["{mix,.formatter}.exs", "{config,dev,lib,test}/**/*.{ex,exs}"],
  import_deps: [:spark],
  locals_without_parens: spark_locals_without_parens,
  export: [locals_without_parens: spark_locals_without_parens]
]
