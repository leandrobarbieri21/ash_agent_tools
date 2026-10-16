# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.Edit.BatchTest do
  use ExUnit.Case, async: true

  alias AshAgentTools.Edit.Batch

  describe "resolve_module_only/1" do
    test "names the module a name path starts at" do
      assert Batch.resolve_module_only("AshAgentTools.Test.Post/actions/create") ==
               AshAgentTools.Test.Post
    end

    test "a module part that resolves to nothing is nil, not a raise" do
      assert Batch.resolve_module_only("NoSuchResourceAnywhere/actions/create") == nil
    end
  end
end
