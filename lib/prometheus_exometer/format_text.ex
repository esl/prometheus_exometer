defmodule PrometheusExometer.FormatText do
  @moduledoc false

  # These functions generate output in Prometheus text format
  #
  # They are internal, exported only so that they can be accessed by tests

  # require Lager

  import PrometheusExometer.Convert

  @type name :: :exometer.name
  @type labels :: Keyword.t
  @type value :: any
  @type error :: {:error, any}

  def format_entry(entry, config) do
    # Everything here is a prometheus parent or generic Exometer entry
    info = entry.info
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    exometer_name = info[:name]
    exometer_type = info[:type]

    {name, name_labels} = split_name_labels(exometer_name, prometheus_options)
    {name, converted_labels} = convert_name(name, info, config)
    labels = name_labels ++ converted_labels

    [
      format_header(name, labels, prometheus_options, exometer_name, exometer_type),
      format_data(name, labels, exometer_name, exometer_type, prometheus_options),
      for child <- entry.children do format_child(child, name, converted_labels) end
    ]
  end

  defp format_child(info, parent_name, parent_labels) do
    options = info[:options]
    prometheus_options = options[:prometheus] || %{}
    exometer_name = info[:name]
    exometer_type = info[:type]

    {_name, labels} = split_name_labels(exometer_name, prometheus_options)
    format_data(parent_name, parent_labels ++ labels, exometer_name, exometer_type, prometheus_options)
  end

  @spec format_data(name, labels, :exometer.name, atom, map) :: iolist
  defp format_data(name, labels, exometer_name, :prometheus_histogram, prometheus_options) do
    # [{sum: 0.0}, {:count, 0.0}, {50, "50}, {75, "75"}, {90, "90"}, {95, "95"}, {inf, "+Inf"}]
    {:ok, data_points} = :exometer.get_value(exometer_name)
    # Lager.debug("data_points: #{inspect data_points}")

    [
      if Map.get(prometheus_options, :export_buckets, false) do
        for {k, v} <- data_points, k not in [:ms_since_reset, :sum, :count] do
          format_data(name, labels ++ [le: k], v)
        end
      else
        []
      end,
      format_data(name ++ [:sum], labels, convert_unit(prometheus_options, data_points[:sum])),
      format_data(name ++ [:count], labels, data_points[:count])
    ]
  end

  defp format_data(name, labels, exometer_name, :histogram, prometheus_options) do
    # [{:n, 0.0}, {:mean, 0.0}, {:min, 0.0}, {:max, 0.0}, {:median, 0.0},
    # {50, 0.0}, {75, 0.0}, {90, 0.0}, {95, 0.0}, {99, 0.0}, {999, 0.0}]}
    {:ok, data_points} = :exometer.get_value(exometer_name)
    # Lager.debug("data_points: #{inspect data_points}")
    n = data_points[:n]
    [
      format_data(name ++ [:sum], labels, convert_unit(prometheus_options, data_points[:mean] * n)),
      format_data(name ++ [:count], labels, n),
      if Map.get(prometheus_options, :export_quantiles, false) do
        for {k, q} <- [{50, "0.5"}, {75, "0.75"}, {90, "0.9"}, {95, "0.95"}, {99, "0.99"}, {999, "0.999"}] do
          {_k, v} = List.keyfind(data_points, k, 0)
          format_data(name, labels ++ [quantile: q], v)
        end
      else
       []
      end
    ]
  end

  defp format_data(name, labels, exometer_name, exometer_type, prometheus_options)
    when exometer_type in [:counter, :prometheus_counter] do

    # [{:value, 0}, {:ms_since_reset, 15615}]
    {:ok, data_points} = :exometer.get_value(exometer_name)
    [
      format_data(name, labels, convert_unit(prometheus_options, data_points[:value]))
    ]
  end

  defp format_data(name, labels, exometer_name, exometer_type, prometheus_options)
    when exometer_type in [:gauge, :prometheus_gauge] do

    # [value: 0, ms_since_reset: 15615]
    {:ok, data_points} = :exometer.get_value(exometer_name)
    [
      format_data(name, labels, convert_unit(prometheus_options, data_points[:value]))
    ]
  end

  defp format_data(name, labels, exometer_name, :meter, prometheus_options) do
    # [count: 0, one: 0, five: 0, fifteen: 0, day: 0, mean: 0,
    # acceleration: [one_to_five: 0.0, five_to_fifteen: 0.0, one_to_fifteen: 0.0]]
    {:ok, data_points} = :exometer.get_value(exometer_name)
    [
      # TODO: make sure this is the right value to read; are other values interesting
      # should we use data format https://github.com/boundary/folsom
      format_data(name, labels, convert_unit(prometheus_options, data_points[:one]))
    ]
  end
  defp format_data(_name, _labels, _exometer_name, _exometer_type, _prometheus_options) do
    # Lager.debug("Skipping #{inspect name} #{inspect labels} #{inspect exometer_name} #{inspect exometer_type} #{inspect prometheus_options}")
    []
  end

  # These functions have tests

  @spec format_names(name) :: list(binary)
  def format_names(names) when is_list(names) do
    names = for name <- names, do: to_string(name)
    Enum.intersperse(names, "_")
  end

  @spec format_value(term) :: binary
  def format_value(value) when is_float(value), do: to_string(Float.round(value, 4))
  def format_value(value), do: to_string(value)

  @spec format_help(list(atom), binary) :: iolist
  def format_help(names, description) when is_binary(description) do
    ["# HELP ", format_names(names), " ", description, "\n"]
  end

  @spec format_type(list(atom), binary) :: iolist
  def format_type(names, type_name) when is_binary(type_name) do
    ["# TYPE ", format_names(names), " ", type_name, "\n"]
  end

  @spec format_description(map | nil, :exometer.name) :: binary
  def format_description(prometheus_options, exometer_name)
  def format_description(%{description: description}, _) when is_binary(description), do: description
  def format_description(_, exometer_name), do: inspect(exometer_name)

  @spec format_label(binary | atom | {atom, any}) :: binary | list(binary)
  def format_label(label) when is_binary(label), do: label
  def format_label(label) when is_atom(label), do: to_string(label)
  def format_label({key, value} = label) when is_tuple(label), do: [to_string(key), "=\"", to_string(value), "\""]

  @spec format_labels(labels) :: list
  def format_labels([]), do: []
  def format_labels(labels) do
    label_strings = Enum.map(labels, &format_label/1)
    Enum.intersperse(label_strings, ",")
  end

  @spec format_metric(name, labels) :: list(binary)
  def format_metric(name, []), do: format_names(name)
  def format_metric(name, labels), do: [format_names(name), "{", format_labels(labels), "}"]

  @spec format_data(name, Keyword.t, term) :: list(binary)
  def format_data(name, labels, value) do
    [format_metric(name, labels), " ", format_value(value), "\n"]
  end

  # Convert internal type to Prometheus type name
  @spec format_type_name(map | nil, atom) :: binary
  def format_type_name(prometheus_options, exometer_type)
  def format_type_name(%{type: type}, _exometer_type), do: format_type_name(type)
  def format_type_name(_, exometer_type),              do: format_type_name(exometer_type)

  # Convert Exometer type to Prometheus type name
  @spec format_type_name(:exometer.type) :: binary
  def format_type_name(exometer_type)
  def format_type_name(:prometheus_counter), do: "counter"
  def format_type_name(:prometheus_gauge), do: "gauge"
  def format_type_name(:prometheus_histogram), do: "histogram"
  def format_type_name(:counter), do: "counter"
  def format_type_name(:gauge), do: "gauge"
  def format_type_name(:meter), do: "counter"
  def format_type_name(:spiral), do: "gauge"
  def format_type_name(:histogram), do: "summary"
  def format_type_name(_), do: "untyped"

  # Format scrape duration metric
  @spec format_scrape_duration(map, :erlang.timestamp) :: iolist
  def format_scrape_duration(config, start_time) do
    namespace = config[:namespace] || []
    duration = :timer.now_diff(:os.timestamp(), start_time) / 1_000_000
    format_data(namespace ++ [:scrape_duration_seconds], [], duration / 1)
  end

  # Format up metric
  @spec format_namespace_up(map) :: iolist
  def format_namespace_up(%{namespace: namespace}) when is_list(namespace) do
    format_data(namespace ++ ["up"], [], 1)
  end
  def format_namespace_up(_), do: []

  # Format metric header
  @spec format_header(name, Keyword.t, map, :exometer.name, :exometer.type) :: iolist
  def format_header(name, labels, prometheus_options, exometer_name, exometer_type)
  def format_header(name, [], prometheus_options, exometer_name, exometer_type) do
    [
      format_help(name, format_description(prometheus_options, exometer_name)),
      format_type(name, format_type_name(prometheus_options, exometer_type)),
    ]
  end
  def format_header(_, _, _, _, _), do: []

end
