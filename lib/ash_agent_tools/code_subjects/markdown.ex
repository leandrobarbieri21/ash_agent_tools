# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.CodeSubjects.Markdown do
  @moduledoc false
  # Paragraphs of a Markdown document. A paragraph is addressed by the
  # heading path it sits under and its position in that section:
  # `"Non-negotiables[2]"`, `"Environment > Postgres[0]"`, or `"[0]"` before
  # the first heading. Inserting a paragraph renumbers only its own
  # section, so edits elsewhere in the document keep every other address.

  alias AshAgentTools.CodeSubjects.Text

  @heading ~r/^(?<hashes>\#{1,6})\s+(?<title>.+?)\s*#*\s*$/

  @doc false
  @spec extract(String.t()) :: [map()]
  def extract(source) when is_binary(source) do
    lines = Text.lines(source)

    lines
    |> Text.numbered(1, length(lines))
    |> sections()
    |> Enum.flat_map(fn {heading_path, numbered} ->
      numbered
      |> Text.paragraphs()
      |> Enum.with_index()
      |> Enum.map(fn {paragraph, index} ->
        %{
          kind: :doc_paragraph,
          name_path: "#{heading_path}[#{index}]",
          module: nil,
          parent: if(heading_path == "", do: nil, else: heading_path),
          line: paragraph.line,
          span: %{start_line: paragraph.line, end_line: paragraph.end_line},
          text: paragraph.text
        }
      end)
    end)
  end

  # Groups numbered lines under their heading path. Heading lines are
  # structure, not paragraphs; fenced code is scanned past so a `#` comment
  # inside a code block never opens a section.
  defp sections(numbered) do
    {sections, current_path, current, _stack, _fence} =
      Enum.reduce(numbered, {[], "", [], [], nil}, fn {number, text},
                                                      {sections, path, current, stack, fence} ->
        trimmed = String.trim(text)

        cond do
          fence != nil ->
            fence = if String.starts_with?(trimmed, fence), do: nil, else: fence
            {sections, path, [{number, text} | current], stack, fence}

          String.starts_with?(trimmed, "```") or String.starts_with?(trimmed, "~~~") ->
            {sections, path, [{number, text} | current], stack, String.slice(trimmed, 0, 3)}

          heading = Regex.named_captures(@heading, text) ->
            level = String.length(heading["hashes"])

            stack =
              Enum.reject(stack, fn {lvl, _title} -> lvl >= level end) ++
                [{level, heading["title"]}]

            new_path = Enum.map_join(stack, " > ", fn {_lvl, title} -> title end)
            {[{path, Enum.reverse(current)} | sections], new_path, [], stack, nil}

          true ->
            {sections, path, [{number, text} | current], stack, nil}
        end
      end)

    [{current_path, Enum.reverse(current)} | sections]
    |> Enum.reverse()
    |> merge_repeated_paths()
  end

  # Two sections with the same heading path (a repeated heading) share one
  # paragraph sequence, so every address stays unique.
  defp merge_repeated_paths(sections) do
    {order, grouped} =
      Enum.reduce(sections, {[], %{}}, fn {path, lines}, {order, grouped} ->
        if Map.has_key?(grouped, path) do
          # A blank separator keeps the last paragraph of one section from
          # running into the first of the next.
          {order, Map.update!(grouped, path, &(&1 ++ [{0, ""}] ++ lines))}
        else
          {[path | order], Map.put(grouped, path, lines)}
        end
      end)

    order |> Enum.reverse() |> Enum.map(&{&1, Map.fetch!(grouped, &1)})
  end
end
