struct Orange::Stats
  def initialize
  end

  def client_authentication=(value : Authentication?)
    @clientAuthentication = value
  end

  def remote_address=(value : RemoteAddress?)
    @remoteAddress = value
  end

  def request_payload=(value : HTTP::Request?)
    @requestPayload = value
  end

  def request_payload
    @requestPayload
  end

  def traffic_type=(value : Traffic?)
    @trafficType = value
  end

  def traffic_type
    @trafficType
  end

  def tunnel_mode=(value : Bool?)
    @tunnelMode = value
  end

  def tunnel_mode
    @tunnelMode
  end

  def self.from_socket(socket : Socket)
    stats = new

    stats.client_authentication = socket.client_authentication
    stats.remote_address = socket.remote_address
    stats.request_payload = socket.request_payload
    stats.tunnel_mode = socket.tunnel_mode
    stats.traffic_type = socket.traffic_type

    stats
  end
end