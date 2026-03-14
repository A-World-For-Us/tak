defmodule Tak do
  @moduledoc """
  Git worktree management for Elixir/Phoenix development.

  Tak (Dutch for "branch") helps you manage multiple git worktrees,
  each with isolated ports and databases for parallel development.

  ## Available Tasks

    * `mix tak.create` - Create a new worktree with isolated config
    * `mix tak.list` - List all worktrees and their status
    * `mix tak.remove` - Remove a worktree and clean up resources
    * `mix tak.doctor` - Check if project is configured correctly

  ## Configuration

  Configure Tak in your `config/config.exs`:

      config :tak,
        names: ~w(armstrong hickey mccarthy lovelace kay valim),
        base_port: 4000,
        trees_dir: "trees",
        create_database: true

  ### Options

    * `names` - Available worktree slot names (default: armstrong, hickey, mccarthy, lovelace, kay, valim)
    * `base_port` - Base port number; worktrees use 4010, 4020, etc. (default: 4000)
    * `trees_dir` - Directory to store worktrees (default: "trees")
    * `create_database` - Whether to run `mix ecto.setup` on create (default: true)

  The `create_database` option can be overridden per-command with `--db` or `--no-db` flags.

  ## How It Works

  Each worktree gets:
    * `config/dev.local.exs` with isolated port and database
    * `mise.local.toml` with PORT env var (if mise is installed)

  Ports are assigned based on name index: armstrong=4010, hickey=4020, mccarthy=4030, etc.
  """

  @default_names ~w(armstrong hickey mccarthy lovelace kay valim)
  @default_base_port 4000
  @default_trees_dir "trees"
  @default_create_database true

  @doc """
  Returns the list of available worktree names.
  """
  def names do
    Application.get_env(:tak, :names, @default_names)
  end

  @doc """
  Returns the base port number.
  """
  def base_port do
    Application.get_env(:tak, :base_port, @default_base_port)
  end

  @doc """
  Returns the directory where worktrees are stored.
  """
  def trees_dir do
    Application.get_env(:tak, :trees_dir, @default_trees_dir)
  end

  @doc """
  Returns whether to create databases by default.
  """
  def create_database? do
    Application.get_env(:tak, :create_database, @default_create_database)
  end

  @doc """
  Returns the app name from the current Mix project.
  """
  def app_name do
    Mix.Project.config()[:app]
  end

  @doc """
  Returns the module name (camelized) from the app name.
  """
  def module_name do
    app_name()
    |> Atom.to_string()
    |> Macro.camelize()
  end

  @doc """
  Calculates the port for a given worktree name.
  """
  def port_for(name) do
    case Enum.find_index(names(), &(&1 == name)) do
      nil -> nil
      index -> base_port() + (index + 1) * 10
    end
  end

  @doc """
  Returns the database name for a given worktree.
  """
  def database_for(name) do
    "#{app_name()}_dev_#{name}"
  end

  @doc """
  Checks if mise is available on the system.
  """
  def mise_available? do
    System.find_executable("mise") != nil
  end
end
