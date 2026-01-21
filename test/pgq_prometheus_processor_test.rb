# frozen_string_literal: true

require 'test_helper'

class PgqPrometheusProcessorTest < Minitest::Test
  def teardown
    PgqPrometheus::Processor.sql_caller = nil
  end

  def test_that_it_has_a_version_number
    refute_nil ::PgqPrometheus::VERSION
  end

  def test_processor_raise_when_sql_caller_nil
    old_threads_count = running_thread_count

    assert_raises(ArgumentError, 'PgqPrometheus::Processor.sql_caller must be defined') do
      PgqPrometheus::Processor.start
    end

    assert_equal old_threads_count, running_thread_count
    refute PgqPrometheus::Processor.running?
  end

  def test_processor_start_not_raise
    sql_caller = create_sql_caller_mock([], [], with_connection: true, release_connection: true)
    sql_caller.expect(:nil?, false)
    PgqPrometheus::Processor.sql_caller = sql_caller
    old_threads_count = running_thread_count

    refute PgqPrometheus::Processor.running?

    assert PgqPrometheus::Processor.start
    assert_equal old_threads_count + 1, running_thread_count
    assert PgqPrometheus::Processor.running?
    sleep 2 # give time for process thread to execute one iteration

    assert_nil PgqPrometheus::Processor.stop
    sleep 2 # give time for process thread to shutdown
    assert_equal old_threads_count, running_thread_count
    refute PgqPrometheus::Processor.running?

    assert sql_caller.verify
  end

  def test_processor_run_once_ar
    sql_caller = create_sql_caller_mock(
      [queue_name: 'q', ev_new: 5, ev_per_sec: 1.33],
      [consumer_name: 'c', pending_events: 18],
      with_connection: true
    )
    PgqPrometheus::Processor.sql_caller = sql_caller

    client = create_prometheus_client_mock(
      { type: 'pgq', new_events: 5, metric_labels: { queue: 'q' } },
      { type: 'pgq', events_per_second: 1.33, metric_labels: { queue: 'q' } },
      { type: 'pgq', pending_events: 18, metric_labels: { queue: 'q', consumer: 'c' } }
    )
    processor = PgqPrometheus::Processor.new
    PgqPrometheus::Processor.run_once(process_collector: processor, client:)

    assert sql_caller.verify
    assert client.verify
  end

  def test_processor_run_once_rails
    # Create mock Rails.application.reloader.wrap
    reloader = Minitest::Mock.new
    reloader.expect(:wrap, nil) do |*args, &block|
      assert_empty args
      refute_nil block
      block.call
      true
    end
    application = Minitest::Mock.new
    application.expect(:reloader, reloader)
    rails_mock = Minitest::Mock.new
    2.times { rails_mock.expect(:application, application) }
    Object.const_set(:Rails, rails_mock)

    sql_caller = create_sql_caller_mock(
      [queue_name: 'q', ev_new: 5, ev_per_sec: 1.33],
      [consumer_name: 'c', pending_events: 18],
      with_connection: false
    )
    PgqPrometheus::Processor.sql_caller = sql_caller

    client = create_prometheus_client_mock(
      { type: 'pgq', new_events: 5, metric_labels: { queue: 'q' } },
      { type: 'pgq', events_per_second: 1.33, metric_labels: { queue: 'q' } },
      { type: 'pgq', pending_events: 18, metric_labels: { queue: 'q', consumer: 'c' } }
    )
    processor = PgqPrometheus::Processor.new
    PgqPrometheus::Processor.run_once(process_collector: processor, client:)

    assert rails_mock.verify
    assert application.verify
    assert reloader.verify
    assert sql_caller.verify
    assert client.verify
  ensure
    Object.send(:remove_const, :Rails) if defined?(Rails)
  end

  def test_processor_collect
    sql_caller = create_sql_caller_mock(
        [queue_name: 'q', ev_new: 5, ev_per_sec: 1.33],
        [consumer_name: 'c', pending_events: 18],
        with_connection: false
    )
    PgqPrometheus::Processor.sql_caller = sql_caller

    processor = PgqPrometheus::Processor.new
    metrics = processor.collect

    assert_includes metrics, { type: 'pgq', new_events: 5, metric_labels: { queue: 'q' } }
    assert_includes metrics, { type: 'pgq', events_per_second: 1.33, metric_labels: { queue: 'q' } }
    assert_includes metrics, { type: 'pgq', pending_events: 18, metric_labels: { queue: 'q', consumer: 'c' } }
    assert_equal 3, metrics.size

    assert sql_caller.verify
  end

  def test_processor_collect_with_custom_labels
    # create constant Rails

    sql_caller = create_sql_caller_mock(
        [queue_name: 'q', ev_new: 5, ev_per_sec: 7.33],
        [consumer_name: 'c', pending_events: 12],
        with_connection: false
    )
    PgqPrometheus::Processor.sql_caller = sql_caller

    processor = PgqPrometheus::Processor.new(foo: 'bar')
    metrics = processor.collect

    assert_includes metrics, { type: 'pgq', new_events: 5, metric_labels: { queue: 'q', foo: 'bar' } }
    assert_includes metrics, { type: 'pgq', events_per_second: 7.33, metric_labels: { queue: 'q', foo: 'bar' } }
    assert_includes metrics, { type: 'pgq', pending_events: 12, metric_labels: { queue: 'q', consumer: 'c', foo: 'bar' } }
    assert_equal 3, metrics.size

    assert sql_caller.verify
  end

  def test_processor_collect_with_custom_metric
    sql_caller = create_sql_caller_mock(
        [queue_name: 'q', ev_new: 6, ev_per_sec: 1.33],
        [consumer_name: 'c', pending_events: 12],
        with_connection: false
    )
    PgqPrometheus::Processor.sql_caller = sql_caller
    PgqPrometheus.configure do |config|
      config.register_counter :custom_q, 'custom test q', from: :queue, apply: proc { |q| q[:ev_per_sec].round }
      config.register_summary :custom_c, 'custom test c', from: :consumer, apply: proc { |c| c[:pending_events] * 10 }
      config.register_gauge :custom, 'custom test', labels: { bar: 'baz' }, apply: proc { 1234 }
    end

    processor = PgqPrometheus::Processor.new
    metrics = processor.collect

    assert_includes metrics, { type: 'pgq', new_events: 6, metric_labels: { queue: 'q' } }
    assert_includes metrics, { type: 'pgq', events_per_second: 1.33, metric_labels: { queue: 'q' } }
    assert_includes metrics, { type: 'pgq', pending_events: 12, metric_labels: { queue: 'q', consumer: 'c' } }
    assert_includes metrics, { type: 'pgq', custom_q: 1, metric_labels: { queue: 'q' } }
    assert_includes metrics, { type: 'pgq', custom_c: 120, metric_labels: { queue: 'q', consumer: 'c' } }
    assert_includes metrics, { type: 'pgq', custom: 1234, metric_labels: { bar: 'baz' } }
    assert_equal 6, metrics.size

    assert sql_caller.verify
  ensure
    PgqPrometheus::Config.unregister_metric :custom_q
    PgqPrometheus::Config.unregister_metric :custom_c
    PgqPrometheus::Config.unregister_metric :custom
  end

  private

  def running_thread_count
    Thread.list.select { |thread| thread.status == 'run' }.count
  end

  def create_prometheus_client_mock(*expected_events)
    mock = Minitest::Mock.new
    expected_events.each do |expected_event|
      mock.expect(:send_json, nil) do |*args, &block|
        assert_equal 1, args.size
        assert_equal expected_event, args[0]
        assert_nil block
      end
    end
    mock
  end

  # @param queues [Array, nil]
  # @param consumers [Array, nil]
  def create_sql_caller_mock(queues, consumers, with_connection: false, release_connection: false)
    mock = Minitest::Mock.new

    if release_connection
      mock.expect(:release_connection, nil) do |*args, &block|
        assert_empty args
        assert_nil block
        assert_nil @inside_with_connection
      end
    end

    if with_connection
      mock.expect(:with_connection, nil) do |*args, &block|
        assert_empty args
        refute_nil block

        @inside_with_connection = true
        begin
          block.call
          true
        ensure
          @inside_with_connection = nil
        end
      end
    end

    mock.expect(:queue_info, queues) do |*args, &block|
      assert_empty args
      assert_nil block
      assert(@inside_with_connection) if with_connection
      true
    end

    queues.each do |queue|
      mock.expect(:consumer_info, consumers) do |*args, &block|
        assert_equal [queue[:queue_name]], args
        assert_nil block
        assert(@inside_with_connection) if with_connection
        true
      end
    end

    mock
  end
end
