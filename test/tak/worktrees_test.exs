defmodule Tak.WorktreesTest do
  use ExUnit.Case, async: false

  describe "pick_available_name/0" do
    test "returns first available name" do
      assert {:ok, name} = Tak.Worktrees.pick_available_name()
      assert name == List.first(Tak.names())
    end
  end

  describe "list/0" do
    test "always includes main repository as first entry" do
      [main | _] = Tak.Worktrees.list()
      assert main.name == "main"
      assert main.main? == true
      assert is_integer(main.port)
      assert main.status in [:running, :stopped]
    end

    test "returns status atoms, not strings" do
      entries = Tak.Worktrees.list()

      for entry <- entries do
        assert entry.status in [:running, :stopped, :unknown]
      end
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
    test "rejects invalid names" do
      assert {:error, {:invalid_name, "nope"}} = Tak.Worktrees.create("branch", "nope")
    end
  end
end
