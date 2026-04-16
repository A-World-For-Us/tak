defmodule Tak.TestSystem do
  def configure(handler, executables \\ %{}) do
    Process.put({__MODULE__, :handler}, handler)
    Process.put({__MODULE__, :executables}, executables)
    Process.put({__MODULE__, :history}, [])
  end

  def history do
    Process.get({__MODULE__, :history}, []) |> Enum.reverse()
  end

  def cmd(command, args, opts \\ []) do
    Process.put({__MODULE__, :history}, [
      {command, args, opts} | Process.get({__MODULE__, :history}, [])
    ])

    Process.get({__MODULE__, :handler}).(command, args, opts)
  end

  def find_executable(name) do
    Map.get(Process.get({__MODULE__, :executables}, %{}), name)
  end

  def run_mix_stream(path, args, _opts \\ []) do
    command = Enum.join(["mix" | args], " ")
    opts = [cd: path]

    Process.put({__MODULE__, :history}, [
      {"mix", args, opts} | Process.get({__MODULE__, :history}, [])
    ])

    case Process.get({__MODULE__, :handler}).("mix", args, opts) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, {:bootstrap_failed, command, output}}
    end
  end
end

defmodule Tak.WorktreesTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  setup do
    tmp_dir =
      Path.join(System.tmp_dir!(), "tak_worktrees_test_#{System.unique_integer([:positive])}")

    trees_dir = Path.join(tmp_dir, "trees")
    File.mkdir_p!(trees_dir)

    previous = %{
      trees_dir: Application.get_env(:tak, :trees_dir),
      names: Application.get_env(:tak, :names),
      base_port: Application.get_env(:tak, :base_port),
      system_mod: Application.get_env(:tak, :system_mod)
    }

    Application.put_env(:tak, :trees_dir, trees_dir)
    Application.put_env(:tak, :names, ["armstrong", "hickey"])
    Application.put_env(:tak, :base_port, 4000)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)

      Enum.each(previous, fn
        {key, nil} -> Application.delete_env(:tak, key)
        {key, value} -> Application.put_env(:tak, key, value)
      end)
    end)

    {:ok, tmp_dir: tmp_dir, trees_dir: trees_dir}
  end

  describe "list/0" do
    test "returns {main, worktrees} tuple of typed status entries" do
      {main, worktrees} = Tak.Worktrees.list()

      assert %Tak.WorktreeStatus{} = main
      assert %Tak.Worktree{name: "main", port: port} = main.worktree
      assert is_integer(port)
      assert main.status in [:running, :stopped]
      assert is_list(worktrees)
    end

    test "entries use a consistent typed shape" do
      {main, worktrees} = Tak.Worktrees.list()

      for entry <- [main | worktrees] do
        assert %Tak.WorktreeStatus{} = entry
        assert %Tak.Worktree{} = entry.worktree
        assert entry.status in [:running, :stopped, :unknown]
      end
    end

    test "main status is inferred from the nested worktree name" do
      {main, worktrees} = Tak.Worktrees.list()

      assert main.worktree.name == "main"
      assert Enum.all?(worktrees, fn entry -> entry.worktree.name != "main" end)
    end

    test "prefers metadata over legacy config when both exist", %{trees_dir: trees_dir} do
      worktree_path = Path.join(trees_dir, "armstrong")
      File.mkdir_p!(Path.join(worktree_path, "config"))

      Tak.Metadata.write!(%Tak.Worktree{
        name: "armstrong",
        branch: "feature/from-metadata",
        port: 4550,
        path: worktree_path,
        database: "tak_dev_armstrong",
        database_managed?: true
      })

      File.write!(Path.join(worktree_path, "config/dev.local.exs"), """
      import Config

      # Tak worktree config (armstrong)
      config :tak, TakWeb.Endpoint,
        http: [port: 4999]

      config :tak, Tak.Repo,
        database: "wrong_db"
      """)

      {_main, [entry]} = Tak.Worktrees.list()

      assert entry.worktree.branch == "feature/from-metadata"
      assert entry.worktree.port == 4550
      assert entry.worktree.database == "tak_dev_armstrong"
    end

    test "falls back to legacy config when metadata is absent", %{trees_dir: trees_dir} do
      worktree_path = Path.join(trees_dir, "armstrong")
      File.mkdir_p!(Path.join(worktree_path, "config"))

      File.write!(Path.join(worktree_path, "config/dev.local.exs"), """
      import Config

      # Tak worktree config (armstrong)
      config :tak, TakWeb.Endpoint,
        http: [port: 4770]

      config :tak, Tak.Repo,
        database: "tak_dev_armstrong"
      """)

      {_main, [entry]} = Tak.Worktrees.list()

      assert entry.worktree.name == "armstrong"
      assert entry.worktree.port == 4770
      assert entry.worktree.database == "tak_dev_armstrong"
      assert entry.worktree.database_managed? == true
    end
  end

  describe "doctor/0" do
    test "returns structured results" do
      {passed, failed, results} = Tak.Worktrees.doctor()
      assert is_integer(passed)
      assert is_integer(failed)
      assert is_list(results)

      for result <- results do
        case result do
          {:ok, msg} -> assert is_binary(msg)
          {:error, msg, reason} -> assert is_binary(msg) and is_binary(reason)
          {:warn, msg, reason} -> assert is_binary(msg) and is_binary(reason)
        end
      end
    end

    test "git check passes" do
      {_, _, results} = Tak.Worktrees.doctor()
      assert {:ok, "git available"} in results
    end
  end

  describe "create/3 validation" do
    test "rejects invalid names in fixed mode" do
      assert {:error, {:invalid_name, "nope"}} = Tak.Worktrees.create("branch", "nope")
    end

    test "accepts any name in dynamic mode" do
      Application.put_env(:tak, :names, :dynamic)
      # "nope" would be rejected in fixed mode, but accepted in dynamic mode.
      # It will fail at the git step (not validation), which proves it passed name validation.
      result = Tak.Worktrees.create("branch", "nope")
      refute match?({:error, {:invalid_name, _}}, result)
    after
      Application.put_env(:tak, :names, ["armstrong", "hickey"])
    end

    test "rejects already-existing worktrees", %{trees_dir: trees_dir} do
      name = List.first(Tak.names())
      path = Path.join(trees_dir, name)
      File.mkdir_p!(path)

      assert {:error, {:already_exists, ^name}} =
               Tak.Worktrees.create("feature/test", name)
    end
  end

  describe "create/3" do
    test "writes metadata only after successful bootstrap", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "mix", ["deps.get"], opts ->
          assert opts[:cd] == Path.join(trees_dir, "armstrong")
          {"", 0}

        "mix", ["ecto.setup"], opts ->
          assert opts[:cd] == Path.join(trees_dir, "armstrong")
          {"", 0}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:ok, worktree} = Tak.Worktrees.create("feature/test", "armstrong", create_db: true)
      assert File.exists?(Path.join(worktree.path, ".tak"))

      metadata = Tak.Metadata.read(worktree.path)
      assert metadata.name == "armstrong"
      assert metadata.database == "tak_dev_armstrong"
      assert metadata.database_managed? == true
    end

    test "cleans up the worktree when bootstrap fails", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "git", ["worktree", "remove", "--force", path], _opts ->
          File.rm_rf!(path)
          {"", 0}

        "git", ["worktree", "prune"], _opts ->
          {"", 0}

        "git", ["branch", "-D", _branch], _opts ->
          {"", 0}

        "mix", ["deps.get"], _opts ->
          {"", 0}

        "mix", ["ecto.setup"], _opts ->
          {"ecto failed", 1}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:error, {:bootstrap_failed, "mix ecto.setup", "ecto failed"}} =
               Tak.Worktrees.create("feature/test", "armstrong", create_db: true)

      refute File.exists?(Path.join([trees_dir, "armstrong", ".tak"]))
      refute File.dir?(Path.join(trees_dir, "armstrong"))
    end

    test "returns cleanup_failed when automatic cleanup cannot complete", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "git", ["worktree", "remove", "--force", _path], _opts ->
          {"cleanup failed", 1}

        "mix", ["deps.get"], _opts ->
          {"", 0}

        "mix", ["ecto.setup"], _opts ->
          {"ecto failed", 1}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:error, {:bootstrap_failed, "mix ecto.setup", "ecto failed", :cleanup_failed}} =
               Tak.Worktrees.create("feature/test", "armstrong", create_db: true)

      # Metadata is written before bootstrap, so .tak exists even when cleanup fails
      assert File.exists?(Path.join([trees_dir, "armstrong", ".tak"]))
      assert File.dir?(Path.join(trees_dir, "armstrong"))
    end

    test "logs a warning when the assigned port is already in use" do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "mix", ["deps.get"], _opts ->
          {"", 0}

        _command, _args, _opts ->
          {"", 0}
      end)

      {:ok, socket} = :gen_tcp.listen(4010, reuseaddr: true)

      log =
        capture_log(fn ->
          assert {:ok, _worktree} =
                   Tak.Worktrees.create("feature/test", "armstrong", create_db: false)
        end)

      assert log =~ "Tak worktree port 4010 is already in use"
      :gen_tcp.close(socket)
    end

    test "calls copy_build_artifacts during creation", _context do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, ["_build"])

      File.mkdir_p!("_build")

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:ok, worktree} =
               Tak.Worktrees.create("feature/test", "armstrong", create_db: false)

      cp_calls =
        Tak.TestSystem.history()
        |> Enum.filter(fn {cmd, _, _} -> cmd == "cp" end)

      assert length(cp_calls) == 1
      {_, ["-r", "_build", dest], _} = hd(cp_calls)
      assert dest == Path.join(worktree.path, "_build")
    after
      Application.delete_env(:tak, :copy_dirs)
    end

    test "uses write_mise? to gate mise config", _context do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, false)
      Application.put_env(:tak, :write_mise, false)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "mise", _args, _opts ->
          flunk("mise should not be called when write_mise is false")

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:ok, worktree} =
               Tak.Worktrees.create("feature/test", "armstrong", create_db: false)

      refute File.exists?(Path.join(worktree.path, "mise.local.toml"))
    after
      Application.delete_env(:tak, :copy_dirs)
      Application.delete_env(:tak, :write_mise)
    end

    test "writes metadata before bootstrap so runtime.exs can read it", _context do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, false)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "mix", ["deps.get"], opts ->
          worktree_path = opts[:cd]

          assert File.exists?(Path.join(worktree_path, ".tak")),
                 ".tak should be written before bootstrap runs"

          {"", 0}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:ok, _worktree} =
               Tak.Worktrees.create("feature/test", "armstrong", create_db: false)
    after
      Application.delete_env(:tak, :copy_dirs)
    end

    test "runs deps.get and ecto.setup as separate steps", _context do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, false)

      deps_get_called = :ets.new(:deps_get_called, [:set, :public])
      :ets.insert(deps_get_called, {:called, false})

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        "mix", ["deps.get"], _opts ->
          :ets.insert(deps_get_called, {:called, true})
          {"", 0}

        "mix", ["ecto.setup"], _opts ->
          [{:called, true}] = :ets.lookup(deps_get_called, :called)
          {"", 0}

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:ok, _worktree} =
               Tak.Worktrees.create("feature/test", "armstrong", create_db: true)

      mix_calls =
        Tak.TestSystem.history()
        |> Enum.filter(fn
          {"mix", _, _} -> true
          _ -> false
        end)

      assert [{"mix", ["deps.get"], _}, {"mix", ["ecto.setup"], _}] = mix_calls
    after
      Application.delete_env(:tak, :copy_dirs)
    end

    test "prints step labels during creation", _context do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, false)

      Tak.TestSystem.configure(fn
        "git", ["show-ref" | _], _opts ->
          {"", 1}

        "git", ["worktree", "add", "-b", _branch, path], _opts ->
          File.mkdir_p!(path)
          {"", 0}

        _command, _args, _opts ->
          {"", 0}
      end)

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert {:ok, _worktree} =
                   Tak.Worktrees.create("feature/test", "armstrong", create_db: false)
        end)

      assert output =~ "Creating git worktree"
      assert output =~ "Copying .env"
      assert output =~ "Writing .tak metadata"
      assert output =~ "Writing config/runtime.local.exs"
      assert output =~ "Running mix deps.get"
    after
      Application.delete_env(:tak, :copy_dirs)
    end
  end

  describe "copy_build_artifacts/1" do
    test "copies configured dirs via Tak.System.cmd", %{tmp_dir: tmp_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, ["_build", "deps"])

      worktree_path = Path.join(tmp_dir, "wt")
      File.mkdir_p!(worktree_path)

      File.mkdir_p!("_build")
      File.mkdir_p!("deps")

      Tak.TestSystem.configure(fn _cmd, _args, _opts -> {"", 0} end)

      assert :ok = Tak.Worktrees.copy_build_artifacts(worktree_path)

      history = Tak.TestSystem.history()
      cp_calls = Enum.filter(history, fn {cmd, _, _} -> cmd == "cp" end)
      assert length(cp_calls) == 2

      {_, ["-r", "_build", dest1], _} = Enum.at(cp_calls, 0)
      assert dest1 == Path.join(worktree_path, "_build")

      {_, ["-r", "deps", dest2], _} = Enum.at(cp_calls, 1)
      assert dest2 == Path.join(worktree_path, "deps")
    after
      Application.delete_env(:tak, :copy_dirs)
    end

    test "skips non-existent source dirs", %{tmp_dir: tmp_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, ["nonexistent_dir"])

      worktree_path = Path.join(tmp_dir, "wt")
      File.mkdir_p!(worktree_path)

      Tak.TestSystem.configure(fn _cmd, _args, _opts -> {"", 0} end)

      assert :ok = Tak.Worktrees.copy_build_artifacts(worktree_path)

      cp_calls = Enum.filter(Tak.TestSystem.history(), fn {cmd, _, _} -> cmd == "cp" end)
      assert cp_calls == []
    after
      Application.delete_env(:tak, :copy_dirs)
    end

    test "does nothing when copy_dirs is empty", %{tmp_dir: tmp_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, false)

      worktree_path = Path.join(tmp_dir, "wt")
      File.mkdir_p!(worktree_path)

      Tak.TestSystem.configure(fn _cmd, _args, _opts -> {"", 0} end)

      assert :ok = Tak.Worktrees.copy_build_artifacts(worktree_path)
      assert Tak.TestSystem.history() == []
    after
      Application.delete_env(:tak, :copy_dirs)
    end

    test "logs warning when manifest is missing and copy_dirs is non-empty", %{tmp_dir: tmp_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)
      Application.put_env(:tak, :copy_dirs, ["_build"])

      worktree_path = Path.join(tmp_dir, "wt")
      File.mkdir_p!(worktree_path)

      Tak.TestSystem.configure(fn _cmd, _args, _opts -> {"", 0} end)

      log =
        capture_log(fn ->
          Tak.Worktrees.copy_build_artifacts(worktree_path)
        end)

      assert log =~ "No compiled app found"
    after
      Application.delete_env(:tak, :copy_dirs)
    end
  end

  describe "patch_elixir_manifest/1" do
    test "patches manifests for all environments under _build", %{tmp_dir: tmp_dir} do
      worktree_path = Path.join(tmp_dir, "wt")
      old_root = Path.expand(".")
      fake_manifest = {:elixir, %{}, [], old_root, []}

      for env <- ["dev", "test"] do
        manifest_dir = Path.join([worktree_path, "_build", env, "lib", "tak", ".mix"])
        File.mkdir_p!(manifest_dir)
        File.write!(Path.join(manifest_dir, "compile.elixir"), :erlang.term_to_binary(fake_manifest))
      end

      Tak.Worktrees.patch_elixir_manifest(worktree_path)

      new_root = Path.expand(worktree_path)

      for env <- ["dev", "test"] do
        manifest_path = Path.join([worktree_path, "_build", env, "lib", "tak", ".mix", "compile.elixir"])
        patched = :erlang.binary_to_term(File.read!(manifest_path))
        assert elem(patched, 3) == new_root, "expected #{env} manifest root to be patched"
        assert elem(patched, 0) == :elixir
      end
    end

    test "is a no-op when _build does not exist", %{tmp_dir: tmp_dir} do
      worktree_path = Path.join(tmp_dir, "wt")
      assert :ok = Tak.Worktrees.patch_elixir_manifest(worktree_path)
    end
  end

  describe "remove/2" do
    test "keeps the database when requested", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      worktree_path = Path.join(trees_dir, "armstrong")
      File.mkdir_p!(worktree_path)

      Tak.Metadata.write!(%Tak.Worktree{
        name: "armstrong",
        branch: "feature/test",
        port: 4010,
        path: worktree_path,
        database: "tak_dev_armstrong",
        database_managed?: true
      })

      Tak.TestSystem.configure(fn
        "lsof", _args, _opts ->
          {"", 1}

        "git", ["worktree", "remove", path], _opts ->
          File.rm_rf!(path)
          {"", 0}

        "git", ["worktree", "prune"], _opts ->
          {"", 0}

        "git", ["branch", "-d", _branch], _opts ->
          {"", 0}

        "dropdb", _args, _opts ->
          flunk("dropdb should not run when keep_db is true")

        _command, _args, _opts ->
          {"", 0}
      end)

      assert {:ok, %Tak.RemoveResult{} = result} =
               Tak.Worktrees.remove("armstrong", keep_db: true)

      assert result.worktree.database == "tak_dev_armstrong"
      assert result.database_cleanup == :kept
      refute File.dir?(worktree_path)
      refute Enum.any?(Tak.TestSystem.history(), fn {command, _, _} -> command == "dropdb" end)
    end

    test "succeeds even when prune fails after worktree removal", %{trees_dir: trees_dir} do
      Application.put_env(:tak, :system_mod, Tak.TestSystem)

      worktree_path = Path.join(trees_dir, "armstrong")
      File.mkdir_p!(worktree_path)

      Tak.Metadata.write!(%Tak.Worktree{
        name: "armstrong",
        branch: "feature/test",
        port: 4010,
        path: worktree_path,
        database: nil,
        database_managed?: false
      })

      Tak.TestSystem.configure(fn
        "lsof", _args, _opts ->
          {"", 1}

        "git", ["worktree", "remove", path], _opts ->
          File.rm_rf!(path)
          {"", 0}

        "git", ["branch", "-d", _branch], _opts ->
          {"", 0}

        "git", ["worktree", "prune"], _opts ->
          {"prune warning", 1}

        _command, _args, _opts ->
          {"", 0}
      end)

      log =
        capture_log(fn ->
          assert {:ok, %Tak.RemoveResult{} = result} = Tak.Worktrees.remove("armstrong")
          assert result.worktree.name == "armstrong"
          assert result.database_cleanup == nil
        end)

      assert log =~ "Tak prune failed after worktree removal"
      refute File.dir?(worktree_path)
    end
  end
end
