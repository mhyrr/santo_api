# Corpus corrections for TK-003. Run after the three car scripts:
#
#     mix run priv/corpus/adjudications.exs
#
# Re-runnable: Registry.adjudicate_claims/4 returns the immutable casebook row
# when the same decision has already landed. No claim or adjudication is inserted
# directly here.

alias SantoApi.Registry
alias SantoApi.Registry.{Artifact, Claim}

decider = Registry.vin_santo_party()

decisions = [
  %{
    name: "2007 Porsche Cayman S",
    vin: "WP0AB29827U782968",
    prevailing_method: :structured_api,
    superseded_method: :santo,
    evidence_file: "porsche_coa.jpg",
    note: "The Porsche CoA identifies this VIN as a Cayman S; santo's 987 model claim is wrong."
  },
  %{
    name: "2005 Porsche Carrera GT",
    vin: "WP0CA298X5L001256",
    prevailing_method: :santo,
    superseded_method: :structured_api,
    evidence_file: "window_sticker.jpg",
    note:
      "The original window sticker identifies the Carrera GT; vPIC's 911 model claim is wrong."
  }
]

for decision <- decisions do
  {:ok, vehicle} = Registry.ingest(decision.vin)
  claims = Registry.list_claims(vehicle.id)
  artifacts = Registry.list_artifacts(vehicle.id)

  prevailing =
    Enum.find(claims, fn %Claim{} = claim ->
      claim.predicate == "identity.model" and claim.method == decision.prevailing_method
    end) || raise "#{decision.name}: prevailing model claim missing; run its corpus script first"

  superseded =
    Enum.find(claims, fn %Claim{} = claim ->
      claim.predicate == "identity.model" and claim.method == decision.superseded_method
    end) || raise "#{decision.name}: superseded model claim missing; run its corpus script first"

  evidence =
    Enum.find(artifacts, fn %Artifact{} = artifact ->
      artifact.metadata["filename"] == decision.evidence_file
    end) ||
      raise "#{decision.name}: #{decision.evidence_file} missing; run its corpus script first"

  {:ok, adjudication} =
    Registry.adjudicate_claims(decider, prevailing.id, superseded.id, %{
      outcome: :supersede,
      prevailing_claim_id: prevailing.id,
      evidence_artifact_ids: [evidence.id],
      note: decision.note
    })

  {:ok, corrected} = Registry.fetch_vehicle(vehicle.id)
  model = corrected.facts["identity.model"]

  IO.puts("== #{decision.name} — #{decision.vin}")
  IO.puts("   adjudication #{adjudication.id}")
  IO.puts("   identity.model #{inspect(model["value"])} [#{model["status"]}]")
end
