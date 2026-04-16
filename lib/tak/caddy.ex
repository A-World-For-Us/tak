defmodule Tak.Caddy do
  @moduledoc """
  Manages Caddy reverse-proxy routes for worktrees via the admin API.

  Routes are added to an existing Caddy server (default `srv0`) so they
  inherit its TLS configuration. This avoids HSTS issues with `.localhost`
  subdomains that browsers force to HTTPS.

  ## Configuration

      config :tak,
        caddy_route_patterns: [
          "{name}.app.localhost",
          "*.catalog-{name}.localhost"
        ],
        caddy_server: "srv0",
        caddy_admin: "http://localhost:2019"

  Each pattern uses `{name}` as a placeholder for the worktree name.
  All hostnames are added to a single Caddy route.
  """

  require Logger

  @default_admin "http://localhost:2019"
  @default_server "srv0"

  @doc """
  Registers a Caddy route for a worktree.

  Adds a route to the configured Caddy server matching the worktree's
  hostnames to its port.
  """
  @spec add_route(Tak.Worktree.t()) :: :ok
  def add_route(%Tak.Worktree{} = worktree) do
    patterns = Application.get_env(:tak, :caddy_route_patterns, [])

    if patterns == [] do
      :ok
    else
      hostnames = Enum.map(patterns, &String.replace(&1, "{name}", worktree.name))
      route_id = route_id(worktree.name)

      with :ok <- ensure_caddy_running(),
           :ok <- delete_route(route_id),
           :ok <- put_route(route_id, hostnames, worktree.port) do
        :ok
      else
        {:error, reason} ->
          Logger.warning("Caddy route setup failed: #{reason}")
          :ok
      end
    end
  end

  @doc """
  Removes the Caddy route for a worktree.
  """
  @spec remove_route(String.t()) :: :ok
  def remove_route(name) do
    delete_route(route_id(name))
  end

  @doc """
  Returns the URL for accessing a worktree through Caddy, or `nil`
  if no route pattern is configured.
  """
  @spec url_for(Tak.Worktree.t()) :: String.t() | nil
  def url_for(%Tak.Worktree{} = worktree) do
    case Application.get_env(:tak, :caddy_route_patterns, []) do
      [] ->
        nil

      [first | _] ->
        hostname = String.replace(first, "{name}", worktree.name)
        "https://#{hostname}"
    end
  end

  # --- Private ---

  defp admin_url, do: Application.get_env(:tak, :caddy_admin, @default_admin)
  defp server_name, do: Application.get_env(:tak, :caddy_server, @default_server)

  defp route_id(name) do
    app = Tak.app_name()
    "wt:#{app}:#{name}"
  end

  defp ensure_caddy_running do
    case curl(:get, "/config/") do
      {:ok, _} -> :ok
      {:error, _} -> start_caddy()
    end
  end

  defp start_caddy do
    case System.cmd("caddy", ["start"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> {:error, "caddy start failed: #{String.trim(output)}"}
    end
  end

  defp put_route(route_id, hostnames, port) when is_list(hostnames) do
    path = "/config/apps/http/servers/#{server_name()}/routes/0"

    body =
      JSON.encode!(%{
        "@id": route_id,
        match: [%{host: hostnames}],
        handle: [
          %{
            handler: "subroute",
            routes: [
              %{
                handle: [
                  %{
                    handler: "reverse_proxy",
                    upstreams: [%{dial: "127.0.0.1:#{port}"}]
                  }
                ]
              }
            ]
          }
        ]
      })

    case curl(:put, path, body) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "put route #{route_id}: #{reason}"}
    end
  end

  defp delete_route(route_id) do
    case curl(:delete, "/id/#{route_id}") do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp curl(method, path, body \\ nil) do
    url = admin_url() <> path

    args =
      ["-sf", "--max-time", "2"] ++
        method_args(method) ++
        body_args(body) ++
        [url]

    case System.cmd("curl", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, String.trim(output)}
    end
  end

  defp method_args(:get), do: []
  defp method_args(:put), do: ["-X", "PUT", "-H", "Content-Type: application/json"]
  defp method_args(:delete), do: ["-X", "DELETE"]

  defp body_args(nil), do: []
  defp body_args(body), do: ["-d", body]
end
