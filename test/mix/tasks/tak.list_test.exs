defmodule Mix.Tasks.Tak.ListTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "shows main repository info" do
    output =
      capture_io(fn ->
        try do
          Mix.Tasks.Tak.List.run([])
        catch
          :exit, :normal -> :ok
        end
      end)

    assert output =~ "Git Worktrees"
    assert output =~ "main"
    assert output =~ "Port:"
  end
end
