defmodule Tak.System do
  @moduledoc false

  def cmd(command, args, opts \\ []) do
    impl().cmd(command, args, opts)
  end

  def find_executable(name) do
    impl().find_executable(name)
  end

  defp impl do
    Application.get_env(:tak, :system_mod, Tak.System.Real)
  end
end

defmodule Tak.System.Real do
  @moduledoc false

  def cmd(command, args, opts \\ []) do
    System.cmd(command, args, opts)
  end

  def find_executable(name) do
    System.find_executable(name)
  end
end
