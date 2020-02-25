# frozen_string_literal: true

require 'prometheus_exporter'
require 'pgq_prometheus/version'
require 'pgq_prometheus/config'
require 'pgq_prometheus/processor'

module PgqPrometheus
  def self.configure
    yield Config
  end
end
