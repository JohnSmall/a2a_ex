defmodule A2AEx.ID do
  @moduledoc false

  @doc """
  Generate a new random UUID v4 string.
  """
  @spec new() :: String.t()
  def new do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)

    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
    |> uuid_to_string()
  end

  defp uuid_to_string(<<a::32, b::16, c::16, d::16, e::48>>) do
    hex(a, 8) <> "-" <> hex(b, 4) <> "-" <> hex(c, 4) <> "-" <> hex(d, 4) <> "-" <> hex(e, 12)
  end

  defp hex(int, pad) do
    int
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(pad, "0")
  end
end
