defmodule Tak.System do
  @moduledoc false

  def cmd(command, args, opts \\ []) do
    impl().cmd(command, args, opts)
  end

  def find_executable(name) do
    impl().find_executable(name)
  end

  def run_mix_stream(path, args, opts \\ []) do
    impl().run_mix_stream(path, args, opts)
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

  def run_mix_stream(path, args, opts \\ []) do
    command = Enum.join(["mix" | args], " ")
    mix = System.find_executable("mix") || "mix"
    extra_env = Keyword.get(opts, :extra_env, [])
    env = [{~c"MIX_ENV", ~c"dev"} | extra_env]

    port =
      Port.open({:spawn_executable, mix}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        cd: path,
        env: env
      ])

    collect_port_output(port, command, "")
  end

  defp collect_port_output(port, command, acc) do
    receive do
      {^port, {:data, data}} ->
        IO.write(data)
        collect_port_output(port, command, acc <> data)

      {^port, {:exit_status, 0}} ->
        {:ok, acc}

      {^port, {:exit_status, _}} ->
        {:error, {:bootstrap_failed, command, acc}}
    end
  end
end
