# frozen_string_literal: true

require 'test_helper'

class PgqPrometheusCollectorTest < Minitest::Test

  def test_empty_metrics
    collector = PgqPrometheus::Collector.new
    assert_equal [], collector.metrics
  end

  def test_filled_with_valid_metrics
    PgqPrometheus.configure do |config|
      config.register_gauge :custom, 'custom test', apply: proc { 1234 }
    end
    collector = PgqPrometheus::Collector.new

    collector.collect(
        'type' => PgqPrometheus::Config.type,
        'new_events' => 5,
        'metric_labels' => { 'queue' => 'q' }
    )
    collector.collect(
        'type' => PgqPrometheus::Config.type,
        'pending_events' => 5,
        'metric_labels' => { 'queue' => 'q', 'consumer' => 'c' },
        'custom_labels' => { 'foo' => 'bar' }
    )
    collector.collect(
        'type' => PgqPrometheus::Config.type,
        'custom' => 1
    )
    collector.collect(
        'type' => PgqPrometheus::Config.type,
        'custom' => 2,
        'metric_labels' => { 'bar' => 'baz' },
        'custom_labels' => { 'baz' => 'boo' }
    )

    actual_metrics = collector.metrics.map { |m| m.metric_text.split("\n") }

    expected_metrics = [
        [%Q{pgq_new_events{queue="q"} 5}],
        [%Q{pgq_custom{bar="baz",baz="boo"} 2}, %Q{pgq_custom 1}],
        [%Q{pgq_pending_events{queue="q",consumer="c",foo="bar"} 5}]
    ]

    assert_match_array_of_arrays expected_metrics, actual_metrics

  ensure
    PgqPrometheus::Config.unregister_metric :custom
  end

  private

  def assert_match_array_of_arrays(exp, act, msg = nil)
    sorted_exp = exp.map { |item| item.sort }.sort
    sorted_act = act.map { |item| item.sort }.sort
    assert_equal sorted_exp, sorted_act, msg
  end
end
