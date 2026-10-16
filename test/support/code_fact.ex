# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.Test.CodeFact do
  @moduledoc """
  The facts table for code subjects: `ash_judgments`' temporal facts
  fragment on ETS, so `AshJudgments.Query` reads staleness over real
  facts without a database.
  """

  use Ash.Resource,
    domain: AshAgentTools.Test.CodeSubjectsDomain,
    data_layer: Ash.DataLayer.Ets,
    fragments: [AshJudgments.Facts.TemporalFragment]

  ets do
    private? true
  end

  # ETS cannot check identities natively, and Ash refuses an identity
  # without `pre_check_with` unless the resource exports this marker (Ash's
  # own test hook). The fragment's identity is a WITHOUT OVERLAPS
  # constraint on Postgres 18; these tests write one fact per subject and
  # predicate, so nothing here relies on it.
  @doc false
  def testing_identities, do: :ok
end
