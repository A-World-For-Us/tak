defmodule Tak.ConfigTest do
  use ExUnit.Case, async: true

  # Move config-related tests from tak_test.exs here for the new module

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "tak_config_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)
    {:ok, tmp_dir: tmp_dir}
  end

  describe "get_port/1" do
    test "reads port from dev.local.exs", %{tmp_dir: tmp_dir} do
      write_dev_local!(tmp_dir, """
      import Config

      config :myapp, MyappWeb.Endpoint,
        http: [port: 4010]
      """)

      assert Tak.Config.get_port(tmp_dir) == 4010
    end

    test "reads port from dev.local.exs with multiple http options", %{tmp_dir: tmp_dir} do
      write_dev_local!(tmp_dir, """
      import Config

      config :myapp, MyappWeb.Endpoint,
        http: [ip: {127, 0, 0, 1}, port: 4020]
      """)

      assert Tak.Config.get_port(tmp_dir) == 4020
    end

    test "reads port from multiline http config", %{tmp_dir: tmp_dir} do
      write_dev_local!(tmp_dir, """
      import Config

      config :myapp, MyappWeb.Endpoint,
        http: [
          ip: {127, 0, 0, 1},
          port: 4050
        ]
      """)

      assert Tak.Config.get_port(tmp_dir) == 4050
    end

    test "falls back to mise.local.toml", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "mise.local.toml"), """
      [env]
      PORT = "4030"
      """)

      assert Tak.Config.get_port(tmp_dir) == 4030
    end

    test "falls back to .env", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, ".env"), """
      PORT=4040
      """)

      assert Tak.Config.get_port(tmp_dir) == 4040
    end

    test "returns nil when no config found", %{tmp_dir: tmp_dir} do
      assert Tak.Config.get_port(tmp_dir) == nil
    end

    test "prefers dev.local.exs over mise.local.toml", %{tmp_dir: tmp_dir} do
      write_dev_local!(tmp_dir, """
      import Config

      config :myapp, MyappWeb.Endpoint,
        http: [port: 4010]
      """)

      File.write!(Path.join(tmp_dir, "mise.local.toml"), """
      [env]
      PORT = "4030"
      """)

      assert Tak.Config.get_port(tmp_dir) == 4010
    end
  end

  describe "has_database?/1" do
    test "returns true when tak added database config", %{tmp_dir: tmp_dir} do
      write_dev_local!(tmp_dir, """
      import Config

      # Tak worktree config (armstrong)
      config :myapp, MyappWeb.Endpoint,
        http: [port: 4010]

      config :myapp, Myapp.Repo,
        database: "myapp_dev_armstrong"
      """)

      assert Tak.Config.has_database?(tmp_dir) == true
    end

    test "returns false when tak config exists but no database", %{tmp_dir: tmp_dir} do
      write_dev_local!(tmp_dir, """
      import Config

      # Tak worktree config (armstrong)
      config :myapp, MyappWeb.Endpoint,
        http: [port: 4010]
      """)

      assert Tak.Config.has_database?(tmp_dir) == false
    end

    test "returns false when database config exists but not from tak", %{tmp_dir: tmp_dir} do
      write_dev_local!(tmp_dir, """
      import Config

      config :myapp, Myapp.Repo,
        database: "myapp_dev"
      """)

      assert Tak.Config.has_database?(tmp_dir) == false
    end

    test "returns false when no config file exists", %{tmp_dir: tmp_dir} do
      assert Tak.Config.has_database?(tmp_dir) == false
    end
  end

  defp write_dev_local!(tmp_dir, content) do
    config_dir = Path.join(tmp_dir, "config")
    File.mkdir_p!(config_dir)
    File.write!(Path.join(config_dir, "dev.local.exs"), content)
  end
end
