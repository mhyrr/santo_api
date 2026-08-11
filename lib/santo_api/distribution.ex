defmodule SantoApi.Distribution do
  @moduledoc """
  Turns one public owner update into portable, rights-clean formats.

  The source is always the owner's own Vin Santo entry and first-party photo.
  Forum output is copy/paste text, the badge is a small SVG, and the share card
  is one named 4:5 JPEG transform. No platform credentials or inbound media are
  involved.
  """

  alias SantoApi.{Media, Storage}

  @card_width 1080
  @card_height 1350

  @doc "A ready-to-paste forum post in Markdown or BBCode."
  def forum_snippet(payload, :markdown) do
    details =
      payload.details
      |> Enum.map_join("\n", &"- **#{markdown_text(&1.label)}:** #{markdown_text(&1.value)}")

    [
      "## #{markdown_text(payload.title)}",
      dated_headline(payload, :markdown),
      photo_line(payload, :markdown),
      present(details),
      "[View this update on Vin Santo](#{payload.url})"
    ]
    |> compact_sections()
  end

  def forum_snippet(payload, :bbcode) do
    details =
      payload.details
      |> Enum.map_join("\n", &"[b]#{bbcode_text(&1.label)}:[/b] #{bbcode_text(&1.value)}")

    [
      "[size=150][b]#{bbcode_text(payload.title)}[/b][/size]",
      dated_headline(payload, :bbcode),
      photo_line(payload, :bbcode),
      present(details),
      "[url=#{payload.url}]View this update on Vin Santo[/url]"
    ]
    |> compact_sections()
  end

  @doc "Copyable HTML or BBCode for the small, linked vehicle badge."
  def badge_embed(payload, :html) do
    ~s(<a href="#{xml_escape(payload.car_url)}"><img src="#{xml_escape(payload.badge_url)}" alt="#{xml_escape(payload.title)} on Vin Santo" width="560" height="120"></a>)
  end

  def badge_embed(payload, :bbcode) do
    "[url=#{payload.car_url}][img]#{payload.badge_url}[/img][/url]"
  end

  @doc "Render a 1080×1350 JPEG share card from an update and its lead photo."
  def share_card(payload) do
    svg = share_card_svg(payload, photo_data(payload.photo))

    with {:ok, image} <- Image.from_svg(svg),
         {:ok, bytes} <-
           Image.write(image, :memory,
             suffix: ".jpg",
             quality: 86,
             strip_metadata: true,
             background: "#ece2d1"
           ) do
      {:ok, bytes}
    else
      _failure -> {:error, :share_card_failed}
    end
  rescue
    _image_error -> {:error, :share_card_failed}
  end

  @doc "Render the linked vehicle badge served to forum signatures."
  def badge_svg(payload) do
    title = payload.title |> wrap_lines(34, 1) |> hd() |> xml_escape()
    detail = payload.badge_detail |> wrap_lines(48, 1) |> hd() |> xml_escape()

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="560" height="120" viewBox="0 0 560 120" role="img" aria-label="#{title} on Vin Santo">
      <rect width="560" height="120" fill="#171b1b"/>
      <rect width="8" height="120" fill="#ee6c24"/>
      <circle cx="506" cy="28" r="54" fill="none" stroke="#1f6d6a" stroke-width="8" opacity=".45"/>
      <circle cx="506" cy="28" r="38" fill="none" stroke="#ece2d1" stroke-width="2" opacity=".2"/>
      <text x="30" y="28" fill="#ee6c24" font-family="Arial, sans-serif" font-size="13" font-weight="700" letter-spacing="3">VIN SANTO</text>
      <text x="30" y="65" fill="#f5efe4" font-family="Arial Narrow, Arial, sans-serif" font-size="28" font-weight="800" font-style="italic">#{title}</text>
      <text x="30" y="92" fill="#93c4bf" font-family="Arial, sans-serif" font-size="15">#{detail}</text>
    </svg>
    """
  end

  defp share_card_svg(payload, photo_data) do
    title_lines = wrap_lines(payload.title, 27, 2)
    headline_lines = wrap_lines(payload.headline, 37, 3)

    detail =
      payload.details |> Enum.take(3) |> Enum.map_join("  ·  ", &"#{&1.label}: #{&1.value}")

    photo_layer = photo_layer(photo_data)

    """
    <svg xmlns="http://www.w3.org/2000/svg" width="#{@card_width}" height="#{@card_height}" viewBox="0 0 #{@card_width} #{@card_height}">
      <rect width="1080" height="1350" fill="#ece2d1"/>
      #{photo_layer}
      <rect x="0" y="0" width="18" height="1350" fill="#ee6c24"/>
      <rect x="0" y="745" width="1080" height="18" fill="#1f6d6a"/>
      <text x="72" y="822" fill="#1f6d6a" font-family="Arial, sans-serif" font-size="24" font-weight="700" letter-spacing="6">VIN SANTO  ·  #{xml_escape(payload.date || "UPDATE")}</text>
      <text x="72" y="902" fill="#171b1b" font-family="Arial Narrow, Arial, sans-serif" font-size="68" font-weight="900" font-style="italic">#{svg_lines(title_lines, 72)}</text>
      <text x="72" y="#{1006 + max(length(title_lines) - 1, 0) * 72}" fill="#303736" font-family="Arial, sans-serif" font-size="44" font-weight="600">#{svg_lines(headline_lines, 56)}</text>
      <text x="72" y="1260" fill="#58605e" font-family="Arial, sans-serif" font-size="24">#{xml_escape(detail)}</text>
      <text x="72" y="1312" fill="#1f6d6a" font-family="Arial, sans-serif" font-size="24" font-weight="700">#{xml_escape(payload.car_url |> short_url() |> truncate(66))}</text>
    </svg>
    """
  end

  defp photo_layer(nil) do
    """
    <rect x="0" y="0" width="1080" height="763" fill="#171b1b"/>
    <path d="M760 -40 C970 105 955 360 1125 510" fill="none" stroke="#ece2d1" stroke-width="28" opacity=".13"/>
    <path d="M705 -30 C920 125 900 390 1070 550" fill="none" stroke="#1f6d6a" stroke-width="12" opacity=".65"/>
    <text x="72" y="650" fill="#f5efe4" font-family="Arial Narrow, Arial, sans-serif" font-size="42" font-weight="800" font-style="italic">A LIVING GARAGE LOG</text>
    """
  end

  defp photo_layer(data) do
    """
    <image x="0" y="0" width="1080" height="763" preserveAspectRatio="xMidYMid slice" href="data:image/jpeg;base64,#{data}"/>
    <rect x="0" y="565" width="1080" height="198" fill="url(#fade)"/>
    <defs>
      <linearGradient id="fade" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stop-color="#171b1b" stop-opacity="0"/>
        <stop offset="1" stop-color="#171b1b" stop-opacity=".48"/>
      </linearGradient>
    </defs>
    """
  end

  defp photo_data(nil), do: nil

  defp photo_data(%{artifact: artifact}) do
    with {:ok, variant} <- Media.variant(artifact),
         {:ok, bytes} <- Storage.fetch(variant.storage_ref) do
      Base.encode64(bytes)
    else
      _missing -> nil
    end
  end

  defp dated_headline(payload, format) do
    headline =
      if format == :bbcode,
        do: bbcode_text(payload.headline),
        else: markdown_text(payload.headline)

    case payload.date do
      date when is_binary(date) -> "#{date} — #{headline}"
      _undated -> headline
    end
  end

  defp photo_line(%{photo_url: url, title: title}, :markdown) when is_binary(url),
    do: "![#{markdown_text(title)}](#{url})"

  defp photo_line(%{photo_url: url}, :bbcode) when is_binary(url), do: "[img]#{url}[/img]"
  defp photo_line(_payload, _format), do: nil

  defp compact_sections(sections) do
    sections
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp present(""), do: nil
  defp present(value), do: value

  defp wrap_lines(text, max_chars, max_lines) do
    lines =
      text
      |> to_string()
      |> String.split(~r/\s+/, trim: true)
      |> Enum.reduce([], fn word, lines -> append_word(lines, word, max_chars) end)
      |> Enum.map(&truncate(&1, max_chars))

    case Enum.split(lines, max_lines) do
      {kept, []} ->
        if kept == [], do: [""], else: kept

      {kept, _rest} ->
        List.update_at(kept, -1, &truncate(String.trim_trailing(&1, "…") <> "…", max_chars))
    end
  end

  defp append_word([], word, _max), do: [word]

  defp append_word(lines, word, max_chars) do
    last = List.last(lines)

    if String.length(last) + String.length(word) + 1 <= max_chars do
      List.replace_at(lines, -1, last <> " " <> word)
    else
      lines ++ [word]
    end
  end

  defp truncate(text, max_chars) do
    if String.length(text) <= max_chars do
      text
    else
      String.slice(text, 0, max_chars - 1) <> "…"
    end
  end

  defp svg_lines(lines, line_height) do
    lines
    |> Enum.with_index()
    |> Enum.map_join(fn {line, index} ->
      dy = if index == 0, do: 0, else: line_height
      ~s(<tspan x="72" dy="#{dy}">#{xml_escape(line)}</tspan>)
    end)
  end

  defp short_url(url) do
    url
    |> String.replace_prefix("https://", "")
    |> String.replace_prefix("http://", "")
  end

  defp markdown_text(text) do
    text |> to_string() |> String.replace("[", "\\[") |> String.replace("]", "\\]")
  end

  defp bbcode_text(text) do
    text |> to_string() |> String.replace("[", "(") |> String.replace("]", ")")
  end

  defp xml_escape(text) do
    text
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&apos;")
  end
end
