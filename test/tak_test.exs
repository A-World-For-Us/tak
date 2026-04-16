defmodule TakTest do
  use ExUnit.Case, async: true

  describe "names/0" do
    test "defaults to :dynamic" do
      assert Tak.names() == :dynamic
    end

    test "returns list when configured" do
      Application.put_env(:tak, :names, ~w(a b c))
      assert Tak.names() == ~w(a b c)
    after
      Application.delete_env(:tak, :names)
    end
  end

  describe "dynamic?/0" do
    test "true by default" do
      assert Tak.dynamic?() == true
    end

    test "false when names configured" do
      Application.put_env(:tak, :names, ~w(a b))
      assert Tak.dynamic?() == false
    after
      Application.delete_env(:tak, :names)
    end
  end

  describe "base_port/0" do
    test "returns default base port" do
      assert Tak.base_port() == 4000
    end
  end

  describe "trees_dir/0" do
    test "returns default trees directory" do
      assert Tak.trees_dir() == "trees"
    end
  end

  describe "create_database?/0" do
    test "returns true by default" do
      assert Tak.create_database?() == true
    end

    test "respects config override" do
      Application.put_env(:tak, :create_database, false)
      assert Tak.create_database?() == false
    after
      Application.delete_env(:tak, :create_database)
    end
  end

  describe "port_for/1" do
    test "calculates port based on name index in fixed mode" do
      Application.put_env(:tak, :names, ~w(armstrong hickey mccarthy))
      assert Tak.port_for("armstrong") == 4010
      assert Tak.port_for("hickey") == 4020
      assert Tak.port_for("mccarthy") == 4030
    after
      Application.delete_env(:tak, :names)
    end

    test "returns nil for unknown name in fixed mode" do
      Application.put_env(:tak, :names, ~w(armstrong))
      assert Tak.port_for("unknown") == nil
    after
      Application.delete_env(:tak, :names)
    end

    test "returns nil in dynamic mode when worktree does not exist" do
      assert Tak.port_for("nonexistent") == nil
    end
  end

  describe "database_for/1" do
    test "generates database name with app and worktree name" do
      assert Tak.database_for("armstrong") == "tak_dev_armstrong"
    end
  end

  describe "module_name/0" do
    test "camelizes the app name" do
      assert Tak.module_name() == "Tak"
    end
  end

  describe "copy_dirs/0" do
    test "returns default dirs" do
      assert Tak.copy_dirs() == ["_build", "deps"]
    end

    test "returns empty list when set to false" do
      Application.put_env(:tak, :copy_dirs, false)
      assert Tak.copy_dirs() == []
    after
      Application.delete_env(:tak, :copy_dirs)
    end

    test "respects custom list" do
      Application.put_env(:tak, :copy_dirs, ["_build"])
      assert Tak.copy_dirs() == ["_build"]
    after
      Application.delete_env(:tak, :copy_dirs)
    end

    test "falls back to default for invalid value" do
      Application.put_env(:tak, :copy_dirs, "invalid")
      assert Tak.copy_dirs() == ["_build", "deps"]
    after
      Application.delete_env(:tak, :copy_dirs)
    end
  end

  describe "write_mise?/0" do
    test "returns false when config is false" do
      Application.put_env(:tak, :write_mise, false)
      assert Tak.write_mise?() == false
    after
      Application.delete_env(:tak, :write_mise)
    end

    test "returns boolean based on config and executable presence" do
      assert is_boolean(Tak.write_mise?())
    end
  end

  describe "mise_available?/0" do
    test "returns a boolean" do
      result = Tak.mise_available?()
      assert is_boolean(result)
    end
  end

  describe "endpoint/0" do
    test "infers from app name by default" do
      assert Tak.endpoint() == TakWeb.Endpoint
    end

    test "respects config override" do
      Application.put_env(:tak, :endpoint, MyCustomWeb.Endpoint)
      assert Tak.endpoint() == MyCustomWeb.Endpoint
    after
      Application.delete_env(:tak, :endpoint)
    end
  end

  describe "repo/0" do
    test "infers from app name by default" do
      assert Tak.repo() == Tak.Repo
    end

    test "respects config override" do
      Application.put_env(:tak, :repo, MyCustom.Repo)
      assert Tak.repo() == MyCustom.Repo
    after
      Application.delete_env(:tak, :repo)
    end
  end
end
