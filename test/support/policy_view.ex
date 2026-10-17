# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.Test.PolicyView do
  @moduledoc """
  A code-subject projection with declared context: the unit's text, its
  module header and the enclosing module's policies.
  """

  use AshAgentTools.CodeSubjects.Projection, context: [:module_header, {:section, :policies}]
end
