defmodule Tak do
  @moduledoc """
  Resolves names, ports, and database identifiers for git worktrees.

  Tak (Dutch for "branch") manages multiple git worktrees in parallel, each
  with an isolated port and database. This module is the central source of
  truth for configuration: it reads application config, derives per-worktree
  values, and exposes them to the Mix tasks and helper modules.

  ## Mix tasks

    * `mix tak.create` — create a new worktree with isolated config
    * `mix tak.list` — list all worktrees and their status
    * `mix tak.remove` — remove a worktree and clean up resources
    * `mix tak.doctor` — check if the project is configured correctly

  ## Runtime API

  The supported runtime API lives in:

    * `Tak.Worktrees` — create, list, remove, and doctor operations
    * `Tak.Worktree` — stable worktree identity and configuration
    * `Tak.WorktreeStatus` — transient runtime status layered on a worktree
    * `Tak.RemoveResult` — removal outcome layered on a worktree

  ## Configuration

  Set options in `config/config.exs`:

      config :tak,
        base_port: 4000,
        trees_dir: "trees",
        create_database: true,
        endpoint: MyAppWeb.Endpoint,
        repo: MyApp.Repo

  ### Options

    * `:names` — `:dynamic` (default) for branch-name-based naming, or a
      list of fixed slot names for index-based port assignment
    * `:base_port` — base port; worktrees get ports in `base_port + 10` to
      `base_port + 250` range (step 10). Default: `4000`
    * `:trees_dir` — directory where worktrees are checked out (default: `"trees"`)
    * `:create_database` — run `mix ecto.setup` when creating a worktree
      (default: `true`); override per invocation with `--db` or `--no-db`
    * `:endpoint` — the Phoenix endpoint module (default: inferred from app name)
    * `:repo` — the Ecto repo module (default: inferred from app name)

  ## Port assignment

  In dynamic mode (default), ports are allocated by scanning existing
  worktrees and picking the first free port in `base_port + 10` to
  `base_port + 250` (step 10).

  In fixed mode (`names: ~w(a b c)`), ports are derived from position:
  `base_port + (index + 1) * 10`.

  ## Per-worktree files

  `mix tak.create` writes these files inside each worktree:

    * `.tak` — Tak-owned metadata (name, branch, port, database)
    * `config/dev.local.exs` — sets the HTTP port and (optionally) the database name
    * `mise.local.toml` — sets the `PORT` env var (only when `mise` is installed)

  `mix tak.list` and `mix tak.remove` read `.tak` first. If a worktree was
  created before `.tak` existed, Tak falls back to the legacy config-scraping
  path. No migration is required for older worktrees.
  """

  @default_base_port 4000
  @default_trees_dir "trees"
  @default_create_database true

  @doc """
  Returns the configured endpoint module.

  Defaults to `MyAppWeb.Endpoint` based on the app name convention.
  Override with `config :tak, endpoint: MyCustomWeb.Endpoint`.
  """
  def endpoint do
    case Application.get_env(:tak, :endpoint) do
      nil -> Module.concat([module_name() <> "Web", "Endpoint"])
      mod -> mod
    end
  end

  @doc """
  Returns the configured repo module.

  Defaults to `MyApp.Repo` based on the app name convention.
  Override with `config :tak, repo: MyCustom.Repo`.
  """
  def repo do
    case Application.get_env(:tak, :repo) do
      nil -> Module.concat([module_name(), "Repo"])
      mod -> mod
    end
  end

  @doc """
  Returns the configured worktree naming mode.

  Returns a list of fixed slot names, or `:dynamic` for branch-name-based
  naming. Defaults to `:dynamic` when not configured.
  """
  def names do
    case Application.get_env(:tak, :names, :dynamic) do
      :dynamic -> :dynamic
      names when is_list(names) -> names
    end
  end

  @doc """
  Returns whether tak is in dynamic naming mode.
  """
  def dynamic?, do: names() == :dynamic

  @doc """
  Returns the configured base port number.

  ## Example

      iex> is_integer(Tak.base_port())
      true
  """
  def base_port do
    Application.get_env(:tak, :base_port, @default_base_port)
  end

  @doc """
  Returns the configured directory where worktrees are stored.

  ## Example

      iex> is_binary(Tak.trees_dir())
      true
  """
  def trees_dir do
    Application.get_env(:tak, :trees_dir, @default_trees_dir)
    |> Path.expand()
  end

  @doc """
  Returns whether `mix tak.create` should run `mix ecto.setup` by default.

  Override per invocation with `--db` or `--no-db`.

  ## Example

      iex> is_boolean(Tak.create_database?())
      true
  """
  def create_database? do
    Application.get_env(:tak, :create_database, @default_create_database)
  end

  @doc """
  Returns the hostname pattern for worktrees, or `nil` if not configured.

  The pattern should contain `{name}` which will be replaced with the
  worktree name. Example: `"{name}.app-local.example.com"`.
  """
  def hostname_pattern do
    Application.get_env(:tak, :hostname_pattern)
  end

  @doc """
  Returns the OTP application name from the current Mix project.

  Delegates to `Mix.Project.config/0`, so it reflects whichever project is
  currently loaded. In a worktree, that is the worktree's project.
  """
  def app_name do
    Mix.Project.config()[:app]
  end

  @doc false
  def module_name do
    app_name()
    |> Atom.to_string()
    |> Macro.camelize()
  end

  @doc """
  Returns the port assigned to a worktree name.

  In fixed mode, the port is `base_port() + (index + 1) * 10`, where
  `index` is the name's position in `names()`. Returns `nil` if the
  name is not in the list.

  In dynamic mode, looks up the port from the worktree's `.tak` metadata.
  Returns `nil` if not found.
  """
  def port_for(name) do
    case names() do
      :dynamic ->
        path = Path.join(trees_dir(), name)

        case Tak.Metadata.read(path) do
          %Tak.Worktree{port: port} -> port
          _ -> nil
        end

      names ->
        case Enum.find_index(names, &(&1 == name)) do
          nil -> nil
          index -> base_port() + (index + 1) * 10
        end
    end
  end

  @doc """
  Allocates the next available port by scanning existing worktrees.

  Scans `.tak` metadata in `trees_dir` for ports already in use,
  then returns the first free port in the range
  `base_port + 10` to `base_port + 250` (step 10).
  """
  def allocate_port do
    used_ports = used_ports()
    base = base_port()

    Enum.find(1..25, fn i ->
      port = base + i * 10
      port not in used_ports
    end)
    |> case do
      nil -> {:error, :no_ports_available}
      i -> {:ok, base + i * 10}
    end
  end

  defp used_ports do
    dir = trees_dir()

    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(dir, &1)))
      |> Enum.flat_map(fn name ->
        case Tak.Metadata.read(Path.join(dir, name)) do
          %Tak.Worktree{port: port} when is_integer(port) -> [port]
          _ -> []
        end
      end)
    else
      []
    end
  end

  @doc """
  Returns the PostgreSQL database name for a worktree.

  The name follows the pattern `<app>_dev_<worktree>`. For example, with
  `app_name()` of `:my_app` and a worktree named `"armstrong"`, this returns
  `"my_app_dev_armstrong"`.

  ## Example

      iex> is_binary(Tak.database_for("armstrong"))
      true
  """
  def database_for(name) do
    "#{app_name()}_dev_#{name}"
  end

  @default_copy_dirs ["_build", "deps"]

  @doc """
  Returns the list of directories to copy into new worktrees.

  Defaults to `#{inspect(@default_copy_dirs)}`. Set to `false` to disable copying.
  """
  def copy_dirs do
    case Application.get_env(:tak, :copy_dirs, @default_copy_dirs) do
      false -> []
      dirs when is_list(dirs) -> dirs
      _ -> @default_copy_dirs
    end
  end

  @doc """
  Returns whether `mix tak.create` should write a `mise.local.toml` file.

  When `:write_mise` is explicitly set to `false`, mise config is skipped
  even if the mise executable is available.
  """
  def write_mise? do
    Application.get_env(:tak, :write_mise, true) and mise_available?()
  end

  @doc """
  Returns `true` if the `mise` executable is on `PATH`.

  When `true`, `mix tak.create` also writes a `mise.local.toml` that sets
  the `PORT` env var, ensuring the port is consistent whether the server is
  started through `mise` or directly.
  """
  def mise_available? do
    Tak.System.find_executable("mise") != nil
  end
end
