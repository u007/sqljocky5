part of sqljocky;

typedef void Callback();

class Connection {
  static const int HEADER_SIZE = 4;
  static const int STATE_PACKET_HEADER = 0;
  static const int STATE_PACKET_DATA = 1;
  final Logger log;

  ConnectionPool _pool;
  Handler _handler;
  Completer<dynamic> _completer;
  
  Socket _socket;

  final Buffer _headerBuffer;
  Buffer _dataBuffer;
  
  int _packetNumber = 0;
  int _packetState = STATE_PACKET_HEADER;
  
  int _dataSize;
  int _readPos = 0;
  
  String _user;
  String _password;
  
  bool _inUse;
  bool _retain;
  final Map<String, PreparedQuery> _preparedQueryCache;
  
  Callback onFinished;

  Connection(ConnectionPool pool) :
      log = new Logger("AsyncTransport"),
      _headerBuffer = new Buffer(HEADER_SIZE),
      _preparedQueryCache = new Map<String, PreparedQuery>(),
      _pool = pool,
      _inUse = false;
  
  void close() {
    _socket.close();
  }
  
  bool get inUse => _inUse;
  
  void use({retain: false}) {
    _inUse = true;
    _retain = retain;
  }
  
  void release() {
    _retain = false;
    _finished();
  }
  
  void _finished() {
    if (onFinished != null && !_retain) {
      _inUse = false;
      onFinished();
    }
  }
  
  Future connect({String host, int port, String user, 
      String password, String db}) {
    if (_socket != null) {
      throw "connection already open";
    }
    
    _user = user;
    _password = password;
    _handler = new HandshakeHandler(user, password, db);
    
    _completer = new Completer();
    log.fine("opening connection to $host:$port/$db");
    _socket = new Socket(host, port);
    _socket.onClosed = () {
      _finished();
      log.fine("closed");
    };
    _socket.onConnect = () {
      log.fine("connected");
    };
    _socket.onData = _onData;
    _socket.onError = (Exception e) {
      log.fine("exception $e");
      _finished();
      _completer.completeException(e);
    };
    _socket.onWrite = () {
      log.fine("write");
    };
    return _completer.future;
  }
  
  void _sendBuffer(Buffer buffer) {
    _headerBuffer[0] = buffer.length & 0xFF;
    _headerBuffer[1] = (buffer.length & 0xFF00) >> 8;
    _headerBuffer[2] = (buffer.length & 0xFF0000) >> 16;
    _headerBuffer[3] = ++_packetNumber;
    log.fine("sending header, packet $_packetNumber");
    _headerBuffer.writeAllTo(_socket);
    buffer.writeAllTo(_socket);
  }

  void _onData() {
    log.fine("got data");
    switch (_packetState) {
    case Connection.STATE_PACKET_HEADER:
      log.fine("reading header $_readPos");
      int bytes = _headerBuffer.readFrom(_socket, HEADER_SIZE - _readPos);
      _readPos += bytes;
      if (_readPos == HEADER_SIZE) {
        _packetState = STATE_PACKET_DATA;
        _dataSize = _headerBuffer[0] + (_headerBuffer[1] << 8) + (_headerBuffer[2] << 16);
        _packetNumber = _headerBuffer[3];
        _readPos = 0;
        log.fine("about to read $_dataSize bytes for packet ${_headerBuffer[3]}");
        _dataBuffer = new Buffer(_dataSize);
      }
      break;
    case STATE_PACKET_DATA:
      int bytes = _dataBuffer.readFrom(_socket, _dataSize - _readPos);
      log.fine("got $bytes bytes");
      _readPos += bytes;
      if (_readPos == _dataSize) {
        log.fine("read all data: ${_dataBuffer._list}");
        log.fine("read all data: ${Buffer.listChars(_dataBuffer._list)}");
        _packetState = STATE_PACKET_HEADER;
        _headerBuffer.reset();
        _readPos = 0;
        
        var result;
        try {
          result = _handler.processResponse(_dataBuffer);
        } catch (e) {
          _handler = null;
          log.fine("completing with exception: $e");
          _finished();
          _completer.completeException(e);
          return;
        }
        if (result is Handler) {
          // if handler.processResponse() returned a Handler, pass control to that
          // handler now
          _handler = result;
          _sendBuffer(_handler.createRequest());
        } else if (_handler.finished) {
          // otherwise, complete using the result, and that result will be
          // passed back to the future.
          _handler = null;
          _finished();
          _completer.complete(result);
        }
      }
      break;
    }
  }
  
  /**
   * Processes a handler, from sending the initial request to handling any packets returned from
   * mysql (unless [noResponse] is true).
   *
   * Returns a future
   */
  Future<dynamic> processHandler(Handler handler, {bool noResponse:false}) {
    if (_handler != null) {
      throw "request already in progress";
    }
    _packetNumber = -1;
    if (!noResponse) {
      _completer = new Completer<dynamic>();
      _handler = handler;
    }
    _sendBuffer(handler.createRequest());
    if (!noResponse) {
      return _completer.future;
    }
  }
  
  PreparedQuery removePreparedQueryFromCache(String sql) {
    var preparedQuery = null;
    if (_preparedQueryCache.containsKey(sql)) {
      preparedQuery = _preparedQueryCache[sql];
      _preparedQueryCache.remove(sql);
    }
    return preparedQuery;
  }
  
  PreparedQuery getPreparedQueryFromCache(String sql) {
    return _preparedQueryCache[sql];
  }
  
  putPreparedQueryInCache(String sql, PreparedQuery preparedQuery) {
    _preparedQueryCache[sql] = preparedQuery;
  }
  
  /**
   * The future returned by [whenReady] fires when there is nothing
   * in the queue.
   */
  Future<Connection> whenReady() {
    var c = new Completer<Connection>();
    if (!_inUse) {
      c.complete(this);
    } else {
      _pool.addPendingConnection(c);
    }
    return c.future;
  }
}
