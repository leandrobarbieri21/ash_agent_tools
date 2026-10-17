# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.CodeSubjects.Fragment do
  @moduledoc """
  The code-unit subject resource, as a `Spark.Dsl.Fragment` the host
  includes on its own resource (the `ash_judgments` pattern: the package
  supplies the shape, the host supplies the domain, data layer and
  policies):

      defmodule MyApp.Standards.CodeUnit do
        use Ash.Resource,
          domain: MyApp.Standards,
          extensions: [AshJudgments.Registry],
          fragments: [AshAgentTools.CodeSubjects.Fragment]

        judgments do
          question :policy_check_queries do
            # ...
            state_projection MyApp.Standards.PolicyView
          end
        end
      end

  Records are keyed by `id` (`"<repository>:<path>#<name_path>"`), with
  the identity `[:repository, :path, :name_path]`. The `:scan` read
  extracts them from a checkout (`AshAgentTools.CodeSubjects.scan/2`)
  without persisting anything; `:record` stores one when the host keeps
  subjects in a table. Pass `type: "MyApp.Standards.CodeUnit"` to
  `AshAgentTools.CodeSubjects.subject_term/2` so facts name this
  resource.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource

  @kinds AshAgentTools.CodeSubjects.kinds()

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :repository, :string, allow_nil?: false, public?: true

    attribute :path, :string,
      public?: true,
      description: "Relative to the repository root; nil for a committed message."

    attribute :name_path, :string, allow_nil?: false, public?: true
    attribute :kind, :atom, allow_nil?: false, public?: true, constraints: [one_of: @kinds]
    attribute :line, :integer, allow_nil?: false, public?: true
    attribute :span, :map, allow_nil?: false, public?: true

    attribute :location, :string,
      allow_nil?: false,
      public?: true,
      description: "The clickable `path:line` (the sha for a committed message)."

    attribute :text, :string,
      allow_nil?: false,
      public?: true,
      constraints: [trim?: false, allow_empty?: true]

    attribute :module, :string, public?: true
    attribute :parent, :string, public?: true
    attribute :context, :map, public?: true, default: %{}
    attribute :chunk, :map, public?: true
    attribute :sha, :string, public?: true
    attribute :url, :string, public?: true
  end

  identities do
    identity :unique_address, [:repository, :path, :name_path], nils_distinct?: false
  end

  actions do
    defaults [:read]

    read :scan do
      description "Extracts the code subjects of a checkout (read-only; nothing is stored)."

      argument :root, :string, allow_nil?: false
      argument :repository, :string
      argument :paths, {:array, :string}

      argument :context, {:array, :string},
        default: [],
        description:
          ~s(Context keys to capture: "module_header", "moduledoc", "module", "section:<name>".)

      manual AshAgentTools.CodeSubjects.ScanRead
    end

    create :record do
      accept [
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
    end
  end
end
