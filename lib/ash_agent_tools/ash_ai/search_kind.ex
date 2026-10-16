# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

if Code.ensure_loaded?(AshAi) do
  defmodule AshAgentTools.AshAi.SearchKind do
    @moduledoc """
    The symbol kinds `ash_search` accepts, as an enum read at runtime.

    The kinds include the dynamic ones that loaded Spark extensions add
    (`AshAgentTools.Search.valid_kinds/0`), so the list is not known at
    compile time and `Ash.Type.Enum`'s compile-time values do not fit.
    ash_ai derives the schema's `enum` from `values/0`, which makes the
    derived schema list the same kinds as the daemon card. Casting matches
    strings against the known kinds and never creates an atom.
    """

    use Ash.Type
    @behaviour Ash.Type.Enum

    @impl Ash.Type.Enum
    def values, do: Enum.map(AshAgentTools.Search.valid_kinds(), &Atom.to_string/1)

    @impl Ash.Type.Enum
    def label(_value), do: nil

    @impl Ash.Type.Enum
    def description(_value), do: nil

    @impl Ash.Type.Enum
    def details(_value), do: %{label: nil, description: nil}

    @impl Ash.Type.Enum
    def match?(value), do: match(value) != :error

    @impl Ash.Type.Enum
    def match(value) when is_atom(value) do
      if value in AshAgentTools.Search.valid_kinds(), do: {:ok, value}, else: :error
    end

    def match(value) when is_binary(value) do
      case Enum.find(AshAgentTools.Search.valid_kinds(), &(Atom.to_string(&1) == value)) do
        nil -> :error
        kind -> {:ok, kind}
      end
    end

    def match(_value), do: :error

    @impl Ash.Type
    def storage_type(_constraints), do: :string

    @impl Ash.Type
    def cast_input(nil, _constraints), do: {:ok, nil}

    def cast_input(value, _constraints) do
      case match(value) do
        {:ok, kind} -> {:ok, kind}
        :error -> {:error, message: "is not a search kind (one of: %{kinds})", kinds: values()}
      end
    end

    @impl Ash.Type
    def cast_stored(value, constraints), do: cast_input(value, constraints)

    @impl Ash.Type
    def dump_to_native(nil, _constraints), do: {:ok, nil}
    def dump_to_native(kind, _constraints) when is_atom(kind), do: {:ok, Atom.to_string(kind)}
    def dump_to_native(_value, _constraints), do: :error
  end
end
