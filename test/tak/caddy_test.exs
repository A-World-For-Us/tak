defmodule Tak.CaddyTest do
  use ExUnit.Case, async: true

  describe "url_for/1" do
    test "returns HTTPS URL from first pattern" do
      Application.put_env(:tak, :caddy_route_patterns, [
        "{name}.app.localhost",
        "*.catalog-{name}.localhost"
      ])

      worktree = %Tak.Worktree{
        name: "my-branch",
        branch: "feature/my-branch",
        port: 4010,
        path: "/tmp/trees/my-branch"
      }

      assert Tak.Caddy.url_for(worktree) == "https://my-branch.app.localhost"
    after
      Application.delete_env(:tak, :caddy_route_patterns)
    end

    test "returns nil when no patterns configured" do
      Application.delete_env(:tak, :caddy_route_patterns)

      worktree = %Tak.Worktree{
        name: "my-branch",
        branch: "feature/my-branch",
        port: 4010,
        path: "/tmp/trees/my-branch"
      }

      assert Tak.Caddy.url_for(worktree) == nil
    end
  end

  describe "add_route/1" do
    test "does nothing when no patterns configured" do
      Application.delete_env(:tak, :caddy_route_patterns)

      worktree = %Tak.Worktree{
        name: "test",
        branch: "feature/test",
        port: 4010,
        path: "/tmp/trees/test"
      }

      assert :ok = Tak.Caddy.add_route(worktree)
    end
  end

  describe "remove_route/1" do
    test "succeeds even when caddy is not running" do
      assert :ok = Tak.Caddy.remove_route("nonexistent")
    end
  end
end
