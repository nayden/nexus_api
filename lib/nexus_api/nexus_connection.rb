require 'base64'
require 'rest-client'

module NexusAPI
  class NexusConnection
    VALID_RESPONSE_CODES = [200, 204].freeze
    
    attr_accessor :continuation_token

    def initialize(username:, password:, hostname:)
      @username = username
      @password = password
      @hostname = hostname
    end

    def get_response(endpoint:, paginate: false, headers: {'Content-Type' => 'application/json'})
      response = send_get(endpoint, paginate, headers)
      response.nil? ? Hash.new : jsonize(response)
    end

    def get(endpoint:, paginate: false, headers: {'Content-Type' => 'application/json'})
      valid?(send_get(endpoint, paginate, headers))
    end

    def post(endpoint:, parameters: '', headers: {'Content-Type' => 'application/json'})
      response = send_request(
        :post, 
        endpoint,
        parameters: parameters,
        headers: headers
      )
      valid?(response)
    end

    def put(endpoint:, parameters: '', headers: {'Content-Type' => 'application/json'})
      response = send_request(
        :put,
        endpoint,
        parameters: parameters,
        headers: headers
      )
      valid?(response)
    end

    def delete(endpoint:, headers: {'Content-Type' => 'application/json'})
      response = send_request(
        :delete,
        endpoint,
        headers: headers
      )
      valid?(response)
    end

    def head(asset_url:)
      catch_connection_error do
        RestClient.head(asset_url)
      end
    end

    def content_length(asset_url:)
      response = head(asset_url: asset_url)
      return -1 unless response.respond_to?(:headers)
      response.headers[:content_length]
    end

    def download(url:)
      catch_connection_error do
        RestClient.get(url, authorization_header)
      end
    end

    def paginate?
      !@continuation_token.nil?
    end


    private

    def valid?(response)
      return false if response.nil?
      VALID_RESPONSE_CODES.include?(response.code) ? true : false
    end

    def handle(error)
      puts "ERROR: Request failed"
      puts error.description if error.is_a?(RestClient::Response)
    end

    def catch_connection_error
      begin
        yield
      rescue SocketError => error
        return handle(error)
      rescue RestClient::Unauthorized => error
        return handle(error)
      rescue RestClient::ExceptionWithResponse => error
        return handle(error.response)
      end
    end

    def authorization_header
      { :Authorization => 'Basic ' + Base64.strict_encode64( "#{@username}:#{@password}" ) }
    end

    def send_request(connection_method, endpoint, parameters: '', headers: {})
      catch_connection_error do
        RestClient::Request.execute(
          method: connection_method,
          url:    "https://#{@hostname}/service/rest/v1/#{endpoint}",
          payload: parameters,
          headers: authorization_header.merge(headers)
        )
      end
    end

    def send_get(endpoint, paginate, headers)
      # paginate answers is the user requesting pagination, paginate? answers does a continuation token exist
      # if an empty continuation token is included in the request we'll get an ArrayIndexOutOfBoundsException
      endpoint += "&continuationToken=#{@continuation_token}" if paginate && paginate?
      response = send_request(
        :get,
        endpoint,
        headers: headers
      )
    end

    # That's right, nexus has inconsistent null values for its api
    def continuation_token_for(json)
      return nil if json['continuationToken'].nil?
      return nil if json['continuationToken'] == 'nil'
      json['continuationToken']
    end

    def jsonize(response)
      json = JSON.parse(response.body)
      if json.class == Hash
        @continuation_token = continuation_token_for(json)
        json = json["items"] if json["items"]
      end
      json
    rescue JSON::ParserError
      response.body
    end
  end
end
