#!/usr/bin/ruby
require 'json'
require 'socket'
include Socket::Constants


# Clone of {http://docs.python.org/2/library/functools.html#functools.partial Python functools.partial}
#   Creates a lambda with passed func and applies to it args. Args can be overriden when this lambda called.
#
#@param [Proc] func - func to be called with partial parameters
#@param [Array] *args   - default parameters which should be passed to func
#@return [Proc] wrapper around func which passes *args or new args, passed to wrapper to func
def partial(func, *args)
    return  Proc.new do |*new_args|
        merged_params = args.clone()
        new_args.each_with_index {|v,k|
            merged_params[k] = new_args[k]
        }
        func.call(*merged_params)
    end
end


# Simple implementation of {http://docs.python.org/2/library/asyncore.html Python Asyncore}
class Async
    #!attribute @@map
    #  List of objects, implements asyncore methods
    @@map = []

    #Checks sockets from map objects using {IO.select}
    #@param [Float] timeout timeout in seconds, passed to {IO.select}
    #@param [Hash] map list of objects implements asyncore methods
    def Async.check(timeout=false, map=false)
        if not map
            map = @@map
        end
        readable = []
        writable = []
        excepted = []

        changedCount = 0
        map.each do |obj|
            if obj.writable?
                if obj.fileno
                    writable << obj.fileno
                end
            end

            if obj.readable?
                if obj.fileno
                    readable << obj.fileno
                end
            end

            if obj.exceptable?
                if obj.fileno
                    excepted << obj.fileno
                end
            end
        end

        if readable.size == 0 and writable.size == 0 and excepted.size == 0
            return false
        end

        if (timeout)
            r,w,e = IO.select(readable, writable, excepted,timeout)
        else
            r,w,e = IO.select(readable, writable, excepted)
        end
        map.each do |obj|
            if obj.writable? and w.include? obj.fileno
                obj.handle_write_event
            end
            if obj.readable? and r.include? obj.fileno
                obj.handle_read_event
            end
            if obj.exceptable? and e.include? obj.fileno
                obj.handle_expt_event
            end
        end

        return r.size + w.size + e.size
    end

    #Running check while at least one socket in objects map is connected
    #@param [Float] timeout - timeout, passed to {.check}
    #@param [Hash] map, passed to {.check}
    def Async.loop(timeout,map=false)
        while Async.check(timeout, map) != false
        end
    end
end



# Implements new pythonic {http://docs.python.org/2/library/stdtypes.html#dict.setdefault setdefault} method in ruby class Hash
class Hash
    #(see {Hash})
    #@param key key of hash
    #@param value value of key in hash
    #@return [Value] if key in hash - hash value, attached to key; otherwise value, passed to setdefault
    def setdefault(key, value)
        if self[key] == nil
            self[key] = value
        end
        return self[key]
    end
end


# @abstract This is common interface of Bellite json-rpc API
class BelliteJsonRpcApi
    #Constructor. Connects to server with cred credentials
    #@param [String] cred Credentials in format: 'host:port/token';
    def initialize(cred)
        cred = findCredentials(cred)
        if cred
            _connect(cred)
        end
    end

    #Authenticates with server using token
    #@param [String] token Token to access server
    #@return {Promise}
    def auth(token)
        return _invoke('auth', [token])
    end

    #Server version
    #@return {Promise} 
    def version
        return _invoke('version')
    end

    #Ping server
    #@return {Promise}
    def ping
        return _invoke('ping')
    end

    #invokes respondsTo
    #@param [Fixnum] selfId Id for internal use (events, for example)
    #@param [Hash] cmd - some data, which can be encoded as JSON to pass to server
    #@return {Promise}
    def respondsTo(selfId, cmd)
        if not selfId
            selfId = 0
        end
        return _invoke('respondsTo', [selfId, cmd])
    end

    #perform JSON-RPC request 
    #@param [String] cmd command
    #@param [Array] *args Variable-length arguments, passed with cmd. :key => value ruby Hash parameter sugar also works
    #@return [Promise]
    def perform(selfId, cmd, *args)
        if args.size > 1
            args.each do |arg|
                if arg.instance_of(Hash)
                    raise ArgumentError, "Cannot specify both positional and keyword arguments"
                end
            end
        end
        if args.size == 1 and (args[0].instance_of? Hash or args[0].instance_of? Array)
            args = args[0]
        end
        if args == []
            args = nil
        end
        if not selfId
            selfId = 0
        end
        return _invoke('perform',[selfId, cmd, args])
    end

    # binds Event on some evtType
    #@param [Fixnum] selfId internal id
    #@param [String] evtType type of event
    #@param [Fixnum] res
    #@param [Hash] ctx - context, passed to event handler
    #@return [Promise]
    def bindEvent(selfId=0, evtType='*', res = -1, ctx=false)
        if not selfId
            selfId = 0
        end
        return _invoke('bindEvent',[selfId, evtType, res, ctx])
    end

    # Unbins Event on some evtType
    #@param [Fixnum] selfId internal id
    #@param [String] evtType type of event
    #@return [Promise]
    def unbindEvent(selfId, evtType=false)
        if not selfId
            selfId = 0
        end
        return _invoke('unbindEvent',[selfId, evtType])
    end


    # Finds credentials in environment variable BELLITE_SERVER or in passed parameter
    #@param [String] cred server credentials in format host:port/token
    #@return [Hash] with credentials or false if failed
    def findCredentials(cred=false)
        if not cred
            cred = ENV['BELLITE_SERVER']
            if not cred
                cred = '127.0.0.1:3099/bellite-demo-host';
                $stderr.puts 'BELLITE_SERVER environment variable not found, using "'+cred+'"'
            end
        elsif not cred.instance_of String
            return cred
        end

        begin
            host, token = cred.split('/', 2)
            host, port = host.split(':', 2)
            return ({"credentials" => cred, "token" => token, "host" => host, "port" => Integer(port)})
        rescue
            return false
        end
    end

    #@abstract Connecting to JSON-RPC server
    #@param [String] host Host
    #@param [Fixnum] port Port
    def _connect(host, port)
        raise NotImplementedError, "Subclass Responsibility"
    end

    #@abstract Invokes method
    #@param [String] method
    #@param [Hash] params Something JSONable to pass as ethod params
    def _invoke(method, params=nil)
        raise NotImplementedError, "Subclass Responsibility"
    end
end


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#


#@abstract Next level of Bellite server API implementation: Basic operations with server like Bellite.
class BelliteJsonRpc < BelliteJsonRpcApi
    #constructor. 
    #@param [String] cred Server credentials
    #@param [Boolean] logging Logging flag
    def initialize(cred=false, logging=false)
        @_resultMap = {}
        @_evtTypeMap = {}
        @_nextMsgId = 100
        super(cred)
        @logging = logging
    end

    #Notify JSON-RPC server by method call, but skip response
    #@param [String] method Method to call
    #@param [Hash,Array,String,Float,Fixnum] params parameters for method
    #@return [Boolean] true if sent
    def _notify(method, params=nil)
        return _sendJsonRpc(method, params)
    end

    #Calls JSON-RPC method
    #@param [String] method Method to call
    #@param [Hash,Array,String,Float,Fixnum] params parameters for method
    #@return [Promise]
    def _invoke(method, params=nil)
        msgId = @_nextMsgId
        @_nextMsgId += 1
        res = _newResult(msgId)
        _sendJsonRpc(method, params, msgId)
        return res.promise
    end

    #returns new Promise object, attached to msgId 
    #@param [Fixnum] msgId id of message for this result
    #@return [Promise]
    def _newResult(msgId)
        res = deferred()
        @_resultMap[msgId] = res
        return res
    end

    #Sends JSON-RPC call to server
    #@param [String] method Method to call
    #@param [Hash,Array,String,Float,Fixnum] params parameters for method
    #@param [Fixnum] msgId Message Id. If default, it uses internal autoincrement counter
    #@return [Boolean] True if sent
    def _sendJsonRpc(method, params=nil, msgId=false)
        msg = {"jsonrpc" => "2.0", "method" => method}
        if params
            msg['params'] = params
        end
        if msgId
            msg['id'] = msgId
        end
        logSend(msg)
        return _sendMessage(JSON.fast_generate(msg))
    end

    #Sends JSON-RPC string to server
    #@param [String] msg JSON-encoded JSON-RPC call to send
    #@return [Boolean] True if sent
    def _sendMessage(msg)
        raise NotImplementedError('Subclass Responsibility')
    end

    #Puts send packets to STDOUT
    #@param [String] msg Same as for _sendMessage
    def logSend(msg)
        puts "send ==> " + JSON.fast_generate(msg)
    end

    #Puts received packets to STDOUT
    #@param [String] msg Same as for _sendMessage
    def logRecv(msg)
        puts "recv ==> " + JSON.fast_generate(msg)
    end

    #Receives JSON-RPC response or call from JSON-RPC Server
    #@param [Array<String>] msgList Array of messages from Server
    def _recvJsonRpc(msgList)
        msgList.each do |msg|
            begin
                msg = JSON.parse(msg)
                isCall = msg.has_key?("method")
            rescue
                next
            end
            logRecv(msg)
            begin
                if isCall
                    on_rpc_call(msg)
                else
                    on_rpc_response(msg)
                end
            end
        end
    end

    #Called on JSON-RPC call FROM server.
    #@param [String] msg Server response with call
    def on_rpc_call(msg)
        if msg['method'] == 'event'
            args = msg['params']
            emit(args['evtType'], args)
        end
    end

    #Called on JSON-RPC response (not call) from Server
    #@param [String] msg Server respon with data
    def on_rpc_response(msg)
        tgt = @_resultMap.delete msg['id']
        if tgt == nil
            return
        end

        if msg.has_key?('error')
            tgt.reject.call(msg['error'])
        else
            tgt.resolve.call(msg['result'])
        end
    end

    #Called on connect to remote JSON-RPC server. 
    #@param [Hash] cred Server credentials: port, host, token and original `credentials` string
    def on_connect(cred)
        auth(cred['token'])._then.call(method(:on_auth_succeeded), method(:on_auth_failed))
    end

    #Called when auth is successfully ended
    # Emits 'auth' and 'ready' event handlers
    #@param [String] msg Message from JSON-RPC server
    def on_auth_succeeded(msg)
        emit('auth', true, msg)
        emit('ready')
    end

    #Called when auth is failed
    # Emits 'auth' event handlers with fail flag
    #@param [String] msg Message from JSON-RPC server
    def on_auth_failed(msg)
        emit('auth', false, msg)
    end


    #~ micro event implementation ~~~~~~~~~~~~~~~~~~~~~~~
    #

    #Adds ready event handler
    #@param [Proc] fnReady Event hanlder lambda 
    #@return [Proc] Your event handler
    def ready(fnReady)
        return on('ready', fnReady)
    end

    #Adds any event handler
    #@param [String] key Event name like `ready`
    #@param [Proc] fn Function to bind on event
    #@return [Proc] Your event handler or bindEvent method to bind your handler later if you skip fn
    def on(key, fn=false)
        bindEvent = lambda do |fn|
            @_evtTypeMap.setdefault(key, []) << fn
            return fn
        end
        if not fn
            return bindEvent
        else
            return bindEvent.call(fn)
        end
    end

    #Calls event handler when event occured
    #@param [String] key Event name like `ready`
    #@param [Hash,Array,Float,String,Fixnum] *args Argument to pass to event handler(s).
    def emit(key, *args)
        if @_evtTypeMap.has_key? key
            @_evtTypeMap[key].each do |fn|
                begin
                    fn.call(self, *args)
                rescue
                    puts "EMIT exception"
                end
            end
        end
    end
end


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#


#Main Bellite class to use
class Bellite < BelliteJsonRpc


#!attribute [rw] timeout 
# Timeout of IO.select socket wait
#@return [Float] Timeout value in seconds
    attr_accessor :timeout

    #Connecting to JSON-RPC server
    # Calls on_connect if connection successfull
    #@param [Hash] cred Server credentials: port, host, token and original `credentials` string
    def _connect(cred)
        @timeout = 0.5
        @conn = TCPSocket.new cred['host'], cred['port']
        @buf = ""

        if @conn
            on_connect(cred)
        end
    end

    #Obtains responses from JSON-RPC server
    #@param [Float] timeout Timeout, if false, @_timeout used
    def loop(timeout=0.5)
        if timeout == false
            timeout = @timeout
        end
        Async.loop(timeout, [self])
    end

    #Sends message to server
    #@param [String] msg JSON-encoded JSON-RPC call to send
    #@return [Boolean] True if sent
    def _sendMessage(msg)
        if not isConnected?
            return false
        end

        @conn.puts(msg + "\0")
        return true
    end

    #Checks, is connection still alive
    #@return [Boolean] True if connection alive
    def isConnected?
        return @conn != false
    end

    #Closing connection to JSON-RPC Server
    def close()
        @conn.close
        @conn = false
        return true
    end

    #Returns TCPSocket connection for {Async}
    #@return [TCPSocket] 
    def fileno()
        return @conn
    end

    #Returns is this object readable for {Async}
    #@return [Boolean]
    def readable?
        return true
    end

    #Returns is this object can read out-of-band data for {Async}
    #@return [Boolean]
    def exceptable?
        return false
    end

    #Reads new data and runs {#_recvJsonRpc}
    # This method called by {Async.loop}
    #@return [Boolean]
    def handle_read_event()
        if not isConnected?
            return false
        end

        buf = @buf
        begin
            while true
                begin
                    part = @conn.recv_nonblock(4096)
                rescue IO::WaitReadable
                    break
                end
                if not part
                    close()
                    break
                elsif part == ""
                    break
                else
                    buf += part
                end
            end
        rescue
        end


        buf = buf.split("\0")
        _recvJsonRpc(buf)
    end

    #Returns is this object can write data to socket 
    # This method called by {Async}
    #@return [Boolean]
    def writable?()
        return false
    end

    #Writes new data to socket
    # Stub for {Async}
    def handle_write_event()
    end

    #Handles out-of-band data
    # This method can be called by {Async}. Closes connection if called
    def handle_expt_event()
        close()
    end

    #Handles socket closing
    # This method can be called by {Async}
    def handle_close()
        close()
    end

    #Handles socket error
    # This method can be called by {Async}. Closing connection
    def handle_error()
        close()
    end
end

#@abstract Promise API
class PromiseApi
    #Runs then-function call with same function for success and failure
    #@param [Proc] fn Function to handle success or failure
    #@return Result of then-function call
    def always(fn)
        return @_then.call(fn, fn)
    end

    #Runs then-function in case of failure
    #@param [Proc] failure Failure handler
    #@return Result of then-function call
    def fail(failure)
        return @_then.call(false, failure)
    end

    #Runs then-function in case of success
    #@param [Proc] success Success handler
    #@return Result of then-function call
    def done(success)
        return @_then.call(success,false)
    end
end

#Class implements promise/future promise
class Promise < PromiseApi
    #Constructing object with then-function
    #@param [Proc] _then Then-function
    def initialize(_then) 
        if _then
            @_then = _then
        end
    end

    #Returns this object
    #@return [Promise]
    def promise
        return self
    end

    #@!attribute [r] _then
    # Then-function
    #@return [Proc,lambda]
    def _then
        @_then
    end
end

#Implements Future
class Future < PromiseApi
    #Constructing object with then, success and failure functions
    #@param [Proc,lambda] _then Then-function
    #@param [Proc,lambda] resolve Success-function
    #@param [Proc,lambda] reject Failure-function
    def initialize(_then, resolve=false, reject=false)
        @promise = Promise.new _then
        if resolve
            @resolve = resolve
        end
        if reject
            @reject = reject
        end
    end


    #@!attribute [r] resolve
    # Success-function
    #@return [Proc,lambda]
    def resolve
        @resolve
    end

    #@!attribute [r] reject
    # Failure-function
    #@return [Proc,lambda]
    def reject
        @reject
    end

    #@!attribute [r] promise
    # Promise object of this Future
    #@return [Promise]
    def promise
        @promise
    end
end

#Creates Future object for JSON-RPC Server response
#@return [Future]
def deferred()
    cb = []
    answer = false

    future = false
    reject = false

    _then = lambda do |*args|
        success = args[0] || false
        failure = args[1] || false
        cb << [success,failure]
        if answer
            answer.call
        end
        return future.promise
    end

    resolve = lambda do |result|
        while cb.size > 0
            success, failure = cb.pop()
            begin
                if success != false
                    res = success.call(result)
                    if res != false
                        result = res
                    end
                end
            rescue Exception => err
                if failure != false
                    res = failure.call(err)
                elsif cb.size = 0
                    #excepthook
                end
                if res == false
                    return reject.call(err)
                else
                    return reject.call(res)
                end
            end
        end
        answer = partial(resolve, result)
    end

    reject = lambda do |error|
        while cb.size > 0
            failure = cb.pop()[1]
            begin
                if failure != false
                    res = failure.call(error)
                    if res != false
                        error = res
                    end
                end
            rescue Exception => err
                res = err
                if cb.size == 0
                    #excepthook
                end
            end
        end
        answer = partial(reject, error)
    end

    future = Future.new _then, resolve, reject
    return future
end
