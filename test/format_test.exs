defmodule PrometheusExometer.FormatTest do
  use ExUnit.Case, async: true

  import PrometheusExometer.FormatText

  test "format_value" do
    assert format_value(:foo) == "foo"
    assert format_value("foo") == "foo"
  end

  test "format_value float" do
    assert format_value(0.0) == "0.0"
    assert format_value(1.0) == "1.0"
    assert format_value(0.0000001) == "0.0"
    assert format_value(0.1111111) == "0.1111"
    assert format_value(0.1111111) == "0.1111"
    assert format_value(1) == "1"
  end

  test "format_names" do
    assert format_names([]) == []
    assert format_names([:foo]) == ["foo"]
    assert format_names([:foo, :bar]) == ["foo", "_", "bar"]
    assert format_names(["foo"]) == ["foo"]
    assert format_names(["foo", "bar"]) == ["foo", "_", "bar"]
  end

  test "format_help" do
    assert bin(format_help([:foo], "The description")) == "# HELP foo The description\n"
    assert bin(format_help([:foo, :bar], "The description")) == "# HELP foo_bar The description\n"
  end

  test "format_type" do
    assert bin(format_type([:foo], "The description")) == "# TYPE foo The description\n"
    assert bin(format_type([:foo, :bar], "The description")) == "# TYPE foo_bar The description\n"
  end

  test "format_description" do
    assert format_description(%{description: "the description"}, [:foo, :bar]) == "the description"
    assert format_description(nil, [:foo, :bar]) == "[:foo, :bar]"
  end

  test "format_label" do
    assert format_label("foo") == "foo"
    assert format_label(:foo) == "foo"
    assert bin(format_label({:foo, :bar})) == ~s|foo="bar"|
  end

  test "format_labels" do
    assert format_labels([]) == []
    assert format_labels(["foo"]) == ["foo"]
    assert bin(format_labels([{"foo", "bar"}, "this=\"that\""])) == ~s|foo="bar",this="that"|
  end

  test "format_metric" do
    assert bin(format_metric([:foo, :bar], [])) == "foo_bar"
    assert bin(format_metric([:foo, :bar], [{:biz, :baz}])) == "foo_bar{biz=\"baz\"}"
  end

  test "format_data" do
    assert bin(format_data([:foo, :bar], [{:biz, :baz}], 1)) == "foo_bar{biz=\"baz\"} 1\n"
  end

  test "format_type_name" do
    assert format_type_name(nil, :histogram) == "summary"
    assert format_type_name(%{type: :spiral}, :whatever) == "gauge"
  end

  test "format_scrape_duration" do
    start_time = :os.timestamp() 
    assert bin(format_scrape_duration(%{namespace: [:foo, :bar]}, start_time)) == "foo_bar_scrape_duration_seconds 0.0\n"
  end

  test "format_namespace_up" do
    assert bin(format_namespace_up(%{namespace: [:foo, :bar]})) == "foo_bar_up 1\n"
  end

  test "format_header" do
    assert bin(format_header([:foo, :bar], [], %{description: "the bazzer"}, [:baz], :gauge)) == "# HELP foo_bar the bazzer\n# TYPE foo_bar gauge\n"
    assert format_header([:foo, :bar], [:"biz=\"baz\""], %{description: "the bazzer"}, [:baz], :gauge) == []
  end

  # Utility
  defp bin(value), do: IO.iodata_to_binary(value)

end
