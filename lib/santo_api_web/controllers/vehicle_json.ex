defmodule SantoApiWeb.VehicleJSON do
  def show(%{
        vehicle: vehicle,
        claims: claims,
        evidence_requests: requests,
        comparison: comparison
      }) do
    %{
      vehicle: %{
        id: vehicle.id,
        identity_kind: vehicle.identity_kind,
        identity_key: vehicle.identity_key,
        candidates: vehicle.candidates,
        input: vehicle.input,
        santo_version: vehicle.santo_version,
        decode_snapshot: vehicle.decode_snapshot,
        facts: vehicle.facts
      },
      claims: Enum.map(claims, &claim/1),
      evidence_requests: Enum.map(requests, &request/1),
      comparison: comparison
    }
  end

  def evidence(%{artifact: artifact} = assigns) do
    assigns
    |> show()
    |> Map.put(:artifact, %{
      id: artifact.id,
      kind: artifact.kind,
      sha256: artifact.sha256,
      source_url: artifact.source_url,
      acquired_at: artifact.acquired_at,
      metadata: artifact.metadata
    })
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
