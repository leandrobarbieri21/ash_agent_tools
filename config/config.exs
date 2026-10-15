# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

# This repository's own configuration. Host applications never read it:
# config of a dependency does not apply to its host. Test-only settings
# (the sandboxed TestRepo behind the BPMN/decision tests) live in test.exs.
import Config

# Ash requires an explicit string length count once a resource declares a
# :string field; the ash_ai adapter's tool arguments do, in every env.
# Codepoints is the recommended setting (and what SQL data layers count).
config :ash, default_string_length_count: :codepoints

if config_env() == :test do
  import_config "test.exs"
end
