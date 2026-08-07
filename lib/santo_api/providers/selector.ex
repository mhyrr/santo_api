defmodule SantoApi.Providers.Selector do
  @moduledoc """
  Provider-neutral locators discovered or supplied during acquisition.

  The first slice deliberately covers model-population lookup. Jurisdiction,
  registration, plate, title, and authorization selectors can extend this value
  without becoming vendor options.
  """

  @enforce_keys []
  defstruct [:marque, :model, :model_year]

  @type model :: %{required(String.t()) => String.t() | nil}
  @type t :: %__MODULE__{
          marque: String.t() | nil,
          model: model() | nil,
          model_year: integer() | nil
        }

  @fields [:marque, :model, :model_year]

  def fields, do: @fields

  def new(%__MODULE__{} = selector), do: validate_result(selector)

  def new(attrs) when is_map(attrs) do
    accepted_keys = @fields ++ Enum.map(@fields, &to_string/1)
    unknown = Map.keys(attrs) -- accepted_keys

    if unknown == [] do
      selector = %__MODULE__{
        marque: fetch(attrs, :marque),
        model: fetch(attrs, :model),
        model_year: fetch(attrs, :model_year)
      }

      validate_result(selector)
    else
      {:error, {:unknown_selectors, unknown}}
    end
  end

  def new(_attrs), do: {:error, :invalid_selectors}

  def validate(%__MODULE__{} = selector) do
    cond do
      !valid_optional_string?(selector.marque) -> {:error, {:invalid_selector, :marque}}
      !valid_model?(selector.model) -> {:error, {:invalid_selector, :model}}
      !valid_year?(selector.model_year) -> {:error, {:invalid_selector, :model_year}}
      true -> :ok
    end
  end

  def required_missing(%__MODULE__{} = selector, required) when is_list(required) do
    Enum.filter(required, &(Map.fetch!(selector, &1) in [nil, ""]))
  end

  def to_map(%__MODULE__{} = selector) do
    selector
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp validate_result(selector) do
    case validate(selector) do
      :ok -> {:ok, selector}
      {:error, _reason} = error -> error
    end
  end

  defp fetch(attrs, key), do: Map.get(attrs, key, Map.get(attrs, to_string(key)))

  defp valid_optional_string?(nil), do: true
  defp valid_optional_string?(value), do: is_binary(value) and value != ""

  defp valid_model?(nil), do: true

  defp valid_model?(%{"code" => code, "label" => label}) do
    is_binary(code) and code != "" and (is_binary(label) or is_nil(label))
  end

  defp valid_model?(_value), do: false

  defp valid_year?(nil), do: true
  defp valid_year?(year), do: is_integer(year) and year in 1886..2200
end
