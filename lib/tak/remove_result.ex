defmodule Tak.RemoveResult do
  @moduledoc """
  Result data for worktree removal.

  `%Tak.RemoveResult{}` keeps stable worktree identity separate from the
  database cleanup outcome for the removal operation.
  """

  @type database_cleanup :: :dropped | :kept | :failed | nil

  @type t :: %__MODULE__{
          worktree: Tak.Worktree.t(),
          database_cleanup: database_cleanup()
        }

  @enforce_keys [:worktree]
  defstruct [:worktree, :database_cleanup]
end
