class Carton::Socket < IO
  property wrapped : IO

  def initialize(@wrapped : IO)
  end

  def client_authentication=(value : Authentication)
    @clientAuthentication = value
  end

  def client_authentication
    @clientAuthentication
  end

  def authentication=(value : Authentication)
    @authentication = value
  end

  def authentication
    @authentication || Authentication::None
  end

  def on_auth=(value : Proc(String, String?, Carton::Verify))
    @onAuth = value
  end

  def on_auth
    @onAuth
  end

  def destination_address=(value : DestinationAddress)
    @destinationAddress = value
  end

  def destination_address
    @destinationAddress
  end

  def request_payload=(value : HTTP::Request)
    @requestPayload = value
  end

  def request_payload
    @requestPayload
  end

  def tunnel_mode=(value : Bool)
    @tunnelMode = value
  end

  def tunnel_mode
    @tunnelMode
  end

  def traffic_type=(value : Traffic)
    @trafficType = value
  end

  def traffic_type
    @trafficType
  end

  def extract_size=(value : Int32)
    @extractSize = value
  end

  def extract_size
    @extractSize || 0_i32
  end

  def stats
    Stats.from_socket self
  end

  def read_timeout=(value : Int | Float | Time::Span | Nil)
    _wrapped = wrapped

    _wrapped.read_timeout = value if value if _wrapped.responds_to? :read_timeout=
  end

  def write_timeout=(value : Int | Float | Time::Span | Nil)
    _wrapped = wrapped

    _wrapped.write_timeout = value if value if _wrapped.responds_to? :write_timeout=
  end

  def read_timeout
    _wrapped = wrapped
    _wrapped.read_timeout if _wrapped.responds_to? :read_timeout
  end

  def write_timeout
    _wrapped = wrapped
    _wrapped.write_timeout if _wrapped.responds_to? :write_timeout
  end

  def local_address : ::Socket::Address?
    _wrapped = wrapped
    _wrapped.responds_to?(:local_address) ? _wrapped.local_address : nil
  end

  def remote_address : ::Socket::Address?
    _wrapped = wrapped
    _wrapped.responds_to?(:remote_address) ? _wrapped.remote_address : nil
  end

  def read(slice : Bytes) : Int32
    wrapped.read slice
  end

  def write(slice : Bytes) : Nil
    wrapped.write slice
  end

  def <<(value : String) : IO
    wrapped << value

    self
  end

  def flush
    wrapped.flush
  end

  def close
    wrapped.close
  end

  def closed?
    wrapped.closed?
  end

  def auth_challenge(request : HTTP::Request) : Verify
    return Verify::Pass if authentication.none?

    case authentication
    when .basic?
      auth = request.headers["Proxy-Authorization"]?
      return Verify::Deny unless auth

      type_payload = auth.rpartition " "
      auth_type, delimiter, payload = type_payload

      _auth_type = Authentication.parse? auth_type
      return Verify::Deny unless _auth_type
      return Verify::Deny unless _auth_type.basic?

      self.client_authentication = Authentication::Basic
      base64 = Base64.decode_string payload rescue nil
      return Verify::Deny unless base64

      username_password = base64.rpartition ":"
      user_name, delimiter, password = username_password

      call = on_auth.try &.call user_name, password
    end

    call || Verify::Pass
  end

  def reject_establish!
    write Carton.deny_payload.to_slice
    flush
  end

  def set_connect_information!(request : HTTP::Request)
    host = request.connect_host || request.header_host
    raise MismatchFlag.new unless host

    port = request.regular_port
    port = traffic_type.try &.to_i unless port
    raise UnknownFlag.new unless port

    self.destination_address = DestinationAddress.new host, port
    self.request_payload = request
    self.tunnel_mode = request.connect?
    self.traffic_type = Traffic::HTTP unless tunnel_mode
  end

  def handshake! : Verify
    request = HTTP::Request.from_io self
    raise BadRequest.new unless request.is_a? HTTP::Request

    set_connect_information! request
    auth_challenge request
  end

  def staple_request(socket : IO) : IO
    return socket unless request = request_payload

    memory = IO::Memory.new
    request.to_io memory
    memory.rewind

    stream = Extract.new socket, memory
    Socket.staple_socket stream, socket
  end

  def self.staple_socket(stream, socket : IO) : IO::Stapled?
    IO::Stapled.new stream, socket, sync_close: true
  end

  def self.extract(socket : IO)
    part = Extract.part socket
    stream = Extract.new socket, part
    staple = staple_socket stream, socket

    Tuple.new part.dup, staple
  end

  private def update_traffic_wrapped!
    return self.wrapped = staple_request wrapped unless tunnel_mode

    _extract, _wrapped = Socket.extract wrapped
    request = HTTP::Request.from_io _extract

    _http_payload = request.is_a? HTTP::Request
    self.wrapped = _wrapped
    self.traffic_type = _http_payload ? Traffic::HTTP : Traffic::HTTPS
    self.extract_size = _extract.size
  end

  def establish!
    if tunnel_mode
      write Carton.establish_payload.to_slice
      flush
    end

    update_traffic_wrapped!
  end
end
