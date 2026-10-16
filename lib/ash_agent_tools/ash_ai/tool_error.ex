# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshAi) do
  defmodule AshAgentTools.AshAi.ToolError do
    @moduledoc """
    A tool's structured error (`%{"error" => message, "did_you_mean" =>
    candidates}`, plus any hint), carried through Ash so ash_ai renders it
    as the same JSON the daemon returns.
    """

    use Splode.Error, fields: [details: %{}], class: :invalid

    @impl true
    def message(%{details: details}), do: Map.get(details, "error", "tool error")
  end

  defimpl AshAi.ToToolError, for: AshAgentTools.AshAi.ToolError do
    def to_tool_error(%{details: details}), do: Jason.encode!(details)
  end
end
