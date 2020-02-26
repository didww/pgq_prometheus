# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'pgq_prometheus'
require 'pgq_prometheus/processor'
require 'pgq_prometheus/collector'

require 'minitest/autorun'
