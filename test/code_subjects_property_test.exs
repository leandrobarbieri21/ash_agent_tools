# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.CodeSubjectsPropertyTest do
  @moduledoc """
  AST-137/AC-1: editing a function invalidates its facts; editing an
  unrelated function does not.

  The facts are real: each generated function's judgment is materialised
  into `ash_judgments`' temporal facts fragment with the digest of what
  the question saw, and `AshJudgments.Query.status/4` reads them back
  against the code's current digests after an edit.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias AshAgentTools.CodeSubjects
  alias AshAgentTools.CodeSubjects.Projection
  alias AshAgentTools.Test.CodeFact
  alias AshAgentTools.Test.PolicyView
  alias AshJudgments.Facts.Materialiser

  @path "lib/generated.ex"

  setup_all do
    [question] = AshJudgments.Registry.Info.questions(AshAgentTools.Test.CodeUnit)
    %{predicate: question.question_id}
  end

  # -- generators ----------------------------------------------------------------

  # A function: arity, visibility, an optional leading comment, and a body
  # of 1 to 4 statements, so an edit can change the line count and shift
  # every function below it.
  defp function_spec do
    gen all(
          arity <- integer(0..3),
          private? <- boolean(),
          comment? <- boolean(),
          body <- list_of(integer(0..999), min_length: 1, max_length: 4)
        ) do
      %{arity: arity, private?: private?, comment?: comment?, body: body}
    end
  end

  defp module_spec do
    gen all(
          functions <- list_of(function_spec(), min_length: 2, max_length: 6),
          policy_values <- list_of(integer(0..9), min_length: 1, max_length: 2)
        ) do
      %{functions: functions, policies: policy_values}
    end
  end

  defp render(%{functions: functions, policies: policies}) do
    defs =
      functions
      |> Enum.with_index()
      |> Enum.map_join("\n", fn {function, index} -> render_function(function, index) end)

    policy_lines =
      Enum.map_join(policies, "\n", fn value ->
        "    policy action_type(:read) do\n      authorize_if expr(level == #{value})\n    end"
      end)

    """
    defmodule Generated.Subject do
      use Ash.Resource, domain: Generated

      policies do
    #{policy_lines}
      end

    #{defs}
    end
    """
  end

  defp render_function(function, index) do
    args = Enum.map_join(1..function.arity//1, ", ", &"arg#{&1}")
    keyword = if function.private?, do: "defp", else: "def"
    comment = if function.comment?, do: "  # Function number #{index}.\n", else: ""
    statements = Enum.map_join(function.body, "\n", &"    _ = #{&1}")

    "#{comment}  #{keyword} f#{index}(#{args}) do\n#{statements}\n    :ok\n  end\n"
  end

  defp function_path(index, function), do: "Generated.Subject.f#{index}/#{function.arity}"

  # -- facts ---------------------------------------------------------------------

  defp extract!(source, repository) do
    {:ok, subjects} =
      CodeSubjects.from_source(source, @path,
        repository: repository,
        context: [:module_header, {:section, :policies}]
      )

    subjects |> Enum.filter(&(&1.kind == :function)) |> Map.new(&{&1.name_path, &1})
  end

  # One admitted fact per function, recording the digest the question saw.
  defp admit_all!(functions, projection, predicate) do
    for {_path, subject} <- functions do
      {:ok, :materialised} =
        Materialiser.materialise(
          %{
            result: :admitted,
            subject: CodeSubjects.subject_term(subject),
            predicate: predicate,
            value: true,
            holds: true,
            grade: :grant,
            subject_state_digest: CodeSubjects.digest(subject, projection),
            admission_id: Ash.UUID.generate()
          },
          resource: CodeFact
        )
    end
  end

  defp statuses(functions, projection, predicate) do
    current = CodeSubjects.current_digests(Map.values(functions), projection)

    Map.new(functions, fn {path, subject} ->
      status =
        CodeFact
        |> AshJudgments.Query.status(CodeSubjects.subject_term(subject), predicate,
          current_digests: current
        )
        |> case do
          {:in, _fact} -> :in
          {:unknown, reason} -> reason
          other -> other
        end

      {path, status}
    end)
  end

  defp unique_repository, do: "generated-#{System.unique_integer([:positive])}"

  # -- AC-1 ----------------------------------------------------------------------

  @tag ac: "AST-137/AC-1"
  property "editing a function invalidates its facts; editing an unrelated function does not",
           %{predicate: predicate} do
    check all(
            module <- module_spec(),
            target <- integer(0..(length(module.functions) - 1)),
            new_body <- list_of(integer(0..999), min_length: 1, max_length: 4),
            new_body != Enum.at(module.functions, target).body,
            max_runs: 60
          ) do
      repository = unique_repository()
      edited = update_in(module, [:functions, Access.at(target)], &%{&1 | body: new_body})
      edited_path = function_path(target, Enum.at(module.functions, target))

      before = extract!(render(module), repository)
      after_edit = extract!(render(edited), repository)

      # Addresses survive the edit, even where lines moved.
      assert Map.keys(before) == Map.keys(after_edit)

      for projection <- [Projection.Text, PolicyView] do
        predicate = "#{predicate}:#{inspect(projection)}"
        admit_all!(before, projection, predicate)

        for {path, status} <- statuses(after_edit, projection, predicate) do
          if path == edited_path do
            assert status == :stale, "#{path} was edited but its fact reads #{inspect(status)}"
          else
            assert status == :in, "#{path} was not edited but its fact reads #{inspect(status)}"
          end
        end
      end
    end
  end

  @tag ac: "AST-137/AC-1"
  property "editing the declared context invalidates exactly the facts of questions that declare it",
           %{predicate: predicate} do
    check all(
            module <- module_spec(),
            new_policies <- list_of(integer(0..9), min_length: 1, max_length: 2),
            new_policies != module.policies,
            max_runs: 30
          ) do
      repository = unique_repository()
      before = extract!(render(module), repository)
      after_edit = extract!(render(%{module | policies: new_policies}), repository)

      text_predicate = "#{predicate}:text"
      policy_predicate = "#{predicate}:policies"
      admit_all!(before, Projection.Text, text_predicate)
      admit_all!(before, PolicyView, policy_predicate)

      # No function's text changed: the text-only question's facts hold.
      assert after_edit
             |> statuses(Projection.Text, text_predicate)
             |> Map.values()
             |> Enum.all?(&(&1 == :in))

      # Every function's question that sees the policies goes stale.
      assert after_edit
             |> statuses(PolicyView, policy_predicate)
             |> Map.values()
             |> Enum.all?(&(&1 == :stale))
    end
  end
end
