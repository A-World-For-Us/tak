defmodule Mix.Tasks.Tak.Remove do
  @shortdoc "Remove a git worktree and clean up resources"
  @moduledoc """
  Removes a git worktree and releases its port, branch, and database.

      $ mix tak.remove <name> [--force] [--yes]

  Steps, in order:

  1. Kill any process using the worktree's port (SIGTERM, then SIGKILL after 2s).
     See `Tak.Port.kill/1`.
  2. Remove the git worktree directory.
  3. Delete the git branch with `git branch -d` (safe: skips if the branch is
     unmerged). Pass `--force` to use `git branch -D` instead.
  4. Drop the database with `dropdb`, but only if tak created it (i.e., the
     worktree has a Tak-managed database entry in `config/dev.local.exs`).

  Without `--yes`, the task prints what it will delete and asks for confirmation.

  ## Arguments

    * `name` — the worktree slot name to remove (required)

  ## Options

    * `--force` — remove even with uncommitted changes; force-delete the branch
    * `--yes` — skip the confirmation prompt

  ## Examples

      $ mix tak.remove armstrong
      $ mix tak.remove armstrong --force
      $ mix tak.remove armstrong --yes

  > #### Warning {: .warning}
  >
  > `--force` deletes the branch even if it has unmerged commits. Make sure
  > your work is pushed or merged before using it.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, args, _} = OptionParser.parse(args, strict: [force: :boolean, yes: :boolean])
    force = Keyword.get(opts, :force, false)
    skip_confirm = Keyword.get(opts, :yes, false)

    case args do
      [] ->
        Mix.shell().error("Usage: mix tak.remove <name> [--force] [--yes]")
        list_available_worktrees()
        exit({:shutdown, 1})

      [name | _] ->
        trees_dir = Tak.trees_dir()
        worktree_path = Path.join(trees_dir, name)

        unless File.dir?(worktree_path) do
          Mix.shell().error("Error: Worktree #{worktree_path} does not exist")
          list_available_worktrees()
          exit({:shutdown, 1})
        end

        unless skip_confirm do
          has_db = Tak.Config.has_database?(worktree_path)

          Mix.shell().info("This will remove:")
          Mix.shell().info("  Worktree: #{worktree_path}")
          if has_db, do: Mix.shell().info("  Database: #{Tak.database_for(name)}")

          unless Mix.shell().yes?("Continue?") do
            Mix.shell().info("Aborted.")
            exit(:normal)
          end
        end

        remove_worktree(name, force)
    end
  end

  defp list_available_worktrees do
    trees_dir = Tak.trees_dir()

    if File.dir?(trees_dir) do
      worktrees = trees_dir |> File.ls!() |> Enum.filter(&File.dir?(Path.join(trees_dir, &1)))

      unless Enum.empty?(worktrees) do
        Mix.shell().info("Available: #{Enum.join(worktrees, ", ")}")
      end
    end
  end

  defp remove_worktree(name, force) do
    trees_dir = Tak.trees_dir()
    worktree_path = Path.join(trees_dir, name)

    # Get info before removal
    branch = Tak.Git.worktree_branch(worktree_path)
    port = Tak.Config.get_port(worktree_path)
    database = Tak.database_for(name)
    has_db = Tak.Config.has_database?(worktree_path)

    # Stop services on port
    if port do
      Mix.shell().info("Stopping services on port #{port}...")
      Tak.Port.kill(port)
    end

    # Remove worktree
    Mix.shell().info("Removing worktree...")

    remove_result =
      if force do
        System.cmd("git", ["worktree", "remove", "--force", worktree_path], stderr_to_stdout: true)
      else
        System.cmd("git", ["worktree", "remove", worktree_path], stderr_to_stdout: true)
      end

    case remove_result do
      {_, 0} ->
        :ok

      {output, _} ->
        unless force do
          Mix.shell().error("Failed to remove worktree (uncommitted changes?)")
          Mix.shell().error(output)
          Mix.shell().info("Use --force to force removal")
          exit({:shutdown, 1})
        end
    end

    # Clean up any orphaned files
    File.rm_rf(worktree_path)
    System.cmd("git", ["worktree", "prune"], stderr_to_stdout: true)

    # Delete branch
    if branch && branch != "unknown" do
      Mix.shell().info("Deleting branch #{branch}...")

      if force do
        System.cmd("git", ["branch", "-D", branch], stderr_to_stdout: true)
      else
        case System.cmd("git", ["branch", "-d", branch], stderr_to_stdout: true) do
          {_, 0} -> :ok
          {_, _} -> Mix.shell().info("Branch not deleted (unmerged changes or doesn't exist)")
        end
      end
    end

    # Drop database (only if it was created)
    if has_db do
      Mix.shell().info("Dropping database #{database}...")

      case System.cmd("dropdb", [database], stderr_to_stdout: true) do
        {_, 0} -> :ok
        {_, _} -> Mix.shell().info("Database not dropped (may not exist)")
      end
    end

    # Success output
    Mix.shell().info("")
    Mix.shell().info(IO.ANSI.format([:green, "Worktree removed successfully!"]))
    Mix.shell().info("")
    Mix.shell().info("  Name:     #{name}")
    if branch && branch != "unknown", do: Mix.shell().info("  Branch:   #{branch}")
    if has_db, do: Mix.shell().info("  Database: #{database}")
  end

end
