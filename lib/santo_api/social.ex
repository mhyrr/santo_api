defmodule SantoApi.Social do
  @moduledoc """
  Conversation around a car's public updates.

  This context is intentionally outside `SantoApi.Registry`: likes and replies
  discuss a record but do not become claims, timeline entries, verification
  inputs, or current-state data. Every write rechecks both the signed-in member
  and the public update it targets. A car's steward has no moderation power over
  other people's replies; reports go to an operator.
  """

  import Ecto.Query, warn: false

  alias SantoApi.Accounts.{Scope, User}
  alias SantoApi.Registry
  alias SantoApi.Registry.Vehicle
  alias SantoApi.Repo
  alias SantoApi.Social.{CommentReport, UpdateComment, UpdateLike}

  @doc "One update's visible conversation and reaction state for this viewer."
  def conversation(scope, %Vehicle{} = vehicle, entry_ref) do
    with {:ok, ref} <- Ecto.UUID.cast(entry_ref) do
      comments =
        Repo.all(
          from(c in UpdateComment,
            where:
              c.vehicle_id == ^vehicle.id and c.entry_ref == ^ref and
                c.status == :visible,
            order_by: [asc: c.inserted_at]
          )
        )

      like_count =
        Repo.aggregate(
          from(l in UpdateLike, where: l.vehicle_id == ^vehicle.id and l.entry_ref == ^ref),
          :count
        )

      %{
        comments: comments,
        comment_count: length(comments),
        like_count: like_count,
        liked?: liked?(scope, vehicle.id, ref)
      }
    else
      :error -> %{comments: [], comment_count: 0, like_count: 0, liked?: false}
    end
  end

  @doc "Add or remove this member's appreciation for one public update."
  def toggle_like(%Scope{user: %User{} = user}, %Vehicle{} = vehicle, entry_ref) do
    with {:ok, ref} <- public_entry(vehicle, entry_ref) do
      case Repo.get_by(UpdateLike, vehicle_id: vehicle.id, entry_ref: ref, user_id: user.id) do
        %UpdateLike{} = like ->
          with {:ok, _like} <- Repo.delete(like), do: {:ok, :removed}

        nil ->
          case vehicle.id |> UpdateLike.create_changeset(ref, user.id) |> Repo.insert() do
            {:ok, _like} -> {:ok, :added}
            {:error, %Ecto.Changeset{} = changeset} -> duplicate_like(changeset)
          end
      end
    end
  end

  def toggle_like(_scope, %Vehicle{}, _entry_ref), do: {:error, :authentication_required}

  @doc "Build the reply changeset used by the update form."
  def change_comment(
        %Scope{user: %User{handle: handle} = user},
        %Vehicle{} = vehicle,
        entry_ref,
        attrs \\ %{}
      )
      when is_binary(handle) do
    UpdateComment.create_changeset(vehicle.id, entry_ref, user, attrs)
  end

  @doc "Publish a reply under the member's immutable public handle."
  def create_comment(
        %Scope{user: %User{handle: handle} = user},
        %Vehicle{} = vehicle,
        entry_ref,
        attrs
      )
      when is_binary(handle) do
    with {:ok, ref} <- public_entry(vehicle, entry_ref) do
      vehicle.id
      |> UpdateComment.create_changeset(ref, user, attrs)
      |> Repo.insert()
    end
  end

  def create_comment(%Scope{user: %User{}}, %Vehicle{}, _entry_ref, _attrs),
    do: {:error, :handle_required}

  def create_comment(_scope, %Vehicle{}, _entry_ref, _attrs),
    do: {:error, :authentication_required}

  @doc "Withdraw the caller's own reply without erasing the moderation trail."
  def withdraw_comment(%Scope{user: %User{} = user}, comment_id) do
    with {:ok, id} <- Ecto.UUID.cast(comment_id),
         %UpdateComment{} = comment <- Repo.get(UpdateComment, id),
         true <- comment.author_user_id == user.id,
         true <- comment.status == :visible do
      comment
      |> Ecto.Changeset.change(status: :withdrawn, withdrawn_at: DateTime.utc_now())
      |> Repo.update()
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
      false -> {:error, :not_authorized}
    end
  end

  def withdraw_comment(_scope, _comment_id), do: {:error, :authentication_required}

  @doc "One visible reply on the update currently being viewed."
  def fetch_comment(_scope, %Vehicle{} = vehicle, entry_ref, comment_id) do
    with {:ok, ref} <- Ecto.UUID.cast(entry_ref),
         {:ok, id} <- Ecto.UUID.cast(comment_id),
         %UpdateComment{status: :visible} = comment <-
           Repo.get_by(UpdateComment, id: id, vehicle_id: vehicle.id, entry_ref: ref) do
      {:ok, comment}
    else
      _absent -> {:error, :not_found}
    end
  end

  @doc "Build the report form for one visible reply."
  def change_report(
        %Scope{user: %User{handle: handle} = user},
        %UpdateComment{} = comment,
        attrs \\ %{}
      )
      when is_binary(handle) do
    CommentReport.create_changeset(comment.id, user, attrs)
  end

  @doc "Send a visible reply to the operator queue."
  def report_comment(
        %Scope{user: %User{handle: handle} = user},
        comment_id,
        attrs
      )
      when is_binary(handle) do
    with {:ok, id} <- Ecto.UUID.cast(comment_id),
         %UpdateComment{status: :visible} = comment <- Repo.get(UpdateComment, id),
         false <- comment.author_user_id == user.id do
      comment.id
      |> CommentReport.create_changeset(user, attrs)
      |> Repo.insert()
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
      true -> {:error, :own_comment}
      %UpdateComment{} -> {:error, :not_visible}
    end
  end

  def report_comment(%Scope{user: %User{}}, _comment_id, _attrs),
    do: {:error, :handle_required}

  def report_comment(_scope, _comment_id, _attrs), do: {:error, :authentication_required}

  @doc "Open reply reports for the operator workbench, oldest first."
  def list_open_reports(%Scope{user: %User{operator: true}}) do
    Repo.all(
      from(r in CommentReport,
        where: r.status == :open,
        order_by: [asc: r.inserted_at],
        preload: [comment: :vehicle]
      )
    )
  end

  def list_open_reports(_scope), do: []

  @doc "Hide the reported reply and resolve every open report against it."
  def hide_reported_comment(%Scope{user: %User{operator: true} = operator}, report_id, note) do
    with {:ok, id} <- Ecto.UUID.cast(report_id) do
      Repo.transaction(fn ->
        report = locked_report(id)

        if is_nil(report), do: Repo.rollback(:not_found)
        if report.status != :open, do: Repo.rollback(:already_decided)

        comment = Repo.get(UpdateComment, report.comment_id)
        if is_nil(comment), do: Repo.rollback(:not_found)
        now = DateTime.utc_now()

        {:ok, hidden} =
          comment
          |> Ecto.Changeset.change(
            status: :hidden,
            hidden_at: now,
            hidden_by_user_id: operator.id,
            moderation_note: presence(note)
          )
          |> Repo.update()

        Repo.update_all(
          from(r in CommentReport,
            where: r.comment_id == ^comment.id and r.status == :open
          ),
          set: [
            status: :actioned,
            decided_by_user_id: operator.id,
            decided_at: now,
            decision_note: presence(note),
            updated_at: now
          ]
        )

        hidden
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  def hide_reported_comment(_scope, _report_id, _note), do: {:error, :not_authorized}

  @doc "Dismiss one report while leaving the reply visible."
  def dismiss_report(%Scope{user: %User{operator: true} = operator}, report_id, note) do
    with {:ok, id} <- Ecto.UUID.cast(report_id) do
      Repo.transaction(fn ->
        report = locked_report(id)

        if is_nil(report), do: Repo.rollback(:not_found)
        if report.status != :open, do: Repo.rollback(:already_decided)

        report
        |> Ecto.Changeset.change(
          status: :dismissed,
          decided_by_user_id: operator.id,
          decided_at: DateTime.utc_now(),
          decision_note: presence(note)
        )
        |> Repo.update!()
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  def dismiss_report(_scope, _report_id, _note), do: {:error, :not_authorized}

  defp public_entry(vehicle, entry_ref) do
    with {:ok, entry} <- Registry.fetch_timeline_entry(vehicle.id, entry_ref) do
      {:ok, entry.entry_ref}
    end
  end

  defp locked_report(id) do
    Repo.one(from(r in CommentReport, where: r.id == ^id, lock: "FOR UPDATE"))
  end

  defp liked?(%Scope{user: %User{} = user}, vehicle_id, entry_ref) do
    Repo.exists?(
      from(l in UpdateLike,
        where: l.vehicle_id == ^vehicle_id and l.entry_ref == ^entry_ref and l.user_id == ^user.id
      )
    )
  end

  defp liked?(_scope, _vehicle_id, _entry_ref), do: false

  # Two browser clicks can race. The unique index wins; the resulting state is
  # still liked, so report the semantic result instead of surfacing a form error.
  defp duplicate_like(changeset) do
    if Keyword.has_key?(changeset.errors, :vehicle_id),
      do: {:ok, :added},
      else: {:error, changeset}
  end

  defp presence(nil), do: nil

  defp presence(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end
end
