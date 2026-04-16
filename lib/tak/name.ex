defmodule Tak.Name do
  @moduledoc """
  Derives worktree names from git branch names.

  Sanitizes branch names into DNS-safe, filesystem-safe identifiers
  suitable for use as hostnames and directory names.
  """

  @prefixes ~w(feature/ feat/ fix/ bugfix/ hotfix/ chore/ release/)
  @max_length 30

  @doc """
  Derives a worktree name from a branch name.

  Strips common prefixes (`feature/`, `fix/`, etc.), lowercases,
  replaces non-alphanumeric characters with hyphens, collapses
  consecutive hyphens, and truncates to #{@max_length} characters.

  ## Examples

      iex> Tak.Name.from_branch("feature/my-cool-branch")
      "my-cool-branch"

      iex> Tak.Name.from_branch("fix/PROJ-123-broken-auth")
      "proj-123-broken-auth"

      iex> Tak.Name.from_branch("feature/123_some_thing")
      "123-some-thing"

      iex> Tak.Name.from_branch("main")
      "main"
  """
  @spec from_branch(String.t()) :: String.t()
  def from_branch(branch) do
    branch
    |> strip_prefix()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]/, "-")
    |> String.replace(~r/-{2,}/, "-")
    |> String.trim_leading("-")
    |> String.trim_trailing("-")
    |> truncate()
    |> fallback(branch)
  end

  @doc """
  Like `from_branch/1`, but appends a numeric suffix if the name
  already exists in `existing_names`.

  ## Examples

      iex> Tak.Name.from_branch("feature/login", ["login"])
      "login-2"

      iex> Tak.Name.from_branch("feature/login", ["login", "login-2"])
      "login-3"

      iex> Tak.Name.from_branch("feature/login", [])
      "login"
  """
  @spec from_branch(String.t(), [String.t()]) :: String.t()
  def from_branch(branch, existing_names) do
    base = from_branch(branch)
    deduplicate(base, existing_names)
  end

  defp strip_prefix(branch) do
    Enum.reduce_while(@prefixes, branch, fn prefix, acc ->
      case String.split(acc, prefix, parts: 2) do
        ["", rest] -> {:halt, rest}
        _ -> {:cont, acc}
      end
    end)
  end

  defp truncate(name) when byte_size(name) > @max_length do
    name
    |> String.slice(0, @max_length)
    |> String.trim_trailing("-")
  end

  defp truncate(name), do: name

  # If sanitization produces an empty string, use a short hash
  defp fallback("", branch) do
    hash = :crypto.hash(:sha256, branch) |> Base.encode16(case: :lower) |> String.slice(0, 8)
    "wt-#{hash}"
  end

  defp fallback(name, _branch), do: name

  defp deduplicate(base, existing) do
    if base in existing do
      find_available(base, existing, 2)
    else
      base
    end
  end

  defp find_available(base, existing, n) do
    candidate = "#{base}-#{n}"

    if candidate in existing do
      find_available(base, existing, n + 1)
    else
      candidate
    end
  end
end
