defmodule Tak.Git do
  @moduledoc """
  Git operations used by Tak's Mix tasks.

  All functions shell out to `git` and require it to be on `PATH`. They are
  designed to be called from the main repository root, not from inside a
  worktree directory.
  """

  @doc """
  Returns the branch name checked out in a worktree, or `nil` if it cannot
  be determined.

  Parses `git worktree list --porcelain` output and matches on the absolute
  path of the worktree. Returns `nil` for detached HEAD worktrees (which have
  no `branch refs/heads/` line) and when `git` exits with a non-zero status.

  ## Example

      Tak.Git.worktree_branch("/path/to/trees/armstrong")
      # => "feature/login" or nil
  """
  def worktree_branch(worktree_path) do
    abs_path = Path.expand(worktree_path)

    case System.cmd("git", ["worktree", "list", "--porcelain"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n\n")
        |> Enum.find_value(fn block ->
          if String.contains?(block, "worktree #{abs_path}") do
            block
            |> String.split("\n")
            |> Enum.find_value(fn line ->
              case String.split(line, "branch refs/heads/") do
                [_, branch] -> branch
                _ -> nil
              end
            end)
          end
        end)

      _ ->
        nil
    end
  end

  @doc """
  Returns the current branch name, or `"unknown"` if `git` fails.

  Runs `git branch --show-current`. Returns an empty string on a detached
  HEAD, which callers should treat as an unknown state.

  ## Example

      Tak.Git.current_branch()
      # => "main"
  """
  def current_branch do
    case System.cmd("git", ["branch", "--show-current"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> "unknown"
    end
  end

  @doc """
  Returns `true` if a local branch with the given name exists.

  Uses `git show-ref --verify` against `refs/heads/<branch>`.

  ## Example

      Tak.Git.branch_exists?("main")
      # => true
  """
  def branch_exists?(branch) do
    case System.cmd("git", ["show-ref", "--verify", "--quiet", "refs/heads/#{branch}"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  end

  @doc """
  Runs a `git` command with the given arguments. Returns `:ok` on success.

  Raises via `Mix.raise/1` when `git` exits with a non-zero status, including
  the full command output in the error message.

  ## Example

      Tak.Git.run!(["worktree", "add", "trees/armstrong", "feature/login"])
      :ok
  """
  def run!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> Mix.raise("git #{Enum.join(args, " ")} failed:\n#{output}")
    end
  end
end
