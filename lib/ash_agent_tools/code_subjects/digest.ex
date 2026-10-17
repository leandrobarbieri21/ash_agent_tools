# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

# Compiled conditionally (Ecto's optional-Jason pattern): `ash_judgments` is
# an optional dependency. Without it `AshAgentTools.CodeSubjects.digest/2`
# raises the structured "add the dep" error (see
# `AshAgentTools.Availability`) before reaching this module.
if Code.ensure_loaded?(AshJudgments.Registry.Canonical) do
  defmodule AshAgentTools.CodeSubjects.Digest do
    @moduledoc false
    # The one digest computation, delegated: `AshJudgments.Registry.Judge`
    # records `Canonical.digest(Canonical.encode(state))` as a judgment's
    # `state_digest`, and a code subject's current digest must be that
    # same value for the same state, or staleness would compare unlike
    # things.

    alias AshJudgments.Registry.Canonical

    @spec digest(map()) :: String.t()
    def digest(state) when is_map(state), do: Canonical.digest(Canonical.encode(state))
  end
end
