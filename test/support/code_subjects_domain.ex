# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.Test.CodeSubjectsDomain do
  @moduledoc """
  The code-subjects test host: a code-unit resource carrying a declared
  question, and a temporal facts table that question's facts land in.
  """

  use Ash.Domain

  resources do
    resource AshAgentTools.Test.CodeUnit
    resource AshAgentTools.Test.CodeFact
  end
end
