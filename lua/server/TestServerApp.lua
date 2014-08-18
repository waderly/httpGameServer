
local OnlineUsersService = import(".services.OnlineUsersService")
local MessageService = import(".services.MessageService")

local TestServerApp = class("TestServerApp", cc.server.WebSocketServerBase)

 function TestServerApp:ctor( config )
 	TestServerApp.super.ctor(self, config)

 	if self.config.debug then
 		print("---------------- START -----------------")
 	end

 	self:addEventListener(TestServerApp.WEBSOCKETS_READY_EVENT, self.onWebSocketsReady, self)
 	self:addEventListener(TestServerApp.WEBSOCKETS_CLOSE_EVENT, self.onWebSocketsClose, self)
    self:addEventListener(TestServerApp.CLIENT_ABORT_EVENT, self.onClientAbort, self)

    self.onlineUsersService = OnlineUsersService.new(self)
    self.messageService = MessageService.mew(self)

    -- 创建一个 session id
    local redis = self:getRedis()
    local sessid , err = redis:command("INCR", SESSION_COUNTER_KEY)
    if err then
    	throw(ERR_SERVER_REDIS_ERROR, err)
    end 
    self.sessionId = sessid
 end

 function TestServerApp:doRequest( actionName, data )
 	if self.config.debug then
 		printLog("ACTION", ">> call [%s]", actionName)
 	end

 	local _, result = xpcall(function( )
 		return TestServerApp.super.doRequest(self, actionName, data)
 	end, function( msg )
 		return {error = msg}
 	end)

 	if self.config.debug then
 		local j = json.decode(result)
 		printLog("ACTION", "<< ret [%s] = (%d bytes) %s", actionName, string.len(j), j)
 		printLog("ACTION", "<<<<")
 	end

 	return result
 end

 function TestServerApp:getUID(  )
 	if not self.uid then
 		throw(ERR_SERVER_INVALID_PARAMETERS, "not set uid")
 	end
 	return self.uid 
 end

 function TestServerApp:setUID( uid )
 	self.uid = uid 
 end

 -- events callback
function TestServerApp:onWebSocketsReady( event )
	-- body
end

function TestServerApp:onWebSocketsClose( event )
	self:unsubscribePushMessageChannel()
end

function TestServerApp:onClientAbort( event )
	self:unsubscribePushMessageChannel()
end

-- internal methods
function TestServerApp:subscribePushMessageChannel(  )
	assert(type(self.uid) == "string" and self.uid ~= "", "TestServerApp:subscribePushMessageChannel() - invalid uid")
	assert(self.subscribePushMessageChannelEnabled ~= true, "TestServerApp:subscribePushMessageChannel() - already subscribed")
	--subscribe
	self.OnlineUsersChannel = self.format(ONLINE_USERS_CHANNEL_PATTERN, self.uid)

	local function subscribe(  )
		self.subscribePushMessageChannelEnabled = true

		local channel = self.OnlineUsersChannel
		local isRunning = true

		local redis = self:newRedis()
		local loop, err = redis:pubsub({subscribe = channel})
		if err then 
			throw(ERR_SERVER_OPERATION_FAILED, "subscribe channel [%s] failed, %s", channel, err)
		end

		for msg, abort in loop do 
			if msg.kind == "subscribe" then
				if self.config.debug then
					echoInfo("subscribed channel [%s], sessid = %d", msg.channel, self.sessionId)
				end
			elseif msg.kind == "message" then 
				if self.config.debug then
					local msg_ = msg.payload
					if string.len(msg_) > 20 then
						msg_ = string.sub(msg_, 1, 20) .. " ..."
					end 
					echoInfo("get message [%s] from channel [%s]", msg_, channel)
				end 

				local cmd = string.sub(msg.payload, 1, 4)
				if cmd == "keep" then
					local sessid = checkint(string.sub(msg.payload, 6))
					if sessid ~= self.sessionId then
						if self.websockets then
							self.websockets:send_text(json.encode({name = "kick"}))
							self:closeClientConnect() -- close
						end 
					end 
				elseif cmd == "quit" then
					local sessid = checkint(string.sub(msg.payload, 6))
					if sessid == self.sessionId then
						isRunning = false
						abort()
						break
					end 
				else 
					--forward message to client
					self.websockets:send_text(msg.payload)	
				end 
			end 
		end 

		-- 
		redis:close()
		redis = nil

		if self.config.debug then

		end 

		self.subscribePushMessageChannelEnabled = false

		if isRunning then
			self:subscribePushMessageChannel()
		end 
	end

	ngx.thread.spawn(subscribe)
end

function TestServerApp:unsubscribePushMessageChannel(  )
	self:getRedis():command("publish", self.OnlineUsersChannel, string.format("quit %d", self.sessionId))
end

return TestServerApp
