# This file is loaded by the autoloader, and it does not find the data function support unless required relative
#
require 'json'
require_relative 'hiera_interpolate'

module Puppet::DataProviders
  class JsonDataProviderFactory < Puppet::Plugins::DataProviders::FileBasedDataProviderFactory
    def create(name, paths)
      JsonDataProvider.new(name, paths)
    end

    def path_extension
      '.json'
    end
  end

  class JsonDataProvider < Puppet::Plugins::DataProviders::PathBasedDataProvider
    include HieraInterpolate

    def initialize_data(path, lookup_invocation)
      JSON.parse(File.read(path))
    rescue JSON::ParserError => ex
      # Filename not included in message, so we add it here.
      raise Puppet::DataBinding::LookupError, "Unable to parse (#{path}): #{ex.message}"
    end

    def post_process(value, lookup_invocation)
      interpolate(value, lookup_invocation, true)
    end
  end
end
