#!/usr/bin/ruby

require '../lib/bellite.rb'
app = Bellite.new

app.on 'ready', lambda {
    app.ping
    app.version
    app.perform(142, "echo", {"name" => [nil, true, 42, "value"]})

    app.bindEvent(118, "*")
    app.unbindEvent(118, "*")

    app.on("testEvent", lambda { |app, eobj|
        if eobj['evt']
            app.perform(0, eobj['evt'])
        else
            app.close
        end
    })

    app.bindEvent(0, "testEvent", 42, {'testCtx' => true})
    app.perform(0, "testEvent")
}

app.timeout = false
while app.loop()
end
