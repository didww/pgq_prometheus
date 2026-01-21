# frozen_string_literal: true

require 'prometheus_exporter/client'

module PgqPrometheus
  class Processor
    class << self
      attr_accessor :sql_caller,
                    :logger,
                    :on_error,
                    :before_collect,
                    :after_collect

      def start(client: nil, frequency: 30, labels: nil)
        raise ArgumentError, "#{name}.sql_caller must be defined" if sql_caller.nil?

        stop

        client ||= PrometheusExporter::Client.default
        metric_labels = labels&.dup || {}
        process_collector = new(metric_labels)

        @thread = Thread.new do
          wrap_thread_loop(name) do
            sql_caller.release_connection
            logger&.info { "Start #{name}" }
            while true
              run_once(process_collector:, client:)
              sleep frequency
            end
          end
        end

        true
      end

      def run_once(process_collector:, client:)
        wrap_execution do
          before_collect&.call
          metrics = process_collector.collect
          metrics.each do |metric|
            client.send_json metric
          end
          after_collect&.call
        rescue StandardError => e
          warn "#{self.class} Failed To Collect Stats #{e.class} #{e.message}"
          logger&.error { "#{e.class} #{e.message} #{e.backtrace.join("\n")}" }
          on_error&.call(e)
        end
      end

      def stop
        @thread&.kill
        @thread = nil
      end

      def running?
        defined?(@thread) && @thread
      end

      def wrap_thread_loop(*tags, &block)
        return yield if logger.nil? || !logger.respond_to?(:tagged)

        logger.tagged(*tags, &block)
      end

      def wrap_execution(&)
        if defined?(Rails) && Rails.application
          # When run inside Rails, this is a correct way to wrap app code
          Rails.application.reloader.wrap(&)
        else
          # When using just ActiveRecord, with_connection will be enough
          sql_caller.with_connection(&)
        end
      end
    end

    def initialize(labels = {})
      @metric_labels = labels || {}
    end

    def collect
      metrics = []
      sql_caller.queue_info.each do |queue_info|
        queue = queue_info[:queue_name]

        queue_metric_opts.each do |name, opts|
          value = opts[:apply].call(queue_info)
          labels = opts[:labels].merge(queue: queue)
          metrics << format_metric(name, value, labels)
        end

        sql_caller.consumer_info(queue).each do |consumer_info|
          consumer = consumer_info[:consumer_name]

          consumer_metric_opts.each do |name, opts|
            value = opts[:apply].call(consumer_info, queue_info)
            labels = opts[:labels].merge(queue: queue, consumer: consumer)
            metrics << format_metric(name, value, labels)
          end
        end
      end

      custom_metric_opts.each do |name, opts|
        value, labels = opts[:apply].call
        labels = (labels || {}).merge(opts[:labels])
        metrics << format_metric(name, value, labels)
      end

      metrics
    end

    private

    [:sql_caller, :logger].each do |meth|
      define_method(meth) { |*args, &block| self.class.public_send(meth, *args, &block) }
    end

    def queue_metric_opts
      Config._metrics.select { |_, opts| opts[:from] == :queue }
    end

    def consumer_metric_opts
      Config._metrics.select { |_, opts| opts[:from] == :consumer }
    end

    def custom_metric_opts
      Config._metrics.select { |_, opts| opts[:from].nil? }
    end

    def format_metric(name, value, labels)
      {
        type: Config.type,
        name => value,
        metric_labels: labels.merge(@metric_labels)
      }
    end
  end
end
