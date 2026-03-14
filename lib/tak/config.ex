defmodule Tak.Config do
  @moduledoc """
  Reads worktree configuration from files on disk.

  Parses port and database settings from Tak-generated config files.
  These functions reliably read config that Tak itself writes. They use
  regex matching and are not intended for arbitrary Elixir config files.
  """

  @doc """
  Gets the port configured for a worktree by reading its config files.

  Checks in order:
  1. `config/dev.local.exs` - Elixir config
  2. `mise.local.toml` - mise env (legacy)
  3. `.env` - dotenv file (legacy)
  """
  def get_port(worktree_path) do
    dev_local_path = Path.join([worktree_path, "config", "dev.local.exs"])
    mise_path = Path.join(worktree_path, "mise.local.toml")
    env_path = Path.join(worktree_path, ".env")

    cond do
      File.exists?(dev_local_path) ->
        dev_local_path
        |> File.read!()
        |> then(fn content ->
          case Regex.run(~r/http:\s*\[[\s\S]*?port:\s*(\d+)/, content) do
            [_, port] -> String.to_integer(port)
            _ -> nil
          end
        end)

      File.exists?(mise_path) ->
        mise_path
        |> File.read!()
        |> then(fn content ->
          case Regex.run(~r/PORT\s*=\s*"?(\d+)"?/, content) do
            [_, port] -> String.to_integer(port)
            _ -> nil
          end
        end)

      File.exists?(env_path) ->
        env_path
        |> File.read!()
        |> then(fn content ->
          case Regex.run(~r/^PORT=(\d+)/m, content) do
            [_, port] -> String.to_integer(port)
            _ -> nil
          end
        end)

      true ->
        nil
    end
  end

  @doc """
  Checks if a worktree has Tak-managed database config in dev.local.exs.
  """
  def has_database?(worktree_path) do
    dev_local_path = Path.join([worktree_path, "config", "dev.local.exs"])

    if File.exists?(dev_local_path) do
      content = File.read!(dev_local_path)

      String.contains?(content, "# Tak worktree config") and
        String.contains?(content, "Repo,") and
        String.contains?(content, "database:")
    else
      false
    end
  end
end
