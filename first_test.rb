#!/usr/bin/ruby
require 'json'
require 'socket'
include Socket::Constants

$id = 100

def findCredentials(cred=false)
    if not cred
        cred = ENV['BELLITE_SERVER']
        if not cred
            cred = '127.0.0.1:3099/bellite-demo-host';
            puts 'BELLITE_SERVER environment variable not found, using "'+cred+'"'
        end
    end
    host, token = cred.split('/', 2)
    host, port = host.split(':', 2)
    return ({"credentials" => cred, "token" => token, "host" => host, "port" => Integer(port)})
end

def jsonRpcCall(host, port, method, params)
    jsonString = JSON.fast_generate({"jsonrpc" => "2.0", "method" => method, "params" => params, "id" => $id})

    socket = TCPSocket.new host, port
    puts "send ==> " + jsonString
    socket.puts jsonString + "\0"
    answer = socket.gets
    puts "recv <== " + answer
    result = JSON.parse(answer[0..-2])

    $id += 1
    return result['result']
end

#credentials =  findCredentials()
#result = jsonRpcCall(credentials['host'],credentials['port'],"ping",{"some" => "data", "and" => "and", "array" => [3,4,5]})
#puts result[2]





####^^^^ above just first test
####vvvv below testing implementation of bellite json-rpc


def partial(func, *args)
    return  Proc.new do |*new_args|
        merged_params = args.clone()
        new_args.each_with_index {|v,k|
            merged_params[k] = new_args[k]
        }
        func.call(*merged_params)
    end
end

def partialTest(a, b)
    puts a,  b
end

#latePartial = partial(method(:partialTest),"C","D")
#latePartial.call("E")


class Async
    @@map = []

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

        r,w,e = IO.select(readable, writable, excepted)
        #puts r
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

    def Async.loop(map=false)
        while Async.check(false, map) != false
        end
    end
end

class Hash
    def setdefault(key, value)
        if self[key] == nil
            self[key] = value
        end
        return self[key]
    end
end


class BelliteJsonRpcApi
    def initialize(cred)
        cred = findCredentials(cred)
        if cred
            _connect(cred)
        end
    end

    def auth(token)
        return _invoke('auth', [token])
    end

    def version
        return _invoke('version')
    end

    def ping
        return _invoke('ping')
    end

    def respondsTo(selfId, cmd)
        if not selfId
            selfId = 0
        end
        _invoke('respondsTo', [selfId, cmd])
    end

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

    def bindEvent(selfId=0, evtType='*', res = -1, ctx=false)
        if not selfId
            selfId = 0
        end
        return _invoke('bindEvent',[selfId, evtType, res, ctx])
    end

    def unbindEvent(selfId, evtType=false)
        if not selfId
            selfId = 0
        end
        return _invoke('unbindEvent',[selfId, evtType])
    end


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

    def _connect(host, port)
        raise NotImplementedError, "Subclass Responsibility"
    end

    def _invoke(method, params=nil)
        raise NotImplementedError, "Subclass Responsibility"
    end
end


#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#


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
        #puts "_recvJsonRpc"
        msgList.each do |msg|
            begin
                #msg = JSON.parse(msg[0..-2])
                msg = JSON.parse(msg)
                isCall = msg.has_key?("method")
            rescue
                #puts "parse fail"
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
        #puts "RPC CALL"
        if msg['method'] == 'event'
            args = msg['params']
            emit(args['evtType'], args)
        end
    end

    def on_rpc_response(msg)
        #puts "RPC RESPONSE"
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
        #puts "on connect"
        auth(cred['token'])._then.call(method(:on_auth_succeeded), method(:on_auth_failed))
    end

    def on_auth_succeeded(msg)
        #puts "auth success"
        emit('auth', true, msg)
        emit('ready')
    end

    def on_auth_failed(msg)
        #puts "auth fail"
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
            #puts "on -> bindEvent:"
            #puts @_evtTypeMap
            return fn
        end
        if not fn
            return bindEvent
        else
            return bindEvent.call(fn)
        end
    end

    def emit(key, *args)
        #puts "EMIT with key: " + key
        #puts @_evtTypeMap
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
    #TODO: timeout variables
    #
    #


    def _connect(cred)
        @conn = TCPSocket.new cred['host'], cred['port']
        @buf = ""

        if @conn
            on_connect(cred)
        end
    end

    def addAsyncMap(map=false)
        #TODO
    end

    def loop(timeout=0.5)
        #TODO
        Async.loop([self])
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
        #puts "CLOSED"
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
        #puts "handle_read_event"
        if not isConnected?
            #puts "not connected in handle_read_event"
            return false
        end

        buf = @buf
        begin
            while true
                begin
                    part = @conn.recv_nonblock(4096)
                rescue IO::WaitReadable
                    #puts "WaitReadable"
                    break
                end
                #puts 'PART + `' + part + '`'
                #if part.index('}')
                    #puts 'PART zero-terminator: ' + part.index('}')
                #else
                    #puts "Zero-terminator not found in part"
                #end
                if not part
                    #puts " CLOSE " + part
                    close()
                    break
                elsif part == ""
                    break
                else
                    buf += part
                    #puts " BUF + " +  buf 
                end
            end
        rescue
            #puts "EXCEPTION"
        end

##        puts bf

        buf = buf.split("\0")
        #puts "all readed BUF + "
        #buf.each_with_index do |msg,i|
            #puts "MSG " + i.to_s + ": " + msg
        #end
        #puts "after WHILE"
        #@buf = buf.pop()
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


app = Bellite.new
app.ready Proc.new { 
    puts "READY"
    app.ping
    app.version
    app.perform(142, "echo", {"name" => [nil, true, 42, "value"]})

    app.bindEvent(118, "*")
    app.unbindEvent(118, "*")

    app.on("testEvent", lambda { |app, eobj|
        puts "TEST EVENT"
        puts eobj
        if eobj['evt']
            app.perform(0, eobj['evt'])
        else
            app.close
        end
    })

    app.bindEvent(0, "testEvent", 42, {'testCtx' => true})
    app.perform(0, "testEvent")
}

app.loop
