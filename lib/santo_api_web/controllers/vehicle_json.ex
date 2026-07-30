defmodule SantoApiWeb.VehicleJSON do
  def show(%{vehicle: vehicle, claims: claims, evidence_requests: requests}) do
    %{
      vehicle: %{
        id: vehicle.id,
        identity_kind: vehicle.identity_kind,
        identity_key: vehicle.identity_key,
        candidates: vehicle.candidates,
        input: vehicle.input,
        santo_version: vehicle.santo_version,
        decode_snapshot: vehicle.decode_snapshot
      },
      claims: Enum.map(claims, &claim/1),
      evidence_requests: Enum.map(requests, &request/1)
    }
  end

  defp claim(claim) do
    %{
      id: claim.id,
      predicate: claim.predicate,
      value: claim.value,
      scope_kind: claim.scope_kind,
      scope_date: claim.scope_date,
      state: claim.state,
      method: claim.method,
      content_hash: claim.content_hash
    }
  end

  defp request(request) do
    %{
      id: request.id,
      subject: request.subject,
      evidence_classes: request.evidence_classes,
      status: request.status
    }
  end
end
