# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.KaizenProbe do
  @moduledoc """
  Forwards `[:ash_agent, :tool_gap]` events to the calling test process,
  for async tests that assert a gap was emitted. The dev sink
  (`AshAgentTools.Kaizen.attach/0`) is one table shared by every test, so a
  test that resets and reads it races any other test that does the same.
  """

  import ExUnit.Callbacks, only: [on_exit: 1]

  @doc "Attaches a handler that sends `{:tool_gap, measurements, metadata}` to `self()`."
  def forward_gaps_to_self do
    test = self()
    id = "kaizen-probe-#{inspect(test)}-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach(id, AshAgentTools.Kaizen.event_name(), &__MODULE__.forward/4, test)

    on_exit(fn -> :telemetry.detach(id) end)
  end

  @doc false
  def forward(_event, measurements, metadata, test),
    do: send(test, {:tool_gap, measurements, metadata})
end
