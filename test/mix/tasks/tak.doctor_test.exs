defmodule Mix.Tasks.Tak.DoctorTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "runs without crashing" do
    output =
      capture_io(fn ->
        Mix.Tasks.Tak.Doctor.run([])
      end)

    assert output =~ "Tak Doctor"
    assert output =~ "git available"
  end
end
