# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.Test.CodeUnit do
  @moduledoc """
  A host code-unit resource: the package fragment plus one declared
  question over it, the shape a standards run declares its questions in.
  """

  use Ash.Resource,
    domain: AshAgentTools.Test.CodeSubjectsDomain,
    extensions: [AshJudgments.Registry],
    fragments: [AshAgentTools.CodeSubjects.Fragment]

  judgments do
    question :policy_check_queries do
      type AshAi.Evaluate.Noul
      instructions("Does a policy check in this code issue a query?")
      version(1)
      family(:code_standards)
      profile(:code_review_local)
      record(:best_effort)
      state_projection(AshAgentTools.Test.PolicyView)
      state_shape(AshAgentTools.Test.PolicyView.shape())
    end
  end
end
