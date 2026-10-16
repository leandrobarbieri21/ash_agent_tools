# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.CodeSubjects.Text do
  @moduledoc false
  # Line-level text helpers shared by the extractors. Lines are 1-based,
  # like editors and `path:line` links.

  @doc false
  @spec lines(String.t()) :: [String.t()]
  def lines(source), do: String.split(source, ~r/\r?\n/)

  @doc false
  # Lines `from..to` (inclusive), with their common indentation removed and
  # trailing whitespace dropped. Indentation is where a unit sits, not what
  # it says, so it stays out of the text a digest covers.
  @spec slice([String.t()], pos_integer(), pos_integer()) :: String.t()
  def slice(lines, from, to) when from <= to do
    lines
    |> Enum.slice((from - 1)..(to - 1)//1)
    |> Enum.map(&String.trim_trailing/1)
    |> dedent()
    |> Enum.join("\n")
  end

  def slice(_lines, _from, _to), do: ""

  @doc false
  # Lines `from..to` as `{line_number, text}` pairs.
  @spec numbered([String.t()], pos_integer(), pos_integer()) :: [{pos_integer(), String.t()}]
  def numbered(lines, from, to) when from <= to do
    lines
    |> Enum.slice((from - 1)..(to - 1)//1)
    |> Enum.with_index(from)
    |> Enum.map(fn {text, number} -> {number, text} end)
  end

  def numbered(_lines, _from, _to), do: []

  @doc false
  # Splits numbered lines into blank-line-separated paragraphs, each
  # `%{line, end_line, text}`. A fenced code block (``` or ~~~) is one
  # paragraph even when it holds blank lines.
  @spec paragraphs([{pos_integer(), String.t()}]) :: [map()]
  def paragraphs(numbered) do
    {done, current, _fence} =
      Enum.reduce(numbered, {[], [], nil}, fn {number, text}, {done, current, fence} ->
        trimmed = String.trim(text)

        cond do
          fence != nil ->
            fence = if String.starts_with?(trimmed, fence), do: nil, else: fence
            {done, [{number, text} | current], fence}

          fence_open = fence_marker(trimmed) ->
            {done, [{number, text} | current], fence_open}

          trimmed == "" ->
            {close(current, done), [], nil}

          true ->
            {done, [{number, text} | current], nil}
        end
      end)

    current |> close(done) |> Enum.reverse()
  end

  defp fence_marker("```" <> _), do: "```"
  defp fence_marker("~~~" <> _), do: "~~~"
  defp fence_marker(_), do: nil

  defp close([], done), do: done

  defp close(current, done) do
    [{last, _} | _] = current
    lines = Enum.reverse(current)
    [{first, _} | _] = lines

    text =
      lines
      |> Enum.map(fn {_number, text} -> String.trim_trailing(text) end)
      |> dedent()
      |> Enum.join("\n")

    [%{line: first, end_line: last, text: text} | done]
  end

  @doc false
  @spec dedent([String.t()]) :: [String.t()]
  def dedent(lines) do
    indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(&(byte_size(&1) - byte_size(String.trim_leading(&1, " "))))
      |> Enum.min(fn -> 0 end)

    Enum.map(lines, fn line ->
      if String.trim(line) == "",
        do: "",
        else: binary_part(line, indent, byte_size(line) - indent)
    end)
  end
end
