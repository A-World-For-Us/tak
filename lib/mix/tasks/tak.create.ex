defmodule Mix.Tasks.Tak.Create do
  @shortdoc "Create a new git worktree with isolated config"
  @moduledoc """
  Creates a git worktree with an isolated port and database for parallel development.

      $ mix tak.create <branch-name> [name]

  The worktree lands in `trees/<name>/` and gets its own `config/dev.local.exs`
  with a dedicated port and (optionally) a dedicated database. If
  [mise](https://mise.jdx.dev) is installed, a `mise.local.toml` is also written
  so the `PORT` env var stays consistent across shells.

  After setup, the task runs `mix deps.get` and, when creating a database,
  `mix ecto.setup` inside the new worktree.

  If a `.env` file exists in the project root, it is copied into the worktree.

  ## Arguments

    * `branch-name` — the git branch to create or check out (required)
    * `name` — the worktree slot name (optional; auto-assigned when omitted)

  ## Options

    * `--db` — create the database, overriding the `create_database` config value
    * `--no-db` — skip database creation, overriding the `create_database` config value

  By default, tak follows the `create_database` setting in your config (which
  defaults to `true`). See `Tak.create_database?/0`.

  ## Available Names

  Names come from the `names` config key. The defaults are:
  `armstrong`, `hickey`, `mccarthy`, `lovelace`, `kay`, `valim`.

  Each name maps to a fixed port offset: the first name gets `base_port + 10`,
  the second gets `base_port + 20`, and so on. See `Tak.port_for/1`.

  Change the names in `config/config.exs`:

      config :tak, names: ~w(custom names here)

  ## Examples

      # Auto-assign a name from the available slots
      $ mix tak.create feature/login

      # Pin to a specific slot
      $ mix tak.create feature/login armstrong

      # Skip database setup
      $ mix tak.create feature/login --no-db

  Run `mix tak.doctor` first if this is a new project to verify your config is ready.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, positional, _} = OptionParser.parse(args, switches: [db: :boolean])

    create_db =
      case opts[:db] do
        nil -> Tak.create_database?()
        value -> value
      end

    case positional do
      [] ->
        Mix.shell().error("Usage: mix tak.create <branch-name> [name] [--db | --no-db]")
        Mix.shell().info("Available names: #{Enum.join(Tak.names(), ", ")}")
        exit({:shutdown, 1})

      [branch | rest] ->
        name = List.first(rest) || pick_available_name()
        create_worktree(branch, name, create_db: create_db)
    end
  end

  defp pick_available_name do
    trees_dir = Tak.trees_dir()

    available =
      Enum.filter(Tak.names(), fn name ->
        not File.dir?(Path.join(trees_dir, name))
      end)

    case available do
      [] ->
        Mix.shell().error("Error: All worktree names are in use (#{Enum.join(Tak.names(), ", ")})")
        exit({:shutdown, 1})

      names ->
        Enum.random(names)
    end
  end

  defp create_worktree(branch, name, opts) do
    unless name in Tak.names() do
      Mix.shell().error("Error: Invalid name '#{name}'. Choose from: #{Enum.join(Tak.names(), ", ")}")
      exit({:shutdown, 1})
    end

    trees_dir = Tak.trees_dir()
    worktree_path = Path.join(trees_dir, name)

    if File.dir?(worktree_path) do
      Mix.shell().error("Error: Worktree #{worktree_path} already exists")
      exit({:shutdown, 1})
    end

    port = Tak.port_for(name)

    if Tak.Port.in_use?(port) do
      Mix.shell().info("Warning: Port #{port} is already in use")
    end

    # Create trees directory
    File.mkdir_p!(trees_dir)

    # Create worktree
    Mix.shell().info("Creating worktree '#{name}' for branch '#{branch}'...")

    if Tak.Git.branch_exists?(branch) do
      Tak.Git.run!(["worktree", "add", worktree_path, branch])
    else
      Tak.Git.run!(["worktree", "add", "-b", branch, worktree_path])
    end

    # Copy .env if it exists
    if File.exists?(".env") do
      File.cp!(".env", Path.join(worktree_path, ".env"))
    end

    # Create dev.local.exs for port (and optionally database)
    app_name = Tak.app_name()
    module_name = Tak.module_name()

    config_dir = Path.join(worktree_path, "config")
    File.mkdir_p!(config_dir)
    dest_path = Path.join(config_dir, "dev.local.exs")
    source_path = "config/dev.local.exs"

    # Tak-specific config to append
    db_config =
      if opts[:create_db] do
        database = Tak.database_for(name)

        """

        config :#{app_name}, #{module_name}.Repo,
          database: "#{database}"
        """
      else
        ""
      end

    tak_config = """

    # Tak worktree config (#{name})
    # These values override any earlier config above
    config :#{app_name}, #{module_name}Web.Endpoint,
      http: [port: #{port}]
    """ <> db_config

    if File.exists?(source_path) do
      # Copy existing dev.local.exs and append tak config
      existing = File.read!(source_path)
      File.write!(dest_path, existing <> tak_config)
    else
      # Create new dev.local.exs
      File.write!(dest_path, "import Config" <> tak_config)
    end

    # If mise is installed, create mise.local.toml for PORT env var
    # This ensures PORT overrides any inherited env var from parent directories
    if Tak.mise_available?() do
      mise_config = """
      [env]
      PORT = "#{port}"
      """

      mise_path = Path.join(worktree_path, "mise.local.toml")
      File.write!(mise_path, mise_config)
      System.cmd("mise", ["trust", mise_path], stderr_to_stdout: true)
    end

    # Run setup in worktree
    Mix.shell().info("Fetching dependencies...")
    mix_in_worktree!(worktree_path, ["deps.get"])

    if opts[:create_db] do
      Mix.shell().info("Setting up database...")
      mix_in_worktree!(worktree_path, ["ecto.setup"])
    end

    # Success output
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:green, "Worktree created successfully!"]))
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:bright, name, :reset, " ", :faint, "(#{branch})"]))
    Mix.shell().info("  Port:     #{port}")
    if opts[:create_db], do: Mix.shell().info("  Database: #{Tak.database_for(name)}")
    Mix.shell().info("  Location: #{worktree_path}")
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:faint, "To start the server:"]))
    Mix.shell().info(IO.ANSI.format([:bright, "  cd #{worktree_path} && iex -S mix phx.server"]))
    Mix.shell().info("")
  end

  defp mix_in_worktree!(path, args) do
    case System.cmd("mix", args, cd: path, stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}]) do
      {_, 0} -> :ok
      {output, _} -> Mix.raise("mix #{Enum.join(args, " ")} failed in #{path}:\n#{output}")
    end
  end
end
