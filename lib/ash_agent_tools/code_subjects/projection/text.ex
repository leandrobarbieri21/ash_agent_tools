# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshJudgments.Registry.StateProjection) do
  defmodule AshAgentTools.CodeSubjects.Projection.Text do
    @moduledoc """
    The code-subject projection with no declared context: the question
    sees the unit's kind, address and text only. Editing anything outside
    the unit leaves its digest unchanged.
    """

    use AshAgentTools.CodeSubjects.Projection, context: []
  end
end
