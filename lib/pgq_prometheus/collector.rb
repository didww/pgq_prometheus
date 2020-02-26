require_relative 'config'
require 'prometheus_exporter/server'

module PgqPrometheus
  class Collector < PrometheusExporter::Server::TypeCollector

    def initialize
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

      metrics = {}

      @data.map do |obj|
        labels = {}
        # labels are passed by PgqPrometheus::Processor
        labels.merge!(obj['metric_labels']) if obj['metric_labels']
        # custom_labels are passed by PrometheusExporter::Client
        labels.merge!(obj['custom_labels']) if obj['custom_labels']

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
      @data << obj
    end
  end
end
