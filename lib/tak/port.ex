defmodule Tak.Port do
  @moduledoc """
  Detects port availability and stops processes that hold a port.

  `in_use?/1` uses `:gen_tcp` and works anywhere Erlang runs.
  `pid/1` and `kill/1` shell out to `lsof` and `kill`, so they require
  macOS or Linux.
  """

  @doc """
  Returns `true` if the port is already bound by another process.

  Probes the port with `:gen_tcp` directly, so it does not depend on `lsof`
  or any external command.

  ## Example

      # Check whether the default Phoenix port is free
      Tak.Port.in_use?(4000)
  """
  def in_use?(port) do
    case :gen_tcp.listen(port, reuseaddr: true) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        false

      {:error, :eaddrinuse} ->
        true

      {:error, _} ->
        false
    end
  end

  @doc """
  Returns the PID of the process listening on `port`, or `nil` if none.

  Shells out to `lsof -ti :<port>`. Requires macOS or Linux.

  ## Example

      # Returns a string like "12345", or nil
      Tak.Port.pid(4010)
  """
  def pid(port) do
    case System.cmd("lsof", ["-ti", ":#{port}"], stderr_to_stdout: true) do
      {output, 0} ->
        output |> String.trim() |> String.split("\n") |> List.first()

      _ ->
        nil
    end
  end

  @doc """
  Stops the process listening on `port`. Always returns `:ok`.

  Sends `SIGTERM` first to allow graceful shutdown. If the process is still
  alive after four 500 ms checks (2 seconds total), sends `SIGKILL`.

  Returns `:ok` immediately when no process holds the port.

  Requires macOS or Linux (`lsof`, `kill`).

  ## Example

      Tak.Port.kill(4010)
      :ok
  """
  def kill(port) do
    case pid(port) do
      nil ->
        :ok

      pid_str ->
        System.cmd("kill", [pid_str], stderr_to_stdout: true)

        if process_alive?(pid_str, _retries = 4, _interval_ms = 500) do
          System.cmd("kill", ["-9", pid_str], stderr_to_stdout: true)
        end

        :ok
    end
  end

  defp process_alive?(pid_str, 0, _interval_ms), do: signal_zero?(pid_str)

  defp process_alive?(pid_str, retries, interval_ms) do
    if signal_zero?(pid_str) do
      Process.sleep(interval_ms)
      process_alive?(pid_str, retries - 1, interval_ms)
    else
      false
    end
  end

  defp signal_zero?(pid_str) do
    case System.cmd("kill", ["-0", pid_str], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end
end
