defmodule SantoApi.Nhtsa.Corpus.Importer do
  @moduledoc false

  @batch_size 500
  @diagnostic_limit 100

  @type dataset :: :recall_campaigns | :technical_bulletins

  def import_archive(dataset, archive, insert_batch)
      when dataset in [:recall_campaigns, :technical_bulletins] and is_binary(archive) and
             is_function(insert_batch, 1) do
    temp_dir = Path.join(System.tmp_dir!(), "santo-nhtsa-#{Ecto.UUID.generate()}")

    with :ok <- File.mkdir_p(temp_dir) do
      try do
        with {:ok, source_path} <- extract_one_source(archive, temp_dir),
             {:ok, stats} <- import_file(dataset, source_path, insert_batch) do
          {:ok, stats}
        end
      after
        File.rm_rf(temp_dir)
      end
    end
  end

  def import_archive(_dataset, _archive, _insert_batch), do: {:error, :invalid_archive}

  defp extract_one_source(archive, temp_dir) do
    with {:ok, entries} <- :zip.list_dir(archive),
         {:ok, [entry]} <- safe_data_entries(entries),
         {:ok, _files} <- :zip.extract(archive, cwd: String.to_charlist(temp_dir)) do
      {:ok, Path.join(temp_dir, entry)}
    else
      {:ok, entries} when is_list(entries) -> {:error, {:unexpected_archive_entries, entries}}
      {:error, reason} -> {:error, {:invalid_zip, reason}}
    end
  end

  defp safe_data_entries(entries) do
    names =
      for entry <- entries,
          is_tuple(entry),
          tuple_size(entry) > 1,
          elem(entry, 0) == :zip_file,
          name = entry |> elem(1) |> List.to_string(),
          source_file?(name) do
        name
      end

    if length(names) == 1 and Enum.all?(names, &safe_entry?/1),
      do: {:ok, names},
      else: {:error, {:unexpected_archive_entries, names}}
  end

  defp source_file?(name), do: String.ends_with?(String.downcase(name), ".txt")

  defp safe_entry?(name) do
    Path.basename(name) == name and name not in [".", ".."]
  end

  defp import_file(dataset, source_path, insert_batch) do
    initial = %{
      batch: [],
      record_count: 0,
      malformed_row_count: 0,
      skipped_row_count: 0,
      malformed_rows: []
    }

    source_path
    |> File.stream!([], :line)
    |> Stream.with_index(1)
    |> Enum.reduce_while({:ok, initial}, fn {line, source_row}, {:ok, stats} ->
      case parse(dataset, line, source_row) do
        {:ok, attrs} -> add_record(stats, attrs, insert_batch)
        :skip -> {:cont, {:ok, %{stats | skipped_row_count: stats.skipped_row_count + 1}}}
        {:error, reason} -> {:cont, {:ok, add_malformed(stats, source_row, line, reason)}}
      end
    end)
    |> flush(insert_batch)
  rescue
    exception -> {:error, {:source_read_failed, Exception.message(exception)}}
  end

  defp add_record(stats, attrs, insert_batch) do
    batch = [attrs | stats.batch]
    stats = %{stats | batch: batch, record_count: stats.record_count + 1}

    if length(batch) >= @batch_size do
      case insert_batch.(Enum.reverse(batch)) do
        :ok -> {:cont, {:ok, %{stats | batch: []}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    else
      {:cont, {:ok, stats}}
    end
  end

  defp flush({:error, _reason} = error, _insert_batch), do: error

  defp flush({:ok, %{batch: []} = stats}, _insert_batch),
    do: {:ok, Map.delete(stats, :batch)}

  defp flush({:ok, stats}, insert_batch) do
    case insert_batch.(Enum.reverse(stats.batch)) do
      :ok -> {:ok, stats |> Map.put(:batch, []) |> Map.delete(:batch)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp add_malformed(stats, source_row, line, reason) do
    diagnostic = %{
      "source_row" => source_row,
      "reason" => inspect(reason),
      "excerpt" => line |> safe_excerpt() |> String.slice(0, 240)
    }

    malformed_rows =
      if length(stats.malformed_rows) < @diagnostic_limit,
        do: [diagnostic | stats.malformed_rows],
        else: stats.malformed_rows

    %{
      stats
      | malformed_row_count: stats.malformed_row_count + 1,
        malformed_rows: malformed_rows
    }
  end

  defp safe_excerpt(line) do
    if String.valid?(line), do: String.trim(line), else: inspect(line, limit: 240)
  end

  defp parse(_dataset, line, _source_row) when not is_binary(line),
    do: {:error, :invalid_line}

  defp parse(dataset, line, source_row) do
    if String.valid?(line) do
      fields =
        line |> String.trim_trailing("\n") |> String.trim_trailing("\r") |> String.split("\t")

      parse_fields(dataset, fields, source_row, line)
    else
      {:error, :invalid_encoding}
    end
  end

  defp parse_fields(:recall_campaigns, fields, source_row, raw) do
    case fields do
      [
        record_id,
        campaign_number,
        make,
        model,
        year,
        manufacturer_campaign_number,
        component,
        filing_manufacturer,
        manufacturing_begin,
        manufacturing_end,
        recall_type,
        potential_units,
        owner_notification_date,
        influenced_by,
        recalled_manufacturer,
        report_received_date,
        record_created_date,
        regulation_part,
        fmvss,
        defect_summary,
        consequence_summary,
        corrective_summary,
        notes,
        component_id,
        manufacturer_component_name,
        manufacturer_component_description,
        manufacturer_component_part_number,
        do_not_drive,
        park_outside
      ] ->
        recall_record(
          %{
            record_id: record_id,
            campaign_number: campaign_number,
            make: make,
            model: model,
            year: year,
            manufacturer_campaign_number: manufacturer_campaign_number,
            component: component,
            filing_manufacturer: filing_manufacturer,
            manufacturing_begin: manufacturing_begin,
            manufacturing_end: manufacturing_end,
            recall_type: recall_type,
            potential_units: potential_units,
            owner_notification_date: owner_notification_date,
            influenced_by: influenced_by,
            recalled_manufacturer: recalled_manufacturer,
            report_received_date: report_received_date,
            record_created_date: record_created_date,
            regulation_part: regulation_part,
            fmvss: fmvss,
            defect_summary: defect_summary,
            consequence_summary: consequence_summary,
            corrective_summary: corrective_summary,
            notes: notes,
            component_id: component_id,
            manufacturer_component_name: manufacturer_component_name,
            manufacturer_component_description: manufacturer_component_description,
            manufacturer_component_part_number: manufacturer_component_part_number,
            do_not_drive: do_not_drive,
            park_outside: park_outside
          },
          source_row,
          raw
        )

      _fields ->
        {:error, {:field_count, expected: 29, actual: length(fields)}}
    end
  end

  defp parse_fields(:technical_bulletins, fields, source_row, raw) do
    case fields do
      [
        nhtsa_id,
        replacement_document_id,
        date_added,
        document_id,
        communication_date,
        manufacturer_campaign_id,
        communication_type,
        make,
        model,
        year,
        nhtsa_components,
        manufacturer_system,
        manufacturer_subsystem,
        summary
      ] ->
        bulletin_record(
          %{
            nhtsa_id: nhtsa_id,
            replacement_document_id: replacement_document_id,
            date_added: date_added,
            document_id: document_id,
            communication_date: communication_date,
            manufacturer_campaign_id: manufacturer_campaign_id,
            communication_type: communication_type,
            make: make,
            model: model,
            year: year,
            nhtsa_components: nhtsa_components,
            manufacturer_system: manufacturer_system,
            manufacturer_subsystem: manufacturer_subsystem,
            summary: summary
          },
          source_row,
          raw
        )

      _fields ->
        {:error, {:field_count, expected: 14, actual: length(fields)}}
    end
  end

  defp recall_record(%{recall_type: recall_type}, _source_row, _raw)
       when recall_type != "V",
       do: :skip

  defp recall_record(values, source_row, raw) do
    with {:ok, year} <- parse_year(values.year),
         {:ok, make} <- required(values.make, :make),
         {:ok, model} <- required(values.model, :model),
         {:ok, campaign_number} <- required(values.campaign_number, :campaign_number),
         {:ok, record_id} <- required(values.record_id, :record_id) do
      source_url = recall_url(campaign_number)

      payload = %{
        "identifier" => campaign_number,
        "nhtsa_record_id" => record_id,
        "manufacturer_campaign_number" => blank_to_nil(values.manufacturer_campaign_number),
        "title" => blank_to_nil(values.component) || "Safety recall #{campaign_number}",
        "summary" => blank_to_nil(values.defect_summary),
        "component" => blank_to_nil(values.component),
        "manufacturer" => blank_to_nil(values.recalled_manufacturer),
        "filing_manufacturer" => blank_to_nil(values.filing_manufacturer),
        "consequence" => blank_to_nil(values.consequence_summary),
        "remedy" => blank_to_nil(values.corrective_summary),
        "notes" => blank_to_nil(values.notes),
        "potential_units" => integer_or_nil(values.potential_units),
        "report_received_date" => iso_date_or_nil(values.report_received_date),
        "owner_notification_date" => iso_date_or_nil(values.owner_notification_date),
        "applicability" => %{
          "marque" => String.trim(make),
          "model" => String.trim(model),
          "model_year" => year,
          "manufacturing_begin" => iso_date_or_nil(values.manufacturing_begin),
          "manufacturing_end" => iso_date_or_nil(values.manufacturing_end)
        },
        "source_url" => source_url,
        "document_url" => source_url,
        "do_not_drive" => yes?(values.do_not_drive),
        "park_outside" => yes?(values.park_outside)
      }

      {:ok, record_attrs(source_row, raw, make, model, year, payload)}
    else
      {:error, :unknown_year} -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  defp bulletin_record(values, source_row, raw) do
    with {:ok, year} <- parse_year(values.year),
         {:ok, make} <- required(values.make, :make),
         {:ok, model} <- required(values.model, :model),
         {:ok, nhtsa_id} <- required(values.nhtsa_id, :nhtsa_id),
         {:ok, document_id} <- required(values.document_id, :document_id),
         {:ok, document_year} <- document_year(values.date_added) do
      document_url =
        "https://static.nhtsa.gov/odi/tsbs/#{document_year}/MC-#{nhtsa_id}-0001.pdf"

      payload = %{
        "identifier" => document_id,
        "nhtsa_id" => nhtsa_id,
        "replacement_document_id" => blank_to_nil(values.replacement_document_id),
        "manufacturer_campaign_id" => blank_to_nil(values.manufacturer_campaign_id),
        "communication_type" => blank_to_nil(values.communication_type),
        "title" => document_id,
        "summary" => blank_to_nil(values.summary),
        "communication_date" => iso_date_or_nil(values.communication_date),
        "date_added" => iso_date_or_nil(values.date_added),
        "component" => blank_to_nil(values.nhtsa_components),
        "manufacturer_system" => blank_to_nil(values.manufacturer_system),
        "manufacturer_subsystem" => blank_to_nil(values.manufacturer_subsystem),
        "applicability" => %{
          "marque" => String.trim(make),
          "model" => String.trim(model),
          "model_year" => year
        },
        "source_url" => document_url,
        "document_url" => document_url
      }

      {:ok, record_attrs(source_row, raw, make, model, year, payload)}
    else
      {:error, :unknown_year} -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  defp record_attrs(source_row, raw, make, model, year, payload) do
    %{
      source_row: source_row,
      record_key: sha256(Integer.to_string(source_row) <> "\0" <> raw),
      marque: normalize_lookup(make),
      model: normalize_lookup(model),
      model_year: year,
      payload: payload
    }
  end

  defp required(value, field) do
    case blank_to_nil(value) do
      nil -> {:error, {:missing_field, field}}
      value -> {:ok, value}
    end
  end

  defp parse_year("9999"), do: {:error, :unknown_year}

  defp parse_year(value) do
    case Integer.parse(String.trim(value)) do
      {year, ""} when year in 1886..2200 -> {:ok, year}
      _invalid -> {:error, {:invalid_year, value}}
    end
  end

  defp document_year(<<year::binary-size(4), _rest::binary>>) do
    case Integer.parse(year) do
      {parsed, ""} when parsed in 1995..2200 -> {:ok, parsed}
      _invalid -> {:error, {:invalid_date_added, year}}
    end
  end

  defp document_year(value), do: {:error, {:invalid_date_added, value}}

  defp iso_date_or_nil(<<year::binary-size(4), month::binary-size(2), day::binary-size(2)>>) do
    with {year, ""} <- Integer.parse(year),
         {month, ""} <- Integer.parse(month),
         {day, ""} <- Integer.parse(day),
         {:ok, date} <- Date.new(year, month, day) do
      Date.to_iso8601(date)
    else
      _invalid -> nil
    end
  end

  defp iso_date_or_nil(_value), do: nil

  defp integer_or_nil(value) do
    case Integer.parse(String.trim(value)) do
      {integer, ""} -> integer
      _invalid -> nil
    end
  end

  defp yes?(value), do: value |> String.trim() |> String.downcase() == "yes"

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_lookup(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end

  defp recall_url(campaign_number) do
    query = URI.encode_query(%{"campaignNumber" => campaign_number})
    "https://api.nhtsa.gov/recalls/campaignNumber?#{query}"
  end

  defp sha256(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
