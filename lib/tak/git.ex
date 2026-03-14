defmodule Tak.Git do
  @moduledoc """
  Git operations for worktree management.
  """

  @doc """
  Gets the branch name for a worktree from git.
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
  Returns the current branch name.
  """
  def current_branch do
    case System.cmd("git", ["branch", "--show-current"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      _ -> "unknown"
    end
  end

  @doc """
  Checks if a local branch exists.
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
  Runs a git command, raising on failure.
  """
  def run!(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> Mix.raise("git #{Enum.join(args, " ")} failed:\n#{output}")
    end
  end
end
