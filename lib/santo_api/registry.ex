defmodule SantoApi.Registry do
  @moduledoc """
  The vehicle registry: ingest identifiers, persist identity rows, hold
  the claim record. Semantics live in docs/design/evidence_contract.md.

  Santo-derived claims enter as `:admitted` without the ratification
  gate: they are deterministic functions of the identifier itself — the
  one class of fact the registry may assert on its own authority.
  Extracted and human claims will enter as `:proposed`.

  No scope threading yet: registry data is global and there is no auth;
  scopes arrive with the first authenticated surface.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Repo
  alias SantoApi.Registry.{Claim, EvidenceRequest, IdentityKey, Party, Vehicle, Vocabulary}
  alias SantoApi.Terms

  def ingest(input) do
    case Santo.Identity.key(input) do
      {:ok, identity} ->
        normalized = Santo.Normalize.normalize(input)
        decode = Santo.decode(normalized)

        {:ok, vehicle} =
          Repo.transaction(fn -> upsert_vehicle(identity, normalized, decode) end)

        {:ok, vehicle}

      {:error, %Santo.Invalid{} = invalid} ->
        {:error, invalid}
    end
  end

  def fetch_vehicle(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Vehicle{} = vehicle <- Repo.get(Vehicle, uuid) do
      {:ok, vehicle}
    else
      _ -> {:error, :not_found}
    end
  end

  def list_claims(vehicle_id) do
    Repo.all(from c in Claim, where: c.vehicle_id == ^vehicle_id, order_by: c.predicate)
  end

  def list_evidence_requests(vehicle_id) do
    Repo.all(from r in EvidenceRequest, where: r.vehicle_id == ^vehicle_id, order_by: r.subject)
  end

  def vin_santo_party do
    Repo.get_by(Party, kind: :vin_santo) ||
      Repo.insert!(%Party{name: "Vin Santo", kind: :vin_santo})
  end

  defp upsert_vehicle(identity, input, decode) do
    key = IdentityKey.serialize(identity)

    case Repo.get_by(Vehicle, identity_key: key) do
      %Vehicle{} = existing -> existing
      nil -> create_vehicle(identity, key, input, decode)
    end
  end

  defp create_vehicle(identity, key, input, decode) do
    vehicle =
      Repo.insert!(%Vehicle{
        identity_kind: IdentityKey.kind(identity),
        identity_key: key,
        candidates: IdentityKey.candidates(identity),
        input: input,
        decode_snapshot: snapshot(decode),
        santo_version: santo_version()
      })

    emit_claims(vehicle, decode)
    open_evidence_requests(vehicle, identity)
    vehicle
  end

  defp snapshot({:ok, decoded}), do: Terms.sanitize(decoded)
  defp snapshot({:ambiguous, readings}), do: %{"ambiguous" => Terms.sanitize(readings)}

  defp santo_version, do: to_string(Application.spec(:santo, :vsn))

  # Claims come only from unambiguous decodes — the registry never guesses.
  defp emit_claims(vehicle, {:ok, decoded}) do
    party = vin_santo_party()

    for {predicate, value} <- decode_facts(decoded) do
      :ok = Vocabulary.validate(predicate, value)
      scope_kind = Vocabulary.scope_kind(predicate)

      Repo.insert!(%Claim{
        vehicle_id: vehicle.id,
        asserted_by_party_id: party.id,
        predicate: predicate,
        value: value,
        scope_kind: scope_kind,
        state: :admitted,
        method: :santo,
        method_meta: %{"santo_version" => santo_version()},
        content_hash: Claim.hash(vehicle.identity_key, predicate, value, scope_kind, nil, :santo)
      })
    end

    :ok
  end

  defp emit_claims(_vehicle, _decode), do: :ok

  defp decode_facts(%Santo.Decoded{} = decoded) do
    [
      {"identity.marque", maybe_string(decoded.marque)},
      {"identity.model", model_value(decoded.model)},
      {"identity.model_year", single_year(decoded.years)},
      {"identity.market", market_value(decoded.market)},
      {"build.plant", decoded.attributes[:plant]},
      {"build.variant", maybe_string(decoded.attributes[:variant])}
    ]
    |> Enum.reject(fn {_predicate, value} -> is_nil(value) end)
  end

  defp maybe_string(nil), do: nil
  defp maybe_string(value), do: to_string(value)

  defp model_value({code, label}), do: %{"code" => to_string(code), "label" => label}
  defp model_value(nil), do: nil

  defp single_year([year]), do: year
  defp single_year(_years), do: nil

  defp market_value(market) when market in [:us, :row], do: to_string(market)
  defp market_value(_market), do: nil

  # A disputed row gets exactly one request — resolve identity first;
  # subordinate gaps only make sense once we know which car it is.
  defp open_evidence_requests(vehicle, {:disputed, _candidates, evidence}) do
    Repo.insert!(%EvidenceRequest{
      vehicle_id: vehicle.id,
      subject: "identity",
      evidence_classes: Enum.map(evidence, &to_string/1)
    })

    :ok
  end

  defp open_evidence_requests(_vehicle, _identity), do: :ok
end
