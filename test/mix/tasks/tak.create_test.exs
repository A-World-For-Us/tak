defmodule Mix.Tasks.Tak.CreateTest do
  use ExUnit.Case, async: false

  describe "validation via Tak.Worktrees" do
    test "rejects invalid slot names" do
      assert {:error, {:invalid_name, "nope"}} =
               Tak.Worktrees.create("feature/test", "nope")
    end

    test "rejects already existing worktrees" do
      trees_dir = Tak.trees_dir()
      name = List.first(Tak.names())
      path = Path.join(trees_dir, name)

      if File.dir?(path) do
        assert {:error, {:already_exists, ^name}} =
                 Tak.Worktrees.create("feature/test", name)
      end
    end
  end
end
