# Contributing to BB.TUI

Thanks for your interest in contributing!

BB.TUI is a terminal dashboard for [Beam Bots](https://github.com/beam-bots) robots, built on [ExRatatui](https://github.com/mcass19/ex_ratatui). If you're missing a feature or something isn't working, consider contributing upstream too — both to [ExRatatui](https://github.com/mcass19/ex_ratatui) (the terminal UI library) and to [Beam Bots](https://github.com/beam-bots) (the robotics framework). Contributions are welcome everywhere!

This guide will help you get set up.

## Setup

1. Clone the repo:

```sh
git clone https://github.com/mcass19/bb_tui.git
cd bb_tui
```

2. Prerequisites:

- **Elixir** 1.19+ and **Erlang/OTP** 27+.

3. Fetch dependencies:

```sh
mix deps.get
```

## Running the dashboard

The project ships a simulated WidowX-200 robot arm that starts automatically in dev, so you can smoke-test the TUI without hardware:

```sh
mix bb.tui --robot Dev.TestRobot
```

`Dev.TestRobot` exercises every panel feature end-to-end — commands with all argument shapes, parameter groups for every primitive type, a `:mavlink` bridge tab, and a `stream` command that emits a high-rate sensor burst.

## Running Tests

```sh
mix test
mix test --cover        # must report 100% Total
```

A small number of test/fixture modules are excluded from coverage in `mix.exs`. The threshold applies to everything else.

## Branching and Commits

- Branch from `main`
- Keep commits focused and atomic
- Use descriptive commit message prefixes: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`

## Pull Requests

Before submitting a PR, make sure the full check suite passes (this is what CI runs):

```sh
mix format --check-formatted
mix deps.unlock --check-unused
mix credo --strict
mix compile --warnings-as-errors
mix xref graph --format cycles --fail-above 0
mix dialyzer
mix test --cover
```

- Keep PRs focused — one feature or fix per PR
- Add tests for new functionality
- Add `@doc`, `@spec`, and `@moduledoc` for new public functions and modules
- Update documentation (moduledocs, CHANGELOG, README if applicable)
- For breaking changes, include migration notes in the CHANGELOG
- Follow existing code style and patterns
- Ensure CI passes before requesting review
