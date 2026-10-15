# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshAi) do
  defmodule AshAgentTools.AshAi.Run do
    @moduledoc """
    The generic-action implementation behind every `AshAgentTools.AshAi`
    tool: refuse outside dev, then hand the arguments to the daemon's
    dispatch (`AshAgentTools.Mcp.Tools.call/2`) and return its report in
    the daemon's JSON shape.
    """

    use Ash.Resource.Actions.Implementation

    alias AshAgentTools.AshAi.ToolError
    alias AshAgentTools.Mcp.Tools

    @impl true
    def run(input, opts, _context) do
      tool = Keyword.fetch!(opts, :tool)

      with :ok <- guard() do
        case Tools.call(tool, client_arguments(input.arguments)) do
          {:ok, report} -> {:ok, json_shape(report)}
          {:error, structured} -> {:error, ToolError.exception(details: json_shape(structured))}
        end
      end
    end

    @doc """
    `:ok` in a VM with Mix loaded; otherwise the refusal. These are dev
    tools, and a release has no Mix. The argument exists for tests.
    """
    @spec guard(boolean()) :: :ok | {:error, Exception.t()}
    def guard(mix_loaded? \\ Code.ensure_loaded?(Mix))

    def guard(true), do: :ok

    def guard(false) do
      {:error,
       ToolError.exception(
         details: %{
           "error" =>
             "ash_agent_tools tools are dev-only and Mix is not loaded in this VM " <>
               "(a release?). Mount AshAgentTools.AshAi.Tools only in dev.",
           "did_you_mean" => []
         }
       )}
    end

    # Back to the JSON spelling the daemon receives: string keys, nil
    # arguments dropped, enum atoms as strings.
    defp client_arguments(arguments) do
      for {key, value} <- arguments, not is_nil(value), into: %{} do
        {Atom.to_string(key), client_value(value)}
      end
    end

    defp client_value(values) when is_list(values), do: Enum.map(values, &client_value/1)

    defp client_value(value) when is_atom(value) and not is_boolean(value),
      do: Atom.to_string(value)

    defp client_value(value), do: value

    # The daemon serves Jason.encode!(report); decoding that gives exactly
    # what a daemon client parses.
    defp json_shape(term), do: term |> Jason.encode!() |> Jason.decode!()
  end
end
