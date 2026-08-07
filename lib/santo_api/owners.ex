defmodule SantoApi.Owners do
  @moduledoc """
  The owner side of the house: who a user is in the ledger, which cars they
  steward, and what they may assert about them.

  This context holds the authorization layer and calls `SantoApi.Registry` for
  every write. The separation is deliberate (owner_surface §4): **stewardship is
  authz, never registry truth.** Claiming a car creates no ownership claim —
  possession proves access, not title — so a page says "maintained by", never
  "owned by". Keeping stewardship out of `Registry` keeps the ledger's write
  paths ignorant of users, which is what lets a party outlive its account.

  The scope split (§3) is enforced here, and here only: an owner self-ratifies
  event- and observed-scope claims on a car they steward, and factory- or
  provenance-scope claims from an owner wait at the operator gate.
  `Vocabulary.scope_kind/1` draws the line.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts.Scope
  alias SantoApi.Accounts.User
  alias SantoApi.Owners.{Challenge, Notifier, Stewardship}
  alias SantoApi.Registry
  alias SantoApi.Registry.{Artifact, Claim, Party, Vehicle}
  alias SantoApi.Repo

  @doc """
  The ledger identity for a user, or `nil` before they have asserted anything.

  Read through the user's id rather than off the struct, because a struct held
  from before `ensure_party/2` still says `nil` and callers would silently mint a
  second party.
  """
  def party(%User{id: user_id}) do
    Repo.one(
      from(p in Party,
        join: u in User,
        on: u.party_id == p.id,
        where: u.id == ^user_id
      )
    )
  end

  @doc """
  Give a user their permanent ledger identity — the first assertive act
  (owner_surface §5).

  Idempotent on the handle already held. A *different* handle is refused rather
  than applied: the name is baked into every claim's `content_hash`, so a rename
  is not an edit we can make, and silently ignoring the argument would hide that
  from the caller. The same immutability starts at the reservation (§9.1): a
  user who reserved a handle at registration mints with that name or not at
  all — minting another would burn both names, one on the party and one held
  forever by the reservation.
  """
  def ensure_party(%User{} = user, handle) when is_binary(handle) do
    case party(user) do
      %Party{} = existing ->
        if existing.name == normalize_handle(handle),
          do: {:ok, existing},
          else: {:error, :handle_immutable}

      nil ->
        if is_binary(user.handle) and normalize_handle(handle) != user.handle,
          do: {:error, :handle_immutable},
          else: create_party(user, handle)
    end
  end

  # A name reserved by another user is spoken for even before their party
  # exists (§9.1) — the parties unique index alone cannot see reservations,
  # so the mint checks them here, for every caller.
  defp create_party(user, handle) do
    normalized = normalize_handle(handle)

    if reserved_by_someone_else?(user, normalized) do
      {:error, :handle_taken}
    else
      Repo.transaction(fn ->
        with {:ok, party} <- Repo.insert(Party.handle_changeset(handle)),
             {:ok, _user} <- link_party(user, party) do
          party
        else
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end
  end

  defp reserved_by_someone_else?(user, normalized) do
    Repo.exists?(from(u in User, where: u.handle == ^normalized and u.id != ^user.id))
  end

  defp link_party(user, party) do
    user
    |> Ecto.Changeset.change(party_id: party.id)
    |> Ecto.Changeset.unique_constraint(:party_id)
    |> Repo.update()
  end

  defp normalize_handle(handle), do: handle |> String.trim() |> String.downcase()

  ## Stewardship — who maintains which car

  @doc """
  Authorize a user to maintain a car's log (owner_surface §4 step 5).

  Mints the user's permanent handle on the way through, because a grant is the
  first assertive act and there is no stewardship without a ledger identity to
  attribute entries to. Writes no claim: this says who maintains the log, not
  who owns the car.

  ## Options

    * `:handle` — the user's permanent public handle. Defaults to the handle
      reserved at registration (§9.1); required only for accounts that
      predate the reservation.
    * `:proof_artifact` — the possession proof that justified the grant (§4)
    * `:decided_by` — the operator who approved it

  Idempotent for a user who already stewards the car. A car another user
  actively stewards returns `{:error, :already_stewarded}` — a second claimant is
  a contested claim for an operator to adjudicate, not a second row.
  """
  def grant_stewardship(%User{} = user, %Vehicle{} = vehicle, opts \\ []) do
    case active_stewardship(vehicle) do
      %Stewardship{user_id: user_id} = existing when user_id == user.id ->
        {:ok, existing}

      %Stewardship{} ->
        {:error, :already_stewarded}

      nil ->
        with {:ok, handle} <- stewardship_handle(user, opts),
             {:ok, _party} <- ensure_party(user, handle) do
          {:ok,
           Repo.insert!(%Stewardship{
             user_id: user.id,
             vehicle_id: vehicle.id,
             proof_artifact_id: artifact_id(opts[:proof_artifact]),
             status: :active,
             decided_by_user_id: user_id(opts[:decided_by]),
             decided_at: DateTime.utc_now()
           })}
        end
    end
  end

  @doc """
  End a stewardship. A status flip with a reason and a decider — the row stays,
  and so does everything logged under it.
  """
  def revoke_stewardship(%Stewardship{} = stewardship, reason, decided_by \\ nil)
      when is_binary(reason) do
    case Repo.get(Stewardship, stewardship.id) do
      %Stewardship{status: :active} = current ->
        current
        |> Ecto.Changeset.change(
          status: :revoked,
          reason: reason,
          decided_by_user_id: user_id(decided_by),
          decided_at: DateTime.utc_now()
        )
        |> Repo.update()

      _inactive ->
        {:error, :not_active}
    end
  end

  @doc """
  The party a page names as maintaining this car, or `nil` when nobody does.
  """
  def steward(%Vehicle{} = vehicle) do
    Repo.one(
      from(s in Stewardship,
        join: u in User,
        on: u.id == s.user_id,
        join: p in Party,
        on: p.id == u.party_id,
        where: s.vehicle_id == ^vehicle.id and s.status == :active,
        select: p
      )
    )
  end

  @doc """
  The caller's active stewardship of this car, or `nil`. The authorization every
  owner write goes through.
  """
  def stewardship(%Scope{user: %User{} = user}, %Vehicle{} = vehicle) do
    Repo.one(
      from(s in Stewardship,
        where:
          s.user_id == ^user.id and s.vehicle_id == ^vehicle.id and
            s.status == :active
      )
    )
  end

  def stewardship(_scope, %Vehicle{}), do: nil

  @doc "Whether the caller may maintain this car's log."
  def stewarding?(scope, %Vehicle{} = vehicle), do: stewardship(scope, vehicle) != nil

  @doc "The caller's garage — every car they currently steward, newest first."
  def list_stewarded_vehicles(%Scope{user: %User{} = user}) do
    Repo.all(
      from(v in Vehicle,
        join: s in Stewardship,
        on: s.vehicle_id == v.id,
        where: s.user_id == ^user.id and s.status == :active,
        order_by: [desc: s.decided_at]
      )
    )
  end

  def list_stewarded_vehicles(_scope), do: []

  defp active_stewardship(%Vehicle{} = vehicle) do
    Repo.one(from(s in Stewardship, where: s.vehicle_id == ^vehicle.id and s.status == :active))
  end

  # The grant's handle: an explicit option wins (the claim flow passes the one
  # the challenge reserved), then the registration reservation (§9.1). An
  # account with neither predates both rules and has nothing to attribute
  # entries to — the caller has to ask.
  defp stewardship_handle(%User{} = user, opts) do
    case opts[:handle] || user.handle do
      nil -> {:error, :handle_required}
      handle -> {:ok, handle}
    end
  end

  ## Claiming — proof of possession (owner_surface §4)

  @challenge_ttl_hours 72

  @doc """
  Start a claim: mint the code the claimant will write on paper and photograph
  next to the VIN plate (§4 steps 1–2).

  The code is what makes the photo proof. It did not exist when a stranger
  photographed the car at a show, so satisfying it means going back to the
  physical car — which for a high-value car is a problem of physical access,
  not of this flow.

  One live challenge per person per car: asking again hands back the code
  already issued rather than inventing a second one to compare against. A code
  that ran out of time is retired and replaced.

  A car somebody else maintains still issues — §4 escalates a second claimant to
  an operator, and refusing here would leave them nothing to escalate.

  ## Options

    * `:handle` — the permanent public handle, required for a claimant who has
      no ledger identity yet. Settled here rather than at the operator's desk,
      and immutable from the moment a claim is attributed to it (§9.1).
  """
  def issue_challenge(%User{} = user, %Vehicle{} = vehicle, opts \\ []) do
    with :ok <- refuse_own_car(user, vehicle) do
      case live_challenge(user, vehicle) do
        %Challenge{} = live ->
          {:ok, live}

        nil ->
          with {:ok, handle} <- settle_handle(user, opts[:handle]) do
            {:ok,
             Repo.insert!(%Challenge{
               user_id: user.id,
               vehicle_id: vehicle.id,
               handle: handle,
               code: Challenge.mint_code(),
               status: :issued,
               expires_at: DateTime.add(DateTime.utc_now(), @challenge_ttl_hours, :hour)
             })}
          end
      end
    end
  end

  defp refuse_own_car(user, vehicle) do
    case Repo.get_by(Stewardship, user_id: user.id, vehicle_id: vehicle.id, status: :active) do
      %Stewardship{} -> {:error, :already_stewarded}
      nil -> :ok
    end
  end

  # A code past its window is retired on the way past, which is what keeps the
  # one-live-challenge index true without a job sweeping the table.
  defp live_challenge(user, vehicle) do
    Repo.one(
      from(c in Challenge,
        where:
          c.user_id == ^user.id and c.vehicle_id == ^vehicle.id and
            c.status in [:issued, :submitted]
      )
    )
    |> case do
      %Challenge{status: :issued} = challenge ->
        if expired?(challenge), do: retire(challenge) && nil, else: challenge

      other ->
        other
    end
  end

  defp retire(%Challenge{} = challenge) do
    challenge |> Ecto.Changeset.change(status: :expired) |> Repo.update!()
  end

  # Expiry governs the window between issuing a code and photographing it.
  # Once a photo is in, a slow operator must not cost the claimant their claim.
  defp expired?(%Challenge{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  # The handle has to be grantable before a code goes out, or an operator
  # discovers at approval time that the name is taken and has nothing to do
  # about it.
  defp settle_handle(user, given) do
    case party(user) do
      %Party{name: name} ->
        if is_nil(given) or normalize_handle(given) == name,
          do: {:ok, name},
          else: {:error, :handle_immutable}

      nil ->
        settle_reserved(user, given)
    end
  end

  # §9.1 round 5: the user carries the reserved handle from registration, so
  # the claim flow no longer asks. The reservation is as immutable as the
  # party name it becomes — a different handle offered here is refused the
  # same way it would be after minting. The validate path survives only for
  # accounts that predate the reservation.
  defp settle_reserved(%User{handle: reserved}, given) when is_binary(reserved) do
    if is_nil(given) or normalize_handle(given) == reserved,
      do: {:ok, reserved},
      else: {:error, :handle_immutable}
  end

  defp settle_reserved(_legacy_user, given), do: validate_available(given)

  defp validate_available(nil), do: {:error, :handle_required}

  defp validate_available(given) when is_binary(given) do
    changeset = Party.handle_changeset(given)

    cond do
      not changeset.valid? -> {:error, changeset}
      handle_taken?(Ecto.Changeset.get_field(changeset, :name)) -> {:error, :handle_taken}
      true -> {:ok, Ecto.Changeset.get_field(changeset, :name)}
    end
  end

  @doc """
  Whether a handle is spoken for anywhere: held by a minted owner party,
  reserved by a registered user (§9.1), or riding a live possession
  challenge. The last two matter because two people reserving one name would
  both pass a party-only check and the loser would find out at the
  operator's desk. Public because registration asks the same question
  (`SantoApi.Accounts.User.registration_changeset/3`) — one function owns it.
  """
  def handle_taken?(name) when is_binary(name) do
    Repo.exists?(from(p in Party, where: p.name == ^name and p.kind == :owner)) or
      Repo.exists?(from(u in User, where: u.handle == ^name)) or
      Repo.exists?(
        from(c in Challenge, where: c.handle == ^name and c.status in [:issued, :submitted])
      )
  end

  @doc """
  Attach the possession photo and hand the claim to an operator (§4 step 3).

  The photo is stored as the claimant's own artifact, not ours: the registry did
  not supply it and must not be recorded as having done so. That is what mints
  the claimant's party — the handle they chose at issue becomes permanent here,
  at the first moment there is something to attribute it to.

  Private on arrival. A photo of a VIN plate is the owner's, serving artifact
  images publicly is an open rights question, and a proof photo is read at the
  bench and nowhere else.
  """
  def submit_proof(%Challenge{} = challenge, %{path: _path, filename: _filename} = photo) do
    case Repo.get(Challenge, challenge.id) do
      %Challenge{status: status} = current when status in [:issued, :submitted] ->
        if status == :issued and expired?(current),
          do: {:error, :expired},
          else: attach_proof(current, photo)

      %Challenge{} ->
        {:error, :not_pending}

      nil ->
        {:error, :not_found}
    end
  end

  defp attach_proof(%Challenge{} = challenge, photo) do
    user = Repo.get!(User, challenge.user_id)

    with {:ok, party} <- ensure_party(user, challenge.handle),
         {:ok, artifact} <- store_proof(challenge, party, photo),
         {:ok, private} <- Registry.set_visibility(artifact, :private) do
      submitted =
        challenge
        |> Ecto.Changeset.change(status: :submitted, proof_artifact_id: private.id)
        |> Repo.update!()

      announce_submission(submitted, user)
      {:ok, submitted}
    end
  end

  # The incumbent hears about a claim on their car when it is made, not when it
  # is decided (§4). They are the party with the evidence that settles it.
  defp announce_submission(%Challenge{} = challenge, user) do
    vehicle = Repo.get!(Vehicle, challenge.vehicle_id)
    Notifier.claim_received(user, vehicle)

    case active_stewardship(vehicle) do
      %Stewardship{user_id: incumbent_id} when incumbent_id != user.id ->
        Notifier.counter_claim(Repo.get!(User, incumbent_id), vehicle, challenge.handle)

      _uncontested ->
        :ok
    end
  end

  defp store_proof(challenge, party, photo) do
    Registry.create_upload_artifact(%{
      vehicle_id: challenge.vehicle_id,
      path: photo.path,
      filename: photo.filename,
      mime: photo[:mime],
      kind: :photo,
      source_party: party,
      metadata: %{"purpose" => "possession_proof", "challenge_code" => challenge.code}
    })
  end

  @doc """
  The operator's decision, and the only door to a stewardship (§4 steps 4–5).

  An approval is one transaction: the grant, with the proof and the deciding
  operator attached, and the claim's own status. A car somebody already
  maintains refuses — `{:error, :already_stewarded}` leaves the claim in the
  queue, which is the escalation §4 asks for: the incumbent keeps the car until
  a person adjudicates the dispute.
  """
  def approve_challenge(%Challenge{} = challenge, %User{} = operator) do
    case Repo.get(Challenge, challenge.id) do
      %Challenge{status: :submitted, proof_artifact_id: artifact_id} = current
      when not is_nil(artifact_id) ->
        grant_from(current, operator)

      %Challenge{status: :issued} ->
        {:error, :no_proof}

      %Challenge{} ->
        {:error, :not_pending}

      nil ->
        {:error, :not_found}
    end
  end

  defp grant_from(%Challenge{} = challenge, operator) do
    user = Repo.get!(User, challenge.user_id)
    vehicle = Repo.get!(Vehicle, challenge.vehicle_id)
    proof = Repo.get!(Artifact, challenge.proof_artifact_id)

    granted =
      Repo.transaction(fn ->
        case grant_stewardship(user, vehicle,
               handle: challenge.handle,
               proof_artifact: proof,
               decided_by: operator
             ) do
          {:ok, stewardship} ->
            decide!(challenge, :approved, operator, nil)
            stewardship

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)

    with {:ok, _stewardship} <- granted, do: Notifier.claim_approved(user, vehicle)

    granted
  end

  @doc """
  Turn a claim down, with the reason the claimant is owed. Grants nothing and
  writes nothing; the claimant may photograph the car again with a fresh code.
  """
  def deny_challenge(%Challenge{} = challenge, %User{} = operator, reason)
      when is_binary(reason) do
    case Repo.get(Challenge, challenge.id) do
      %Challenge{status: status} = current when status in [:issued, :submitted] ->
        denied = decide!(current, :denied, operator, reason)

        Notifier.claim_denied(
          Repo.get!(User, denied.user_id),
          Repo.get!(Vehicle, denied.vehicle_id),
          reason
        )

        {:ok, denied}

      %Challenge{} ->
        {:error, :not_pending}

      nil ->
        {:error, :not_found}
    end
  end

  defp decide!(challenge, status, operator, reason) do
    challenge
    |> Ecto.Changeset.change(
      status: status,
      reason: reason,
      decided_by_user_id: operator.id,
      decided_at: DateTime.utc_now()
    )
    |> Repo.update!()
  end

  @doc """
  Where this person stands on this car — the latest claim they made, whatever
  became of it, or `nil` if they never made one.
  """
  def challenge(%User{} = user, %Vehicle{} = vehicle) do
    Repo.one(
      from(c in Challenge,
        where: c.user_id == ^user.id and c.vehicle_id == ^vehicle.id,
        order_by: [desc: c.inserted_at],
        limit: 1
      )
    )
  end

  @doc "Whether somebody else already maintains the car this claim is for."
  def contested?(%Challenge{} = challenge) do
    Repo.exists?(
      from(s in Stewardship,
        where:
          s.vehicle_id == ^challenge.vehicle_id and s.status == :active and
            s.user_id != ^challenge.user_id
      )
    )
  end

  @doc """
  The claiming queue (§9.2): claims with a photo, waiting on a person. Oldest
  first — somebody has been waiting since they took that picture.

  Nothing auto-approves. At this volume an operator is looking at every photo,
  which is also how we learn what the abuse actually looks like.
  """
  def list_pending_challenges do
    Repo.all(
      from(c in Challenge,
        where: c.status == :submitted,
        order_by: [asc: c.inserted_at],
        preload: [:user, :vehicle, :proof_artifact]
      )
    )
  end

  defp artifact_id(%Artifact{id: id}), do: id
  defp artifact_id(nil), do: nil

  defp user_id(%User{id: id}), do: id
  defp user_id(nil), do: nil

  ## Publishing — the magic-link click publishes (owner_surface §7b.1 d.6)

  @doc """
  Whether this car's page renders publicly.

  Origination creates the user, the car, and the stewardship before any
  email is confirmed, and the magic-link click publishes rather than
  unlocks: public rendering gates on `user.confirmed_at` through the
  stewardship join — one join, zero ledger writes, no visibility flipping
  on claims after the fact. A car with no steward at all (seeded by VIN
  lookup, corpus, bench) was never anyone's unconfirmed word and is public
  as it always was.
  """
  def published?(%Vehicle{} = vehicle) do
    not Repo.exists?(
      from(s in Stewardship,
        join: u in User,
        on: u.id == s.user_id,
        where: s.vehicle_id == ^vehicle.id and s.status == :active and is_nil(u.confirmed_at)
      )
    )
  end

  @doc """
  The vehicles the registry index must not list: stewarded by an account
  that never confirmed. One query for the whole index, same join as
  `published?/1`.
  """
  def unpublished_vehicle_ids do
    Repo.all(
      from(s in Stewardship,
        join: u in User,
        on: u.id == s.user_id,
        where: s.status == :active and is_nil(u.confirmed_at),
        select: s.vehicle_id
      )
    )
    |> MapSet.new()
  end

  ## Resolution — an asserted car acquires its VIN (owner_surface §7b.2)

  @doc """
  Resolve the caller's `:asserted` car to a VIN. One-way, one-time, and
  never refused.

    * The VIN is unoccupied — `{:ok, :resolved, vehicle}`. The row flipped
      in place, the decode's facts arrived `:admitted`, and the page's
      comparison audits everything the owner asserted.
    * The VIN is occupied — `{:ok, :counter_claim, occupied, challenge}`.
      The assertion is still recorded (Greg, 2026-08-04: the ledger gates
      nothing at submission time, anywhere): the owner becomes a claimant on
      the occupied row through §4's counter-claim path, an operator
      adjudicates, and the entries stay on the asserted row meanwhile. Only
      the key flip is deferred, never the claim.

  Steward-only: acquiring the identity is the biggest write the owner
  surface has, and it belongs to the person maintaining the log.
  """
  def resolve_asserted(scope, %Vehicle{} = vehicle, vin) do
    with {:ok, stewardship} <- authorize_entry(scope, vehicle) do
      case Registry.resolve_asserted(vehicle, vin) do
        {:ok, resolved} ->
          {:ok, :resolved, resolved}

        {:error, {:occupied, occupied}} ->
          user = Repo.get!(User, stewardship.user_id)

          with {:ok, challenge} <- issue_challenge(user, occupied) do
            {:ok, :counter_claim, occupied, challenge}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  The logbook as this caller may read it (owner_surface §6).

  The steward of a car sees their private entries; everybody else sees the
  public page. This is the read half of the privacy toggle, and it has to exist
  wherever the toggle does — an entry only its author can hide and nobody at all
  can see is a hole, not a feature.
  """
  def timeline(scope, %Vehicle{} = vehicle) do
    Registry.timeline(vehicle.id, include_private: stewarding?(scope, vehicle))
  end

  ## Entries — the composer's write path

  @doc """
  Write one composed entry to the ledger (owner_surface §1, §3).

  Every claim and photo of one entry shares an `entry_ref`, which is what makes
  a fill-up present as one line rather than two and what lets two identical
  ten-gallon fill-ups on one day be two events instead of one deduped claim.

  The scope split, and the only place it is enforced:

    * **event and observed scope** — proposed and ratified in one transaction
      with the owner as ratifier. The gate's shape survives (every claim passes
      through `:proposed`, every admission has a who and a when); only the
      latency collapses.
    * **factory and provenance scope** — proposed and left there. These touch
      `facts` and the verified display, so they wait for the operator gate or
      corroborating evidence.

  All or nothing: one rejected claim rolls the whole entry back, because half an
  entry in the ledger is worse than none.

  ## Attributes

    * `:date` — required. The timeline orders by it and the fold reads recency
      off it, so an owner entry is never undated.
    * `:claims` — `[%{predicate: ..., value: ...}]`, at least one.
    * `:photos` — `[%{path:, filename:, mime:}]`, owner-supplied artifacts.
    * `:visibility` — `:public` (default) or `:private`. Presentation only: a
      private claim is still admitted, still counts, and still folds into
      current state.
  """
  def compose_entry(scope, %Vehicle{} = vehicle, attrs) do
    with {:ok, stewardship} <- authorize_entry(scope, vehicle),
         {:ok, date} <- entry_date(attrs),
         {:ok, claim_attrs} <- entry_claims(attrs) do
      party = party(%User{id: stewardship.user_id})
      write_entry(vehicle, party, date, claim_attrs, attrs)
    end
  end

  defp authorize_entry(scope, vehicle) do
    case stewardship(scope, vehicle) do
      %Stewardship{} = stewardship -> {:ok, stewardship}
      nil -> {:error, :not_stewarded}
    end
  end

  defp entry_date(%{date: %Date{} = date}), do: {:ok, date}

  defp entry_date(%{date: iso}) when is_binary(iso) do
    case Date.from_iso8601(iso) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :missing_date}
    end
  end

  defp entry_date(_attrs), do: {:error, :missing_date}

  defp entry_claims(%{claims: [_first | _rest] = claims}), do: {:ok, claims}
  defp entry_claims(_attrs), do: {:error, :empty_entry}

  defp write_entry(vehicle, party, date, claim_attrs, attrs) do
    entry_ref = Registry.new_entry_ref()
    visibility = Map.get(attrs, :visibility, :public)
    opts = basis_opts(attrs)

    result =
      Repo.transaction(fn ->
        claims = Enum.map(claim_attrs, &write_claim!(vehicle, party, date, entry_ref, &1, opts))

        artifacts =
          Enum.map(Map.get(attrs, :photos, []), &write_photo!(vehicle, party, entry_ref, &1))

        %{
          entry_ref: entry_ref,
          claims: Enum.map(claims, &apply_visibility!(&1, visibility)),
          artifacts: Enum.map(artifacts, &apply_visibility!(&1, visibility))
        }
      end)

    case result do
      {:ok, entry} -> {:ok, entry}
      {:error, reason} -> {:error, reason}
    end
  end

  # Basis travels as options, never as attrs: `method` is stamped and hashed,
  # and a cast basis field lets a caller forge provenance. The composer sends
  # nothing and gets `:human`; the agent surface sends `:llm_extract` plus the
  # calling client, so the ledger records that a model mediated the entry.
  defp basis_opts(attrs) do
    case Map.get(attrs, :method) do
      nil -> []
      method -> [method: method, method_meta: Map.get(attrs, :method_meta, %{})]
    end
  end

  defp write_claim!(vehicle, party, date, entry_ref, %{predicate: predicate, value: value}, opts) do
    attrs = %{
      "predicate" => predicate,
      "value" => value,
      "scope_date" => date,
      "entry_ref" => entry_ref
    }

    case Registry.propose_claim(vehicle, party, attrs, opts) do
      {:ok, claim} ->
        maybe_self_ratify!(claim, party)

      {:error, %Ecto.Changeset{} = changeset} ->
        if duplicate_hash?(changeset),
          do: recover_claim!(vehicle, changeset, party),
          else: Repo.rollback(changeset)

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  # An observation re-asserted is one fact, not two. `entry_ref` joins the hash
  # for event-scoped claims only (owner_surface §2, ratified), so two identical
  # fill-ups on one day are two distinct `event.fuel` claims that share a single
  # `observation.mileage` — the car read 41,660 once, whatever we were doing when
  # we noticed. Recovering the existing claim is what the savepoint in
  # `propose_claim` was built for; the alternative is refusing an entry an owner
  # legitimately wants to make.
  defp duplicate_hash?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {field, {_message, meta}} ->
      field == :content_hash and meta[:constraint] == :unique
    end)
  end

  defp recover_claim!(vehicle, changeset, party) do
    content_hash = Ecto.Changeset.get_field(changeset, :content_hash)

    case Repo.get_by(Claim, vehicle_id: vehicle.id, content_hash: content_hash) do
      %Claim{state: :proposed} = claim ->
        maybe_self_ratify!(claim, party)

      %Claim{state: :admitted} = claim ->
        claim

      # The author changing their mind back. `content_hash` is still held by
      # the row they withdrew, so re-asserting has to revive it or collide with
      # it — and reviving is the honest reading: this is the same assertion by
      # the same party, and refusing would mean an owner could undo a
      # correction exactly once. Guarded on the asserting party, because the
      # act being undone is their own withdrawal and nobody else's.
      %Claim{state: :retracted, asserted_by_party_id: asserter} = claim
      when asserter == party.id ->
        claim
        |> Ecto.Changeset.change(state: :proposed, retracted_by_party_id: nil, retracted_at: nil)
        |> Repo.update!()
        |> maybe_self_ratify!(party)

      # Rejected or superseded: this exact assertion has already been ruled on.
      # Quietly resurrecting it would let the composer undo an adjudication.
      %Claim{state: state} ->
        Repo.rollback({:claim_not_live, state})

      nil ->
        Repo.rollback(changeset)
    end
  end

  # The line the doctrine draws, read straight off the vocabulary so it cannot
  # drift from the scope kinds themselves.
  defp maybe_self_ratify!(%Claim{scope_kind: kind} = claim, party)
       when kind in [:event, :observed] do
    case Registry.ratify_claim(claim.id, party) do
      {:ok, ratified} -> ratified
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  defp maybe_self_ratify!(%Claim{} = claim, _party), do: claim

  # Raises rather than returning an error, which rolls the entry back with the
  # original exception — a photo that cannot be read or stored is not a case the
  # composer can helpfully explain away.
  defp write_photo!(vehicle, party, entry_ref, %{path: path, filename: filename} = photo) do
    {:ok, artifact} =
      Registry.create_upload_artifact(%{
        vehicle_id: vehicle.id,
        path: path,
        filename: filename,
        mime: photo[:mime],
        kind: :photo,
        entry_ref: entry_ref,
        source_party: party
      })

    artifact
  end

  # Public is the default on both tables, so only a private entry writes here.
  defp apply_visibility!(row, :public), do: row

  defp apply_visibility!(row, :private) do
    case Registry.set_visibility(row, :private) do
      {:ok, updated} -> updated
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  ## Corrections — the owner's own data, revised (owner_surface §8)

  @doc """
  Revise an entry the caller logged.

  The line is the **asserting party**, not the scope kind (Greg, 2026-08-03):
  a claim is yours to change because you made it, not because of what it is
  about. An owner-typed `build.paint_code` is as editable as a fill-up;
  a santo decode fact or a vPIC assertion on the same car is not editable at
  all, and a disagreement with one of those produces both sources rather than
  an edit. `identity_key` sits outside this entirely — the VIN is not a claim,
  it is what makes the row that car.

  Only the claims that actually changed are touched. An amendment that churned
  every claim would attribute a fresh assertion to the owner for facts they
  never restated, and would burn a retraction on a row that was never wrong.

  Editing and ratification stay orthogonal. This decides who may revise an
  assertion; `compose_entry/3`'s scope split still decides when one enters the
  record. A corrected factory claim is still proposed, and still waits.
  """
  def amend_entry(scope, %Vehicle{} = vehicle, entry_ref, attrs) do
    with {:ok, stewardship} <- authorize_entry(scope, vehicle),
         {:ok, claim_attrs} <- entry_claims(attrs),
         party = party(%User{id: stewardship.user_id}),
         {:ok, existing} <- fetch_own_entry(vehicle, party, entry_ref) do
      date = amend_date(attrs, existing)
      opts = basis_opts(attrs)
      visibility = entry_visibility(existing)

      result =
        Repo.transaction(fn ->
          # The date is part of the assertion, not a label on it: an entry moved
          # to another day restates every one of its claims, because "the car
          # read 41,660 on 2 August" is not the claim "it read 41,660 in April."
          keep = Enum.map(claim_attrs, &{&1.predicate, &1.value, date})

          existing
          |> Enum.reject(&({&1.predicate, &1.value, &1.scope_date} in keep))
          |> Enum.each(&retract!(&1, party))

          claims =
            claim_attrs
            |> Enum.map(&write_claim!(vehicle, party, date, entry_ref, &1, opts))
            |> Enum.map(&apply_visibility!(&1, visibility))

          %{entry_ref: entry_ref, claims: claims}
        end)

      case result do
        {:ok, entry} -> {:ok, entry}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  One entry as the caller may correct it — their own live claims under that ref.

  Read through the same door `amend_entry/4` writes through, so the composer
  cannot open an entry it would then be refused on. Deliberately not
  `Registry.timeline/2`: that reads admitted claims only, and an owner-typed
  factory claim waiting at the operator gate is still theirs to fix.
  """
  def entry(scope, %Vehicle{} = vehicle, entry_ref) do
    with {:ok, stewardship} <- authorize_entry(scope, vehicle),
         party = party(%User{id: stewardship.user_id}),
         {:ok, [%Claim{scope_date: date} | _rest] = claims} <-
           fetch_own_entry(vehicle, party, entry_ref) do
      {:ok, %{entry_ref: entry_ref, date: date, claims: claims}}
    end
  end

  @doc """
  Withdraw an entry the caller logged, whole. Returns how many claims went.

  Deleting a logbook line is retracting the claims it was made of — the rows
  stay, their state flips, and the entry leaves every projection because both
  of them read `:admitted` only.
  """
  def retract_entry(scope, %Vehicle{} = vehicle, entry_ref) do
    with {:ok, stewardship} <- authorize_entry(scope, vehicle),
         party = party(%User{id: stewardship.user_id}),
         {:ok, existing} <- fetch_own_entry(vehicle, party, entry_ref) do
      Repo.transaction(fn ->
        Enum.each(existing, &retract!(&1, party))
        length(existing)
      end)
    end
  end

  @doc """
  Withdraw one claim the caller asserted on a car they steward.

  The single-claim door behind both paths above, exposed because the agent
  surface hands out claim ids and an assistant asked to remove one line of a
  three-line entry should not have to restate the other two.
  """
  def retract_claim(scope, %Vehicle{} = vehicle, claim_id) do
    with {:ok, stewardship} <- authorize_entry(scope, vehicle) do
      party = party(%User{id: stewardship.user_id})
      Registry.retract_claim(claim_id, party)
    end
  end

  # The caller's own live claims of one entry. Somebody else's claims sharing
  # the ref — an operator's note on the same entry, say — are invisible here
  # rather than refused, so an owner amending their fill-up never discovers
  # they cannot because a third party wrote alongside them.
  defp fetch_own_entry(vehicle, party, entry_ref) do
    case Ecto.UUID.cast(entry_ref) do
      {:ok, ref} ->
        Repo.all(
          from(c in Claim,
            where:
              c.vehicle_id == ^vehicle.id and c.entry_ref == ^ref and
                c.asserted_by_party_id == ^party.id and c.state in [:proposed, :admitted]
          )
        )
        |> case do
          [] -> {:error, :entry_not_found}
          claims -> {:ok, claims}
        end

      :error ->
        {:error, :entry_not_found}
    end
  end

  # An entry is private if any part of it is (the same rule `Registry.timeline/2`
  # reads it back by), and a claim written by an amendment inherits it. Fixing a
  # typo is not consent to publish, and the write path defaults to `:public`.
  defp entry_visibility(claims) do
    if Enum.any?(claims, &(&1.visibility == :private)), do: :private, else: :public
  end

  # An amendment keeps the entry's date unless the owner supplies a new one.
  # They are correcting what the car read that day, not asserting something
  # new about today.
  defp amend_date(attrs, [%Claim{scope_date: existing} | _rest]) do
    case entry_date(attrs) do
      {:ok, date} -> date
      {:error, _missing} -> existing
    end
  end

  defp retract!(%Claim{} = claim, party) do
    case Registry.retract_claim(claim.id, party) do
      {:ok, retracted} -> retracted
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc """
  What the composer pre-fills for the next entry (owner_surface §1).

  The Fuelly bar is three numbers, and it is only three numbers if the odometer
  starts from the last reading rather than from an empty field. Empty for a car
  with no entries — there is nothing to carry forward and a zero would be a lie.
  """
  def last_entry_defaults(scope, %Vehicle{} = vehicle) do
    if stewarding?(scope, vehicle) do
      %{}
      |> put_last(vehicle, "observation.mileage", &%{odometer: &1})
      |> put_last(vehicle, "event.fuel", &%{volume: &1["volume"], unit: &1["unit"]})
    else
      %{}
    end
  end

  defp put_last(defaults, vehicle, predicate, shape) do
    case latest_claim_value(vehicle, predicate) do
      nil -> defaults
      value -> Map.merge(defaults, shape.(value))
    end
  end

  defp latest_claim_value(vehicle, predicate) do
    Repo.one(
      from(c in Claim,
        where:
          c.vehicle_id == ^vehicle.id and c.predicate == ^predicate and
            c.state == :admitted and c.method == :human,
        order_by: [desc: c.scope_date, desc: c.inserted_at],
        limit: 1,
        select: c.value
      )
    )
  end
end
