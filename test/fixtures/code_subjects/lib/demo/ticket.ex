# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule Demo.Ticket do
  @moduledoc """
  A support ticket.

  Tickets are raised by customers
  and answered by staff.
  """

  use Ash.Resource, domain: Demo

  attributes do
    uuid_primary_key :id
    attribute :title, :string
  end

  actions do
    defaults [:read]

    # Opens a ticket.
    create :open do
      accept [:title]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:admin?, true) do
      authorize_if always()
    end
  end

  @doc "The ticket's display title."
  def display(%{title: title}), do: title

  # Normalises a title.
  defp normalise(title) when is_binary(title) do
    String.trim(title)
  end

  defp normalise(nil), do: ""

  defmodule Reply do
    @moduledoc false
    def body(reply), do: reply.body
  end
end
