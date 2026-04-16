defmodule Tak.NameTest do
  use ExUnit.Case, async: true

  doctest Tak.Name

  describe "from_branch/1" do
    test "strips feature/ prefix" do
      assert Tak.Name.from_branch("feature/login-page") == "login-page"
    end

    test "strips fix/ prefix" do
      assert Tak.Name.from_branch("fix/broken-auth") == "broken-auth"
    end

    test "strips hotfix/ prefix" do
      assert Tak.Name.from_branch("hotfix/urgent-fix") == "urgent-fix"
    end

    test "strips chore/ prefix" do
      assert Tak.Name.from_branch("chore/cleanup") == "cleanup"
    end

    test "strips feat/ prefix" do
      assert Tak.Name.from_branch("feat/new-thing") == "new-thing"
    end

    test "lowercases the result" do
      assert Tak.Name.from_branch("feature/PROJ-123-Fix") == "proj-123-fix"
    end

    test "replaces underscores with hyphens" do
      assert Tak.Name.from_branch("feature/some_thing") == "some-thing"
    end

    test "replaces slashes with hyphens" do
      assert Tak.Name.from_branch("nested/deep/branch") == "nested-deep-branch"
    end

    test "collapses consecutive hyphens" do
      assert Tak.Name.from_branch("feature/a--b---c") == "a-b-c"
    end

    test "trims leading and trailing hyphens" do
      assert Tak.Name.from_branch("feature/-padded-") == "padded"
    end

    test "truncates to 30 characters" do
      long = "feature/" <> String.duplicate("a", 40)
      result = Tak.Name.from_branch(long)
      assert byte_size(result) <= 30
    end

    test "does not leave trailing hyphen after truncation" do
      # 30th char lands on a hyphen boundary
      branch = "feature/" <> String.duplicate("abc-", 10)
      result = Tak.Name.from_branch(branch)
      refute String.ends_with?(result, "-")
    end

    test "falls back to hash for empty result" do
      result = Tak.Name.from_branch("///")
      assert String.starts_with?(result, "wt-")
      assert byte_size(result) == 11
    end

    test "passes through simple branch names" do
      assert Tak.Name.from_branch("develop") == "develop"
      assert Tak.Name.from_branch("main") == "main"
    end
  end

  describe "from_branch/2 with existing names" do
    test "returns base name when no collision" do
      assert Tak.Name.from_branch("feature/login", []) == "login"
      assert Tak.Name.from_branch("feature/login", ["other"]) == "login"
    end

    test "appends -2 on first collision" do
      assert Tak.Name.from_branch("feature/login", ["login"]) == "login-2"
    end

    test "appends -3 when -2 is also taken" do
      assert Tak.Name.from_branch("feature/login", ["login", "login-2"]) == "login-3"
    end

    test "keeps incrementing until available" do
      existing = ["login", "login-2", "login-3", "login-4"]
      assert Tak.Name.from_branch("feature/login", existing) == "login-5"
    end
  end
end
