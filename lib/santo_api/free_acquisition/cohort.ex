defmodule SantoApi.FreeAcquisition.Cohort do
  @moduledoc """
  Loads and validates the checked-in, transaction-weighted collector-car cohort.

  The manifest contains bare sale facts and outbound pointers. It deliberately
  contains no copied marketplace prose or media.
  """

  @cohorts ~w(air_cooled_911 vintage_ferrari limited_gt)
  @required_count 10

  def default_path do
    Application.app_dir(:santo_api, "priv/free_acquisition/targets.json")
  end

  def load(path \\ default_path()) do
    with {:ok, contents} <- File.read(path),
         {:ok, manifest} <- Jason.decode(contents),
         :ok <- validate(manifest) do
      {:ok, manifest}
    end
  end

  def load!(path \\ default_path()) do
    case load(path) do
      {:ok, manifest} -> manifest
      {:error, reason} -> raise "invalid free-acquisition cohort: #{inspect(reason)}"
    end
  end

  def select(%{"entries" => entries}, opts \\ []) do
    cohort = Keyword.get(opts, :cohort)
    limit = Keyword.get(opts, :limit)

    entries
    |> maybe_filter(cohort)
    |> maybe_limit(limit)
  end

  def summary(entries) do
    %{
      count: length(entries),
      cohorts: Enum.frequencies_by(entries, & &1["cohort"]),
      vin_count: Enum.count(entries, &(&1["identity"]["kind"] == "vin")),
      chassis_count: Enum.count(entries, &(&1["identity"]["kind"] == "chassis"))
    }
  end

  def cohorts, do: @cohorts

  defp validate(%{"version" => 1, "rights_profile" => rights, "entries" => entries})
       when is_binary(rights) and is_list(entries) do
    with :ok <- validate_count(entries),
         :ok <- validate_unique_ids(entries),
         :ok <- validate_cohort_counts(entries) do
      validate_entries(entries)
    end
  end

  defp validate(_manifest), do: {:error, :invalid_manifest_header}

  defp validate_count(entries) do
    if length(entries) == length(@cohorts) * @required_count,
      do: :ok,
      else: {:error, {:entry_count, length(entries)}}
  end

  defp validate_unique_ids(entries) do
    ids = Enum.map(entries, & &1["id"])
    if length(Enum.uniq(ids)) == length(ids), do: :ok, else: {:error, :duplicate_ids}
  end

  defp validate_cohort_counts(entries) do
    counts = Enum.frequencies_by(entries, & &1["cohort"])
    expected = Map.new(@cohorts, &{&1, @required_count})
    if counts == expected, do: :ok, else: {:error, {:cohort_counts, counts}}
  end

  defp validate_entries(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      case validate_entry(entry) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:entry, index, reason}}}
      end
    end)
  end

  defp validate_entry(%{
         "id" => id,
         "cohort" => cohort,
         "display_name" => name,
         "model_year" => year,
         "identity" => identity,
         "transaction" => transaction
       })
       when is_binary(id) and id != "" and cohort in @cohorts and is_binary(name) and
              is_integer(year) do
    with :ok <- validate_identity(identity),
         :ok <- validate_transaction(transaction) do
      :ok
    end
  end

  defp validate_entry(_entry), do: {:error, :invalid_shape}

  defp validate_identity(%{"kind" => "vin", "value" => vin})
       when is_binary(vin) and byte_size(vin) == 17,
       do: :ok

  defp validate_identity(%{
         "kind" => "chassis",
         "marque" => "ferrari",
         "era" => "pre_vin",
         "value" => number
       })
       when is_binary(number) and number != "",
       do: :ok

  defp validate_identity(_identity), do: {:error, :invalid_identity}

  defp validate_transaction(%{
         "venue" => venue,
         "url" => url,
         "date" => date,
         "price" => price,
         "currency" => currency
       })
       when is_binary(venue) and venue != "" and is_binary(url) and is_binary(date) and
              is_integer(price) and price >= 0 and is_binary(currency) do
    with {:ok, _date} <- Date.from_iso8601(date),
         %URI{scheme: "https", host: host} when is_binary(host) <- URI.parse(url) do
      :ok
    else
      _ -> {:error, :invalid_transaction}
    end
  end

  defp validate_transaction(_transaction), do: {:error, :invalid_transaction}

  defp maybe_filter(entries, nil), do: entries
  defp maybe_filter(entries, cohort), do: Enum.filter(entries, &(&1["cohort"] == cohort))

  defp maybe_limit(entries, nil), do: entries
  defp maybe_limit(entries, limit), do: Enum.take(entries, limit)
end
