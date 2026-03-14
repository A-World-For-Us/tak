defmodule Tak.Port do
  @moduledoc """
  Port detection and process management for worktrees.
  """

  @doc """
  Checks if a port is in use.

  Uses `:gen_tcp` to probe the port directly, avoiding a dependency on `lsof`.
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
  Gets the PID using a given port, if any.
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
  Kills processes on a given port.

  Sends SIGTERM first to allow graceful shutdown, then SIGKILL after
  2 seconds if the process is still running.
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
