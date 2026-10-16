# SPDX-FileCopyrightText: 2026 ash_agent_tools contributors <https://github.com/lukegalea/ash_agent_tools>
#
# SPDX-License-Identifier: MIT

defmodule AshAgentTools.CodeSubjects.ElixirSource do
  @moduledoc false
  # Code units of one Elixir source file: modules, functions (all clauses of
  # a name/arity), DSL entities, and @moduledoc/@doc paragraphs. Pure: the
  # source text comes in, plain maps come out. Spans come from Sourceror's
  # AST ranges, never from line arithmetic on the text.
  #
  # Each unit carries its enclosing module's name, so the caller can attach
  # the module context (header, moduledoc, DSL sections) a question
  # declares. The module index is returned alongside for exactly that.

  alias AshAgentTools.CodeSubjects.Text

  @def_kinds [:def, :defp, :defmacro, :defmacrop, :defguard, :defguardp, :defdelegate]

  # Calls with a lone do-block that are control flow or test scaffolding,
  # not DSL sections.
  @not_sections [
    :if,
    :unless,
    :quote,
    :try,
    :receive,
    :cond,
    :setup,
    :setup_all,
    :describe,
    :test,
    :schema,
    :embedded_schema
  ]

  # Sections whose entities are unnamed: every call is addressed by
  # occurrence. In `policies`, `policy`, `bypass` and `policy_group` share
  # one occurrence sequence named `policy`, which is the spelling
  # `AshAgentTools.NamePath` resolves (`Resource/policies/policy[1]`).
  @unnamed_sections %{
    "policies" => "policy",
    "field_policies" => "field_policy",
    "validations" => nil,
    "changes" => nil,
    "preparations" => nil
  }

  @type module_info :: %{
          name: String.t(),
          text: String.t(),
          header: String.t(),
          moduledoc: String.t() | nil,
          sections: %{String.t() => String.t()}
        }

  @doc false
  @spec extract(String.t(), String.t()) ::
          {:ok, [map()], %{String.t() => module_info()}} | {:error, String.t()}
  def extract(source, path) when is_binary(source) and is_binary(path) do
    lines = Text.lines(source)

    case Sourceror.parse_string(source) do
      {:ok, ast} ->
        state = %{units: [], modules: %{}, lines: lines, path: path}
        state = walk(ast, nil, state)
        {:ok, finish(state.units, lines), state.modules}

      {:error, error} ->
        {:error, parse_error(error)}
    end
  end

  defp parse_error({meta, message, token}) when is_list(meta) do
    "#{Keyword.get(meta, :line, "?")}: #{inspect(message)} #{inspect(token)}"
  end

  defp parse_error(other), do: inspect(other)

  # -- the walk ----------------------------------------------------------------

  # `module` is nil outside any defmodule, else the enclosing module's full
  # name. Defs and DSL sections are only collected inside a module; quoted
  # code is a template, not this module's code, so the walk stops there.
  defp walk({:defmodule, _meta, [alias_ast | rest]} = node, outer, state) do
    case module_name(alias_ast, outer) do
      nil ->
        walk_children(rest, outer, state)

      name ->
        body = do_body(List.last(rest))
        exprs = block_exprs(body)
        state = add_module(node, name, exprs, state)
        state = collect_body(exprs, name, state)
        state
    end
  end

  defp walk({:quote, _meta, _args}, _module, state), do: state

  defp walk({_form, _meta, args}, module, state) when is_list(args),
    do: walk_children(args, module, state)

  defp walk({left, right}, module, state),
    do: walk(right, module, walk(left, module, state))

  defp walk(list, module, state) when is_list(list), do: walk_children(list, module, state)

  defp walk(_other, _module, state), do: state

  defp walk_children(nodes, module, state) do
    Enum.reduce(nodes, state, &walk(&1, module, &2))
  end

  # The direct body of a module: defs, docs and DSL sections are recognised
  # here; anything else (an `if Code.ensure_loaded?` wrapper, a `for`
  # comprehension) is walked for nested modules and conditional defs.
  defp collect_body(exprs, module, state) do
    {state, _pending_doc} =
      Enum.reduce(exprs, {state, nil}, fn expr, {state, pending_doc} ->
        collect_expr(expr, module, state, pending_doc)
      end)

    state
  end

  defp collect_expr({:@, _meta, [{:moduledoc, _, [value]}]} = node, module, state, pending) do
    {add_doc_paragraphs(node, value, module, "#{module}@moduledoc", state), pending}
  end

  defp collect_expr({:@, _meta, [{:doc, _, [value]}]} = node, _module, state, _pending) do
    {state, {node, value}}
  end

  defp collect_expr({kind, _meta, [_head | _]} = node, module, state, pending)
       when kind in @def_kinds do
    case function_name_arity(node) do
      {name, arity} ->
        function_path = "#{module}.#{name}/#{arity}"
        state = add_clause(node, kind, function_path, module, state)

        state =
          case pending do
            {doc_node, value} ->
              add_doc_paragraphs(doc_node, value, module, "#{function_path}@doc", state)

            nil ->
              state
          end

        {state, nil}

      nil ->
        {state, pending}
    end
  end

  defp collect_expr({name, _meta, [do_kw]} = node, module, state, pending)
       when is_atom(name) and name not in @not_sections do
    case do_body(do_kw) do
      nil ->
        {walk(node, module, state), pending}

      body ->
        {add_section(Atom.to_string(name), body, module, state), pending}
    end
  end

  defp collect_expr({:defmodule, _, _} = node, module, state, pending),
    do: {walk(node, module, state), pending}

  defp collect_expr(node, module, state, pending) do
    # Conditional or generated code inside the module body: look inside
    # for defs and nested modules with the same module context.
    case node do
      {form, _meta, args} when form in [:if, :unless] and is_list(args) ->
        exprs = args |> Enum.flat_map(&branch_bodies/1) |> Enum.flat_map(&block_exprs/1)
        {collect_body(exprs, module, state), pending}

      _ ->
        {walk(node, module, state), pending}
    end
  end

  defp branch_bodies(args) when is_list(args) do
    Enum.flat_map(args, fn
      {{:__block__, _, [key]}, body} when key in [:do, :else] -> [body]
      {key, body} when key in [:do, :else] -> [body]
      _ -> []
    end)
  end

  defp branch_bodies(_), do: []

  # -- modules -------------------------------------------------------------------

  defp add_module(node, name, exprs, state) do
    {start_line, end_line} = range(node)
    leading = leading_comment_start(state.lines, start_line)
    text = Text.slice(state.lines, leading, end_line)

    info = %{
      name: name,
      text: text,
      header: module_header(node, exprs, state.lines),
      moduledoc: moduledoc_text(exprs, state.lines),
      sections: module_sections(exprs, state.lines)
    }

    unit = %{
      kind: :module,
      name_path: name,
      module: name,
      parent: parent_module(name),
      line: start_line,
      span: %{start_line: leading, end_line: end_line},
      text: text
    }

    %{state | units: [unit | state.units], modules: Map.put(state.modules, name, info)}
  end

  # The `defmodule` line plus the module's top-level `use`, `import`,
  # `alias`, `require` and `@behaviour` statements: what a reader needs to
  # know what kind of module this is.
  defp module_header({:defmodule, meta, _}, exprs, lines) do
    first = Text.slice(lines, meta[:line], meta[:line])

    statements =
      exprs
      |> Enum.filter(&header_statement?/1)
      |> Enum.map(fn expr ->
        {from, to} = range(expr)
        Text.slice(lines, from, to)
      end)

    Enum.join([first | statements], "\n")
  end

  defp header_statement?({form, _, _}) when form in [:use, :import, :alias, :require], do: true
  defp header_statement?({:@, _, [{:behaviour, _, _}]}), do: true
  defp header_statement?(_), do: false

  defp moduledoc_text(exprs, lines) do
    Enum.find_value(exprs, fn
      {:@, _, [{:moduledoc, _, _}]} = node ->
        {from, to} = range(node)
        Text.slice(lines, from, to)

      _ ->
        nil
    end)
  end

  defp module_sections(exprs, lines) do
    exprs
    |> Enum.flat_map(fn
      {name, _meta, [do_kw]} = node when is_atom(name) and name not in @not_sections ->
        if do_body(do_kw) do
          {from, to} = range(node)
          [{Atom.to_string(name), Text.slice(lines, from, to)}]
        else
          []
        end

      _ ->
        []
    end)
    # The first declaration of a section name wins (Spark merges repeats,
    # and so does the context a question sees).
    |> Enum.reverse()
    |> Map.new()
  end

  defp parent_module(name) do
    case String.split(name, ".") do
      [_single] -> nil
      parts -> parts |> Enum.drop(-1) |> Enum.join(".")
    end
  end

  # -- functions -------------------------------------------------------------------

  defp add_clause(node, kind, function_path, module, state) do
    {start_line, end_line} = range(node)
    leading = leading_comment_start(state.lines, start_line)

    clause = %{
      kind: :function,
      visibility: visibility(kind),
      name_path: function_path,
      module: module,
      parent: module,
      line: start_line,
      span: %{start_line: leading, end_line: end_line}
    }

    %{state | units: [clause | state.units]}
  end

  defp visibility(kind) when kind in [:defp, :defmacrop, :defguardp], do: :private
  defp visibility(_kind), do: :public

  defp function_name_arity({:defdelegate, _, [head | _]}), do: head_name_arity(head)

  defp function_name_arity({_kind, _, [head | _]}), do: head_name_arity(head)

  defp head_name_arity({:when, _, [head | _]}), do: head_name_arity(head)

  defp head_name_arity({name, _, args})
       when is_atom(name) and name not in [:unquote, :__block__] do
    {name, arity(args)}
  end

  defp head_name_arity(_), do: nil

  defp arity(nil), do: 0
  defp arity(args) when is_list(args), do: length(args)

  # -- DSL sections and entities --------------------------------------------------

  defp add_section(section, body, module, state) do
    exprs = block_exprs(body)

    {state, _counts} =
      Enum.reduce(exprs, {state, %{}}, fn expr, {state, counts} ->
        add_entity(expr, section, module, state, counts)
      end)

    state
  end

  defp add_entity({call, _meta, args} = node, section, module, state, counts)
       when is_atom(call) and is_list(args) do
    cond do
      subsection?(args) ->
        {add_section("#{section}_#{call}", do_body(hd(args)), module, state), counts}

      name = entity_name(section, call, args) ->
        {name, index_label, counts} = occurrence(section, name, counts)
        name_path = "#{module}/#{section}/#{name}#{index_label}"
        {start_line, end_line} = range(node)
        leading = leading_comment_start(state.lines, start_line)

        unit = %{
          kind: :dsl_entity,
          name_path: name_path,
          module: module,
          parent: module,
          dsl_path: section,
          line: start_line,
          span: %{start_line: leading, end_line: end_line},
          text: Text.slice(state.lines, leading, end_line)
        }

        {%{state | units: [unit | state.units]}, counts}

      true ->
        {state, counts}
    end
  end

  defp add_entity(_expr, _section, _module, state, counts), do: {state, counts}

  defp subsection?([do_kw]), do: do_body(do_kw) != nil
  defp subsection?(_args), do: false

  # Named entity: the first argument is a literal atom (`attribute :title`,
  # `read :list`), or a module in a domain's `resources` section. Unnamed
  # sections address every call by occurrence. This is a syntactic rule
  # (no DSL is loaded), so an option whose value is a literal atom
  # (`strategy :context`) is addressed as an entity too.
  defp entity_name(section, call, args) do
    case Map.fetch(@unnamed_sections, section) do
      {:ok, shared} ->
        {:unnamed, shared || Atom.to_string(call)}

      :error ->
        case args do
          [first | _] -> literal_name(section, first)
          [] -> nil
        end
    end
  end

  defp literal_name(_section, {:__block__, _, [atom]})
       when is_atom(atom) and not is_boolean(atom) and atom != nil,
       do: Atom.to_string(atom)

  # A domain's `resources do resource MyApp.Post end` names its entities by
  # module. Elsewhere an alias argument is an option (`domain MyApp.Domain`
  # inside `code_interface`), not an entity name.
  defp literal_name("resources", {:__aliases__, _, parts} = alias_ast) when is_list(parts),
    do: Macro.to_string(alias_ast)

  defp literal_name(_section, _arg), do: nil

  # Named entities are unique within a section (an index appears only for
  # a repeat); unnamed ones always carry their occurrence.
  defp occurrence(section, {:unnamed, name}, counts) do
    key = {section, name}
    index = Map.get(counts, key, 0)
    {name, "[#{index}]", Map.put(counts, key, index + 1)}
  end

  defp occurrence(section, name, counts) do
    key = {section, name}
    index = Map.get(counts, key, 0)
    label = if index == 0, do: "", else: "[#{index}]"
    {name, label, Map.put(counts, key, index + 1)}
  end

  # -- doc paragraphs -----------------------------------------------------------------

  defp add_doc_paragraphs(node, value, module, owner_path, state) do
    if doc_text?(value) do
      {start_line, end_line} = range(node)

      paragraphs =
        cond do
          heredoc?(value) ->
            # The paragraphs live between the opening and closing delimiter
            # lines, with their real line numbers.
            state.lines
            |> Text.numbered(start_line + 1, end_line - 1)
            |> Text.paragraphs()

          end_line == start_line ->
            [
              %{
                line: start_line,
                end_line: start_line,
                text: single_line_doc(value, state.lines, start_line)
              }
            ]

          true ->
            [
              %{
                line: start_line,
                end_line: end_line,
                text: Text.slice(state.lines, start_line, end_line)
              }
            ]
        end

      units =
        paragraphs
        |> Enum.with_index()
        |> Enum.map(fn {paragraph, index} ->
          %{
            kind: :doc_paragraph,
            name_path: "#{owner_path}[#{index}]",
            module: module,
            parent: owner_path |> String.split("@") |> hd(),
            line: paragraph.line,
            span: %{start_line: paragraph.line, end_line: paragraph.end_line},
            text: paragraph.text
          }
        end)

      %{state | units: Enum.reverse(units) ++ state.units}
    else
      state
    end
  end

  defp single_line_doc({:__block__, _, [string]}, _lines, _line) when is_binary(string),
    do: string

  defp single_line_doc(_value, lines, line), do: Text.slice(lines, line, line)

  # Only a string documents: `@doc false` documents nothing, and
  # `@moduledoc since: "0.1.0"` is metadata.
  defp doc_text?({:__block__, _, [string]}) when is_binary(string), do: true
  defp doc_text?({sigil, _, _}) when sigil in [:sigil_S, :sigil_s], do: true
  defp doc_text?(_), do: false

  @heredoc_delimiters [~s("""), "'''"]

  defp heredoc?({_form, meta, _}), do: Keyword.get(meta, :delimiter) in @heredoc_delimiters

  # -- finishing ----------------------------------------------------------------------

  # Clauses of one name/arity become one function unit: its span runs from
  # the first clause's leading comments to the last clause's end, and its
  # text is exactly those source lines.
  defp finish(units, lines) do
    units = Enum.reverse(units)

    {functions, others} = Enum.split_with(units, &(&1.kind == :function))

    merged =
      functions
      |> Enum.group_by(& &1.name_path)
      |> Enum.map(fn {_path, [first | _] = clauses} ->
        last_line = clauses |> Enum.map(& &1.span.end_line) |> Enum.max()
        span = %{first.span | end_line: last_line}

        first
        |> Map.put(:span, span)
        |> Map.put(:clauses, length(clauses))
        |> Map.put(:text, Text.slice(lines, span.start_line, span.end_line))
      end)

    Enum.sort_by(others ++ merged, &{&1.span.start_line, &1.line, kind_rank(&1.kind)})
  end

  defp kind_rank(:module), do: 0
  defp kind_rank(:doc_paragraph), do: 1
  defp kind_rank(:function), do: 2
  defp kind_rank(:dsl_entity), do: 3

  # -- AST helpers -----------------------------------------------------------------------

  defp module_name({:__aliases__, _, parts}, outer) do
    # `defmodule __MODULE__.Child` names a child of the enclosing module,
    # which the outer prefix already supplies, so `__MODULE__` drops out.
    parts = Enum.reject(parts, &match?({:__MODULE__, _, _}, &1))

    if parts != [] and Enum.all?(parts, &is_atom/1) do
      name = Enum.map_join(parts, ".", &Atom.to_string/1)
      if outer, do: "#{outer}.#{name}", else: name
    end
  end

  defp module_name({:__block__, _, [atom]}, _outer) when is_atom(atom) do
    atom |> Atom.to_string() |> String.trim_leading("Elixir.")
  end

  defp module_name(_other, _outer), do: nil

  defp do_body([{{:__block__, _, [:do]}, body} | _]), do: body
  defp do_body([{:do, body} | _]), do: body
  defp do_body(_), do: nil

  defp block_exprs({:__block__, _, exprs}) when is_list(exprs), do: exprs
  defp block_exprs(nil), do: []
  defp block_exprs(expr), do: [expr]

  defp range(node) do
    %{start: start, end: finish} = Sourceror.get_range(node)
    {start[:line], finish[:line]}
  end

  # Comment lines directly above a unit belong to it (they are what a
  # reader sees as its explanation). Blank lines and code stop the climb.
  defp leading_comment_start(lines, line) do
    if line > 1 and comment_line?(Enum.at(lines, line - 2)) do
      leading_comment_start(lines, line - 1)
    else
      line
    end
  end

  defp comment_line?(nil), do: false
  defp comment_line?(line), do: String.starts_with?(String.trim_leading(line), "#")
end
