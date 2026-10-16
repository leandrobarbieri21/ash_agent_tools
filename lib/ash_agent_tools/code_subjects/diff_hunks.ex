# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.CodeSubjects.DiffHunks do
  @moduledoc false
  # Hunks of a unified diff (`git diff` output). Each hunk becomes one raw
  # unit on its post-image path, located at its first added line (or, for a
  # pure deletion, the line the deletion sits at). The caller resolves the
  # enclosing unit in the post-image, which is what makes a hunk's address
  # survive edits elsewhere in the file.

  @hunk_header ~r/^@@ -(?<old_start>\d+)(?:,(?<old_count>\d+))? \+(?<new_start>\d+)(?:,(?<new_count>\d+))? @@/

  @doc false
  @spec parse(String.t()) :: [map()]
  def parse(diff) when is_binary(diff) do
    diff
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%{path: nil, old_path: nil, hunks: [], current: nil}, &line/2)
    |> close_hunk()
    |> Map.fetch!(:hunks)
    |> Enum.reverse()
  end

  defp line("diff --git " <> _ = _line, state),
    do: %{close_hunk(state) | path: nil, old_path: nil}

  defp line("--- " <> path, %{current: nil} = state), do: %{state | old_path: strip_prefix(path)}

  defp line("+++ " <> path, %{current: nil} = state) do
    new_path = strip_prefix(path)
    %{state | path: if(new_path == nil, do: state.old_path, else: new_path)}
  end

  defp line("@@" <> _ = header, state) do
    state = close_hunk(state)

    case Regex.named_captures(@hunk_header, header) do
      nil ->
        state

      captures ->
        new_start = String.to_integer(captures["new_start"])
        new_count = count(captures["new_count"])

        hunk = %{
          path: state.path,
          header: header,
          new_start: new_start,
          new_count: new_count,
          # The `@@ -a,b +c,d @@` header carries line numbers, which never
          # enter a digest: the text is the hunk's body lines.
          lines: [],
          next_new: new_start,
          first_added: nil
        }

        %{state | current: hunk}
    end
  end

  defp line(text, %{current: %{} = hunk} = state) do
    hunk =
      case text do
        "+" <> _ ->
          %{hunk | first_added: hunk.first_added || hunk.next_new, next_new: hunk.next_new + 1}

        # A context line; some tools strip the space off an empty one.
        context when context == "" or binary_part(context, 0, 1) == " " ->
          %{hunk | next_new: hunk.next_new + 1}

        _ ->
          hunk
      end

    if text == "" or String.starts_with?(text, ["+", "-", " ", "\\"]) do
      %{state | current: %{hunk | lines: [text | hunk.lines]}}
    else
      close_hunk(state)
    end
  end

  defp line(_text, state), do: state

  defp close_hunk(%{current: nil} = state), do: state

  defp close_hunk(%{current: hunk} = state) do
    lines = hunk.lines |> Enum.drop_while(&(&1 == "")) |> Enum.reverse()
    line = hunk.first_added || max(hunk.new_start, 1)

    unit = %{
      kind: :diff_hunk,
      path: hunk.path,
      line: line,
      span: %{
        start_line: max(hunk.new_start, 1),
        end_line: max(hunk.new_start + hunk.new_count - 1, max(hunk.new_start, 1))
      },
      text: Enum.join(lines, "\n")
    }

    %{state | hunks: [unit | state.hunks], current: nil}
  end

  defp count(nil), do: 1
  defp count(""), do: 1
  defp count(value), do: String.to_integer(value)

  defp strip_prefix("/dev/null"), do: nil
  defp strip_prefix("a/" <> path), do: String.trim_trailing(path)
  defp strip_prefix("b/" <> path), do: String.trim_trailing(path)
  defp strip_prefix(path), do: String.trim_trailing(path)
end
