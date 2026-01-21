# frozen_string_literal: true

require_relative 'config'
require 'prometheus_exporter/server'

module PgqPrometheus
  class Collector < PrometheusExporter::Server::TypeCollector
    MAX_METRIC_AGE = 30

    def initialize
      super
      @data = []
      @observers = {}

      Config._metrics.each do |name, opts|
        metric_class = Kernel.const_get opts[:metric_class].to_s
        help = opts[:help]
        metric_args = opts[:metric_args]
        @observers[name] = metric_class.new("#{type}_#{name}", help, *metric_args)
      end
    end

    def type
      Config.type
    end

    def metrics
      return [] if @data.length == 0

      @observers.each_value(&:reset!)
      metrics = {}

      @data.map do |obj|
        labels = gather_labels(obj)

        @observers.each do |name, observer|
          name = name.to_s
          value = obj[name]
          if value
            observer.observe(value, labels)
            metrics[name] = observer
          end
        end
      end

      metrics.values
    end

    def collect(obj)
      now = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)

      obj['created_at'] = now
      @data.delete_if { |m| m['created_at'] + MAX_METRIC_AGE < now }
      @data << obj
    end

    private

    def gather_labels(obj)
      labels = {}
      # labels are passed by PgqPrometheus::Processor
      labels.merge!(obj['metric_labels']) if obj['metric_labels']
      # custom_labels are passed by PrometheusExporter::Client
      labels.merge!(obj['custom_labels']) if obj['custom_labels']
      labels.to_h { |key, value| [key.to_s, value.to_s] }
    end
  end
end
