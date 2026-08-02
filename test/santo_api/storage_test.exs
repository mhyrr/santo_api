defmodule SantoApi.StorageTest do
  use ExUnit.Case, async: true

  alias SantoApi.Storage

  defp ref, do: "storage-test-#{System.unique_integer([:positive])}.bin"

  test "the configured adapter is what put/2 and fetch/1 go through" do
    assert Storage.adapter() == SantoApi.Storage.Local
  end

  test "round-trips content" do
    ref = ref()

    assert :ok = Storage.put(ref, "window sticker bytes")
    assert {:ok, "window sticker bytes"} = Storage.fetch(ref)
  end

  test "reports whether a ref is present" do
    ref = ref()

    refute Storage.exists?(ref)
    assert :ok = Storage.put(ref, "x")
    assert Storage.exists?(ref)
  end

  test "fetching an absent ref is an error, not a raise" do
    assert {:error, :enoent} = Storage.fetch(ref())
  end

  test "refs are opaque names, not paths — traversal is refused" do
    assert {:error, :invalid_ref} = Storage.put("../escape.txt", "x")
    assert {:error, :invalid_ref} = Storage.fetch("../../etc/passwd")
    assert {:error, :invalid_ref} = Storage.put("nested/ref.txt", "x")
  end
end
