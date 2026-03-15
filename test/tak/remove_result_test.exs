defmodule Tak.RemoveResultTest do
  use ExUnit.Case, async: true

  test "struct enforces required keys" do
    assert_raise ArgumentError, fn ->
      struct!(Tak.RemoveResult, %{})
    end
  end

  test "struct keeps removal outcome separate from stable worktree data" do
    worktree = %Tak.Worktree{name: "armstrong", port: 4010, path: "trees/armstrong"}

    result = %Tak.RemoveResult{worktree: worktree, database_cleanup: :kept}

    assert result.worktree == worktree
    assert result.database_cleanup == :kept
  end
end
