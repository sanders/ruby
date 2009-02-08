require 'socket.so'

class Addrinfo
  # creates an Addrinfo object from the arguments.
  #
  # The arguments are interpreted as similar to self.
  #
  #   Addrinfo.tcp("0.0.0.0", 4649).family_addrinfo("www.ruby-lang.org", 80)
  #   #=> #<Addrinfo: 221.186.184.68:80 TCP (www.ruby-lang.org:80)>
  #
  #   Addrinfo.unix("/tmp/sock").family_addrinfo("/tmp/sock2")
  #   #=> #<Addrinfo: /tmp/sock2 SOCK_STREAM>
  #
  def family_addrinfo(*args)
    if args.empty?
      raise ArgumentError, "no address specified"
    elsif Addrinfo === args.first
      raise ArgumentError, "too man argument" if args.length != 1
    elsif self.ip?
      raise ArgumentError, "IP address needs host and port but #{args.length} arguments given" if args.length != 2
      host, port = args
      Addrinfo.getaddrinfo(host, port, self.pfamily, self.socktype, self.protocol)[0]
    elsif self.unix?
      raise ArgumentError, "UNIX socket needs single path argument but #{args.length} arguments given" if args.length != 1
      path, = args
      Addrinfo.unix(path)
    else
      raise ArgumentError, "unexpected family"
    end
  end

  def connect_internal(local_addrinfo)
    sock = Socket.new(self.pfamily, self.socktype, self.protocol)
    begin
      sock.ipv6only! if self.ipv6?
      sock.bind local_addrinfo if local_addrinfo
      sock.connect(self)
      if block_given?
        yield sock
      else
        sock
      end
    ensure
      sock.close if !sock.closed? && (block_given? || $!)
    end
  end
  private :connect_internal

  # creates a socket connected to the address of self.
  #
  # If one or more arguments given as _local_addr_args_,
  # it is used as the local address of the socket.
  # _local_addr_args_ is given for family_addrinfo to obtain actual address.
  #
  # If no arguments given, the local address of the socket is not bound.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   Addrinfo.tcp("www.ruby-lang.org", 80).connect_from("0.0.0.0", 4649) {|s|
  #     s.print "GET / HTTP/1.0\r\n\r\n"
  #     p s.read
  #   }
  #
  #   # Addrinfo object can be taken for the argument.
  #   Addrinfo.tcp("www.ruby-lang.org", 80).connect_from(Addrinfo.tcp("0.0.0.0", 4649)) {|s|
  #     s.print "GET / HTTP/1.0\r\n\r\n"
  #     p s.read
  #   }
  #
  def connect_from(*local_addr_args, &block)
    connect_internal(family_addrinfo(*local_addr_args), &block)
  end

  # creates a socket connected to the address of self.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   Addrinfo.tcp("www.ruby-lang.org", 80).connect {|s|
  #     s.print "GET / HTTP/1.0\r\n\r\n"
  #     p s.read
  #   }
  #
  def connect(&block)
    connect_internal(nil, &block)
  end

  # creates a socket connected to _remote_addr_args_ and bound to self.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   Addrinfo.tcp("0.0.0.0", 4649).connect_to("www.ruby-lang.org", 80) {|s|
  #     s.print "GET / HTTP/1.0\r\n\r\n"
  #     p s.read
  #   }
  #
  def connect_to(*remote_addr_args, &block)
    remote_addrinfo = family_addrinfo(*remote_addr_args)
    remote_addrinfo.send(:connect_internal, self, &block)
  end

  # creates a socket bound to self.
  #
  # If a block is given, it is called with the socket and the value of the block is returned.
  # The socket is returned otherwise.
  #
  #   Addrinfo.udp("0.0.0.0", 9981).bind {|s|
  #     s.local_address.connect {|s| s.send "hello", 0 }
  #     p s.recv(10) #=> "hello"
  #   }
  #
  def bind
    sock = Socket.new(self.pfamily, self.socktype, self.protocol)
    begin
      sock.ipv6only! if self.ipv6?
      sock.setsockopt(:SOCKET, :REUSEADDR, 1)
      sock.bind(self)
      if block_given?
        yield sock
      else
        sock
      end
    ensure
      sock.close if !sock.closed? && (block_given? || $!)
    end
  end

  # creates a listening socket bound to self.
  def listen(backlog=5)
    sock = Socket.new(self.pfamily, self.socktype, self.protocol)
    begin
      sock.ipv6only! if self.ipv6?
      sock.setsockopt(:SOCKET, :REUSEADDR, 1)
      sock.bind(self)
      sock.listen(backlog)
      if block_given?
        yield sock
      else
        sock
      end
    ensure
      sock.close if !sock.closed? && (block_given? || $!)
    end
  end

  # iterates over the list of Addrinfo objects obtained by Addrinfo.getaddrinfo.
  #
  #   Addrinfo.foreach(nil, 80) {|x| p x }
  #   #=> #<Addrinfo: 127.0.0.1:80 TCP (:80)>
  #   #   #<Addrinfo: 127.0.0.1:80 UDP (:80)>
  #   #   #<Addrinfo: [::1]:80 TCP (:80)>
  #   #   #<Addrinfo: [::1]:80 UDP (:80)>
  #
  def self.foreach(nodename, service, family=nil, socktype=nil, protocol=nil, flags=nil, &block)
    Addrinfo.getaddrinfo(nodename, service, family, socktype, protocol, flags).each(&block)
  end
end

class Socket
  # enable the socket option IPV6_V6ONLY if IPV6_V6ONLY is available.
  def ipv6only!
    if defined? Socket::IPV6_V6ONLY
      self.setsockopt(:IPV6, :V6ONLY, 1)
    end
  end

  # creates a new socket object connected to host:port using TCP.
  #
  # If local_host:local_port is given,
  # the socket is bound to it.
  #
  # If a block is given, the block is called with the socket.
  # The value of the block is returned.
  # The socket is closed when this method returns.
  #
  # If no block is given, the socket is returned.
  #
  #   Socket.tcp("www.ruby-lang.org", 80) {|sock|
  #     sock.print "GET / HTTP/1.0\r\n\r\n"
  #     sock.close_write
  #     print sock.read
  #   }
  #
  def self.tcp(host, port, local_host=nil, local_port=nil) # :yield: socket
    last_error = nil
    ret = nil

    local_addr_list = nil
    if local_host != nil || local_port != nil
      local_addr_list = Addrinfo.getaddrinfo(local_host, local_port, nil, :STREAM, nil)
    end

    Addrinfo.foreach(host, port, nil, :STREAM) {|ai|
      if local_addr_list
        local_addr = local_addr_list.find {|local_ai| local_ai.afamily == ai.afamily }
        next if !local_addr
      else
        local_addr = nil
      end
      begin
        sock = local_addr ? ai.connect_from(local_addr) : ai.connect
      rescue SystemCallError
        last_error = $!
        next
      end
      ret = sock
      break
    }
    if !ret
      if last_error
        raise last_error
      else
        raise SocketError, "no appropriate local address"
      end
    end
    if block_given?
      begin
        yield ret
      ensure
        ret.close if !ret.closed?
      end
    else
      ret
    end
  end

  def self.tcp_server_sockets_port0(host)
    ai_list = Addrinfo.getaddrinfo(host, 0, nil, :STREAM, nil, Socket::AI_PASSIVE)
    begin
      sockets = []
      port = nil
      ai_list.each {|ai|
        begin
          s = Socket.new(ai.pfamily, ai.socktype, ai.protocol)
        rescue SystemCallError
          next
        end
        sockets << s
        s.ipv6only! if ai.ipv6?
        s.setsockopt(:SOCKET, :REUSEADDR, 1)
        if !port
          s.bind(ai)
          port = s.local_address.ip_port
        else
          s.bind(Addrinfo.tcp(ai.ip_address, port))
        end
        s.listen(5)
      }
    rescue Errno::EADDRINUSE
      sockets.each {|s|
        s.close
      }
      retry
    end
    sockets
  ensure
    if $!
      sockets.each {|s|
        s.close if !s.closed?
      }
    end
  end
  class << self
    private :tcp_server_sockets_port0
  end

  # creates TCP server sockets for _host_ and _port_.
  # _host_ is optional.
  #
  # It returns an array of listening sockets.
  #
  # If _port_ is 0, actual port number is choosen dynamically.
  # However all sockets in the result has same port number.
  #
  #   # tcp_server_sockets returns two sockets.
  #   sockets = Socket.tcp_server_sockets(1296)
  #   p sockets #=> [#<Socket:fd 3>, #<Socket:fd 4>]
  #
  #   # The sockets contains IPv6 and IPv4 sockets.
  #   sockets.each {|s| p s.local_address }
  #   #=> #<Addrinfo: [::]:1296 TCP>
  #   #   #<Addrinfo: 0.0.0.0:1296 TCP>
  #
  #   # IPv6 and IPv4 socket has same port number, 53114, even if it is choosen dynamically.
  #   sockets = Socket.tcp_server_sockets(0)
  #   sockets.each {|s| p s.local_address }
  #   #=> #<Addrinfo: [::]:53114 TCP>
  #   #   #<Addrinfo: 0.0.0.0:53114 TCP>
  #
  def self.tcp_server_sockets(host=nil, port)
    return tcp_server_sockets_port0(host) if port == 0
    begin
      last_error = nil
      sockets = []
      Addrinfo.foreach(host, port, nil, :STREAM, nil, Socket::AI_PASSIVE) {|ai|
        begin
          s = ai.listen
        rescue SystemCallError
          last_error = $!
          next
        end
        sockets << s
      }
      if sockets.empty?
        raise last_error
      end
      sockets
    ensure
      if $!
        sockets.each {|s|
          s.close if !s.closed?
        }
      end
    end
  end

  # yield socket and client address for each a connection accepted via given sockets.
  #
  # The arguments are a list of sockets.
  # The individual argument should be a socket or an array of sockets. 
  #
  # This method yields the block sequentially.
  # It means that the next connection is not accepted until the block returns.
  # So concurrent mechanism, thread for example, should be used to service multiple clients at a time.
  #
  def self.accept_loop(*sockets) # :yield: socket, client_addrinfo
    sockets.flatten!(1)
    if sockets.empty?
      raise ArgumentError, "no sockets"
    end
    loop {
      readable, _, _ = IO.select(sockets)
      readable.each {|r|
        begin
          sock, addr = r.accept_nonblock
        rescue Errno::EWOULDBLOCK
          next
        end
        yield sock, addr
      }
    }
  end

  # creates a TCP server on _port_ and calls the block for each connection accepted.
  # The block is called with a socket and a client_address as an Addrinfo object.
  #
  # If _host_ is specified, it is used with _port_ to determine the server addresses.
  #
  # The socket is *not* closed when the block returns.
  # So application should close it explicitly.
  #
  # This method calls the block sequentially.
  # It means that the next connection is not accepted until the block returns.
  # So concurrent mechanism, thread for example, should be used to service multiple clients at a time.
  #
  # Note that Addrinfo.getaddrinfo is used to determine the server socket addresses.
  # When Addrinfo.getaddrinfo returns two or more addresses,
  # IPv4 and IPv6 address for example,
  # all of them are used.
  # Socket.tcp_server_loop succeeds if one socket can be used at least.
  #
  #   # Sequential echo server.
  #   # It services only one client at a time.
  #   Socket.tcp_server_loop(16807) {|sock, client_addrinfo|
  #     begin
  #       IO.copy_stream(sock, sock)
  #     ensure
  #       sock.close
  #     end
  #   }
  #
  #   # Threaded echo server
  #   # It services multiple clients at a time.
  #   # Note that it may accept connections too much.
  #   Socket.tcp_server_loop(16807) {|sock, client_addrinfo|
  #     Thread.new {
  #       begin
  #         IO.copy_stream(sock, sock)
  #       ensure
  #         sock.close
  #       end
  #     }
  #   }
  #
  def self.tcp_server_loop(host=nil, port, &b) # :yield: socket, client_addrinfo
    sockets = tcp_server_sockets(host, port)
    accept_loop(sockets, &b)
  ensure
    if sockets
      sockets.each {|s|
        s.close if !s.closed?
      }
    end
  end

  # creates a new socket connected to path using UNIX socket socket.
  #
  # If a block is given, the block is called with the socket.
  # The value of the block is returned.
  # The socket is closed when this method returns.
  #
  # If no block is given, the socket is returned.
  #
  #   # talk to /tmp/sock socket.
  #   Socket.unix("/tmp/sock") {|sock|
  #     t = Thread.new { IO.copy_stream(sock, STDOUT) }
  #     IO.copy_stream(STDIN, sock)
  #     t.join
  #   }
  #
  def self.unix(path) # :yield: socket
    addr = Addrinfo.unix(path)
    sock = addr.connect
    if block_given?
      begin
        yield sock
      ensure
        sock.close if !sock.closed?
      end
    else
      sock
    end
  end

  # creates UNIX server sockets on _path_
  #
  # It returns a listening socket.
  #
  #   socket = Socket.unix_server_socket("/tmp/s")
  #   p socket               #=> #<Socket:fd 3>
  #   p socket.local_address #=> #<Addrinfo: /tmp/s SOCK_STREAM>
  #
  def self.unix_server_socket(path)
    begin
      st = File.lstat(path)
    rescue Errno::ENOENT
    end
    if st && st.socket? && st.owned?
      File.unlink path
    end
    Addrinfo.unix(path).listen
  end

  # creates a UNIX socket server on _path_.
  # It calls the block for each socket accepted.
  #
  # If _host_ is specified, it is used with _port_ to determine the server ports.
  #
  # The socket is *not* closed when the block returns.
  # So application should close it.
  #
  # This method deletes the socket file pointed by _path_ at first if
  # the file is a socket file and it is owned by the user of the application.
  # This is safe only if the directory of _path_ is not changed by a malicious user.
  # So don't use /tmp/malicious-users-directory/socket.
  # Note that /tmp/socket and /tmp/your-private-directory/socket is safe assuming that /tmp has sticky bit.
  #
  #   # Sequential echo server.
  #   # It services only one client at a time.
  #   Socket.unix_server_loop("/tmp/sock") {|sock, client_addrinfo|
  #     begin
  #       IO.copy_stream(sock, sock)
  #     ensure
  #       sock.close
  #     end
  #   }
  #
  def self.unix_server_loop(path, &b) # :yield: socket, client_addrinfo
    serv = unix_server_socket(path)
    accept_loop(serv, &b)
  ensure
    serv.close if serv && !serv.closed?
  end

end
