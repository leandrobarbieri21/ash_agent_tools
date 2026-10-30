# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.Laws.Source do
  @moduledoc """
  A module of project laws: rules a project wants judged alongside the 26
  core iron laws, with the same tiers, `--diff` mode, `--law` selection and
  JSON report.

  `laws/0` returns law maps in the registry's own shape. Detectors use the
  core kinds (`:line`, `:mount`, `:window`, `:file`) and tiers, and match
  Elixir/HEEx source text:

      defmodule MyAppWeb.Laws.UI do
        @behaviour AshAgentTools.Laws.Source

        @impl true
        def laws do
          [
            %{
              id: "ui-01",
              name: "design-system-buttons",
              category: :ui,
              title: "Buttons come from the design system",
              summary: "A raw <button> drifts from the design system; use <ds-button>.",
              detectors: [
                %{
                  kind: :line,
                  tier: :likely,
                  pattern: ~r/<button[\\s>]/,
                  hint: "use <ds-button> instead of a raw <button>"
                }
              ]
            }
          ]
        end
      end

  A rule a regex cannot express is a `:custom` detector: the project's own
  function of `(source, meta)`, `meta` being `%{file:, lines:, diff?:}`,
  returning the lines it objects to (line numbers, or
  `%{line:, text:, hint:}` maps with `text` and `hint` optional):

      %{kind: :custom, tier: :likely, hint: "put phx-click on the control",
        check: &MyAppWeb.Laws.UI.click_targets/2}

  Register it with `config :ash_agent_tools, extra_laws: [MyAppWeb.Laws.UI]`.
  Ids must be unique and must not be all digits (numeric ids are the core
  numbering); `AshAgentTools.Laws.project_laws/1` validates every law and
  detector when it loads them.
  """

  @doc "The project's laws, in `AshAgentTools.Laws.laws/1`'s registry shape."
  @callback laws() :: [map()]
end
