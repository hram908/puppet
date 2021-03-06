#
# A helper module to look a capability up from PuppetDB
#
# @todo lutter 2015-03-10: determine whether this should be based on
# Puppet::Pops::Evaluator::Collectors, or at least use
# Puppet::Util::Puppetdb::Http

require 'net/http'
require 'cgi'
require 'json'

# @api private
module Puppet::Resource::CapabilityFinder

  # Looks the capability resource with the given +type+ and +title+ up from
  # PuppetDB.
  def self.find(environment, cap)
    unless Puppet::Util.const_defined?('Puppetdb')
      raise Puppet::DevError, 'PuppetDB is not available'
    end

    query = ['and', ['=', 'type', cap.type.capitalize],
      ['=', 'title', cap.title.to_s],
      ['=', 'tag', "producer:#{environment}"]].to_json

    Puppet.notice "Capability lookup #{cap}]: #{query}"

    http = Puppet::Util.const_get('Puppetdb').const_get('Http')
    response = http.action("/pdb/query/v4/resources?query=#{CGI.escape(query)}") do |conn, uri|
      conn.get(uri, { 'Accept' => 'application/json'})
    end
    json = response.body

    # The format of the response body is documented at
    #   http://docs.puppetlabs.com/puppetdb/3.0/api/query/v4/resources.html#response-format
    # In a nutshell, we expect to get an array of resources back. If the
    # array is empty, the lookup failed and we return +nil+, if it
    # contains exactly one, we turn that resource back into a Puppet
    # ::Resource. If the array contains more than one entry, we have a
    # bug in the overall system, as we allowed multiple capabilities with
    # the same type and title to be produced in this environment.
    begin
      data = JSON.parse(json)
    rescue JSON::JSONError => e
      raise Puppet::DevError,
      "Invalid JSON from PuppetDB when looking up #{cap}\n#{e}\nRaw JSON was:\n#{json}"
    end
    unless data.is_a?(Array)
      raise Puppet::DevError,
      "Unexpected response from PuppetDB when looking up #{cap}: " +
        "expected an Array but got #{data.inspect}"
    end
    if data.size > 1
      raise Puppet::DevError,
      "Unexpected response from PuppetDB when looking up #{cap}:\n" +
        "expected exactly one resource but got #{data.size};\n" +
        "returned data is:\n#{data.inspect}"
    end

    unless data.empty?
      resource_hash = data.first
      resource = Puppet::Resource.new(resource_hash['type'],
                                      resource_hash['title'])
      real_type = Puppet::Type.type(resource.type)
      if real_type.nil?
        fail Puppet::ParseError,
          "Could not find resource type #{resource.type} returned from PuppetDB"
      end
      real_type.parameters.each do |param|
        param = param.to_s
        next if param == 'name'
        if value = resource_hash['parameters'][param]
          resource[param] = value
        else
          Puppet.debug "No capability value for #{resource}->#{param}"
        end
      end
      return resource
    end
  end
end
