defmodule SantoApiWeb.VinController do
  use SantoApiWeb, :controller

  @doc """
  Decode a VIN or pre-VIN chassis number via `Santo.decode/1`.

  This is a pure passthrough to the santo library — no persistence, no
  context. Ambiguity is data (200), not an error; only structurally
  invalid/unrecognized input is a 422.
  """
  def show(conn, %{"vin" => vin}) do
    case Santo.decode(vin) do
      {:ok, decoded} ->
        render(conn, :show, decoded: decoded)

      {:ambiguous, candidates} ->
        render(conn, :ambiguous, candidates: candidates)

      {:error, invalid} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:invalid, invalid: invalid)
    end
  end
end
