defmodule Tak.PortTest do
  use ExUnit.Case, async: true

  describe "in_use?/1" do
    test "returns false for an unused port" do
      # Use a high ephemeral port unlikely to be in use
      refute Tak.Port.in_use?(59_123)
    end

    test "returns true for a port that is in use" do
      {:ok, socket} = :gen_tcp.listen(0, reuseaddr: true)
      {:ok, port} = :inet.port(socket)

      assert Tak.Port.in_use?(port)

      :gen_tcp.close(socket)
    end

    test "returns false after a port is released" do
      {:ok, socket} = :gen_tcp.listen(0, reuseaddr: true)
      {:ok, port} = :inet.port(socket)
      :gen_tcp.close(socket)

      refute Tak.Port.in_use?(port)
    end
  end
end
