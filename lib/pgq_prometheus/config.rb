# frozen_string_literal: true

require 'prometheus_exporter/metric'

module PgqPrometheus
  module Config
    ALLOWED_FROM = [:queue, :consumer, nil]

    class << self
      attr_accessor :type, :_metrics
    end

    # @param metric_class [Class<Object>, String]
    # @param name [Symbol, String]
    # @param help [String]
    # @param options [String] keys :from, :column, :apply
    # @raise ArgumentError
    def self.register_metric(metric_class, name, help, options = {})
      raise ArgumentError, 'metric_class must be present' if metric_class.nil?

      name = name.to_sym
      raise ArgumentError, "metric #{name} already defined - unregister it" if _metrics.key?(name)

      from = options[:from]
      column = options[:column] || name
      apply = options[:apply]

      unless ALLOWED_FROM.include?(from)
        raise ArgumentError, "invalid :from, allowed: #{ALLOWED_FROM.map(&:inspect).join(', ')}"
      end

      if apply.nil?
        case from
        when :queue
          apply = proc { |queue_info| queue_info[column.to_sym] }
        when :consumer
          apply = proc { |consumer_info, _queue_info| consumer_info[column.to_sym] }
        else
          raise ArgumentError, 'require :apply block for metric without :from'
        end
      end

      _metrics[name] = {
          metric_class: metric_class,
          help: help,
          metric_args: options[:metric_args] || [],
          labels: options[:labels] || {},
          from: from,
          apply: apply
      }
    end

    # @param name [Symbol, String]
    def self.unregister_metric(name)
      _metrics.delete(name.to_sym)
    end

    # @param name [Symbol, String]
    # @param help [String]
    # @param options [String] keys :from, :column, :apply
    # @raise ArgumentError
    def self.register_counter(name, help, options = {})
      register_metric 'PrometheusExporter::Metric::Counter', name, help, options
    end

    # @param name [Symbol, String]
    # @param help [String]
    # @param options [String] keys :from, :column, :apply
    # @raise ArgumentError
    def self.register_gauge(name, help, options = {})
      register_metric 'PrometheusExporter::Metric::Gauge', name, help, options
    end

    # @param name [Symbol, String]
    # @param help [String]
    # @param options [String] keys :from, :column, :apply
    # @raise ArgumentError
    def self.register_histogram(name, help, options = {})
      buckets = options.delete(:buckets)
      options[:metric_args] ||= [buckets: buckets]
      register_metric 'PrometheusExporter::Metric::Histogram', name, help, options
    end

    # @param name [Symbol, String]
    # @param help [String]
    # @param options [String] keys :from, :column, :apply
    # @raise ArgumentError
    def self.register_summary(name, help, options = {})
      buckets = options.delete(:quantiles)
      options[:metric_args] ||= [quantiles: buckets]
      register_metric 'PrometheusExporter::Metric::Summary', name, help, options
    end

    self.type = 'pgq'
    self._metrics = {}

    register_gauge :new_events, 'new events qty for queue',
                   from: :queue, column: :ev_new

    register_gauge :events_per_second, 'new events qty for queue',
                   from: :queue,
                   apply: proc { |queue_info| queue_info[:ev_per_sec] || 0.0 }

    register_gauge :pending_events, 'pending events qty for queue and consumer',
                   from: :consumer

  end
end
