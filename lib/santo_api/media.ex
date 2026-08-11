defmodule SantoApi.Media do
  @moduledoc """
  Validates first-party image uploads and produces the metadata-stripped JPEG
  variants public pages are allowed to serve.

  Original bytes remain in `SantoApi.Registry.Artifact`; pages receive only
  these derivatives. That keeps EXIF location and device metadata off the
  public surface while giving the browser honest intrinsic widths for `srcset`.
  """

  alias SantoApi.Registry.Artifact
  alias SantoApi.Storage

  @max_file_size 20_000_000
  @variant_lengths [480, 960, 1600]
  @variant_quality 82

  @doc "Validate an uploaded image and persist responsive, stripped variants."
  def prepare_photo(path) when is_binary(path) do
    with {:ok, %File.Stat{size: size}} when size <= @max_file_size <- File.stat(path),
         {:ok, image} <- Image.open(path),
         {:ok, variants} <- build_variants(image, sha256(path)) do
      {width, height, _bands} = Image.shape(image)

      {:ok,
       %{
         "original_width" => width,
         "original_height" => height,
         "variants" => variants
       }}
    else
      {:ok, %File.Stat{}} -> {:error, :photo_too_large}
      {:error, _reason} -> {:error, :invalid_photo}
    end
  rescue
    _image_error -> {:error, :invalid_photo}
  end

  @doc "The ordered responsive variants recorded on a photo artifact."
  def variants(%Artifact{} = artifact) do
    artifact.metadata
    |> Map.get("photo_derivatives", %{})
    |> Map.get("variants", [])
    |> Enum.sort_by(& &1["width"])
  end

  @doc "Resolve a named derivative without ever accepting a storage path from the URL."
  def variant(%Artifact{} = artifact, requested \\ nil) do
    variants = variants(artifact)

    selected =
      if is_binary(requested) do
        Enum.find(variants, &(Integer.to_string(&1["width"]) == requested))
      else
        List.last(variants)
      end

    case selected do
      %{"storage_ref" => ref, "mime" => mime} = variant ->
        {:ok, %{storage_ref: ref, mime: mime, width: variant["width"], height: variant["height"]}}

      _missing ->
        {:error, :not_found}
    end
  end

  defp build_variants(image, sha) do
    {original_width, original_height, _bands} = Image.shape(image)

    lengths =
      @variant_lengths
      |> Enum.map(&min(&1, max(original_width, original_height)))
      |> Enum.uniq()

    variants =
      Enum.map(lengths, fn length ->
        {:ok, variant} = Image.thumbnail(image, length, autorotate: true)
        {width, height, _bands} = Image.shape(variant)

        {:ok, bytes} =
          Image.write(variant, :memory,
            suffix: ".jpg",
            quality: @variant_quality,
            strip_metadata: true,
            background: "#f2eadb"
          )

        storage_ref = "#{sha}-display-#{width}x#{height}.jpg"
        :ok = Storage.put(storage_ref, bytes)

        %{
          "width" => width,
          "height" => height,
          "storage_ref" => storage_ref,
          "mime" => "image/jpeg"
        }
      end)

    {:ok, Enum.uniq_by(variants, &{&1["width"], &1["height"]})}
  rescue
    _image_error -> {:error, :invalid_photo}
  end

  defp sha256(path) do
    path
    |> File.read!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
