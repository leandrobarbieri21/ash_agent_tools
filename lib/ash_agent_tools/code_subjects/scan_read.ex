# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.CodeSubjects.ScanRead do
  @moduledoc false
  # The fragment's `:scan` read: extraction as records of the host
  # resource. Read-only; the query's filter, sort and limit apply in
  # memory.

  use Ash.Resource.ManualRead

  @fields [
    :id,
    :repository,
    :path,
    :name_path,
    :kind,
    :line,
    :span,
    :location,
    :text,
    :module,
    :parent,
    :context,
    :chunk,
    :sha,
    :url
  ]

  @impl true
  def read(query, _data_layer_query, _opts, context) do
    args = query.arguments

    opts =
      [context: args[:context] || []]
      |> put_opt(:repository, args[:repository])
      |> put_opt(:paths, args[:paths])

    records =
      args.root
      |> AshAgentTools.CodeSubjects.scan(opts)
      |> Map.fetch!(:subjects)
      |> Enum.map(&struct(query.resource, Map.take(&1, @fields)))

    with {:ok, records} <-
           Ash.Filter.Runtime.filter_matches(context[:domain], records, query.filter) do
      records =
        if query.sort in [nil, []],
          do: records,
          else: Ash.Sort.runtime_sort(records, query.sort, domain: context[:domain])

      {:ok, records |> Enum.drop(query.offset || 0) |> maybe_limit(query.limit)}
    end
  end

  defp put_opt(opts, _key, nil), do: opts
  defp put_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_limit(records, nil), do: records
  defp maybe_limit(records, limit), do: Enum.take(records, limit)
end
