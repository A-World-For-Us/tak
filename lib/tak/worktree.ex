defmodule Tak.Worktree do
  @moduledoc """
  Stable worktree data returned by Tak runtime APIs.

  `%Tak.Worktree{}` models facts that belong to a worktree itself: its slot
  name, git branch, filesystem path, assigned port, optional database name,
  and whether Tak manages that database.

  It intentionally excludes ephemeral process state such as running status or
  PID. Use `Tak.WorktreeStatus` when you need a runtime observation layered on
  top of a worktree.
  """

  @type t :: %__MODULE__{
          name: String.t(),
          branch: String.t() | nil,
          port: non_neg_integer() | nil,
          path: String.t(),
          database: String.t() | nil,
          database_managed?: boolean()
        }

  @enforce_keys [:name, :path]
  defstruct [:name, :branch, :port, :path, :database, database_managed?: false]
end
