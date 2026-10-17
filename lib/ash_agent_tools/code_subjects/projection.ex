# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

# Compiled conditionally (Ecto's optional-Jason pattern): the behaviour this
# implements belongs to the optional `ash_judgments` dependency.
if Code.ensure_loaded?(AshJudgments.Registry.StateProjection) do
  defmodule AshAgentTools.CodeSubjects.Projection do
    @moduledoc """
    The `state_projection` of a question declared over code subjects: the
    unit's text plus the context the question declares (see
    `AshAgentTools.CodeSubjects` for the context specs).

    `ash_judgments` names a projection by module, so each distinct context
    is one small module:

        defmodule MyApp.Standards.PolicyView do
          use AshAgentTools.CodeSubjects.Projection,
            context: [:module_header, {:section, :policies}]
        end

        judgments do
          question :policy_check_queries do
            type AshAi.Evaluate.Noul
            instructions "Does this policy check issue a query?"
            state_projection MyApp.Standards.PolicyView
            state_shape MyApp.Standards.PolicyView.shape()
            # family, version, profile, ...
          end
        end

    The judge action's `input` argument is the code subject (the map
    `AshAgentTools.CodeSubjects` extracts, with atom or string keys). The
    projected state is `AshAgentTools.CodeSubjects.state/2` of it, so the
    `state_digest` the judgment records equals
    `AshAgentTools.CodeSubjects.digest(subject, MyApp.Standards.PolicyView)`
    while the unit is unchanged, and differs once the text or the declared
    context changes.

    `AshAgentTools.CodeSubjects.Projection.Text` is the projection with no
    context.
    """

    alias AshAgentTools.CodeSubjects

    @doc false
    defmacro __using__(opts) do
      quote bind_quoted: [context: Keyword.get(opts, :context, [])] do
        @behaviour AshJudgments.Registry.StateProjection

        @code_subject_context AshAgentTools.CodeSubjects.normalize_context(context)

        @doc false
        def __code_subject_context__, do: @code_subject_context

        @impl AshJudgments.Registry.StateProjection
        def project(input, _context),
          do: AshAgentTools.CodeSubjects.Projection.project(input, @code_subject_context)

        @impl AshJudgments.Registry.StateProjection
        def shape, do: AshAgentTools.CodeSubjects.shape(@code_subject_context)
      end
    end

    @doc """
    Projects a judge action's input (or a bare subject map) through the
    given context keys.
    """
    @spec project(map(), CodeSubjects.projection()) :: map()
    def project(%{arguments: %{input: subject}}, context),
      do: CodeSubjects.state(subject, context)

    def project(subject, context) when is_map(subject), do: CodeSubjects.state(subject, context)
  end
end
