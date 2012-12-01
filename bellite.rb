#!/usr/bin/ruby
require 'json'
require 'socket'
include Socket::Constants


# Clone of {http://docs.python.org/2/library/functools.html#functools.partial Python functools.partial}
#   Creates a lambda with passed func and applies to it args. Args can be overriden when this lambda called.
#
#@param [Function] func - func to be called with partial parameters
#@param [Array] *args   - default parameters which should be passed to func
#@return [Function] wrapper around func which passes *args or new args, passed to wrapper to func
#
#
#
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
    #@param [Hash] Something JSONable to pass as ethod params
    def _invoke(method, params=nil)
        raise NotImplementedError, "Subclass Responsibility"
    end
end


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#


#@abstract Next level of Bellite server API implementation: Basic operations with server like Bellite.
class BelliteJsonRpc < BelliteJsonRpcApi
    def initialize(cred=false, logging=false)
        @_resultMap = {}
        @_evtTypeMap = {}
        @_nextMsgId = 100
        super (cred)
        @logging = logging
    end

    def _notify(method, params=nil)
        return _sendJsonRpc(method, params)
    end

    def _invoke(method, params=nil)
        msgId = @_nextMsgId
        @_nextMsgId += 1
        res = _newResult(msgId)
        _sendJsonRpc(method, params, msgId)
        return res.promise
    end

    def _newResult(msgId)
        res = deferred()
        @_resultMap[msgId] = res
        return res
    end

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

    def _sendMessage(msg)
        raise NotImplementedError('Subclass Responsibility')
    end

    def logSend(msg)
        puts "send ==> " + JSON.fast_generate(msg)
    end

    def logRecv(msg)
        puts "recv ==> " + JSON.fast_generate(msg)
    end

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

    def on_rpc_call(msg)
        if msg['method'] == 'event'
            args = msg['params']
            emit(args['evtType'], args)
        end
    end

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

    def on_connect(cred)
        auth(cred['token'])._then.call(method(:on_auth_succeeded), method(:on_auth_failed))
    end

    def on_auth_succeeded(msg)
        emit('auth', true, msg)
        emit('ready')
    end

    def on_auth_failed(msg)
        emit('auth', false, msg)
    end


    #~ micro event implementation ~~~~~~~~~~~~~~~~~~~~~~~
    #

    def ready(fnReady)
        return on('ready', fnReady)
    end

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


class Bellite < BelliteJsonRpc


    attr_accessor :timeout

    def _connect(cred)
        @timeout = 0.5
        @conn = TCPSocket.new cred['host'], cred['port']
        @buf = ""

        if @conn
            on_connect(cred)
        end
    end

    def loop(timeout=0.5)
        if timeout == false
            timeout = @timeout
        end
        Async.loop(timeout, [self])
    end

    def _sendMessage(msg)
        if not isConnected?
            return false
        end

        @conn.puts(msg + "\0")
    end

    def isConnected?
        return @conn != false
    end

    def close()
        @conn.close
        @conn = false
        return true
    end

    def fileno()
        return @conn
    end

    def readable?
        return true
    end

    def exceptable?
        return false
    end

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

    def writable?()
        return false
    end

    def handle_write_event()
    end

    def handle_expt_event()
        close()
    end

    def handle_close()
        close()
    end

    def handle_error()
        close()
    end
end

class PromiseApi
    def always(fn)
        return @_then.call(fn, fn)
    end

    def fail(failure)
        return @_then.call(false, failure)
    end

    def done(success)
        return @_then.call(success,false)
    end
end

class Promise < PromiseApi
    def initialize(_then) 
        if _then
            @_then = _then
        end
    end

    def promise
        return self
    end

    def _then
        @_then
    end
end

class Future < PromiseApi
    def initialize(_then, resolve=false, reject=false)
        @promise = Promise.new _then
        if resolve
            @resolve = resolve
        end
        if reject
            @reject = reject
        end
    end

    def resolve
        @resolve
    end

    def reject
        @reject
    end

    def promise
        @promise
    end
end

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
