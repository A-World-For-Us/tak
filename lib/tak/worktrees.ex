defmodule Tak.Worktrees do
  @moduledoc false

  @doc """
  Returns the first available slot name, or `{:error, :no_slots}`.
  """
  def pick_available_name do
    trees_dir = Tak.trees_dir()

    available =
      Enum.filter(Tak.names(), fn name ->
        not File.dir?(Path.join(trees_dir, name))
      end)

    case available do
      [] -> {:error, :no_slots}
      [first | _] -> {:ok, first}
    end
  end

  @doc """
  Creates a worktree. Returns `{:ok, %Tak.Worktree{}}` or `{:error, reason}`.

  ## Options

    * `:create_db` - whether to create the database (default: from config)
  """
  def create(branch, name, opts \\ []) do
    create_db = Keyword.get(opts, :create_db, Tak.create_database?())

    with :ok <- validate_name(name),
         :ok <- validate_not_exists(name) do
      trees_dir = Tak.trees_dir()
      worktree_path = Path.join(trees_dir, name)
      port = Tak.port_for(name)
      database = if create_db, do: Tak.database_for(name)

      port_warning = if Tak.Port.in_use?(port), do: {:port_in_use, port}

      # Create trees directory
      File.mkdir_p!(trees_dir)

      # Create git worktree
      if Tak.Git.branch_exists?(branch) do
        Tak.Git.run!(["worktree", "add", worktree_path, branch])
      else
        Tak.Git.run!(["worktree", "add", "-b", branch, worktree_path])
      end

      # Copy .env if it exists
      if File.exists?(".env") do
        File.cp!(".env", Path.join(worktree_path, ".env"))
      end

      # Write dev.local.exs
      write_dev_local_config(worktree_path, name, port, create_db)

      # Write mise.local.toml if mise is available
      if Tak.mise_available?() do
        write_mise_config(worktree_path, port)
      end

      # Build the worktree struct
      worktree = %Tak.Worktree{
        name: name,
        branch: branch,
        port: port,
        path: worktree_path,
        database: database,
        database_managed?: create_db
      }

      # Write Tak metadata
      Tak.Metadata.write!(worktree)

      # Run setup in worktree
      mix_in_worktree!(worktree_path, ["deps.get"])

      if create_db do
        mix_in_worktree!(worktree_path, ["ecto.setup"])
      end

      {:ok, worktree, List.wrap(port_warning)}
    end
  end

  @doc """
  Lists all worktrees. Returns a list of worktree info maps.
  """
  def list do
    trees_dir = Tak.trees_dir()
    base_port = Tak.base_port()

    main = %{
      name: "main",
      branch: Tak.Git.current_branch() || "unknown",
      port: base_port,
      status: port_status(base_port),
      pid: if(Tak.Port.in_use?(base_port), do: Tak.Port.pid(base_port)),
      database: nil,
      database_managed?: false,
      main?: true
    }

    worktrees =
      if File.dir?(trees_dir) do
        trees_dir
        |> File.ls!()
        |> Enum.filter(&File.dir?(Path.join(trees_dir, &1)))
        |> Enum.map(fn name ->
          worktree_path = Path.join(trees_dir, name)
          load_worktree_info(name, worktree_path)
        end)
      else
        []
      end

    [main | worktrees]
  end

  @doc """
  Removes a worktree. Returns `{:ok, %Tak.Worktree{}}` or `{:error, reason}`.

  ## Options

    * `:force` - force removal even with uncommitted changes (default: false)
    * `:keep_db` - keep the database instead of dropping it (default: false)
  """
  def remove(name, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    keep_db = Keyword.get(opts, :keep_db, false)
    trees_dir = Tak.trees_dir()
    worktree_path = Path.join(trees_dir, name)

    unless File.dir?(worktree_path) do
      {:error, {:not_found, name}}
    else
      info = load_worktree_info(name, worktree_path)

      # Stop services on port
      if info.port, do: Tak.Port.kill(info.port)

      # Remove git worktree
      remove_args =
        if force,
          do: ["worktree", "remove", "--force", worktree_path],
          else: ["worktree", "remove", worktree_path]

      case System.cmd("git", remove_args, stderr_to_stdout: true) do
        {_, 0} ->
          :ok

        {output, _} ->
          unless force do
            {:error, {:worktree_remove_failed, output}}
          end
      end
      |> case do
        {:error, _} = err ->
          err

        :ok ->
          # Clean up orphaned files
          File.rm_rf(worktree_path)
          System.cmd("git", ["worktree", "prune"], stderr_to_stdout: true)

          # Delete branch
          if info.branch do
            if force do
              System.cmd("git", ["branch", "-D", info.branch], stderr_to_stdout: true)
            else
              System.cmd("git", ["branch", "-d", info.branch], stderr_to_stdout: true)
            end
          end

          # Drop database
          db_dropped =
            if info.database_managed? and not keep_db and info.database do
              case System.cmd("dropdb", [info.database], stderr_to_stdout: true) do
                {_, 0} -> true
                _ -> false
              end
            else
              false
            end

          worktree = %Tak.Worktree{
            name: name,
            branch: info.branch,
            port: info.port,
            path: worktree_path,
            database: if(db_dropped, do: info.database),
            database_managed?: info.database_managed?
          }

          {:ok, worktree}
      end
    end
  end

  @doc """
  Runs doctor checks. Returns `{passed, failed, results}` where results is a
  list of `{:ok | :error | :warn, message}` tuples.
  """
  def doctor do
    results = [
      check_dev_local_import(),
      check_gitignore("dev.local.exs", "config/dev.local.exs", required: true),
      check_gitignore("mise.local.toml", "mise.local.toml",
        required: false,
        note: "only needed if using mise"
      ),
      check_gitignore(Tak.trees_dir(), "#{Tak.trees_dir()}/", required: true),
      check_executable("git", required: true),
      check_executable("dropdb", required: false, note: "needed for tak.remove")
    ]

    passed = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _, _}, &1))

    {passed, failed, results}
  end

  # --- Private helpers ---

  defp validate_name(name) do
    if name in Tak.names(), do: :ok, else: {:error, {:invalid_name, name}}
  end

  defp validate_not_exists(name) do
    path = Path.join(Tak.trees_dir(), name)
    if File.dir?(path), do: {:error, {:already_exists, name}}, else: :ok
  end

  defp load_worktree_info(name, worktree_path) do
    # Prefer metadata file, fall back to legacy config scraping
    case Tak.Metadata.read(worktree_path) do
      %Tak.Worktree{} = wt ->
        port = wt.port
        branch = wt.branch || Tak.Git.worktree_branch(worktree_path)

        %{
          name: name,
          branch: branch,
          port: port,
          status: port_status(port),
          pid: if(Tak.Port.in_use?(port), do: Tak.Port.pid(port)),
          database: wt.database,
          database_managed?: wt.database_managed?,
          main?: false
        }

      nil ->
        # Legacy: no metadata file, scrape config
        branch = Tak.Git.worktree_branch(worktree_path)
        port = Tak.Config.get_port(worktree_path)
        has_db = Tak.Config.has_database?(worktree_path)

        %{
          name: name,
          branch: branch,
          port: port,
          status: port_status(port),
          pid: if(port && Tak.Port.in_use?(port), do: Tak.Port.pid(port)),
          database: if(has_db, do: Tak.database_for(name)),
          database_managed?: has_db,
          main?: false
        }
    end
  end

  defp port_status(nil), do: :unknown
  defp port_status(port), do: if(Tak.Port.in_use?(port), do: :running, else: :stopped)

  defp write_dev_local_config(worktree_path, name, port, create_db) do
    app_name = Tak.app_name()
    endpoint = inspect(Tak.endpoint())
    repo = inspect(Tak.repo())

    config_dir = Path.join(worktree_path, "config")
    File.mkdir_p!(config_dir)
    dest_path = Path.join(config_dir, "dev.local.exs")
    source_path = "config/dev.local.exs"

    db_config =
      if create_db do
        database = Tak.database_for(name)

        """

        config :#{app_name}, #{repo},
          database: "#{database}"
        """
      else
        ""
      end

    tak_config = """

    # Tak worktree config (#{name})
    # These values override any earlier config above
    config :#{app_name}, #{endpoint},
      http: [port: #{port}]
    """ <> db_config

    if File.exists?(source_path) do
      existing = File.read!(source_path)
      File.write!(dest_path, existing <> tak_config)
    else
      File.write!(dest_path, "import Config" <> tak_config)
    end
  end

  defp write_mise_config(worktree_path, port) do
    mise_config = """
    [env]
    PORT = "#{port}"
    """

    mise_path = Path.join(worktree_path, "mise.local.toml")
    File.write!(mise_path, mise_config)
    System.cmd("mise", ["trust", mise_path], stderr_to_stdout: true)
  end

  defp mix_in_worktree!(path, args) do
    case System.cmd("mix", args, cd: path, stderr_to_stdout: true, env: [{"MIX_ENV", "dev"}]) do
      {_, 0} -> :ok
      {output, _} -> Mix.raise("mix #{Enum.join(args, " ")} failed in #{path}:\n#{output}")
    end
  end

  # --- Doctor checks ---

  defp check_dev_local_import do
    config_path = "config/config.exs"

    cond do
      not File.exists?(config_path) ->
        {:error, "config/config.exs imports local overrides", "File not found"}

      true ->
        content = File.read!(config_path)

        if Regex.match?(~r/import_config.*\.local\.exs/, content) do
          {:ok, "config/config.exs imports local overrides"}
        else
          {:error, "config/config.exs imports local overrides", "Missing import"}
        end
    end
  end

  defp check_gitignore(pattern, display, opts) do
    required = Keyword.get(opts, :required, true)
    note = Keyword.get(opts, :note)
    gitignore_path = ".gitignore"

    cond do
      not File.exists?(gitignore_path) ->
        if required,
          do: {:error, "#{display} in .gitignore", ".gitignore not found"},
          else: {:warn, "#{display} in .gitignore", note}

      true ->
        content = File.read!(gitignore_path)
        lines = String.split(content, "\n")

        found =
          Enum.any?(lines, fn line ->
            line = String.trim(line)

            cond do
              String.starts_with?(line, "#") -> false
              line == "" -> false
              String.contains?(line, pattern) -> true
              true -> false
            end
          end)

        cond do
          found -> {:ok, "#{display} in .gitignore"}
          required -> {:error, "#{display} in .gitignore", "Not ignored"}
          true -> {:warn, "#{display} in .gitignore", note}
        end
    end
  end

  defp check_executable(name, opts) do
    required = Keyword.get(opts, :required, true)
    note = Keyword.get(opts, :note)

    if System.find_executable(name) do
      {:ok, "#{name} available"}
    else
      if required,
        do: {:error, "#{name} available", "Not found"},
        else: {:warn, "#{name} available", "Not found (#{note})"}
    end
  end
end
